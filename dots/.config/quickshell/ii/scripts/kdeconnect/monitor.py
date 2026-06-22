#!/usr/bin/env python3
"""
KDE Connect DBus monitor for the ii sidebar "Phone" tab.

Emits one JSON event per line on stdout whenever KDE Connect state changes,
so the QML singleton `services/KdeConnectService.qml` can react in real time.

Event shapes:
  {"event": "ready"}
  {"event": "fatal", "error": "...", "detail": "..."}
  {"event": "device_added", "id": "...", "name": "...", "type": "...",
   "icon": "...", "reachable": true, "paired": true,
   "supported_plugins": [...], "loaded_plugins": [...]}
  {"event": "device_removed", "id": "..."}
  {"event": "device_props", "id": "...", "changed": {"name": "...", "isReachable": true, ...}}
  {"event": "device_visibility", "id": "...", "reachable": true}
  {"event": "battery", "id": "...", "charge": 67, "charging": false}
  {"event": "connectivity", "id": "...", "type": "LTE", "strength": 4}
  {"event": "sync_notifications", "id": "...", "notifications": [{...}, ...]}
  {"event": "notif_posted", "id": "...", "public_id": "..."}
  {"event": "notif_updated", "id": "...", "public_id": "..."}
  {"event": "notif_removed", "id": "...", "public_id": "..."}
  {"event": "notif_cleared", "id": "..."}
  {"event": "share_received", "id": "...", "url": "file:///home/..."}
  {"event": "pairing_request", "id": "...", "name": "Galaxy S23"}

The script is intentionally robust: if the daemon disappears, it will exit and
the parent Process will restart it with a backoff. If a plugin is not supported
by a given device, the relevant listeners are simply not attached.

Notifications schema note (KDE Connect 24.12+):
  `activeNotifications()` on the parent `notifications` interface returns a
  QStringList of **public IDs** (e.g. ["1", "2", "3"]), NOT JSON payloads as
  earlier documentation sometimes implied. The actual notification metadata
  (appName, title, text, ticker, replyId, dismissable, ...) lives on a per-ID
  sub-object at `/notifications/{publicId}` exposing the
  `org.kde.kdeconnect.device.notifications.notification` interface via
  Properties.GetAll. We fetch each one individually when syncing.
"""

import json
import os
import sys
import time

try:
    import dbus
    import dbus.mainloop.glib
    from gi.repository import GLib
except Exception as e:
    sys.stdout.write(json.dumps({
        "event": "fatal",
        "error": "missing_deps",
        "detail": str(e)
    }) + "\n")
    sys.stdout.flush()
    sys.exit(1)

BUS_NAME = "org.kde.kdeconnect"
DAEMON_PATH = "/modules/kdeconnect"
DAEMON_IFACE = "org.kde.kdeconnect.daemon"
DEVICE_IFACE = "org.kde.kdeconnect.device"
NOTIF_IFACE = f"{DEVICE_IFACE}.notifications"
NOTIF_LEAF_IFACE = f"{NOTIF_IFACE}.notification"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

bus = None
loop = None
_attached_devices = set()


def emit(ev):
    try:
        sys.stdout.write(json.dumps(ev, default=str) + "\n")
        sys.stdout.flush()
    except Exception:
        pass


def _unwrap(value):
    """Recursively convert dbus types into plain JSON-serialisable types."""
    try:
        if isinstance(value, dbus.Boolean):
            return bool(value)
        if isinstance(value, (dbus.Int16, dbus.Int32, dbus.Int64,
                              dbus.UInt16, dbus.UInt32, dbus.UInt64)):
            return int(value)
        if isinstance(value, (dbus.Double,)):
            return float(value)
        if isinstance(value, (dbus.Byte,)):
            return int(value)
        if isinstance(value, dbus.ObjectPath):
            return str(value)
        if isinstance(value, dbus.String):
            return str(value)
        if isinstance(value, dbus.UTF8String):
            return str(value)
        if isinstance(value, dbus.Array):
            return [_unwrap(v) for v in value]
        if isinstance(value, dbus.Struct):
            return [_unwrap(v) for v in value]
        if isinstance(value, dbus.Dictionary):
            return {str(_unwrap(k)): _unwrap(v) for k, v in value.items()}
        if isinstance(value, dbus.Variant):
            return _unwrap(value)
    except Exception:
        pass
    if isinstance(value, (list, tuple)):
        return [_unwrap(v) for v in value]
    if isinstance(value, dict):
        return {str(k): _unwrap(v) for k, v in value.items()}
    return value


