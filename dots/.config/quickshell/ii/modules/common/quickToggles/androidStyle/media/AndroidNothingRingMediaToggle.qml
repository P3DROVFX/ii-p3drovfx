pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * Nothing Ring Media quick toggle.
 * Adapted from the desktop background's NothingRingMediaWidget.
 *
 * Freeform adaptive: 360-degree circular progress gauge with
 * dynamic playback status and interactive toggle.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: {
        if (root.player && root.player.trackTitle) {
            var artist = root.player.trackArtist ? root.player.trackArtist : Translation.tr("Unknown Artist");
            return root.player.trackTitle + " - " + artist;
        }
        return Translation.tr("Media Ring");
    }

    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor

    readonly property var player: MprisController.activePlayer
    readonly property bool hasMedia: player !== null && (player.trackTitle || "").length > 0
    readonly property bool isPlaying: MprisController.isPlaying
    readonly property real position: player ? (player.position ?? 0) : 0
    readonly property real length: MprisController.trackLengthOf(player)
    readonly property real progress: (hasMedia && length > 0) ? Math.min(1, Math.max(0, position / length)) : 0
    readonly property int percentInt: Math.round(progress * 100)

    readonly property real containerSize: Math.max(32, Math.min(root.surface.width, root.surface.height))
    readonly property real ringSize: Math.max(24, root.containerSize - 16)
    readonly property real strokeWidth: Math.max(3, Math.min(14, Math.round(root.ringSize * 0.08)))

    Timer {
        running: root.isPlaying
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.player) root.player.positionChanged();
        }
    }

    Rectangle {
        id: mainContainer
        anchors.centerIn: parent
        width: root.containerSize
        height: root.containerSize
        radius: Appearance.rounding.large
        color: WidgetColorScheme.tintBackground(root.cardBgColor)

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (root.player) root.player.togglePlaying();
            }
        }

        // --- 360-Degree Circular Progress Gauge ---
        Canvas {
            id: ringCanvas
            property real ringProgress: root.progress
            property color trackColor: Qt.rgba(root.textColorOnBg.r, root.textColorOnBg.g, root.textColorOnBg.b, 0.18)
            property color progressColor: root.textColorOnBg
            property color handleColor: root.cardBgColor
            property real strokeWidth: root.strokeWidth

            anchors.centerIn: parent
            width: root.ringSize
            height: root.ringSize

            onRingProgressChanged: requestPaint()
            onTrackColorChanged: requestPaint()
            onProgressColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var centerX = width / 2;
                var centerY = height / 2;
                var radius = Math.max(2, (width - strokeWidth - 6) / 2);
                var startAngle = -Math.PI / 2;
                var totalSweep = 2 * Math.PI;

                // 1. Background Track
                ctx.beginPath();
                ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI, false);
                ctx.lineWidth = strokeWidth;
                ctx.strokeStyle = trackColor;
                ctx.stroke();

                // 2. Active Progress Arc
                if (ringProgress > 0) {
                    var activeSweep = Math.min(1, Math.max(0, ringProgress)) * totalSweep;
                    var endAngle = startAngle + activeSweep;
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, startAngle, endAngle, false);
                    ctx.lineWidth = strokeWidth;
                    ctx.strokeStyle = progressColor;
                    ctx.lineCap = "round";
                    ctx.stroke();

                    // 3. Circular Handle Dot
                    var handleX = centerX + radius * Math.cos(endAngle);
                    var handleY = centerY + radius * Math.sin(endAngle);
                    ctx.beginPath();
                    ctx.arc(handleX, handleY, strokeWidth / 2 + 1, 0, 2 * Math.PI, false);
                    ctx.fillStyle = handleColor;
                    ctx.fill();
                    ctx.lineWidth = Math.max(1, strokeWidth * 0.2);
                    ctx.strokeStyle = progressColor;
                    ctx.stroke();
                }
            }
        }

        // --- Center Content ---
        Column {
            anchors.centerIn: parent
            spacing: Math.max(1, Math.round(root.ringSize * 0.03))

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasMedia ? (root.isPlaying ? "music_note" : "pause") : "music_off"
                iconSize: Math.max(16, Math.min(42, Math.round(root.ringSize * 0.28)))
                color: root.hasMedia ? root.textColorOnBg : root.subtextColorOnBg
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasMedia ? (root.percentInt + "%") : Translation.tr("No media")
                font.pixelSize: Math.max(9, Math.min(18, Math.round(root.ringSize * 0.14)))
                font.weight: root.hasMedia ? Font.DemiBold : Font.Normal
                color: root.hasMedia ? root.textColorOnBg : root.subtextColorOnBg
            }
        }
    }
}
