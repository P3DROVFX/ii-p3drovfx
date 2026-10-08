import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A key cap to press and hold: it sinks while pressed, fills over `holdDuration`
 * and reports `held` once full, the way the bar waits before showing numbers.
 */
Item {
    id: root

    property string label: ""
    property string symbol: "keyboard_command_key"
    property int holdDuration: 300
    readonly property bool held: root.progress >= 1 && area.pressed

    readonly property real capRadius: Appearance.rounding.small
    readonly property real capDepth: 4
    readonly property real sinkDepth: 2
    readonly property real sidePadding: 14
    readonly property color colCap: Appearance.colors.colSurfaceContainerHigh
    readonly property color colEdge: Appearance.colors.colOutlineVariant
    readonly property color colFill: Appearance.colors.colPrimaryContainer
    readonly property color colContent: root.held ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface

    property real progress: 0

    implicitWidth: capRow.implicitWidth + root.sidePadding * 2
    implicitHeight: 42

    NumberAnimation {
        id: fillUp
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Math.max(1, root.holdDuration)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.capDepth
        radius: root.capRadius
        color: root.colEdge
    }

    Rectangle {
        id: cap
        width: parent.width
        height: parent.height - root.capDepth
        y: area.pressed ? root.sinkDepth : 0
        radius: root.capRadius
        color: root.colCap
        clip: true
        Behavior on y {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle {
            width: parent.width * root.progress
            height: parent.height
            color: root.colFill
        }

        RowLayout {
            id: capRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                text: root.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: root.colContent
            }
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.colContent
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: fillUp.restart()
        onReleased: {
            fillUp.stop();
            root.progress = 0;
        }
        onCanceled: {
            fillUp.stop();
            root.progress = 0;
        }
    }
}
