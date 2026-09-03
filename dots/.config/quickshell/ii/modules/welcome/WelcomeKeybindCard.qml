import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RippleButton {
    id: root

    required property string title
    property var keys: []
    property string materialIcon: "keyboard"
    property string unassignedText: Translation.tr("No shortcut")
    property bool hero: false

    signal activated()

    readonly property bool isCompactKeycaps: keys.length >= 3

    implicitHeight: root.hero
        ? Appearance.rounding.verylarge * 3
        : Appearance.rounding.verylarge * 2 + Appearance.rounding.small
    buttonRadius: Appearance.rounding.large
    buttonRadiusPressed: Appearance.rounding.normal
    colBackground: Appearance.colors.colLayer1
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colBackgroundActive: Appearance.colors.colLayer1Active
    colRipple: Appearance.colors.colLayer1Active
    Accessible.name: root.title

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: root.hero ? 12 : 8
        anchors.bottomMargin: root.hero ? 12 : 8
        spacing: 8

        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.materialIcon
            shape: MaterialShape.Shape.Square
            // The card is mostly air between a small glyph and a keycap; the
            // shape is the only thing in it that can carry any weight.
            iconSize: root.hero ? Appearance.font.pixelSize.hugeass : Appearance.font.pixelSize.huge
            padding: root.hero ? Appearance.rounding.normal : Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer
            colSymbol: Appearance.colors.colOnSecondaryContainer
        }

        StyledText {
            Layout.fillWidth: true
            Layout.minimumWidth: 44
            Layout.alignment: Qt.AlignVCenter
            text: root.title
            color: Appearance.colors.colOnLayer1
            font.pixelSize: root.hero ? Appearance.font.pixelSize.larger : Appearance.font.pixelSize.normal
            font.weight: Font.Bold
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
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
                        pixelSize: root.isCompactKeycaps
                            ? Appearance.font.pixelSize.smaller - 1
                            : root.hero
                                ? Appearance.font.pixelSize.normal
                                : Appearance.font.pixelSize.smaller
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
            text: root.unassignedText
            color: Appearance.colors.colOnLayer2
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    onClicked: root.activated()
}
