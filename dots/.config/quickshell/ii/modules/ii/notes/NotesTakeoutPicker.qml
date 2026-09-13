pragma ComponentBehavior: Bound

import Quickshell.Io

/**
 * The system folder chooser, for a Google Takeout export.
 *
 * The same shape as `UserProfileImagePicker`: `kdialog` if it is there, `zenity`
 * otherwise, and nothing at all if neither is — a shell has no business drawing its own
 * file browser to pick one directory once.
 *
 * The importer wants the folder that *contains* the Keep JSON files, which in a Takeout
 * archive is `Takeout/Keep`. Pointing it at the archive root works too: the script walks
 * what it is given.
 */
Process {
    id: root

    signal picked(string path)
    /// True while the dialog is up, so a button can say so instead of looking dead.
    property bool choosing: false

    function pick(): void {
        root.running = false;
        root.choosing = true;
        root.running = true;
    }

    command: ["bash", "-c",
        "if command -v kdialog >/dev/null 2>&1; then "
        + "DIR=$(kdialog --getexistingdirectory \"$HOME\" 2>/dev/null); "
        + "elif command -v zenity >/dev/null 2>&1; then "
        + "DIR=$(zenity --file-selection --directory 2>/dev/null); fi; "
        + "if [ -n \"$DIR\" ] && [ -d \"$DIR\" ]; then printf '%s' \"$DIR\"; fi"]

    onExited: root.choosing = false

    stdout: StdioCollector {
        id: chosen
        onStreamFinished: {
            const path = chosen.text.trim();
            if (path.length > 0)
                root.picked(path);
        }
    }
}
