#!/usr/bin/env python3
"""Select one local file or folder through the user's XDG portal; exit with the dialog."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys

from gi.repository import Gio, GLib, GLibUnix


def fallback_picker(title: str, folder: str, is_dir: bool) -> str | None:
    cmd = []
    if is_dir:
        if shutil.which("zenity"):
            cmd = ["zenity", "--file-selection", "--directory", f"--title={title}"]
            if folder:
                cmd.append(f"--filename={folder}/")
        elif shutil.which("kdialog"):
            cmd = ["kdialog", "--title", title, "--getexistingdirectory", folder or os.path.expanduser("~")]
    else:
        if shutil.which("zenity"):
            cmd = ["zenity", "--file-selection", f"--title={title}"]
        elif shutil.which("kdialog"):
            cmd = ["kdialog", "--title", title, "--getopenfilename", folder or os.path.expanduser("~")]
    if cmd:
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            if res.returncode == 0:
                out = res.stdout.strip()
                if out:
                    return out
        except Exception:
            pass
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", required=False, default="Select file")
    parser.add_argument("--folder", required=False, default="")
    parser.add_argument("--filters", required=False, default="[]")
    parser.add_argument("--directory", action="store_true", help="Select directory instead of file")
    parser.add_argument("--profile-dir")
    args = parser.parse_args()

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    loop = GLib.MainLoop()
    token = f"picker_{os.getpid()}"
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
        folder = Gio.File.new_for_commandline_arg(args.folder).get_path() if args.folder else None
        options = {
            "handle_token": GLib.Variant("s", token),
            "multiple": GLib.Variant("b", False),
        }
        if args.directory:
            options["directory"] = GLib.Variant("b", True)
        elif args.filters:
            filters = []
            for name_filter in json.loads(args.filters):
                label, _, patterns = name_filter.rpartition("(")
                filters.append((label.strip(), [(0, pattern) for pattern in patterns.rstrip(")").split()]))
            if filters:
                options["filters"] = GLib.Variant("a(sa(us))", filters)

        if folder:
            options["current_folder"] = GLib.Variant("ay", os.fsencode(folder) + b"\0")
        bus.call_sync(
            "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.FileChooser", "OpenFile",
            GLib.Variant("(ssa{sv})", ("", args.title, options)),
            GLib.VariantType.new("(o)"), Gio.DBusCallFlags.NONE, 10000, None,
        )
        loop.run()
    except Exception as err:
        fallback = fallback_picker(args.title, args.folder, args.directory)
        if fallback:
            if args.directory and not Path(fallback).is_dir():
                raise ValueError("The selected path must be a local directory")
            elif not args.directory and not Path(fallback).is_file():
                raise ValueError("The selected path must be a local file")
            print(json.dumps(fallback), flush=True)
            return 0
        raise err
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
        raise ValueError("The desktop portal could not complete selection")
    uris = response[1].get("uris", [])
    path = Gio.File.new_for_uri(uris[0]).get_path() if uris else None
    if args.directory:
        if not path or not Path(path).is_dir():
            raise ValueError("The selected path must be a local directory")
    else:
        if not path or not Path(path).is_file():
            raise ValueError("The selected file must be a local file")
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
        print(f"File picker: {error}", file=sys.stderr)
        sys.exit(2)