def fetch_device_props(dev_id):
    try:
        obj = bus.get_object(BUS_NAME, f"/modules/kdeconnect/devices/{dev_id}")
        props_iface = dbus.Interface(obj, PROPS_IFACE)
        all_props = props_iface.GetAll(DEVICE_IFACE)
        return {
            "id": str(dev_id),
            "name": str(all_props.get("name", "")),
            "type": str(all_props.get("type", "phone")),
            "icon": str(all_props.get("iconName", "phone")),
            "reachable": bool(all_props.get("isReachable", False)),
            "paired": bool(all_props.get("isPaired", False)),
            "supported_plugins": [str(p) for p in all_props.get("supportedPlugins", [])],
            "loaded_plugins": [str(p) for p in all_props.get("loadedPlugins", [])],
        }
    except Exception as e:
        return {"id": str(dev_id), "error": str(e),
                "name": "", "type": "phone", "icon": "phone",
                "reachable": False, "paired": False,
                "supported_plugins": [], "loaded_plugins": []}


def fetch_active_notifications(dev_id):
    """Fetch all active notifications for a device.

    Three-step query against the KDE Connect DBus:
      1. `activeNotifications()` on parent interface returns list of
         publicId strings (e.g. ["1", "2", "3"]).
      2. For each publicId, `GetAll("...notifications.notification")` on
         `/notifications/{publicId}` sub-object exposes the metadata:
         internalId, appName, ticker, title, text, groupName, iconPath,
         dismissable, hasIcon, silent, replyId, isConversation,
         isGroupConversation.
      3. Per-notification: call `actions(publicId)` on the parent interface
         to retrieve the inline action buttons (e.g. WhatsApp "Reply",
         Maps "Open"). Returns QStringList of "key\\tLabel" strings.

    Returns flat dicts in the schema expected by the QML
    `_normaliseNotifications` function. Each dict carries `publicId`
    explicitly so the QML side can issue `cancel` actions.
    """
    try:
        parent_obj = bus.get_object(
            BUS_NAME, f"/modules/kdeconnect/devices/{dev_id}/notifications")
        parent_iface = dbus.Interface(parent_obj, NOTIF_IFACE)
        public_ids = list(parent_iface.activeNotifications() or [])
    except Exception as e:
        emit({"event": "debug", "id": dev_id,
              "what": "active_notifications_failed",
              "error": str(e)})
        return []

    result = []
    for public_id_raw in public_ids:
        public_id = str(public_id_raw).strip()
        if not public_id:
            continue
        notif = {"publicId": public_id}
        try:
            leaf_obj = bus.get_object(
                BUS_NAME,
                f"/modules/kdeconnect/devices/{dev_id}/notifications/{public_id}")
            props_iface = dbus.Interface(leaf_obj, PROPS_IFACE)
            raw_props = props_iface.GetAll(NOTIF_LEAF_IFACE) or {}
            for k, v in raw_props.items():
                notif[str(k)] = _unwrap(v)
            # Intent — used for "Open on phone" ADB deep link dispatch.
            if "intent" in notif:
                notif["intent"] = _parse_intent(notif["intent"])
        except Exception as e:
            emit({"event": "debug", "id": dev_id,
                  "what": "notif_leaf_failed",
                  "public_id": public_id,
                  "error": str(e)})
            continue
        # Extract package name from internalId (format: "0|<package>|...").
        # KDE Connect DBus does NOT expose an `intent` property, so we derive
        # the app package from the internalId to enable "open on phone" via
        # `adb shell monkey -p <package>` when the user clicks the card.
        notif["package"] = _extract_package(notif.get("internalId", ""))
        # Action buttons: KDE Connect DBus does NOT expose an `actions()`
        # method on the parent notifications interface (confirmed via
        # Introspectable). The only action available is `sendReply` for
        # notifications that have a `replyId` (messaging apps). Other
        # actions (e.g. WhatsApp "Mark as read", Maps "Open") are NOT
        # forwarded through the KDE Connect protocol. We set an empty
        # list so the QML side doesn't render action button placeholders.
        notif["actions"] = []
        notif["publicId"] = public_id
        result.append(notif)
    return result


def _extract_package(internal_id):
    """Extract the Android package name from a KDE Connect internalId.

    internalId format: "0|<package>|<type>|<key>|<id>"
    Example: "0|com.whatsapp|1|N3JGW5Lg6vbO...|10466"
    Returns "" if the format doesn't match.
    """
    if not internal_id:
        return ""
    parts = str(internal_id).split("|")
    if len(parts) >= 2 and parts[0] == "0":
        return parts[1].strip()
    return ""


