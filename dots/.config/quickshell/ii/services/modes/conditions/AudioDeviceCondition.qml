import QtQuick
import Quickshell.Services.Pipewire
import ".."

/**
 * The default sink (`kind: sink`) or source (`kind: source`) has `match` in
 * its name or description. The default node can be null for a frame while
 * PipeWire switches devices; that is treated as "no change".
 */
ModeCondition {
    id: root
    readonly property string match: String(root.params?.match ?? "").toLowerCase()
    readonly property bool useSource: root.params?.kind === "source"
    readonly property var node: root.useSource ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink

    property string deviceText: ""
    readonly property string liveText: root.node
        ? `${root.node.description ?? ""} ${root.node.nickname ?? ""} ${root.node.name ?? ""}`.toLowerCase()
        : ""
    onLiveTextChanged: {
        if (root.node)
            root.deviceText = root.liveText;
    }
    Component.onCompleted: {
        if (root.node)
            root.deviceText = root.liveText;
    }

    satisfied: root.match.length > 0 && root.deviceText.indexOf(root.match) !== -1
    reason: root.node?.description ?? ""
}
