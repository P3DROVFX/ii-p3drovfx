#!/usr/bin/env python3
"""
One-shot KDE Connect notifications fetcher for a single device id.

Used by `KdeConnectService.requestNotificationsRefresh()` to mirror the active
notification list in the ii sidebar "Phone" tab without going through the
long-running `monitor.py` process. The previous implementation shelled out to
`qdbus-qt6` whose output wraps every JSON payload in
`[Variant(QString): "..."]` and silently fails `JSON.parse` — this script goes
straight to DBus via the same Python bindings the monitor uses, so each line
of stdout is a single JSON array usable by `StdioCollector`.

Notes on the DBus schema (KDE Connect 24.12+, kded daemon):
  `org.kde.kdeconnect.device.notifications.activeNotifications()` does NOT
return a list of JSON strings as the previous comment here claimed. It returns
a `QStringList` of **public IDs** (e.g. `["1", "2", "3", ...]`). The actual
notification metadata lives under a sub-object exposed at
`/modules/kdeconnect/devices/{dev_id}/notifications/{publicId}` whose
interface `org.kde.kdeconnect.device.notifications.notification` advertises
read-only properties: `internalId`, `appName`, `ticker`, `title`, `text`,
`groupName`, `isConversation`, `isGroupConversation`, `iconPath`,
`dismissable`, `hasIcon`, `silent`, `replyId`.

This fetcher emits each notification as a flat dict so the QML `_normaliseNotifications`
in `KdeConnectService.qml` can consume it directly. We deliberately avoid
embedding the time field (KDE Connect 26.04+ no longer exposes a separate
`time` property) — the QML side falls back to `Date.now()` so freshly-fetched
notifications appear with "now" relative timestamps, which is the desired
UX anyway.

Usage:
    python3 fetch_notifications.py <device_id>

Stdout: a single JSON array of notification objects on its own line. Empty
list `[]` is emitted when the device is unreachable, the notifications plugin
isn't loaded, or there genuinely are no notifications.

Exit codes:
    0 — query ran (regardless of whether the device answered anything)
    2 — invalid arguments / missing DBus Python bindings
"""

import json
import sys

try:
    import dbus
except Exception:
    # Output an empty list so the QML side doesn't wipe existing entries.
    sys.stdout.write("[]\n")
    sys.stdout.flush()
    sys.exit(2)


BUS_NAME = "org.kde.kdeconnect"
DEVICE_IFACE = "org.kde.kdeconnect.device"
NOTIF_IFACE = f"{DEVICE_IFACE}.notifications"
NOTIF_LEAF_IFACE = f"{NOTIF_IFACE}.notification"
PROPS_IFACE = "org.freedesktop.DBus.Properties"


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
        if isinstance(value, (dbus.String, dbus.UTF8String)):
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


def fetch_active_notifications(dev_id):
    """Fetch all active notifications for a device.

    Three-step query against the KDE Connect DBus:
      1. Get the list of public IDs via parent interface method
         `activeNotifications()` (returns QStringList of publicId strings).
      2. For each publicId, GetAll() properties of the per-notification
         sub-object at `/notifications/{publicId}`.
      3. Per-notification: call `actions()` on the parent interface with the
         publicId. The schema in KDE Connect 24.12+ returns a `QStringList`
         where each element is a `"key\\tLabel"` string (tab-separated). We
         split into `[{key, label}]` dicts so the QML side can render them.

    Returns a list of flat dicts in the schema expected by the QML
    `_normaliseNotifications` function.
    """
    try:
        bus = dbus.SessionBus()
    except Exception:
        return []

    try:
        parent_obj = bus.get_object(
            BUS_NAME, f"/modules/kdeconnect/devices/{dev_id}/notifications")
        parent_iface = dbus.Interface(parent_obj, NOTIF_IFACE)
        public_ids = list(parent_iface.activeNotifications() or [])
    except Exception:
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
            # Intent — Android-side action/data URI that can later be
            # forwarded to `adb shell am start -a <action> -d <data>`.
            # Exposed via DBus as `intent` property (a `QStringVariantMap`
            # or JSON string depending on KC version). Best-effort parse.
            if "intent" in notif:
                notif["intent"] = _parse_intent(notif["intent"])
        except Exception:
            continue
        # Extract package name from internalId (format: "0|<package>|...").
        notif["package"] = _extract_package(notif.get("internalId", ""))
        # Action buttons: KDE Connect DBus does NOT expose an `actions()`
        # method. Only `sendReply` is available for notifications with a
        # `replyId`. We set an empty list — the QML side renders Close/Copy/
        # Open-on-phone as fallback actions.
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
    """Best-effort parse of a KDE Connect notification `intent` property.

    KDE Connect (24.12+) exposes the original Android Intent as a struct of
    dicts on the leaf interface. We extract `action` and `data` URIs so the
    QML side can dispatch them via `adb am start -a <action> -d <data>`.

    Returns a flat dict: {"action": str, "data": str, "package": str, "extra": {...}}.
    Missing fields result in empty strings, never None.
    """
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
            # Some versions stringify the intent; let it be informational only.
            out["action"] = raw.strip()
    except Exception:
        pass
    return out


def main():
    if len(sys.argv) < 2 or not sys.argv[1]:
        sys.stdout.write("[]\n")
        sys.stdout.flush()
        sys.exit(2)
    dev_id = sys.argv[1]
    notifications = fetch_active_notifications(dev_id)
    sys.stdout.write(json.dumps(notifications, default=str) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
