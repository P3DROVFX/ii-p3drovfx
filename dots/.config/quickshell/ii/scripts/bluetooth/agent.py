#!/usr/bin/env python3
"""
Bluetooth pairing agent for the ii shell.

BlueZ never asks the user anything itself: it hands every PIN, passkey and
confirmation to whichever D-Bus object registered as an `org.bluez.Agent1`.
Without one, pairing a device that wants confirmation simply fails, which is
why this exists — it is the piece Quickshell's Bluetooth API cannot provide.

Speaks one JSON object per line on stdout:

    {"event": "ready",   "capability": "...", "default": true}
    {"event": "request", "id": 1, "type": "confirm", "device": "/org/bluez/...",
     "address": "AA:BB:...", "name": "Pixel 8", "passkey": 123456, "entered": 0}
    {"event": "display", "id": 2, "type": "passkey", ...}   # nothing to answer
    {"event": "cancel",  "id": 1}
    {"event": "error",   "message": "..."}

and reads the answers back on stdin, in the same shape:

    {"id": 1, "action": "accept"}
    {"id": 1, "action": "reject"}
    {"id": 1, "action": "value", "value": "0000"}

Requests are answered asynchronously — the D-Bus invocation is parked until the
answer arrives — so the shell can take as long as the user does.
"""

import json
import sys
import threading
import warnings

import gi

# PyGObject flags both register_object() and unix_signal_add() as deprecated in
# favour of APIs that are not available everywhere yet. Their warnings would
# otherwise be the only thing on stderr, where the shell looks for real errors.
warnings.filterwarnings("ignore", category=DeprecationWarning)

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import GLib, Gio  # noqa: E402

BUS_NAME = "org.bluez"
AGENT_PATH = "/org/quickshell/ii/btagent"
AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
DEVICE_IFACE = "org.bluez.Device1"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

# Answering takes as long as the user takes, but a request nobody ever answers
# must not pin a BlueZ call open forever.
REQUEST_TIMEOUT_S = 120

AGENT_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release"/>
    <method name="RequestPinCode">
      <arg name="device" type="o" direction="in"/>
      <arg name="pincode" type="s" direction="out"/>
    </method>
    <method name="DisplayPinCode">
      <arg name="device" type="o" direction="in"/>
      <arg name="pincode" type="s" direction="in"/>
    </method>
    <method name="RequestPasskey">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="out"/>
    </method>
    <method name="DisplayPasskey">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="in"/>
      <arg name="entered" type="q" direction="in"/>
    </method>
    <method name="RequestConfirmation">
      <arg name="device" type="o" direction="in"/>
      <arg name="passkey" type="u" direction="in"/>
    </method>
    <method name="RequestAuthorization">
      <arg name="device" type="o" direction="in"/>
    </method>
    <method name="AuthorizeService">
      <arg name="device" type="o" direction="in"/>
      <arg name="uuid" type="s" direction="in"/>
    </method>
    <method name="Cancel"/>
  </interface>
