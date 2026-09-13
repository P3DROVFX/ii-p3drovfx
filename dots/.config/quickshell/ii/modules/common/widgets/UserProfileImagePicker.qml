pragma ComponentBehavior: Bound

import Quickshell.Io
import qs.modules.common

/**
 * The system file dialog for the profile picture, and the copy into the
 * shell's own config directory that follows it.
 *
 * Settings and the Welcome both offer this choice. The command behind it is a
 * long shell one-liner that has to pick between kdialog and zenity and then
 * land the file in two places; kept in one component so the two callers
 * cannot drift into disagreeing about where a profile picture lives.
 */
Process {
    id: root

    /** Opens the dialog. Restarting is how a second pick is requested. */
    function pick(): void {
        root.running = false;
        root.running = true;
    }

    command: ["bash", "-c", "if command -v kdialog &> /dev/null; then FILE=$(kdialog --getopenfilename \"$HOME\" \"*.png *.jpg *.jpeg *.gif *.webp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP\" 2>/dev/null); elif command -v zenity &> /dev/null; then FILE=$(zenity --file-selection --file-filter=\"Images | *.png *.jpg *.jpeg *.gif *.webp *.svg *.PNG *.JPG *.JPEG *.GIF *.WEBP\" 2>/dev/null); fi; if [ -n \"$FILE\" ] && [ -f \"$FILE\" ]; then EXT=\"${FILE##*.}\"; mkdir -p ~/.config/illogical-impulse && cp \"$FILE\" \"$HOME/.config/illogical-impulse/profile.${EXT}\" && cp \"$FILE\" ~/.config/illogical-impulse/profile.png; echo \"$EXT\"; fi"]

    stdout: SplitParser {
        onRead: data => {
            const ext = data.trim();
            if (ext.length === 0)
                return;
            // The path is cleared first so the image reloads even when the new
            // file has the same name as the old one.
            const targetPath = Directories.shellConfig + "/profile." + ext;
            Config.options.userProfile.imagePath = "";
            Config.options.userProfile.imagePath = targetPath;
        }
    }
}
