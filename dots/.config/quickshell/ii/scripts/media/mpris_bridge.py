#!/usr/bin/env python3
"""MPRIS export for the ii-owned local player.

This module only exposes the player state supplied by its owner.  It does not
derive a queue from external MPRIS players, which is the boundary that keeps the
local queue absent for Spotify, browsers and other applications.
"""

from __future__ import annotations

import hashlib
from collections.abc import Callable, Mapping
from typing import Any

try:
    from gi.repository import Gio, GLib
except ImportError as error:  # pragma: no cover - exercised by dependency detection
    Gio = None
    GLib = None
    _GI_IMPORT_ERROR = error
else:
    _GI_IMPORT_ERROR = None


MPRIS_OBJECT_PATH = "/org/mpris/MediaPlayer2"
ROOT_INTERFACE = "org.mpris.MediaPlayer2"
PLAYER_INTERFACE = "org.mpris.MediaPlayer2.Player"
PROPERTIES_INTERFACE = "org.freedesktop.DBus.Properties"
DEFAULT_BUS_NAME = "org.mpris.MediaPlayer2.ii_local"
DBUS_DAEMON_NAME = "org.freedesktop.DBus"
DBUS_DAEMON_PATH = "/org/freedesktop/DBus"
DBUS_DAEMON_INTERFACE = "org.freedesktop.DBus"
DBUS_NAME_FLAG_DO_NOT_QUEUE = 4
DBUS_REQUEST_NAME_PRIMARY_OWNER = 1

