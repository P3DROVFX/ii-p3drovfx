#!/usr/bin/env python3
"""
KDE Connect DBus monitor for the ii sidebar "Phone" tab.

Emits one JSON event per line on stdout whenever KDE Connect state changes,
so the QML singleton `services/KdeConnectService.qml` can react in real time.

Uses Gio.DBus (PyGObject / gi.repository) — no external python-dbus package needed.
"""

import json
import sys
import time

_connection = None
_attached_devices = set()

BUS_NAME = "org.kde.kdeconnect"
DAEMON_PATH = "/modules/kdeconnect"
DAEMON_IFACE = "org.kde.kdeconnect.daemon"
DEVICE_IFACE = "org.kde.kdeconnect.device"
NOTIF_IFACE = f"{DEVICE_IFACE}.notifications"
NOTIF_LEAF_IFACE = f"{NOTIF_IFACE}.notification"
PROPS_IFACE = "org.freedesktop.DBus.Properties"


def emit(ev):
    try:
        sys.stdout.write(json.dumps(ev, default=str) + "\n")
        sys.stdout.flush()
    except Exception:
        pass


def _fatal(error_type, message, detail=""):
    emit({"event": "fatal", "error": error_type, "message": message, "detail": detail})


# ─── Gio / GLib imports (required) ──────────────────────────────

try:
    from gi.repository import GLib, Gio
except ImportError as e:
    _fatal("missing_deps", "Python PyGObject (gi.repository) is not installed", str(e))
    sys.exit(1)


# ─── D-Bus helpers ──────────────────────────────────────────────

def _call(path, iface, method, params=None):
    """Call a D-Bus method and return the unpacked result value, or None."""
    try:
        proxy = Gio.DBusProxy.new_sync(
            _connection, Gio.DBusProxyFlags.NONE, None,
            BUS_NAME, path, iface)
        variant = proxy.call_sync(
            method, params, Gio.DBusCallFlags.NONE, -1, None)
        if variant is None:
            return None
        return _unpack_variant(variant.get_child_value(0))
    except Exception:
        return None


def _call_raw(path, iface, method, params=None):
    """Call a D-Bus method and return the raw GLib.Variant, or None."""
    try:
        proxy = Gio.DBusProxy.new_sync(
            _connection, Gio.DBusProxyFlags.NONE, None,
            BUS_NAME, path, iface)
        return proxy.call_sync(
            method, params, Gio.DBusCallFlags.NONE, -1, None)
    except Exception:
        return None


def _get_all_props(path, iface):
    """Get all D-Bus properties as a Python dict."""
    try:
        proxy = Gio.DBusProxy.new_sync(
            _connection, Gio.DBusProxyFlags.NONE, None,
            BUS_NAME, path, PROPS_IFACE)
        variant = proxy.call_sync(
            "GetAll", GLib.Variant("(s)", (iface,)),
            Gio.DBusCallFlags.NONE, -1, None)
        d = variant.get_child_value(0).unpack()
        # Unpack any nested Variants
        return {str(k): _unpack_variant(v) if isinstance(v, GLib.Variant) else v
                for k, v in d.items()}
    except Exception:
        return {}


def _get_prop(path, iface, prop):
    """Get a single D-Bus property."""
    try:
        proxy = Gio.DBusProxy.new_sync(
            _connection, Gio.DBusProxyFlags.NONE, None,
            BUS_NAME, path, PROPS_IFACE)
        variant = proxy.call_sync(
            "Get", GLib.Variant("(ss)", (iface, prop)),
            Gio.DBusCallFlags.NONE, -1, None)
        return _unpack_variant(variant.get_child_value(0))
    except Exception:
        return None


def _unpack_variant(v):
    """Recursively unwrap GLib.Variant / GVariant into plain Python types."""
    if v is None:
        return None
    if isinstance(v, GLib.Variant):
        t = v.get_type_string()
        if t in ("s", "o", "g"):
            return v.get_string()
        if t in ("b",):
            return v.get_boolean()
        if t in ("y",):
            return v.get_byte()
        if t in ("n",):
            return v.get_int16()
        if t in ("q",):
            return v.get_uint16()
        if t in ("i",):
            return v.get_int32()
        if t in ("u",):
            return v.get_uint32()
        if t in ("x",):
            return v.get_int64()
        if t in ("t",):
            return v.get_uint64()
        if t in ("d",):
            return v.get_double()
        if t in ("h",):
            return v.get_handle()
        if t == "v":
            return _unpack_variant(v.get_variant())
        if t.startswith("a{"):
            d = {}
            for i in range(v.n_children()):
                entry = v.get_child_value(i)
                k = _unpack_variant(entry.get_child_value(0))
                val = _unpack_variant(entry.get_child_value(1))
                d[str(k)] = val
            return d
        if t.startswith("a"):
            return [_unpack_variant(v.get_child_value(i)) for i in range(v.n_children())]
        return v.unpack()
    if isinstance(v, (bytes, bytearray)):
        return v.decode("utf-8", errors="replace")
    return v


