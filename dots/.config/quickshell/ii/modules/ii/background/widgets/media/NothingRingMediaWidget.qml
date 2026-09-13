import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.services

AbstractBackgroundWidget {
    id: root

    property bool wallpaperSafetyTriggered: false
    // Color Scheme Integration
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor
    // Media State
    readonly property var player: MprisController.activePlayer
    readonly property bool hasMedia: player !== null && (player.trackTitle || "").length > 0
    readonly property bool isPlaying: MprisController.isPlaying
    readonly property real position: player ? (player.position ?? 0) : 0
    readonly property real length: player ? (player.length ?? 0) : 0
    readonly property real progress: (hasMedia && length > 0) ? Math.min(1, Math.max(0, position / length)) : 0
    readonly property int percentInt: Math.round(progress * 100)

    configEntryName: "nothing_ring_media"
    implicitWidth: 240
    implicitHeight: 240

    // Shadow Effect
    StyledDropShadow {
        id: shadowEffect

        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer

        anchors.fill: parent
        radius: Appearance.rounding.large
        color: WidgetColorScheme.tintBackground(root.cardBgColor)

        // --- 360-Degree Circular Progress Gauge ---
        Canvas {
            id: ringCanvas

            property real ringProgress: root.progress
            property color trackColor: Qt.rgba(root.textColorOnBg.r, root.textColorOnBg.g, root.textColorOnBg.b, 0.18)
            property color progressColor: root.textColorOnBg
            property color handleColor: root.cardBgColor
            property real strokeWidth: 14

            anchors.centerIn: parent
            width: 180
            height: 180
            onRingProgressChanged: requestPaint()
            onTrackColorChanged: requestPaint()
            onProgressColorChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var centerX = width / 2;
                var centerY = height / 2;
                var radius = (width - strokeWidth - 8) / 2;
                var startAngle = -Math.PI / 2; // -90° (top center / 12 o'clock)
                var totalSweep = 2 * Math.PI; // 360° full circle
                // 1. Draw Background Track (Full 360° Muted Circle)
                ctx.beginPath();
                ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI, false);
                ctx.lineWidth = strokeWidth;
                ctx.strokeStyle = trackColor;
                ctx.stroke();
                // 2. Draw Active Progress Arc (if has progress)
                if (ringProgress > 0) {
                    var activeSweep = Math.min(1, Math.max(0, ringProgress)) * totalSweep;
                    var endAngle = startAngle + activeSweep;
                    ctx.beginPath();
                    ctx.arc(centerX, centerY, radius, startAngle, endAngle, false);
                    ctx.lineWidth = strokeWidth;
                    ctx.strokeStyle = progressColor;
                    ctx.lineCap = "round";
                    ctx.stroke();
                    // 3. Draw Circular Handle Dot at end of arc
                    var handleX = centerX + radius * Math.cos(endAngle);
                    var handleY = centerY + radius * Math.sin(endAngle);
                    ctx.beginPath();
                    ctx.arc(handleX, handleY, strokeWidth / 2 + 1.5, 0, 2 * Math.PI, false);
                    ctx.fillStyle = handleColor;
                    ctx.fill();
                    ctx.lineWidth = 2.5;
                    ctx.strokeStyle = progressColor;
                    ctx.stroke();
                }
            }
        }

        // --- Center Content (Music Note + Percentage / Empty State) ---
        Column {
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasMedia ? "music_note" : "music_off"
                iconSize: 42
                color: root.hasMedia ? root.textColorOnBg : root.subtextColorOnBg
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.hasMedia ? (root.percentInt + "%") : Translation.tr("No media")
                font.pixelSize: root.hasMedia ? 22 : 14
                font.weight: root.hasMedia ? Font.DemiBold : Font.Normal
                color: root.hasMedia ? root.textColorOnBg : root.subtextColorOnBg
            }

        }

    }

}
