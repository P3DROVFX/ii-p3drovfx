pragma ComponentBehavior: Bound

import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Play buttons for a side's [sound:] clips (Anki's own replay buttons, as chips).
 * Text-to-speech tags have no engine here and are skipped.
 */
Flow {
    id: root

    property var clips: []
    readonly property var files: root.clips.filter(c => c.kind === "file")

    visible: root.files.length > 0
    spacing: 4

    Repeater {
        model: root.files

        AnkiChip {
            required property var modelData
            required property int index
            symbol: "play_arrow"
            label: root.files.length > 1 ? Translation.tr("Play %1").arg(index + 1) : Translation.tr("Play")
            onClicked: Anki.play(modelData.path)
        }
    }
}
