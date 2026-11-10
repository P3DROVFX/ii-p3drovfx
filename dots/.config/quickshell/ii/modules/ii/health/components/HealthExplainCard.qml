pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A finding in plain words, for someone who does not know Linux's vocabulary: what
 * happened, whether it matters, what to do. The text comes from HealthText.explain,
 * explainCrash or explainJournal; the technical facts stay below it, for whoever wants
 * them. Takes no room when there is nothing to say.
 */
Rectangle {
    id: root

    /// { what, matters, todo }, or null.
    property var explanation: null

    readonly property var parts: root.explanation ? [
        ["info", Translation.tr("What happened"), root.explanation.what],
        ["help", Translation.tr("Does it matter?"), root.explanation.matters],
        ["lightbulb", Translation.tr("What to do"), root.explanation.todo]
    ].filter(p => String(p[2] ?? "").length > 0) : []

    visible: root.parts.length > 0
    implicitHeight: column.implicitHeight + ClockStyle.cardPadding * 2
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colSurfaceHigh

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: ClockStyle.cardPadding
        }
        spacing: ClockStyle.gap

        Repeater {
            // Re-made when the finding is re-sent: the parts update in place.
            model: ScriptModel {
                values: root.parts
            }

            ColumnLayout {
                id: part
                required property var modelData
                Layout.fillWidth: true
                spacing: ClockStyle.gapTiny

                RowLayout {
                    spacing: ClockStyle.gapSmall
                    MaterialSymbol {
                        text: part.modelData[0]
                        iconSize: ClockStyle.iconSmall
                        fill: 1
                        color: ClockStyle.colPrimary
                    }
                    StyledText {
                        text: part.modelData[1]
                        font.pixelSize: ClockStyle.textSmall + 1
                        font.weight: Font.Bold
                        color: ClockStyle.colPrimary
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: part.modelData[2]
                    wrapMode: Text.Wrap
                    font.pixelSize: ClockStyle.textNormal + 1
                    color: ClockStyle.colOnSurface
                }
            }
        }
    }
}
