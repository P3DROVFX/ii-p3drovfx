#!/usr/bin/env python3
"""Put a file on the Wayland clipboard the way a file manager's Copy does.

`wl-copy --type text/uri-list` offers a single MIME type, and every target
picks a different one when deciding that a paste is a *file* and not text:
Electron and Qt apps (Discord, Telegram) and Chromium read `text/uri-list`,
GTK3 file managers (Nemo, Thunar, Caja) read `x-special/gnome-copied-files`,
and GTK4 apps go through the xdg-desktop-portal transfer types. GTK's own
file-list provider offers all of them at once, which is what a file manager
itself puts on the clipboard when you press Ctrl+C on a file.

The process owns the selection, so it stays alive until another client takes
the clipboard -- the same lifetime rule `wl-copy` follows. Without GTK, or
without a display, the copy falls back to a plain
`wl-copy --type text/uri-list`.

Usage: copy_file_to_clipboard.py /absolute/path/to/file
"""

import os
import sys
from urllib.parse import quote


def uri_for(path):
    return "file://" + quote(path)


def copy_with_wl_clipboard(uri):
    os.execvp("wl-copy", ["wl-copy", "--type", "text/uri-list", uri])


def copy_with_gtk(path, uri):
    import gi

    gi.require_version("Gdk", "4.0")
    gi.require_version("Gtk", "4.0")
    from gi.repository import Gdk, Gio, GLib, Gtk

    Gtk.init()
    display = Gdk.Display.get_default()
    if display is None:
        raise RuntimeError("no display")

    clipboard = display.get_clipboard()
    loop = GLib.MainLoop()
    ours = False

    def on_changed(_clipboard):
        nonlocal ours
        if clipboard.is_local():
            ours = True
        elif ours:
            # Another client took the selection; nothing left to serve.
            loop.quit()

    clipboard.connect("changed", on_changed)
    target = Gio.File.new_for_path(path)
    clipboard.set_content(Gdk.ContentProvider.new_union([
        Gdk.ContentProvider.new_for_bytes("x-special/gnome-copied-files",
                                          GLib.Bytes.new(f"copy\n{uri}".encode())),
        Gdk.ContentProvider.new_for_value(Gdk.FileList.new_from_list([target])),
    ]))
    loop.run()


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} PATH", file=sys.stderr)
        return 2

    path = os.path.abspath(sys.argv[1])
    if not os.path.isfile(path):
        print(f"not a file: {path}", file=sys.stderr)
        return 1

    uri = uri_for(path)
    try:
        copy_with_gtk(path, uri)
    except Exception as error:
        print(f"gtk clipboard unavailable ({error}); falling back to wl-copy", file=sys.stderr)
        copy_with_wl_clipboard(uri)
    return 0


if __name__ == "__main__":
    sys.exit(main())
