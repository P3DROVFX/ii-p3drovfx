pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    property var modes: []
    property string currentMode: "off"
    property bool compact: false
    property real buttonHeight: root.compact ? 32 : 38
    property real spacing: 6

    signal modeRequested(string modeKey)

    readonly property int modeCount: root.modes ? root.modes.length : 0

    implicitWidth: layout.implicitWidth
    implicitHeight: root.buttonHeight

    RowLayout {
        id: layout
        anchors.fill: parent
        spacing: root.spacing

        Repeater {
            model: root.modes
            delegate: RippleButton {
                id: modeBtn
                required property var modelData
                required property int index

                readonly property var modeObj: modelData
                readonly property bool isSelected: root.currentMode === modeObj.key

                Layout.fillWidth: true
                Layout.preferredHeight: root.buttonHeight
                implicitHeight: root.buttonHeight
                buttonRadius: Appearance.rounding.full

                colBackground: modeBtn.isSelected
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSurfaceContainerHighest

                colBackgroundHover: modeBtn.isSelected
                    ? Appearance.colors.colPrimaryHover
                    : Appearance.colors.colSurfaceContainerHighestHover

                colRipple: modeBtn.isSelected
                    ? Appearance.colors.colOnPrimary
                    : Appearance.colors.colPrimary

                onClicked: {
                    root.modeRequested(modeBtn.modeObj.key);
                }

                clip: true

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: root.compact ? 6 : 8
                        rightMargin: root.compact ? 6 : 8
                    }
                    spacing: root.compact ? 3 : 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: modeBtn.modeObj.icon || "tune"
                        iconSize: root.compact ? 15 : 18
                        color: modeBtn.isSelected
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSurfaceVariant
                    }

                    StyledText {
                        visible: !root.compact || root.modeCount <= 3
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: modeBtn.modeObj.label || ""
                        font.pixelSize: root.compact ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                        font.weight: modeBtn.isSelected ? Font.Bold : Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        color: modeBtn.isSelected
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }
    }
}
