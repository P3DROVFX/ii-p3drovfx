pragma ComponentBehavior: Bound

import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Uses the user's XDG portal and preserves the profile copies shared by
 * Settings and Welcome. The helper exits on selection or cancellation.
 */
Process {
    id: root

    /** Ignore repeated clicks while a selection is already in progress. */
    function pick(): void {
        if (!root.running)
            root.running = true;
    }

    command: ["python3", Directories.scriptPath + "/image_picker.py",
        "--title", Translation.tr("Select profile image"),
        "--folder", Directories.home,
        "--filters", JSON.stringify(["Images (*.png *.jpg *.jpeg *.gif *.webp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP)"]),
        "--profile-dir", Directories.shellConfig]

    stdout: StdioCollector {
        onStreamFinished: {
            if (!text.trim())
                return;
            const targetPath = JSON.parse(text);
            // Clear first to reload even when the filename has not changed.
            Config.options.userProfile.imagePath = "";
            Config.options.userProfile.imagePath = targetPath;
        }
    }
}
