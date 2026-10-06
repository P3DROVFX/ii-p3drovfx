pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property bool picking: picker.running
    property string targetEntryName: ""
    // The instance the picture is for: the widget whose Edit Mode menu opened
    // the page. Empty from the Settings app, which sets the type's picture.
    property string targetInstanceId: ""
    property var customCallback: null
    signal fileSelected(string path)

    function pick(configEntryName: string): void {
        if (root.picking || !Config.options.background.widgets[configEntryName])
            return;
        root.customCallback = null;
        // Capture the destination before dismissing the transient settings page.
        root.targetEntryName = configEntryName;
        root.targetInstanceId = root.menuInstance();
        picker.running = true;
        GlobalStates.closeEditWidgetMenu();
    }

    // The widget whose menu is open, if it is still on the desktop.
    function menuInstance(): string {
        const id = GlobalStates.editWidgetMenuInstanceId;
        return id !== "" && WidgetPlacement.findEntry(Config.options.background.activeWidgets, id) ? id : "";
    }

    // The picture the open page is about: the instance's own when it has one,
    // else the type's. What "Current image" shows and "Remove Image" clears.
    function currentPath(configEntryName: string): string {
        const id = root.menuInstance();
        const entry = id !== "" ? WidgetPlacement.findEntry(Config.options.background.activeWidgets, id) : null;
        if (entry && entry.imagePath !== undefined)
            return String(entry.imagePath);
        return String(Config.options.background.widgets[configEntryName]?.imagePath ?? "");
    }

    function clear(configEntryName: string): void {
        const id = root.menuInstance();
        if (id !== "") {
            Config.updateWidgetImagePath(id, "");
            return;
        }
        const entry = Config.options.background.widgets[configEntryName];
        if (entry)
            entry.imagePath = "";
    }

    function pickWithCallback(cb): void {
        if (root.picking)
            return;
        root.targetEntryName = "";
        root.customCallback = cb;
        picker.running = true;
    }

    // The process and its result must outlive the Edit Mode menu that opens it.
    Process {
        id: picker
        command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP *.BMP *.SVG\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP *.BMP *.SVG\" 2>/dev/null); fi; if [ -n \"$FILE\" ]; then FILE=\"${FILE#file://}\"; printf '%s' \"$FILE\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                let path = this.text.trim();
                if (path.startsWith("file://")) {
                    path = path.slice(7);
                }
                try {
                    path = decodeURIComponent(path);
                } catch (e) {}
                if (path.length > 0) {
                    root.fileSelected(path);
                    if (root.customCallback) {
                        const cb = root.customCallback;
                        root.customCallback = null;
                        cb(path);
                        return;
                    }
                    if (root.targetInstanceId !== "") {
                        Config.updateWidgetImagePath(root.targetInstanceId, path);
                        return;
                    }
                    const entry = Config.options.background.widgets[root.targetEntryName];
                    if (entry)
                        entry.imagePath = path;
                } else {
                    root.customCallback = null;
                }
            }
        }
    }
}
