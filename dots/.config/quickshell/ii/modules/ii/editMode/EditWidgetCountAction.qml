import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * A catalogue card's trailing control: a plus while nothing is placed, which
 * unfolds into − count + once a copy is out. The fold is one 0→1 scalar, so
 * the pill's width, the minus and the digits all move together.
 */
Item {
    id: root

    readonly property real buttonSize: 36
    readonly property real countWidth: 30
    readonly property real glyphSize: 20
    readonly property real tintIdle: 0.08
    readonly property real tintHover: 0.16
    readonly property real tintPressed: 0.24
    readonly property var digitAxes: ({ "wght": 720, "wdth": 50, "ROND": 100 })

    property int count: 0
    property bool highlighted: false
    property color colContent: Appearance.colors.colOnSurface
    property color colAccent: Appearance.colors.colPrimaryContainer
    property color colOnAccent: Appearance.colors.colOnPrimaryContainer

    signal increment()
    signal decrement()

    property real unfold: root.count > 0 ? 1 : 0
    Behavior on unfold {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(root)
    }

    readonly property real foldedWidth: root.buttonSize
    readonly property real unfoldedWidth: root.buttonSize * 2 + root.countWidth
    readonly property real settledWidth: root.count > 0 ? root.unfoldedWidth : root.foldedWidth

    implicitWidth: root.foldedWidth + (root.unfoldedWidth - root.foldedWidth) * root.unfold
    implicitHeight: root.buttonSize

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Qt.alpha(root.colContent, root.tintIdle)
        opacity: root.unfold
    }

    Item {
        id: minusSlot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.buttonSize
        height: root.buttonSize
        opacity: root.unfold
        visible: opacity > 0

        RoundAction {
            anchors.fill: parent
            symbol: "remove"
            colGlyph: root.colContent
            enabled: root.count > 0
            onTriggered: root.decrement()
        }
    }

    StyledText {
        anchors.left: minusSlot.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.countWidth
        horizontalAlignment: Text.AlignHCenter
        opacity: root.unfold
        visible: opacity > 0
        animateChange: true
        text: root.count > 0 ? `${root.count}` : ""
        font.family: Appearance.font.family.main
        font.variableAxes: root.digitAxes
        font.pixelSize: Appearance.font.pixelSize.larger
        color: root.colContent
    }

    RoundAction {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.buttonSize
        height: root.buttonSize
        symbol: "add"
        filled: root.count === 0 && root.highlighted
        colGlyph: filled ? root.colOnAccent : root.colContent
        onTriggered: root.increment()
    }

    component RoundAction: Rectangle {
        id: action

        property string symbol: ""
        property bool filled: false
        property color colGlyph: Appearance.colors.colOnSurface
        signal triggered()

        radius: height / 2
        color: action.filled ? root.colAccent
            : actionMouse.containsPress ? Qt.alpha(root.colContent, root.tintPressed)
            : actionMouse.containsMouse ? Qt.alpha(root.colContent, root.tintHover)
            : "transparent"

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(action)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: action.symbol
            iconSize: root.glyphSize
            color: action.enabled ? action.colGlyph : Qt.alpha(action.colGlyph, 0.38)

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(action)
            }
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            enabled: action.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: action.triggered()
        }
    }
}
