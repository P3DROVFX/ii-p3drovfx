import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A filled pill text field: leading icon, placeholder drawn in the field, no
 * outline. Corners open toward content attached below (`attachedBelow`).
 */
Rectangle {
    id: root

    property string symbol: "edit"
    property string placeholder: ""
    property bool attachedBelow: false
    property color colField: Appearance.colors.colSecondaryContainer
    property color colFieldHover: Appearance.colors.colSecondaryContainerHover
    property color colContent: Appearance.colors.colOnSecondaryContainer
    property alias text: input.text
    property alias input: input
    readonly property bool focused: input.activeFocus

    signal accepted()

    implicitHeight: 56
    readonly property real pill: Appearance.rounding.scale === 0 ? 0 : height / 2
    topLeftRadius: root.attachedBelow ? Appearance.rounding.large : root.pill
    topRightRadius: root.attachedBelow ? Appearance.rounding.large : root.pill
    bottomLeftRadius: root.attachedBelow ? Appearance.rounding.verysmall : root.pill
    bottomRightRadius: root.attachedBelow ? Appearance.rounding.verysmall : root.pill
    color: input.activeFocus || hover.hovered ? root.colFieldHover : root.colField
    opacity: root.enabled ? 1 : 0.6
    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }

    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
    TapHandler { onTapped: input.forceActiveFocus() }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: 18
            rightMargin: 18
        }
        spacing: 12

        MaterialSymbol {
            text: root.symbol
            iconSize: Appearance.font.pixelSize.huge
            color: root.colContent
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: input.implicitHeight

            StyledTextInput {
                id: input
                anchors.left: parent.left
                anchors.right: parent.right
                font.pixelSize: Appearance.font.pixelSize.normal
                color: root.colContent
                clip: true
                onAccepted: root.accepted()
                Keys.onEscapePressed: text = ""
            }
            StyledText {
                anchors.verticalCenter: input.verticalCenter
                width: parent.width
                visible: input.text.length === 0
                text: root.placeholder
                font: input.font
                color: root.colContent
                opacity: 0.7
                elide: Text.ElideRight
            }
        }
    }
}
