import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One app in the drawer: icon over a label, sized for a fingertip.
 *
 * The desktop launcher's tile is 100x110 with a 48px icon and grows on hover. Neither
 * number survives a touchscreen — the whole tile is the target here, and there is no hover
 * to grow on, so the press feedback has to be the press itself.
 */
Item {
    id: root

    /// A desktop entry, or null for a shell surface listed as an app.
    required property var entry
    /// Set instead of `entry` for a shell surface: it has no .desktop file, so its name and
    /// Material symbol are supplied directly.
    property string systemName: ""
    property string systemIcon: ""
    readonly property bool isSystem: root.systemIcon.length > 0

    property real iconSize: 56

    signal activated
    /// Long-press. Android's "add to home" gesture, and the only one available without a
    /// right button.
    signal held

    implicitWidth: 96
    implicitHeight: 116

    // A press ripple is the only feedback a finger gets: no cursor, no hover state. It has
    // to start on press rather than on release, or the tile feels dead for the whole time
    // the finger is down.
    Rectangle {
        id: pressPlate
        anchors.centerIn: parent
        width: root.width
        height: root.height
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2
        opacity: tapArea.pressed ? 1 : 0
        scale: tapArea.pressed ? 1 : 0.9

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize
            // Android shrinks the icon under the finger rather than lighting up a
            // background; the plate behind is a softer version of the same idea.
            scale: tapArea.pressed ? 0.92 : 1
            Behavior on scale {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            IconImage {
                anchors.fill: parent
                visible: !root.isSystem
                source: Quickshell.iconPath(AppSearch.guessIcon(root.entry?.id ?? ""), "image-missing")
            }

            // A shell surface has no application icon, so it gets a symbol on a tinted
            // round plate — visibly a system thing rather than a badly-themed app.
            Rectangle {
                anchors.fill: parent
                visible: root.isSystem
                radius: width * 0.28
                color: Appearance.colors.colPrimaryContainer

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.systemIcon
                    iconSize: Math.round(root.iconSize * 0.52)
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            text: root.isSystem ? Translation.tr(root.systemName) : (root.entry?.name ?? "")
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            color: Appearance.m3colors.m3onSurface
        }
    }

    MouseArea {
        id: tapArea
        anchors.fill: parent
        onClicked: {
            if (holdTimer.fired)
                return;
            root.activated();
        }
        onPressed: {
            holdTimer.fired = false;
            holdTimer.restart();
        }
        onReleased: holdTimer.stop()
        onCanceled: holdTimer.stop()

        Timer {
            id: holdTimer
            property bool fired: false
            interval: 550
            onTriggered: {
                holdTimer.fired = true;
                root.held();
            }
        }
    }
}
