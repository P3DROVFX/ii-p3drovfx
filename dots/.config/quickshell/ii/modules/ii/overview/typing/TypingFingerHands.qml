pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// A compact hand-shaped legend: finger length and mirrored order make the
// map readable before learning the colors. Numbers are anatomical (thumb=1).
GridLayout {
    id: root
    property var activeFingers: []
    property bool stacked: false
    columns: root.stacked ? 1 : 2
    columnSpacing: 20
    rowSpacing: 12

    Repeater {
        model: [false, true]
        delegate: ColumnLayout {
            id: hand
            required property bool modelData
            readonly property var fingers: modelData ? [1, 2, 3, 4, 5] : [-5, -4, -3, -2, -1]
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 5
                Repeater {
                    model: hand.fingers
                    delegate: Rectangle {
                        id: finger
                        required property int modelData
                        readonly property bool active: root.activeFingers.indexOf(modelData) >= 0
                            || (Math.abs(modelData) === 1 && root.activeFingers.indexOf(6) >= 0)
                        Layout.alignment: Qt.AlignBottom
                        implicitWidth: 24
                        implicitHeight: [0, 24, 36, 44, 38, 29][Math.abs(modelData)]
                        radius: Appearance.rounding.full
                        color: active ? Appearance.colors.colPrimary : TypingFingerPalette.fill(modelData)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: TypingFingerPalette.name(modelData)
                        StyledText {
                            anchors.centerIn: parent
                            text: String(Math.abs(finger.modelData))
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: finger.active ? Font.Bold : Font.Medium
                            color: finger.active ? Appearance.colors.colOnPrimary : TypingFingerPalette.ink(finger.modelData)
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 6
                            height: 3
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colOnPrimary
                            visible: finger.active
                        }
                        HoverHandler { id: hover }
                        StyledToolTip {
                            extraVisibleCondition: hover.hovered
                            text: TypingFingerPalette.name(finger.modelData)
                        }
                    }
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: hand.modelData ? Translation.tr("Right hand") : Translation.tr("Left hand")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
    }
}
