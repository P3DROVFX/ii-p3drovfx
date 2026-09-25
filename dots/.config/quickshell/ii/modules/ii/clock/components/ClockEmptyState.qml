import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/** An empty tab: an expressive shape, what belongs here, and how to add it. */
ColumnLayout {
    id: root

    property string symbol: "schedule"
    property string title: ""
    property string subtitle: ""
    property string shape: "Cookie9Sided"
    property real shapeSize: ClockStyle.emptyShape
    property color colShape: ClockStyle.colSecondaryContainer
    property color colIcon: ClockStyle.colOnSecondaryContainer

    spacing: ClockStyle.gap

    Item {
        id: badge
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: root.shapeSize
        implicitHeight: root.shapeSize

        MaterialShape {
            id: badgeShape
            anchors.fill: parent
            shapeString: root.shape
            color: root.colShape
            rotation: -25
            Component.onCompleted: badgeShape.rotation = 0
            Behavior on rotation {
                enabled: !ClockStyle.reducedMotion
                NumberAnimation {
                    duration: ClockStyle.motionDefault.duration * 2
                    easing.type: ClockStyle.motionDefault.type
                    easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                }
            }
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.symbol
            iconSize: root.shapeSize * 0.38
            fill: 1
            color: root.colIcon
        }

        StaggeredEntrance {
            index: 0
            active: !ClockStyle.reducedMotion
            fromScale: 0.8
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: ClockStyle.gapSmall
        text: root.title
        font.family: ClockStyle.fontTitle
        font.variableAxes: ClockStyle.axesTitle
        font.pixelSize: ClockStyle.textTitle
        color: ClockStyle.colOnBackground

        StaggeredEntrance {
            index: 1
            active: !ClockStyle.reducedMotion
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: Math.max(root.shapeSize * 2.4, 240)
        visible: root.subtitle.length > 0
        text: root.subtitle
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        font.pixelSize: ClockStyle.textNormal
        color: ClockStyle.colSubtext

        StaggeredEntrance {
            index: 2
            active: !ClockStyle.reducedMotion
        }
    }
}