</node>
"""

connection = None
pending = {}
next_id = 0
loop = None


def emit(event):
    try:
        sys.stdout.write(json.dumps(event) + "\n")
        sys.stdout.flush()
    except Exception:
        pass


def device_property(path, name, fallback=None):
    try:
        result = connection.call_sync(BUS_NAME, path, PROPS_IFACE, "Get",
                                      GLib.Variant("(ss)", (DEVICE_IFACE, name)),
                                      GLib.VariantType("(v)"), Gio.DBusCallFlags.NONE,
                                      2000, None)
        return result.unpack()[0]
    except Exception:
        return fallback


def describe(path):
    """Everything the prompt needs to name the device it is talking about."""
    name = device_property(path, "Alias") or device_property(path, "Name") or ""
    return {
        "device": path,
        "address": device_property(path, "Address", "") or "",
        "name": name,
        "icon": device_property(path, "Icon", "") or "",
        "paired": bool(device_property(path, "Paired", False)),
        "trusted": bool(device_property(path, "Trusted", False)),
    }


class Request:
    """One parked BlueZ call, waiting on an answer from the shell."""

    # A reply of None is a valid, empty D-Bus return, so rejection needs a
    # marker of its own rather than the usual falsy check.
    INVALID = object()

    def __init__(self, request_id, kind, invocation, reply):
        self.id = request_id
        self.kind = kind
        self.invocation = invocation
        # Builds the success reply out of the user's answer, or returns None to
        # reject. Each request type packs a different signature.
        self.reply = reply
        self.timer = GLib.timeout_add_seconds(REQUEST_TIMEOUT_S, self.expire)

    def finish(self):
        if self.timer:
            GLib.source_remove(self.timer)
            self.timer = None
        pending.pop(self.id, None)

    def expire(self):
        self.timer = None
        self.reject("Timed out waiting for a response")
        return GLib.SOURCE_REMOVE

    def reject(self, message="Rejected"):
        self.finish()
        self.invocation.return_dbus_error("org.bluez.Error.Rejected", message)

    def accept(self, value=None):
        result = self.reply(value)
        if result is Request.INVALID:
            self.reject("Invalid response")
            return
        self.finish()
        self.invocation.return_value(result)


def ask(kind, invocation, path, reply, extra=None):
    global next_id
    next_id += 1
    request = Request(next_id, kind, invocation, reply)
    pending[next_id] = request
    event = {"event": "request", "id": next_id, "type": kind}
    event.update(describe(path))
    if extra:
        event.update(extra)
    emit(event)


def on_method_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method == "Release":
        emit({"event": "released"})
        invocation.return_value(None)
        return

    if method == "Cancel":
        # BlueZ cancels the whole exchange, not one request, so drop them all.
        for request in list(pending.values()):
            request.finish()
            request.invocation.return_dbus_error("org.bluez.Error.Canceled", "Canceled")
        emit({"event": "cancel"})
        invocation.return_value(None)
        return

    if method == "RequestPinCode":
        path = params.unpack()[0]
        ask("pincode", invocation, path,
            lambda value: GLib.Variant("(s)", (str(value or ""),)))
        return

    if method == "RequestPasskey":
        path = params.unpack()[0]

        def as_passkey(value):
            try:
                return GLib.Variant("(u)", (int(value) & 0xFFFFFFFF,))
            except (TypeError, ValueError):
                return Request.INVALID

        ask("passkey", invocation, path, as_passkey)
        return

    if method == "RequestConfirmation":
        path, passkey = params.unpack()
        ask("confirm", invocation, path, lambda _value: None,
            {"passkey": int(passkey)})
        return

    if method == "RequestAuthorization":
        path = params.unpack()[0]
        ask("authorize", invocation, path, lambda _value: None)
        return

    if method == "AuthorizeService":
        path, uuid = params.unpack()
        # A device the user already marked trusted has answered this question
        # once; asking again on every profile it opens is noise, not security.
        if device_property(path, "Trusted", False):
            invocation.return_value(None)
            return
        ask("authorize-service", invocation, path, lambda _value: None, {"uuid": uuid})
        return

    if method in ("DisplayPinCode", "DisplayPasskey"):
        values = params.unpack()
        event = {"event": "display",
                 "type": "pincode" if method == "DisplayPinCode" else "passkey"}
        event.update(describe(values[0]))
        if method == "DisplayPinCode":
            event["pin"] = values[1]
        else:
            event["passkey"] = int(values[1])
            event["entered"] = int(values[2])
        emit(event)
        invocation.return_value(None)
        return

    invocation.return_dbus_error("org.bluez.Error.Rejected", "Unsupported method")


def handle_command(command):
    request = pending.get(command.get("id"))
    if not request:
        return GLib.SOURCE_REMOVE
    action = command.get("action", "")
    if action == "reject":
        request.reject("Rejected by the user")
    elif action in ("accept", "value"):
        request.accept(command.get("value"))
    return GLib.SOURCE_REMOVE


def read_stdin():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            command = json.loads(line)
        except ValueError:
            continue
        GLib.idle_add(handle_command, command)
    GLib.idle_add(shutdown)


def shutdown():
    if loop:
        loop.quit()
    return GLib.SOURCE_REMOVE


def main():
    global connection, loop
    capability = sys.argv[1] if len(sys.argv) > 1 else "DisplayYesNo"

    try:
        connection = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    except GLib.Error as error:
        emit({"event": "error", "message": f"No system bus: {error.message}"})
        return 1

    node = Gio.DBusNodeInfo.new_for_xml(AGENT_XML)
    try:
        connection.register_object(AGENT_PATH, node.interfaces[0], on_method_call, None, None)
    except GLib.Error as error:
        emit({"event": "error", "message": f"Cannot export the agent: {error.message}"})
        return 1

    def manager_call(method, params, signature="(o)"):
        return connection.call_sync(BUS_NAME, "/org/bluez", AGENT_MANAGER_IFACE, method,
                                    GLib.Variant(signature, params), None,
                                    Gio.DBusCallFlags.NONE, 5000, None)

    try:
        manager_call("RegisterAgent", (AGENT_PATH, capability), "(os)")
    except GLib.Error as error:
        emit({"event": "error", "message": f"Cannot register the agent: {error.message}"})
        return 1

    is_default = True
    try:
        manager_call("RequestDefaultAgent", (AGENT_PATH,))
    except GLib.Error:
        # Another agent holds the default slot. Ours still serves the pairings
        # the shell starts itself, so this is a downgrade, not a failure.
        is_default = False

    emit({"event": "ready", "capability": capability, "default": is_default})

    loop = GLib.MainLoop()
    for signal in (1, 2, 15):
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal, shutdown)
    threading.Thread(target=read_stdin, daemon=True).start()

    try:
        loop.run()
    finally:
        try:
            manager_call("UnregisterAgent", (AGENT_PATH,))
        except GLib.Error:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
