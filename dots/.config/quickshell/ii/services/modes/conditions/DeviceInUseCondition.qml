import QtQuick
import Quickshell.Services.Pipewire
import ".."

/**
 * An app is using the microphone (`what: mic`), a camera (`camera`) or
 * capturing the screen (`screen`), judged from the PipeWire links the
 * privacy indicator already watches. Cameras are video sources whose name
 * says so; any other video source being read is taken as screen capture.
 */
ModeCondition {
    id: root
    readonly property string what: ["mic", "camera", "screen"].indexOf(root.params?.what) !== -1
        ? root.params.what : "mic"

    function isCamera(node) {
        const text = `${node?.name ?? ""} ${node?.description ?? ""} ${node?.nickname ?? ""}`;
        return /camera|webcam|v4l2|uvc/i.test(text);
    }

    readonly property var links: Array.from(Pipewire.linkGroups?.values ?? [])
    readonly property var matching: root.links.filter(g => {
        const src = g?.source;
        const dst = g?.target;
        if (!src || !dst)
            return false;
        if (root.what === "mic")
            return src.type === PwNodeType.AudioSource && dst.type === PwNodeType.AudioInStream;
        if (src.type !== PwNodeType.VideoSource)
            return false;
        return root.what === "camera" ? root.isCamera(src) : !root.isCamera(src);
    })

    satisfied: root.matching.length > 0
    reason: {
        const g = root.matching[0];
        if (!g)
            return "";
        return String(g.target?.properties?.["application.name"] ?? g.target?.name ?? "");
    }
}
