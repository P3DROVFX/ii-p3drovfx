import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One app of the feature tour: what it is, the key that opens it, and a
 * button that opens it now.
 *
 * The row itself is not the button. The keycaps are something to read and
 * the description is something to read; the one thing to press says so.
 */
Rectangle {
    id: root

    required property string title
    property string description: ""
    /** Replaces the description when the app has nothing to work with yet. */
    property string note: ""
    property string materialIcon: "apps"
    property var shape: MaterialShape.Shape.Square
    property var keys: []
    property bool performed: false

    signal activated()

    readonly property bool isCompactKeycaps: root.keys.length >= 3

    implicitHeight: rowContent.implicitHeight + Appearance.rounding.small * 2
    radius: Appearance.rounding.large
    color: Appearance.colors.colLayer1

    RowLayout {
        id: rowContent

        anchors.fill: parent
        anchors.leftMargin: Appearance.rounding.small
        anchors.rightMargin: Appearance.rounding.small
        anchors.topMargin: Appearance.rounding.small
        anchors.bottomMargin: Appearance.rounding.small
        spacing: Appearance.rounding.small

        // Morphs toward a circle while the reader points at "Open": the
        // affordance lives on the shape, not on an arrow.
        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.materialIcon
            shape: openButton.hovered ? MaterialShape.Shape.Circle : root.shape
            iconSize: Appearance.font.pixelSize.huge
            padding: Appearance.rounding.small
            fill: 1
            color: Appearance.colors.colSecondaryContainer
            colSymbol: Appearance.colors.colOnSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.rounding.unsharpenmore

                StyledText {
                    Layout.fillWidth: false
                    text: root.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                // Arrives when the reader opens the app, and takes no space
                // before that, like the shortcut cards.
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: root.performed ? implicitWidth : 0
                    text: "check_circle"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                    opacity: root.performed ? 1 : 0
                    scale: root.performed ? 1 : 0.6

                    Behavior on Layout.preferredWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                    }
                }

                Item { Layout.fillWidth: true }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.note.length > 0 ? root.note : root.description
                color: root.note.length > 0 ? Appearance.colors.colTertiary : Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }

        RowLayout {
            visible: root.keys.length > 0
            Layout.alignment: Qt.AlignVCenter
            spacing: root.isCompactKeycaps ? 2 : 4

            Repeater {
                model: root.keys

                delegate: RowLayout {
                    required property string modelData
                    required property int index

                    spacing: root.isCompactKeycaps ? 2 : 4

                    KeyboardKey {
                        key: modelData
                        horizontalPadding: root.isCompactKeycaps ? 4 : 6
                        pixelSize: Appearance.font.pixelSize.smaller
                    }

                    StyledText {
                        visible: index < root.keys.length - 1
                        text: "+"
                        color: Appearance.colors.colOnLayer3
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }

        StyledText {
            visible: root.keys.length === 0
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("Not assigned")
            color: Appearance.colors.colOnLayer2
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        RippleButtonWithIcon {
            id: openButton

            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: Appearance.rounding.verysmall
            implicitHeight: Appearance.rounding.verylarge + Appearance.rounding.verysmall
            centerContent: true
            materialIcon: "open_in_new"
            mainText: Translation.tr("Open")
            textPixelSize: Appearance.font.pixelSize.small
            iconPixelSize: Appearance.font.pixelSize.large
            buttonRadius: Appearance.rounding.full
            colText: Appearance.colors.colOnSecondaryContainer
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colBackgroundActive: Appearance.colors.colSecondaryContainerActive
            colRipple: Appearance.colors.colSecondaryContainerActive
            Accessible.name: Translation.tr("Open %1").arg(root.title)
            onClicked: root.activated()
        }
    }
}