ROOT_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
</node>
"""

PLAYER_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg name="Offset" type="x" direction="in"/></method>
    <method name="SetPosition">
      <arg name="TrackId" type="o" direction="in"/>
      <arg name="Position" type="x" direction="in"/>
    </method>
    <method name="OpenUri"><arg name="Uri" type="s" direction="in"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


class MprisBridgeError(RuntimeError):
    pass


def seconds_to_microseconds(seconds: float | int | None) -> int:
    return max(0, int(round(float(seconds or 0) * 1_000_000)))


def microseconds_to_seconds(microseconds: int) -> float:
    return max(0.0, float(microseconds) / 1_000_000)


def track_object_path(entry_id: str) -> str:
    """Map arbitrary persistent IDs to a valid and deterministic D-Bus path."""

    digest = hashlib.sha256(entry_id.encode("utf-8")).hexdigest()
    return f"{MPRIS_OBJECT_PATH}/track/{digest}"


class MprisBridge:
    def __init__(
        self,
        snapshot_provider: Callable[[], Mapping[str, Any]],
        command_handler: Callable[[str, Mapping[str, Any]], None],
        *,
        bus_name: str = DEFAULT_BUS_NAME,
        connection: Any = None,
    ) -> None:
        self._snapshot_provider = snapshot_provider
        self._command_handler = command_handler
        self.bus_name = bus_name
        self.connection = connection
        self._root_registration = 0
        self._player_registration = 0
        self.name_acquired = False

    def start(self) -> None:
        if Gio is None or GLib is None:
            raise MprisBridgeError(f"PyGObject is required for MPRIS: {_GI_IMPORT_ERROR}")
        if self.name_acquired:
            raise MprisBridgeError("MPRIS bridge is already started")

        self.connection = self.connection or Gio.bus_get_sync(Gio.BusType.SESSION, None)
        try:
            self._claim_bus_name()
            root_info = Gio.DBusNodeInfo.new_for_xml(ROOT_XML).interfaces[0]
            player_info = Gio.DBusNodeInfo.new_for_xml(PLAYER_XML).interfaces[0]
            self._root_registration = self.connection.register_object(
                MPRIS_OBJECT_PATH,
                root_info,
                self._handle_root_method,
                self._get_root_property,
                None,
            )
            self._player_registration = self.connection.register_object(
                MPRIS_OBJECT_PATH,
                player_info,
                self._handle_player_method,
                self._get_player_property,
                self._set_player_property,
            )
        except Exception:
            self.stop()
            raise

    def _claim_bus_name(self) -> None:
        result = self.connection.call_sync(
            DBUS_DAEMON_NAME,
            DBUS_DAEMON_PATH,
            DBUS_DAEMON_INTERFACE,
            "RequestName",
            GLib.Variant("(su)", (self.bus_name, DBUS_NAME_FLAG_DO_NOT_QUEUE)),
            GLib.VariantType.new("(u)"),
            Gio.DBusCallFlags.NONE,
            -1,
            None,
        )
        reply = result.unpack()[0]
        if reply != DBUS_REQUEST_NAME_PRIMARY_OWNER:
            raise MprisBridgeError(f"MPRIS bus name is already owned: {self.bus_name}")
        self.name_acquired = True

    def _release_bus_name(self) -> None:
        if not self.name_acquired or self.connection is None:
            return
        try:
            self.connection.call_sync(
                DBUS_DAEMON_NAME,
                DBUS_DAEMON_PATH,
                DBUS_DAEMON_INTERFACE,
                "ReleaseName",
                GLib.Variant("(s)", (self.bus_name,)),
                GLib.VariantType.new("(u)"),
                Gio.DBusCallFlags.NONE,
                -1,
                None,
            )
        finally:
            self.name_acquired = False

    def stop(self) -> None:
        if self.connection is not None and self._root_registration:
            self.connection.unregister_object(self._root_registration)
        if self.connection is not None and self._player_registration:
            self.connection.unregister_object(self._player_registration)
        self._root_registration = 0
        self._player_registration = 0
        self._release_bus_name()

    def _snapshot(self) -> Mapping[str, Any]:
        result = self._snapshot_provider()
        if not isinstance(result, Mapping):
            raise MprisBridgeError("snapshot_provider must return a mapping")
        return result

    def _root_variant(self, property_name: str) -> Any:
        snapshot = self._snapshot()
        values = {
            "CanQuit": bool(snapshot.get("canQuit", True)),
            "CanRaise": bool(snapshot.get("canRaise", True)),
            "HasTrackList": False,
            "Identity": str(snapshot.get("identity", "II Music")),
            "DesktopEntry": str(snapshot.get("desktopEntry", "ii-local-music")),
            "SupportedUriSchemes": ["file"],
            "SupportedMimeTypes": list(snapshot.get("supportedMimeTypes", [])),
        }
        if property_name not in values:
            return None
        type_string = {
            "CanQuit": "b", "CanRaise": "b", "HasTrackList": "b", "Identity": "s",
            "DesktopEntry": "s", "SupportedUriSchemes": "as", "SupportedMimeTypes": "as",
        }[property_name]
        return GLib.Variant(type_string, values[property_name])

    def _metadata_variant(self, snapshot: Mapping[str, Any]) -> Any:
        track = snapshot.get("track")
        if not isinstance(track, Mapping):
            return GLib.Variant("a{sv}", {})
        entry_id = str(track.get("entryId", ""))
        if not entry_id:
            return GLib.Variant("a{sv}", {})
        metadata: dict[str, Any] = {
            "mpris:trackid": GLib.Variant("o", track_object_path(entry_id)),
            "xesam:title": GLib.Variant("s", str(track.get("title", ""))),
            "xesam:artist": GLib.Variant("as", [str(value) for value in track.get("artists", [])]),
        }
        if track.get("album"):
            metadata["xesam:album"] = GLib.Variant("s", str(track["album"]))
        if track.get("artUrl"):
            metadata["mpris:artUrl"] = GLib.Variant("s", str(track["artUrl"]))
        if track.get("durationSec") is not None:
            metadata["mpris:length"] = GLib.Variant("x", seconds_to_microseconds(track["durationSec"]))
        return GLib.Variant("a{sv}", metadata)

    def _player_variant(self, property_name: str) -> Any:
        snapshot = self._snapshot()
        raw_status = str(snapshot.get("playbackStatus", "Stopped")).lower()
        playback_status = {"playing": "Playing", "paused": "Paused", "stopped": "Stopped"}.get(raw_status, "Stopped")
        values = {
            "PlaybackStatus": GLib.Variant("s", playback_status),
            "LoopStatus": GLib.Variant("s", str(snapshot.get("loopStatus", "None"))),
            "Rate": GLib.Variant("d", float(snapshot.get("rate", 1.0))),
            "Shuffle": GLib.Variant("b", bool(snapshot.get("shuffle", False))),
            "Metadata": self._metadata_variant(snapshot),
            "Volume": GLib.Variant("d", min(1.0, max(0.0, float(snapshot.get("volume", 1.0))))),
            "Position": GLib.Variant("x", seconds_to_microseconds(snapshot.get("positionSec", 0))),
            "MinimumRate": GLib.Variant("d", float(snapshot.get("minimumRate", 0.25))),
            "MaximumRate": GLib.Variant("d", float(snapshot.get("maximumRate", 2.0))),
            "CanGoNext": GLib.Variant("b", bool(snapshot.get("canGoNext", False))),
            "CanGoPrevious": GLib.Variant("b", bool(snapshot.get("canGoPrevious", False))),
            "CanPlay": GLib.Variant("b", bool(snapshot.get("canPlay", False))),
            "CanPause": GLib.Variant("b", bool(snapshot.get("canPause", False))),
            "CanSeek": GLib.Variant("b", bool(snapshot.get("canSeek", False))),
            "CanControl": GLib.Variant("b", bool(snapshot.get("canControl", False))),
        }
        return values.get(property_name)

    def _get_root_property(self, _connection: Any, _sender: str, _path: str, _interface: str, property_name: str) -> Any:
        return self._root_variant(property_name)

    def _get_player_property(self, _connection: Any, _sender: str, _path: str, _interface: str, property_name: str) -> Any:
        return self._player_variant(property_name)

    def _invoke(self, command: str, payload: Mapping[str, Any], invocation: Any) -> None:
        try:
            self._command_handler(command, payload)
        except Exception as error:
            invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.FAILED, str(error))
            return
        invocation.return_value(None)

    def _handle_root_method(self, _connection: Any, _sender: str, _path: str, _interface: str, method: str, _parameters: Any, invocation: Any) -> None:
        if method == "Raise":
            self._invoke("raise", {}, invocation)
        elif method == "Quit":
            self._invoke("quit", {}, invocation)
        else:
            invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, method)

    def _handle_player_method(self, _connection: Any, _sender: str, _path: str, _interface: str, method: str, parameters: Any, invocation: Any) -> None:
        direct_commands = {
            "Next": "next", "Previous": "previous", "Pause": "pause", "PlayPause": "playPause",
            "Stop": "stop", "Play": "play",
        }
        if method in direct_commands:
            self._invoke(direct_commands[method], {}, invocation)
        elif method == "Seek":
            self._invoke("seekRelative", {"offsetSec": microseconds_to_seconds(parameters.unpack()[0])}, invocation)
        elif method == "SetPosition":
            track_id, position = parameters.unpack()
            self._invoke("setPosition", {"trackObjectPath": track_id, "positionSec": microseconds_to_seconds(position)}, invocation)
        elif method == "OpenUri":
            self._invoke("openUri", {"uri": parameters.unpack()[0]}, invocation)
        else:
            invocation.return_error_literal(Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, method)

    def _set_player_property(self, _connection: Any, _sender: str, _path: str, _interface: str, property_name: str, value: Any) -> bool:
        supported = {"LoopStatus": "setLoopStatus", "Rate": "setRate", "Shuffle": "setShuffle", "Volume": "setVolume"}
        command = supported.get(property_name)
        if command is None:
            return False
        try:
            self._command_handler(command, {"value": value.unpack()})
        except Exception:
            return False
        return True

    def publish(self, changed_properties: tuple[str, ...] | None = None, *, seeked_position_sec: float | None = None) -> None:
        if self.connection is None or GLib is None:
            return
        changed_properties = changed_properties or (
            "PlaybackStatus", "LoopStatus", "Rate", "Shuffle", "Metadata", "Volume", "Position",
            "CanGoNext", "CanGoPrevious", "CanPlay", "CanPause", "CanSeek", "CanControl",
        )
        changed = {
            property_name: variant
            for property_name in changed_properties
            if (variant := self._player_variant(property_name)) is not None
        }
        self.connection.emit_signal(
            None,
            MPRIS_OBJECT_PATH,
            PROPERTIES_INTERFACE,
            "PropertiesChanged",
            GLib.Variant("(sa{sv}as)", (PLAYER_INTERFACE, changed, [])),
        )
        if seeked_position_sec is not None:
            self.connection.emit_signal(
                None,
                MPRIS_OBJECT_PATH,
                PLAYER_INTERFACE,
                "Seeked",
                GLib.Variant("(x)", (seconds_to_microseconds(seeked_position_sec),)),
            )
