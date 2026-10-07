import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/*
 * The wavy seek line of the Poster and Deck widgets: a draggable StyledSlider
 * when the player can seek, a StyledProgressBar otherwise. Both read the shell's
 * position clock (MprisController.trackProgressOf) through `source`.
 */
Item {
    id: root

    required property var source
    property color highlightColor: root.source.colAccent
    property color trackColor: root.source.colTrack

    implicitHeight: Math.max(sliderLoader.implicitHeight, progressLoader.implicitHeight)

    Loader {
        id: sliderLoader
        anchors.fill: parent
        active: root.source.player?.canSeek ?? false
        sourceComponent: StyledSlider {
            configuration: StyledSlider.Configuration.Wavy
            animateWave: root.source.animate
            highlightColor: root.highlightColor
            trackColor: root.trackColor
            handleColor: root.highlightColor
            usePercentTooltip: false
            tooltipContent: root.source.positionText
            value: root.source.progress
            // Nothing to seek to while the player publishes no length.
            enabled: root.source.hasLength
            onMoved: root.source.seek(value)
            // QQuickSlider writes `value` itself while dragging, which drops the
            // binding; put it back on release so the line follows the track again.
            onPressedChanged: if (!pressed)
                value = Qt.binding(() => root.source.progress)
        }
    }

    Loader {
        id: progressLoader
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
        }
        active: !sliderLoader.active
        sourceComponent: StyledProgressBar {
            wavy: root.source.isPlaying
            animateWave: root.source.animate
            highlightColor: root.highlightColor
            trackColor: root.trackColor
            value: root.source.progress
        }
    }
}