def _parse_intent(raw):
    """Parse an Android Intent exposed by KDE Connect into a flat dict
    so the QML side can dispatch it via `adb am start -a <action> -d <data>`."""
    out = {"action": "", "data": "", "package": "", "extra": {}}
    if not raw:
        return out
    try:
        if isinstance(raw, dict):
            for k, v in raw.items():
                kk = str(k).lower()
                if kk == "action":
                    out["action"] = str(v).strip()
                elif kk == "data":
                    out["data"] = str(v).strip()
                elif kk == "package":
                    out["package"] = str(v).strip()
                elif kk in ("extras", "extra"):
                    out["extra"] = _unwrap(v) if isinstance(v, dict) else {}
        elif isinstance(raw, str):
            out["action"] = raw.strip()
    except Exception:
        pass
    return out


def sync_notifications(dev_id):
    notifs = fetch_active_notifications(dev_id)
    emit({"event": "sync_notifications", "id": dev_id,
          "notifications": notifs})


def fetch_battery(dev_id):
    try:
        obj = bus.get_object(
            BUS_NAME, f"/modules/kdeconnect/devices/{dev_id}/battery")
        iface = dbus.Interface(obj, PROPS_IFACE)
        props = iface.GetAll(f"{DEVICE_IFACE}.battery")
        return int(props.get("charge", -1)), bool(props.get("isCharging", False))
    except Exception:
        return -1, False


def fetch_connectivity(dev_id):
    try:
        obj = bus.get_object(
            BUS_NAME, f"/modules/kdeconnect/devices/{dev_id}/connectivity_report")
        iface = dbus.Interface(obj, PROPS_IFACE)
        props = iface.GetAll(f"{DEVICE_IFACE}.connectivity_report")
        return str(props.get("cellularNetworkType", "")), \
               int(props.get("cellularNetworkStrength", 0))
    except Exception:
        return "", 0


def _safe_recv(signal_name, handler):
    """Wrap a signal receiver with try/except so a failure does not crash the loop."""
    def wrapped(*args, **kwargs):
        try:
            handler(*args, **kwargs)
        except Exception as e:
            emit({"event": "debug", "what": f"signal_{signal_name}",
                  "error": str(e)})
    return wrapped


def _emit_pairing_requests():
    """Read the daemon's pending pairingRequests property and emit one
    `pairing_request` event per unpaired device that wants to pair.

    KDE Connect exposes pairing requests as a string-list property on the
    daemon (not a per-device signal), so we poll it each time the
    `pairingRequestsChanged` signal fires.
    """
    try:
        main_obj = bus.get_object(BUS_NAME, DAEMON_PATH)
        props_iface = dbus.Interface(main_obj, PROPS_IFACE)
        raw = props_iface.Get(DAEMON_IFACE, "pairingRequests")
        ids = list(raw or [])
    except Exception as e:
        emit({"event": "debug", "what": "pairing_requests_fetch",
              "error": str(e)})
        return

    for dev_id in ids:
        dev_id = str(dev_id)
        name = ""
        try:
            dev_obj = bus.get_object(
                BUS_NAME, f"/modules/kdeconnect/devices/{dev_id}")
            name = str(dbus.Interface(dev_obj, PROPS_IFACE)
                       .Get(DEVICE_IFACE, "name") or "")
        except Exception:
            pass
        emit({"event": "pairing_request", "id": dev_id, "name": name})


