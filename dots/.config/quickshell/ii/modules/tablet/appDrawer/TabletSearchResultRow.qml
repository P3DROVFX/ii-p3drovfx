import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.modules.common
import qs.modules.common.widgets

/**
 * One non-app search result: clipboard entry, file, quick toggle.
 *
 * A row rather than a grid tile, because these have text worth reading. Sized to the
 * family's touch minimum with room to spare — the drawer has a whole screen, and a result
 * you have to aim at is a result you will not use.
 *
 * Optional parts, each only when set:
 *   imageEntry     a clipboard image entry, shown as a thumbnail instead of the symbol
 *   actions        `[{ symbol, label, trigger }]`, finger-sized buttons at the end
 *   switchVisible  a switch at the end, showing `switchChecked`; tapping it activates
 */
Item {
    id: root

    property string symbol: ""
    property string iconPath: ""
    property string title: ""
    property string subtitle: ""
    property string imageEntry: ""
    property var actions: []
    property bool switchVisible: false
    property bool switchChecked: false

    signal activated

    implicitHeight: Math.max(Appearance.sizes.minimumTouchTarget + 16, 64)

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: tapArea.pressed ? Appearance.colors.colLayer2Active : "transparent"

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    // Under the row's own controls: declared first, so the buttons and the switch take
    // their own taps and everything else on the row is the row.
    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: root.activated()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        spacing: 16

        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: width / 2
            color: Appearance.colors.colLayer2
            visible: root.iconPath.length === 0 && root.imageEntry.length === 0

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 22
                color: Appearance.colors.colOnLayer2
            }
        }

        IconImage {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            visible: root.iconPath.length > 0 && root.imageEntry.length === 0
            source: root.iconPath
        }

        // The image itself, not a symbol for "an image": a clipboard full of screenshots
        // is otherwise a column of identical rows.
        Rectangle {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            visible: root.imageEntry.length > 0
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            clip: true

            Loader {
                anchors.centerIn: parent
                active: root.imageEntry.length > 0
                sourceComponent: CliphistImage {
                    entry: root.imageEntry
                    maxWidth: 44
                    maxHeight: 44
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3onSurface
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Repeater {
            model: root.actions

            delegate: RippleButton {
                id: actionButton
                required property var modelData
                Layout.preferredWidth: Appearance.sizes.minimumTouchTarget
                Layout.preferredHeight: Appearance.sizes.minimumTouchTarget
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                Accessible.name: actionButton.modelData.label ?? ""
                onClicked: actionButton.modelData.trigger?.()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: actionButton.modelData.symbol ?? ""
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        StyledSwitch {
            id: rowSwitch
            visible: root.switchVisible
            checked: root.switchChecked
            // A tap on the switch is the same as a tap on the row. The Switch flips its own
            // `checked` on a click, which would cut it loose from the model; putting the
            // binding back lets the real state, not the click, decide what it shows.
            onToggled: {
                root.activated();
                rowSwitch.checked = Qt.binding(() => root.switchChecked);
            }
        }
    }
}
