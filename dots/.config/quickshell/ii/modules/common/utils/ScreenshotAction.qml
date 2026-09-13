pragma ComponentBehavior: Bound
pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import Qt.labs.synchronizer
import Quickshell

Singleton {
    id: root

    enum Action {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound,
        AskAI
    }

    property string imageSearchEngineBaseUrl: Config.options.search.imageSearch.imageSearchEngineBaseUrl
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    function playShutterSound(action) {
        if (action === ScreenshotAction.Action.Record || action === ScreenshotAction.Action.RecordWithSound)
            return;
        SoundService.playEvent("screenshot", ["camera-shutter", "screen-capture"]);
    }

    /**
     * `aiPath`, when given, is where the AskAI crop is written. The chat used
     * to fish the shot back out of the clipboard, which meant waiting a guessed
     * number of milliseconds for cliphist to have noticed it; a file it was
     * told the name of needs no guessing.
     */
    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "", aiPath = "", recordGeometry = null) {
        // Set command for action
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);
        const cropBase = `magick ${StringUtils.shellSingleQuoteEscape(screenshotPath)} ` + `-crop ${rw}x${rh}+${rx}+${ry} +repage`;
        // Force PNG so clipboard/tesseract stay PNG even when grim writes ppm.
        const cropToStdout = `${cropBase} png:-`;
        const cropInPlace = `${cropBase} 'png:${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`;
        const cleanup = (Config.options.regionSelector.enableOverlay ?? true) ? ":" : `rm '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`;
        // Screenshot crops use native pixels, while wf-recorder expects the
        // compositor's logical, global geometry. Callers provide that second
        // coordinate space explicitly for recording actions.
        const recordX = Math.round(recordGeometry ? recordGeometry.x : x);
        const recordY = Math.round(recordGeometry ? recordGeometry.y : y);
        const recordWidth = Math.round(recordGeometry ? recordGeometry.width : width);
        const recordHeight = Math.round(recordGeometry ? recordGeometry.height : height);
        const slurpRegion = `${recordX},${recordY} ${recordWidth}x${recordHeight}`;
        const uploadAndGetUrl = filePath => {
            return `curl -sF files[]=@'${StringUtils.shellSingleQuoteEscape(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`;
        };
        const annotationCommand = `${Config.options.regionSelector.annotation.useSatty ? "satty" : "swappy"} -f -`;
        switch (action) {
        case ScreenshotAction.Action.Copy:
            const copyNotify = (Config.options.regionSelector.copyNotification ?? false)
                ? " && notify-send -i camera-photo -t 4000 'Screenshot copied' 'Copied to clipboard'"
                : "";
            if (saveDir === "") {
                return ["bash", "-c", `${cropToStdout} | wl-copy${copyNotify} && ${cleanup}`];
            } else {
                const targetSaveDir = saveDir.replace(/^file:\/\//, "");
                return ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(targetSaveDir)}' && \
                        saveFileName="screenshot-$(date '+%Y-%m-%d_%H.%M.%S').png" && \
                        savePath="${targetSaveDir}/$saveFileName" && \
                        ${cropToStdout} | tee >(wl-copy) > "$savePath" && \
                        notify-send -i camera-photo -t 4000 'Screenshot saved' "Saved to: $savePath" && \
                        ${cleanup}`];
            }
            break;
        case ScreenshotAction.Action.Edit:
            return ["bash", "-c", `${cropToStdout} | ${annotationCommand} && ${cleanup}`];
            break;
        case ScreenshotAction.Action.Search:
            return ["bash", "-c", `${cropInPlace} && xdg-open "${root.imageSearchEngineBaseUrl}$(${uploadAndGetUrl(screenshotPath)})" && ${cleanup}`];
            break;
        case ScreenshotAction.Action.AskAI:
            if (aiPath === "") {
                return ["bash", "-c", `${cropToStdout} | wl-copy && ${cleanup}`];
            }
            // Written first, copied from the file after, so the chat can watch
            // for the one and the clipboard still gets the other. The folder
            // is made here rather than trusted to exist: it lives under /tmp,
            // where it is created once at startup and can be swept away
            // underneath a running shell, and a crop into a missing folder
            // fails silently — the chat then waits for a file that never comes.
            const quotedAiPath = `'${StringUtils.shellSingleQuoteEscape(aiPath)}'`;
            return ["bash", "-c", `mkdir -p "$(dirname ${quotedAiPath})" && ${cropBase} ${quotedAiPath} && wl-copy < ${quotedAiPath} && ${cleanup}`];
            break;
        case ScreenshotAction.Action.CharRecognition:
            return ["bash", "-c", `${cropInPlace} && tesseract '${StringUtils.shellSingleQuoteEscape(screenshotPath)}' stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\\n' '+' | sed 's/\\+$/\\n/') | wl-copy && ${cleanup}`];
            break;
        case ScreenshotAction.Action.Record:
            return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}'`];
            break;
        case ScreenshotAction.Action.RecordWithSound:
            return ["bash", "-c", `${Directories.recordScriptPath} --region '${slurpRegion}' --sound`];
            break;
        default:
            console.warn("[Region Selector] Unknown snip action, skipping snip.");
            return;
        }
    }
}