def _subscribe(path, iface, signal_name, callback):
    """Subscribe to a D-Bus signal via Gio."""
    try:
        _connection.signal_subscribe(
            BUS_NAME, iface, signal_name, path,
            None, Gio.DBusSignalFlags.NONE,
            lambda conn, sender, obj_path, iface_name, sig_name, params, ud: callback(params),
            None)
    except Exception:
        pass


# ─── D-Bus data helpers ─────────────────────────────────────────

def fetch_device_props(dev_id):
    dev_path = f"/modules/kdeconnect/devices/{dev_id}"
    props = _get_all_props(dev_path, DEVICE_IFACE)
    return {
        "id": str(dev_id),
        "name": str(props.get("name", "")),
        "type": str(props.get("type", "phone")),
        "icon": str(props.get("iconName", "phone")),
        "reachable": bool(props.get("isReachable", False)),
        "paired": bool(props.get("isPaired", False)),
        "supported_plugins": [str(p) for p in props.get("supportedPlugins", [])],
        "loaded_plugins": [str(p) for p in props.get("loadedPlugins", [])],
    }


def fetch_battery(dev_id):
    dev_path = f"/modules/kdeconnect/devices/{dev_id}/battery"
    props = _get_all_props(dev_path, f"{DEVICE_IFACE}.battery")
    return int(props.get("charge", -1)), bool(props.get("isCharging", False))


def fetch_connectivity(dev_id):
    dev_path = f"/modules/kdeconnect/devices/{dev_id}/connectivity_report"
    props = _get_all_props(dev_path, f"{DEVICE_IFACE}.connectivity_report")
    return str(props.get("cellularNetworkType", "")), int(props.get("cellularNetworkStrength", 0))


def fetch_active_notifications(dev_id):
    """Fetch all active notifications for a device via Gio.DBus."""
    notif_path = f"/modules/kdeconnect/devices/{dev_id}/notifications"
    try:
        public_ids = _call(notif_path, NOTIF_IFACE, "activeNotifications") or []
    except Exception:
        return []

    result = []
    for public_id in public_ids:
        public_id = str(public_id).strip()
        if not public_id:
            continue
        leaf_path = f"{notif_path}/{public_id}"
        raw_props = _get_all_props(leaf_path, NOTIF_LEAF_IFACE)
        if not raw_props:
            continue
        notif = {"publicId": public_id}
        for k, v in raw_props.items():
            notif[str(k)] = v
        notif["package"] = _extract_package(notif.get("internalId", ""))
        notif["actions"] = []
        result.append(notif)
    return result


def _extract_package(internal_id):
    if not internal_id:
        return ""
    parts = str(internal_id).split("|")
    if len(parts) >= 2 and parts[0] == "0":
        return parts[1].strip()
    return ""


def sync_notifications(dev_id):
    notifs = fetch_active_notifications(dev_id)
    emit({"event": "sync_notifications", "id": dev_id, "notifications": notifs})


def _emit_pairing_requests():
    try:
        raw = _get_prop(DAEMON_PATH, DAEMON_IFACE, "pairingRequests") or []
    except Exception:
        return
    for dev_id in raw:
        dev_id = str(dev_id)
        name = str(_get_prop(f"/modules/kdeconnect/devices/{dev_id}", DEVICE_IFACE, "name") or "")
        emit({"event": "pairing_request", "id": dev_id, "name": name})


# ─── Device attach / detach ─────────────────────────────────────

