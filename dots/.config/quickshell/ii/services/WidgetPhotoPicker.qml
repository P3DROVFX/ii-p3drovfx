pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

Singleton {
    id: root

    readonly property bool picking: picker.running
    property string targetEntryName: ""

    function pick(configEntryName: string): void {
        if (root.picking || !Config.options.background.widgets[configEntryName])
            return;
        // Capture the destination before dismissing the transient settings page.
        root.targetEntryName = configEntryName;
        picker.running = true;
        GlobalStates.closeEditWidgetMenu();
    }

    // The process and its result must outlive the Edit Mode menu that opens it.
    Process {
        id: picker
        command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP *.BMP *.SVG\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg *.gif *.webp *.bmp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP *.BMP *.SVG\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then printf '%s' \"$FILE\"; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = this.text;
                const entry = Config.options.background.widgets[root.targetEntryName];
                if (path.length > 0 && entry)
                    entry.imagePath = path;
            }
        }
    }
}
