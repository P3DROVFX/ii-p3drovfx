import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common

Item {
    id: lockVignetteRoot

    required property var sourceItem
    required property real baseScale
    required property bool lockAnimationActive

    Loader {
        id: vignetteLoader
        active: Config.options.lock.vignette.enable && (GlobalStates.screenLocked || vignetteAnim.running)
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            Canvas {
                id: vignetteCanvas
                anchors.fill: parent
                opacity: GlobalStates.screenLocked ? Config.options.lock.vignette.amount : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        id: vignetteAnim
                        duration: Math.round(700 * Appearance.animMultiplier)
                        easing.type: Easing.OutCubic
                    }
                }
                onPaint: {
                    var ctx = getContext("2d");
                    var w = width;
                    var h = height;
                    if (w <= 0 || h <= 0) return;
                    ctx.clearRect(0, 0, w, h);
                    var cx = w / 2;
                    var cy = h / 2;
                    var outerRadius = Math.hypot(cx, cy);
                    var innerRadius = outerRadius * 0.35;
                    var grad = ctx.createRadialGradient(cx, cy, innerRadius, cx, cy, outerRadius);
                    grad.addColorStop(0.0, "rgba(0, 0, 0, 0)");
                    grad.addColorStop(0.5, "rgba(0, 0, 0, 0.3)");
                    grad.addColorStop(0.8, "rgba(0, 0, 0, 0.7)");
                    grad.addColorStop(1.0, "rgba(0, 0, 0, 0.95)");
                    ctx.fillStyle = grad;
                    ctx.fillRect(0, 0, w, h);
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Component.onCompleted: requestPaint()
            }
        }
    }
}