def attach_device(dev_id):
    dev_id = str(dev_id)
    if dev_id in _attached_devices:
        return
    _attached_devices.add(dev_id)

    dev_path = f"/modules/kdeconnect/devices/{dev_id}"

    props = fetch_device_props(dev_id)
    emit({"event": "device_added", **props})

    charge, charging = fetch_battery(dev_id)
    emit({"event": "battery", "id": dev_id, "charge": charge, "charging": charging})

    ctype, cstr = fetch_connectivity(dev_id)
    emit({"event": "connectivity", "id": dev_id, "type": ctype, "strength": cstr})

    sync_notifications(dev_id)

    # ── Signal subscriptions ──

    INTERESTING_DEVICE_PROPS = {
        "name", "isReachable", "isPaired", "type", "iconName",
        "pairState", "loadedPlugins", "supportedPlugins",
        "reachableAddresses",
    }

    def on_props_changed(params):
        interface_name = _unpack_variant(params.get_child_value(0)) if params.n_children() > 0 else ""
        if interface_name != DEVICE_IFACE and not interface_name.startswith(DEVICE_IFACE + "."):
            return
        changed = _unpack_variant(params.get_child_value(1)) if params.n_children() > 1 else {}
        interesting = {k: v for k, v in changed.items() if k in INTERESTING_DEVICE_PROPS}
        if interesting:
            emit({"event": "device_props", "id": dev_id, "changed": interesting})
    _subscribe(dev_path, PROPS_IFACE, "PropertiesChanged", on_props_changed)

    def on_battery_refreshed(params):
        is_charging = bool(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else False
        charge = int(_unpack_variant(params.get_child_value(1))) if params.n_children() > 1 else -1
        emit({"event": "battery", "id": dev_id, "charge": charge, "charging": is_charging})
    _subscribe(dev_path + "/battery", f"{DEVICE_IFACE}.battery", "refreshed", on_battery_refreshed)

    def on_connectivity_refreshed(params):
        net_type = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        strength = int(_unpack_variant(params.get_child_value(1))) if params.n_children() > 1 else 0
        emit({"event": "connectivity", "id": dev_id, "type": net_type, "strength": strength})
    _subscribe(dev_path + "/connectivity_report", f"{DEVICE_IFACE}.connectivity_report",
               "refreshed", on_connectivity_refreshed)

    def on_notif_posted(params):
        public_id = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        emit({"event": "notif_posted", "id": dev_id, "public_id": public_id})
        sync_notifications(dev_id)

    def on_notif_updated(params):
        public_id = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        emit({"event": "notif_updated", "id": dev_id, "public_id": public_id})
        sync_notifications(dev_id)

    def on_notif_removed(params):
        public_id = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        emit({"event": "notif_removed", "id": dev_id, "public_id": public_id})
        sync_notifications(dev_id)

    def on_notif_cleared(_params):
        emit({"event": "notif_cleared", "id": dev_id})
        sync_notifications(dev_id)

    notif_path = dev_path + "/notifications"
    _subscribe(notif_path, f"{DEVICE_IFACE}.notifications", "notificationPosted", on_notif_posted)
    _subscribe(notif_path, f"{DEVICE_IFACE}.notifications", "notificationUpdated", on_notif_updated)
    _subscribe(notif_path, f"{DEVICE_IFACE}.notifications", "notificationRemoved", on_notif_removed)
    _subscribe(notif_path, f"{DEVICE_IFACE}.notifications", "allNotificationsRemoved", on_notif_cleared)

    def on_share_received(params):
        url = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        emit({"event": "share_received", "id": dev_id, "url": url})
    _subscribe(dev_path + "/share", f"{DEVICE_IFACE}.share", "shareReceived", on_share_received)

    def on_pair_state_changed(params):
        pair_state = int(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else 0
        if pair_state == 2:
            props = fetch_device_props(dev_id)
            emit({"event": "pairing_request", "id": dev_id, "name": props.get("name", "")})
    _subscribe(dev_path, DEVICE_IFACE, "pairStateChanged", on_pair_state_changed)


def detach_device(dev_id):
    dev_id = str(dev_id)
    _attached_devices.discard(dev_id)
    emit({"event": "device_removed", "id": dev_id})


# ─── Main ───────────────────────────────────────────────────────

def main():
    global _connection

    try:
        _connection = Gio.bus_get_sync(Gio.BusType.SESSION)
    except Exception as e:
        _fatal("no_session_bus", "Could not connect to D-Bus session bus", str(e))
        sys.exit(1)

    try:
        daemon = Gio.DBusProxy.new_sync(
            _connection, Gio.DBusProxyFlags.NONE, None,
            BUS_NAME, DAEMON_PATH, DAEMON_IFACE)
        all_devices = daemon.call_sync(
            "devices", None, Gio.DBusCallFlags.NONE, -1, None)
        device_ids = [str(d) for d in _unpack_variant(all_devices.get_child_value(0))] if all_devices else []
    except Exception as e:
        _fatal("no_daemon", "KDE Connect daemon not found via D-Bus", str(e))
        sys.exit(1)

    emit({"event": "ready"})

    for dev_id in device_ids:
        attach_device(dev_id)

    # Daemon-level signals
    def on_device_added(params):
        dev_id = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        emit({"event": "device_added_signal", "id": dev_id})
        attach_device(dev_id)

    def on_device_removed(params):
        dev_id = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        detach_device(dev_id)

    def on_visibility_changed(params):
        dev_id = str(_unpack_variant(params.get_child_value(0))) if params.n_children() > 0 else ""
        is_visible = bool(_unpack_variant(params.get_child_value(1))) if params.n_children() > 1 else False
        emit({"event": "device_visibility", "id": dev_id, "reachable": is_visible})

    def on_pairing_requests_changed(_params):
        _emit_pairing_requests()

    _subscribe(None, DAEMON_IFACE, "deviceAdded", on_device_added)
    _subscribe(None, DAEMON_IFACE, "deviceRemoved", on_device_removed)
    _subscribe(None, DAEMON_IFACE, "deviceVisibilityChanged", on_visibility_changed)
    _subscribe(None, DAEMON_IFACE, "pairingRequestsChanged", on_pairing_requests_changed)

    # Emit any requests already pending at startup
    _emit_pairing_requests()

    loop = GLib.MainLoop()
    loop.run()


if __name__ == "__main__":
    main()
