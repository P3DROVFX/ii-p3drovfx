#!/usr/bin/env python3
"""Select one local image through the user's XDG portal; exit with the dialog."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import sys

from gi.repository import Gio, GLib, GLibUnix


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=True)
    parser.add_argument("--folder", required=True)
    parser.add_argument("--filters", required=True)
    parser.add_argument("--profile-dir")
    args = parser.parse_args()

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    token = f"image_picker_{os.getpid()}"
    sender = bus.get_unique_name()[1:].replace(".", "_")
    request_path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    response = None

    def on_response(connection, sender_name, object_path, interface, name, parameters):
        nonlocal response
        response = parameters.unpack()
        loop.quit()

    subscription = bus.signal_subscribe(
        "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Request",
        "Response", request_path, None, Gio.DBusSignalFlags.NONE, on_response,
    )
    signals = [GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, sig, loop.quit)
               for sig in (signal.SIGTERM, signal.SIGINT)]
    try:
        filters = []
        for name_filter in json.loads(args.filters):
            label, _, patterns = name_filter.rpartition("(")
            filters.append((label.strip(), [(0, pattern) for pattern in patterns.rstrip(")").split()]))
        folder = Gio.File.new_for_commandline_arg(args.folder).get_path()
        options = {
            "handle_token": GLib.Variant("s", token),
            "multiple": GLib.Variant("b", False),
            "filters": GLib.Variant("a(sa(us))", filters),
        }
        if folder:
            options["current_folder"] = GLib.Variant("ay", os.fsencode(folder) + b"\0")
        bus.call_sync(
            "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.FileChooser", "OpenFile",
            GLib.Variant("(ssa{sv})", ("", args.title, options)),
            GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 10000, None,
        )
        loop.run()
    finally:
        if response is None:
            bus.call_sync(
                "org.freedesktop.portal.Desktop", request_path,
                "org.freedesktop.portal.Request", "Close", None, None,
                Gio.DBusCallFlags.NONE, 1000, None,
            )
        bus.signal_unsubscribe(subscription)
        for source in signals:
            if GLib.MainContext.default().find_source_by_id(source):
                GLib.source_remove(source)

    if response is None or response[0] == 1:
        return 0
    if response[0] != 0:
        raise ValueError("The desktop portal could not select an image")
    uris = response[1].get("uris", [])
    path = Gio.File.new_for_uri(uris[0]).get_path() if uris else None
    if not path or not Path(path).is_file():
        raise ValueError("The selected image must be a local file")
    if args.profile_dir:
        directory = Path(args.profile_dir)
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / f"profile{Path(path).suffix}"
        for destination in dict.fromkeys((target, directory / "profile.png")):
            if not destination.exists() or not os.path.samefile(path, destination):
                shutil.copyfile(path, destination)
        path = str(target)
    print(json.dumps(path), flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (GLib.Error, OSError, ValueError) as error:
        print(f"Image picker: {error}", file=sys.stderr)
        sys.exit(2)
