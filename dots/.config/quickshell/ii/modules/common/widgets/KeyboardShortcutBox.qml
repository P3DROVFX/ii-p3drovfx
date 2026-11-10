import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string text: "Action description"
    property list<string> keys: ["Super", "W"]

    readonly property GroupPosition groupPosition: GroupPosition {
        item: root
    }
    readonly property int itemIndex: groupPosition.index

    readonly property int totalItems: groupPosition.count

    property bool isFirst: itemIndex === 0
    property bool isLast: itemIndex === totalItems - 1
    property bool isAlone: totalItems === 1

    readonly property bool isPressed: false

    readonly property bool prevIsPressed: groupPosition.previousPressed

    readonly property bool nextIsPressed: groupPosition.nextPressed

    readonly property bool isHorizontalLayout: {
        var p = parent;
        if (!p) return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

    readonly property real rFull: Appearance.rounding.scale === 0 ? 0 : Math.min(height / 2, Appearance.rounding.large)

    topLeftRadius: (isPressed || prevIsPressed) ? rFull : ((isFirst || isAlone) ? Appearance.rounding.large : Appearance.rounding.verysmall)
    topRightRadius: (isPressed || prevIsPressed) ? rFull : (isHorizontalLayout ? ((isLast || isAlone) ? Appearance.rounding.large : Appearance.rounding.verysmall) : ((isFirst || isAlone) ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomLeftRadius: (isPressed || nextIsPressed) ? rFull : (isHorizontalLayout ? ((isFirst || isAlone) ? Appearance.rounding.large : Appearance.rounding.verysmall) : ((isLast || isAlone) ? Appearance.rounding.large : Appearance.rounding.verysmall))
    bottomRightRadius: (isPressed || nextIsPressed) ? rFull : ((isLast || isAlone) ? Appearance.rounding.large : Appearance.rounding.verysmall)

    Behavior on topLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on topRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomLeftRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomRightRadius {
        enabled: root.groupPosition.settled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }


    color: Appearance.colors.colSurfaceContainer
    implicitWidth: mainRowLayout.implicitWidth + mainRowLayout.anchors.margins * 2
    implicitHeight: mainRowLayout.implicitHeight + mainRowLayout.anchors.margins * 2

    RowLayout {
        id: mainRowLayout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16

        RowLayout {
            spacing: 6
            Repeater {
                model: root.keys
                delegate: RowLayout {
                    spacing: 6
                    
                    Rectangle {
                        implicitWidth: keyText.implicitWidth + 16
                        implicitHeight: keyText.implicitHeight + 8
                        radius: Appearance.rounding.verysmall
                        color: Appearance.colors.colSurfaceContainerHigh
                        border.color: Appearance.colors.colOutlineVariant
                        border.width: 1

                        StyledText {
                            id: keyText
                            anchors.centerIn: parent
                            text: modelData
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSurface
                        }
                    }

                    StyledText {
                        visible: index < root.keys.length - 1
                        text: "+"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.text
            color: Appearance.colors.colOnSurfaceVariant
            wrapMode: Text.WordWrap
        }
    }
}
