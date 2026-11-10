#!/usr/bin/env python3
"""
Stores one secret in a saved NetworkManager profile, for the ii shell.

nmcli only takes secrets as command-line arguments, and /proc/<pid>/cmdline is
readable by every local user for as long as the command runs. This hands the
secret to NetworkManager over D-Bus instead, reading it from the environment,
which only the same user (and root) can read:

    PASSWORD=... set_secret.py <uuid> <setting>.<property>

nmcli's short setting names are accepted (wifi-sec.psk). A failure is one
"Error: ..." line on stderr and a non-zero exit; the secret is never printed.
"""

import os
import sys

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gio", "2.0")
from gi.repository import GLib, Gio  # noqa: E402

NM = "org.freedesktop.NetworkManager"
SETTINGS_PATH = "/org/freedesktop/NetworkManager/Settings"
SETTINGS_IFACE = NM + ".Settings"
CONNECTION_IFACE = NM + ".Settings.Connection"
UPDATE2_FLAG_TO_DISK = 0x1

ALIASES = {
    "wifi-sec": "802-11-wireless-security",
    "wifi": "802-11-wireless",
    "ethernet": "802-3-ethernet",
}


def fail(message):
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def call(bus, path, iface, method, args, reply_type):
    return bus.call_sync(NM, path, iface, method, args, GLib.VariantType(reply_type),
                         Gio.DBusCallFlags.NONE, -1, None)


def entries(variant):
    """The children of an a{s...} variant as (key, value) pairs, values untouched."""
    for i in range(variant.n_children()):
        entry = variant.get_child_value(i)
        yield entry.get_child_value(0).get_string(), entry.get_child_value(1)


def stored_secrets(bus, path, setting):
    """The secrets NetworkManager already keeps for one setting, as {key: v}."""
    try:
        reply = call(bus, path, CONNECTION_IFACE, "GetSecrets", GLib.Variant("(s)", (setting,)),
                     "(a{sa{sv}})")
    except GLib.Error:
        # Settings that hold no secrets at all answer with an error.
        return {}
    for name, values in entries(reply.get_child_value(0)):
        if name == setting:
            return dict(entries(values))
    return {}


def build(variant_type, pairs):
    builder = GLib.VariantBuilder.new(GLib.VariantType(variant_type))
    for key, value in pairs:
        builder.add_value(GLib.Variant.new_dict_entry(GLib.Variant("s", key), value))
    return builder.end()


def main():
    if len(sys.argv) != 3 or "." not in sys.argv[2]:
        fail("usage: set_secret.py <uuid> <setting>.<property>")
    uuid = sys.argv[1]
    setting, _, key = sys.argv[2].partition(".")
    setting = ALIASES.get(setting, setting)
    secret = os.environ.get("PASSWORD")
    if secret is None:
        fail("no secret in $PASSWORD")

    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        path = call(bus, SETTINGS_PATH, SETTINGS_IFACE, "GetConnectionByUuid",
                    GLib.Variant("(s)", (uuid,)), "(o)").get_child_value(0).get_string()
        current = call(bus, path, CONNECTION_IFACE, "GetSettings", None,
                       "(a{sa{sv}})").get_child_value(0)

        # Update2 keeps the stored secrets only when an update carries none at
        # all. This one carries the new secret, so the others go back in too.
        groups = []
        found = False
        for name, values in entries(current):
            merged = dict(entries(values))
            merged.update(stored_secrets(bus, path, name))
            if name == setting:
                merged[key] = GLib.Variant("v", GLib.Variant("s", secret))
                found = True
            groups.append((name, build("a{sv}", merged.items())))
        if not found:
            fail(f"the profile has no {setting} setting")

        call(bus, path, CONNECTION_IFACE, "Update2",
             GLib.Variant.new_tuple(build("a{sa{sv}}", groups),
                                    GLib.Variant("u", UPDATE2_FLAG_TO_DISK),
                                    GLib.Variant("a{sv}", {})),
             "(a{sv})")
    except GLib.Error as error:
        # "GDBus.Error:org.freedesktop....InvalidProperty: <what NM said>"
        message = error.message
        if message.startswith("GDBus.Error:"):
            message = message.partition(": ")[2] or message
        fail(message)


if __name__ == "__main__":
    main()
