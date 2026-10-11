import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

/**
 * The lock's keyboard-layout dialog, made generic: a surface card that pops
 * out of the button it belongs to, listing rows of icon + label with the
 * current one filled in primary. Used for layouts, sessions and users.
 *
 * `entries` is a list of { icon, label, active }.
 */
Item {
    id: root

    property var entries: []
    property real preferredWidth: 140
    property int growFrom: Item.Bottom
    signal picked(int index)

    readonly property bool shown: card.opacity === 1
    visible: card.opacity > 0.01
    width: root.preferredWidth
    height: list.implicitHeight + 16

    function open() {
        card.opacity = 1;
        card.scale = 1;
    }
    function close() {
        card.opacity = 0;
        card.scale = 0.8;
    }
    function toggle() {
        if (card.opacity === 1)
            close();
        else
            open();
    }

    RectangularShadow {
        anchors.fill: card
        radius: card.radius
        blur: 0.9 * Theme.elevationMargin
        offset: Qt.vector2d(0.0, 1.0)
        spread: 1
        color: Theme.colShadow
        opacity: card.opacity
        scale: card.scale
        transformOrigin: root.growFrom
        visible: !Theme.transparency
    }

    Rectangle {
        id: card
        anchors.fill: parent
        opacity: 0
        scale: 0.8
        transformOrigin: root.growFrom
        radius: Math.round(24 * Theme.roundingScale)
        color: Theme.m3surfaceContainer

        Behavior on opacity {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: 200; easing.type: Easing.OutBack }
        }

        // Keep clicks on the card from reaching the surface behind it.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: list
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            Repeater {
                model: root.entries
                delegate: IslandButton {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isActive: modelData.active === true
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 36

                    colBackground: isActive ? Theme.m3primary : "transparent"
                    colBackgroundHover: isActive ? Theme.colPrimaryHover : Theme.colSecondaryContainerHover
                    colRipple: isActive ? Theme.colPrimaryActive : Theme.colSecondaryContainerActive
                    buttonRadius: Theme.roundingSmall

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        MaterialSymbol {
                            text: row.modelData.icon ?? ""
                            visible: text !== ""
                            iconSize: 18
                            color: row.isActive ? Theme.m3onPrimary : Theme.m3onSecondaryContainer
                            fill: 1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.label ?? ""
                            elide: Text.ElideRight
                            font.weight: Font.Bold
                            font.pixelSize: Theme.pxSmall
                            color: row.isActive ? Theme.m3onPrimary : Theme.m3onSecondaryContainer
                        }
                    }

                    onClicked: {
                        root.picked(row.index);
                        root.close();
                    }
                }
            }
        }
    }
}
