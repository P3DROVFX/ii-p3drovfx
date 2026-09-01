import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: screenshotProc
    running: true
    property string screenshotDir: Directories.screenshotTemp
    required property ShellScreen screen
    property string screenshotPath: `${screenshotDir}/image-${screen.name}`
    property bool completed: false
    property int startedToken: 0
    property bool restarting: false
    // grim output format. ppm skips PNG compression, which is the slow part of
    // grim, but the file is then only safe for consumers that sniff the format
    // (magick/Qt/OpenCV). Anything shipping the bytes as-is to an external API
    // must stay on png, so this is opt-in rather than the default.
    property string format: "png"
    command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(screenshotDir)}' && exec grim -t ${StringUtils.shellSingleQuoteEscape(format)} -o '${StringUtils.shellSingleQuoteEscape(screen.name)}' '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`]

    // runningChanged is emitted from Process::onFinished, never synchronously
    // from `running = false` (that only sends SIGTERM), so the restart guard has
    // to be cleared here — otherwise a terminated grim reports its truncated
    // file as a finished capture.
    onRunningChanged: {
        if (running) {
            screenshotProc.completed = false;
            return;
        }
        if (screenshotProc.restarting) {
            screenshotProc.restarting = false;
            return;
        }
        if (screenshotProc.startedToken === 0)
            return;
        screenshotProc.completed = true;
    }

    function recapture(token) {
        screenshotProc.completed = false;
        screenshotProc.startedToken = token;
        if (screenshotProc.running)
            screenshotProc.restarting = true;
        // Process restarts itself on finish when running is set back to true.
        screenshotProc.running = false;
        screenshotProc.running = true;
    }
}
