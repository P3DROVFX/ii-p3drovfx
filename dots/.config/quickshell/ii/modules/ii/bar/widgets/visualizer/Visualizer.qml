import qs.services
import qs.modules.common
import QtQuick

Item {
    id: root

    property bool vertical: false
    property bool mirrored: false
    readonly property bool isPlaying: CavaService.active
    readonly property list<real> points: CavaService.visualizerPoints
    property int barCount: 20
    property real dotSize: 3
    property real dotSpacing: 3
    property real maxBarHeight: (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.baseBarHeight) * 0.7
    property real maxVisualizerValue: 1000

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : barCount * (dotSize + dotSpacing)
    implicitHeight: vertical ? barCount * (dotSize + dotSpacing) : Appearance.sizes.baseBarHeight

    transform: Scale {
        xScale: !root.vertical && root.mirrored ? -1 : 1
        origin.x: root.width / 2
    }

    Row {
        id: barsRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: root.dotSpacing

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                width: root.dotSize
                property real pointValue: {
                    if (!root.isPlaying || root.points.length === 0)
                        return root.dotSize
                    const idx = Math.floor(index * root.points.length / root.barCount)
                    const v = root.points[idx] ?? 0
                    return Math.max(root.dotSize, (v / root.maxVisualizerValue) * root.maxBarHeight)
                }
                height: pointValue
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colPrimary
                opacity: root.isPlaying ? 0.85 : 0.3
                Behavior on height {
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                    }
                }
            }
        }
    }

    Column {
        id: barsColumn
        visible: root.vertical
        anchors.centerIn: parent
        spacing: root.dotSpacing

        Repeater {
            model: root.barCount
            Rectangle {
                required property int index
                height: root.dotSize
                property real pointValue: {
                    if (!root.isPlaying || root.points.length === 0)
                        return root.dotSize
                    const rawIndex = root.mirrored ? (root.barCount - 1 - index) : index
                    const idx = Math.floor(rawIndex * root.points.length / root.barCount)
                    const v = root.points[idx] ?? 0
                    return Math.max(root.dotSize, (v / root.maxVisualizerValue) * root.maxBarHeight)
                }
                width: pointValue
                radius: height / 2
                anchors.horizontalCenter: parent.horizontalCenter
                color: Appearance.colors.colPrimary
                opacity: root.isPlaying ? 0.85 : 0.3
                Behavior on width {
                    NumberAnimation {
                        duration: 80
                        easing.type: Easing.OutQuad
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                    }
                }
            }
        }
    }
}