def attach_device(dev_id):
    dev_id = str(dev_id)
    if dev_id in _attached_devices:
        return
    _attached_devices.add(dev_id)

    props = fetch_device_props(dev_id)
    emit({"event": "device_added", **props})

    charge, charging = fetch_battery(dev_id)
    emit({"event": "battery", "id": dev_id,
          "charge": charge, "charging": charging})

    ctype, cstr = fetch_connectivity(dev_id)
    emit({"event": "connectivity", "id": dev_id,
          "type": ctype, "strength": cstr})

    sync_notifications(dev_id)

    path = f"/modules/kdeconnect/devices/{dev_id}"

    INTERESTING_DEVICE_PROPS = (
        "name", "isReachable", "isPaired", "type", "iconName",
        "pairState", "loadedPlugins", "supportedPlugins",
        "reachableAddresses",
    )

    def on_props_changed(interface_name, changed, invalidated):
        try:
            if interface_name != DEVICE_IFACE and not interface_name.startswith(DEVICE_IFACE + "."):
                return
            interesting = {}
            for k, v in dict(changed).items():
                if k in INTERESTING_DEVICE_PROPS:
                    interesting[k] = _unwrap(v)
            if interesting:
                emit({"event": "device_props", "id": dev_id, "changed": interesting})
        except Exception as e:
            emit({"event": "debug", "id": dev_id,
                  "what": "props_changed", "error": str(e)})

    try:
        bus.add_signal_receiver(
            _safe_recv("props_changed", on_props_changed),
            dbus_interface=PROPS_IFACE,
            signal_name="PropertiesChanged",
            path=path)
    except Exception as e:
        emit({"event": "debug", "id": dev_id,
              "what": "props_attach", "error": str(e)})

    def on_battery_refreshed(is_charging, charge):
        emit({"event": "battery", "id": dev_id,
              "charge": int(charge), "charging": bool(is_charging)})
    try:
        bus.add_signal_receiver(
            _safe_recv("battery_refreshed", on_battery_refreshed),
            dbus_interface=f"{DEVICE_IFACE}.battery",
            signal_name="refreshed",
            path=path + "/battery")
    except Exception:
        pass

    def on_connectivity_refreshed(net_type, strength):
        emit({"event": "connectivity", "id": dev_id,
              "type": str(net_type), "strength": int(strength)})
    try:
        bus.add_signal_receiver(
            _safe_recv("connectivity_refreshed", on_connectivity_refreshed),
            dbus_interface=f"{DEVICE_IFACE}.connectivity_report",
            signal_name="refreshed",
            path=path + "/connectivity_report")
    except Exception:
        pass

    def on_notif_posted(public_id):
        emit({"event": "notif_posted", "id": dev_id,
              "public_id": str(public_id)})
        sync_notifications(dev_id)
    def on_notif_updated(public_id):
        emit({"event": "notif_updated", "id": dev_id,
              "public_id": str(public_id)})
        sync_notifications(dev_id)
    def on_notif_removed(public_id):
        emit({"event": "notif_removed", "id": dev_id,
              "public_id": str(public_id)})
        sync_notifications(dev_id)
    def on_notif_cleared():
        emit({"event": "notif_cleared", "id": dev_id})
        sync_notifications(dev_id)

    notifications_path = path + "/notifications"
    for sig, h in (("notificationPosted", on_notif_posted),
                   ("notificationUpdated", on_notif_updated),
                   ("notificationRemoved", on_notif_removed),
                   ("allNotificationsRemoved", on_notif_cleared)):
        try:
            bus.add_signal_receiver(
                _safe_recv(sig, h),
                dbus_interface=f"{DEVICE_IFACE}.notifications",
                signal_name=sig,
                path=notifications_path)
        except Exception:
            pass

    def on_share_received(url):
        emit({"event": "share_received", "id": dev_id, "url": str(url)})
    try:
        bus.add_signal_receiver(
            _safe_recv("share_received", on_share_received),
            dbus_interface=f"{DEVICE_IFACE}.share",
            signal_name="shareReceived",
            path=path + "/share")
    except Exception:
        pass

    def on_pair_state_changed(pair_state):
        # KDE Connect pairState: 0 unpaired, 1 paired, 2 requested.
        if int(pair_state) == 2:
            props = fetch_device_props(dev_id)
            emit({"event": "pairing_request", "id": dev_id,
                  "name": props.get("name", "")})
    try:
        bus.add_signal_receiver(
            _safe_recv("pair_state_changed", on_pair_state_changed),
            dbus_interface=DEVICE_IFACE,
            signal_name="pairStateChanged",
            path=path)
    except Exception:
        pass


def detach_device(dev_id):
    dev_id = str(dev_id)
    _attached_devices.discard(dev_id)
    emit({"event": "device_removed", "id": dev_id})


def main():
    global bus, loop
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    try:
        bus = dbus.SessionBus()
    except Exception as e:
        emit({"event": "fatal", "error": "no_session_bus", "detail": str(e)})
        sys.exit(1)

    try:
        main_obj = bus.get_object(BUS_NAME, DAEMON_PATH)
        daemon = dbus.Interface(main_obj, DAEMON_IFACE)
    except Exception as e:
        emit({"event": "fatal", "error": "no_daemon", "detail": str(e)})
        sys.exit(1)

    emit({"event": "ready"})

    try:
        all_devices = daemon.devices()
    except Exception as e:
        all_devices = []
        emit({"event": "debug", "what": "devices_failed", "error": str(e)})

    for dev_id in all_devices:
        attach_device(str(dev_id))

    def on_device_added(dev_id):
        emit({"event": "device_added_signal", "id": str(dev_id)})
        attach_device(str(dev_id))
    def on_device_removed(dev_id):
        detach_device(str(dev_id))
    def on_visibility_changed(dev_id, is_visible):
        emit({"event": "device_visibility", "id": str(dev_id),
              "reachable": bool(is_visible)})

    def on_pairing_requests_changed():
        _emit_pairing_requests()

    for sig, h in (("deviceAdded", on_device_added),
                   ("deviceRemoved", on_device_removed),
                   ("deviceVisibilityChanged", on_visibility_changed),
                   ("pairingRequestsChanged", on_pairing_requests_changed)):
        try:
            bus.add_signal_receiver(
                _safe_recv(sig, h),
                dbus_interface=DAEMON_IFACE,
                signal_name=sig)
        except Exception:
            pass

    # Emit any requests that were already pending when the monitor started.
    _emit_pairing_requests()

    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    main()
