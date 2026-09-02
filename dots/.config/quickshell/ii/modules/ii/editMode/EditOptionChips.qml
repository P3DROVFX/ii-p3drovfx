import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A named choice on Edit Mode's panel, drawn as a wrapping run of chips.
 *
 * Settings answers the same question with ConfigSelectionArray, which lays its
 * options out as a fixed row of cards; the panel is 380px wide and four of
 * those do not fit. These wrap, and carry the icon Settings already picked for
 * each option so the two read as the same choice.
 */
ColumnLayout {
    id: root

    property string label: ""
    property var options: []
    property var currentValue: null
    property string lockedNote: ""

    signal selected(var value)

    spacing: 6
    Layout.fillWidth: true

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 6
        visible: root.label !== ""
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: Appearance.colors.colOnSurfaceVariant
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.options

            delegate: Rectangle {
                id: chip
                required property var modelData
                readonly property bool current: String(chip.modelData.value) === String(root.currentValue)
                readonly property bool available: chip.modelData.enabled !== false

                implicitWidth: chipRow.implicitWidth + 24
                implicitHeight: 38
                radius: Appearance.rounding.full
                opacity: chip.available ? 1 : 0.4
                color: chip.current
                    ? (chipMouse.containsPress ? Appearance.colors.colPrimaryActive
                        : chipMouse.containsMouse ? Appearance.colors.colPrimaryHover
                        : Appearance.colors.colPrimary)
                    : (chipMouse.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                        : chipMouse.containsMouse ? Appearance.colors.colSurfaceContainerHighest
                        : Appearance.colors.colSurfaceContainerHigh)

                readonly property color colOn: chip.current
                    ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface

                Behavior on color {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(chip)
                }

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        visible: (chip.modelData.icon ?? "") !== ""
                        text: chip.modelData.icon ?? ""
                        iconSize: 18
                        fill: chip.current ? 1 : 0
                        color: chip.colOn
                    }
                    StyledText {
                        text: chip.modelData.displayName ?? String(chip.modelData.value)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: chip.colOn
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    enabled: chip.available
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(chip.modelData.value)
                }
            }
        }
    }

    EditPanelNotice {
        Layout.fillWidth: true
        visible: root.lockedNote !== ""
        text: root.lockedNote
    }
}
