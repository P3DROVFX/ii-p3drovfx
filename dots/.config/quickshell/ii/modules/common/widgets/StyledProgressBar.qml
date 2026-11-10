pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls

/**
 * Material 3 progress bar. See https://m3.material.io/components/progress-indicators/overview
 */
ProgressBar {
    id: root
    property real valueBarWidth: 120
    property real valueBarHeight: 4
    property real valueBarGap: 4
    readonly property real stopPointSize: Math.max(4, Math.round(valueBarHeight * 2 / 3))
    readonly property real stopPointMargin: Math.max(2, Math.round(stopPointSize * 0.4))
    property color highlightColor: Appearance?.colors.colPrimary ?? "#685496"
    property color trackColor: Appearance?.m3colors.m3secondaryContainer ?? "#F1D3F9"
    property bool wavy: false // If true, the progress bar will have a wavy fill effect
    property bool animateWave: false
    property real waveAmplitudeMultiplier: wavy ? 0.3 : 0
    property real waveFrequency: 6
    property real waveFps: 60

    Behavior on waveAmplitudeMultiplier {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Behavior on value {
        animation: Appearance?.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    background: Item {
        implicitHeight: valueBarHeight
        implicitWidth: valueBarWidth
    }

    contentItem: Item {
        id: contentItem
        anchors.fill: parent

        Loader {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            active: root.wavy
            sourceComponent: WavyLine {
                id: wavyFill
                frequency: root.waveFrequency
                color: root.highlightColor
                amplitudeMultiplier: root.waveAmplitudeMultiplier
                height: contentItem.height * 6
                width: contentItem.width * root.visualPosition
                lineWidth: contentItem.height
                fullLength: root.width
                animateWave: root.animateWave
            }
        }

        Loader {
            active: !root.wavy
            sourceComponent: Rectangle {
                anchors.left: parent.left
                width: contentItem.width * root.visualPosition
                height: contentItem.height
                radius: Appearance.rounding.full
                color: root.highlightColor
            }
        }

        Rectangle { // Right remaining part fill
            readonly property real remainingSpace: (1 - root.visualPosition) * contentItem.width
            readonly property real computedWidth: remainingSpace - root.valueBarGap
            visible: computedWidth > 1
            anchors.right: parent.right
            width: Math.max(0, computedWidth)
            height: parent.height
            radius: Appearance.rounding.full
            color: root.trackColor
        }

        Rectangle { // Stop point
            readonly property real remainingTrackWidth: (1 - root.visualPosition) * contentItem.width - root.valueBarGap
            readonly property real availableSize: remainingTrackWidth - 2 * root.stopPointMargin
            readonly property int trackGap: Math.max(1, Math.round((parent.height - root.stopPointSize) / 2))
            readonly property real alignedStopPointSize: parent.height - (trackGap * 2)
            readonly property real effectiveSize: Math.min(alignedStopPointSize, Math.max(0, availableSize))
            visible: effectiveSize >= 2
            anchors.rightMargin: root.stopPointMargin
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: effectiveSize
            height: effectiveSize
            radius: effectiveSize / 2
            color: root.highlightColor
        }
    }
}
