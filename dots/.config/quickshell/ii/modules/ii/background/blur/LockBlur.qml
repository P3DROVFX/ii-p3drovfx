import QtQuick
import QtQuick.Effects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

Item {
    id: lockBlurRoot

    required property var sourceItem
    // False until the wallpaper plane has its final size and the image has decoded. The capture
    // below is taken once and never retaken, so a lock that happens before then - the usual case
    // on an autologin boot - keeps a texture that no longer matches the plane, and the lock
    // wallpaper stays split into a blurred and a sharp band until the next unlock.
    required property bool sourceReady
    required property real baseScale
    required property bool lockAnimationActive

    property bool wallpaperIsVideo: false

    readonly property real sourceWidth: sourceItem ? sourceItem.width : 0
    readonly property real sourceHeight: sourceItem ? sourceItem.height : 0

    // The plane resizes whenever the wallpaper's real dimensions, the screen geometry or the zoom
    // scale land. Rebuild the effect so it captures the plane again at its new size.
    property bool reloadRequested: false
    onSourceWidthChanged: rebuildTimer.restart();
    onSourceHeightChanged: rebuildTimer.restart();

    Timer {
        id: rebuildTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (!blurLoader.active)
                return;
            lockBlurRoot.reloadRequested = true;
            Qt.callLater(function() {
                lockBlurRoot.reloadRequested = false;
            });
        }
    }

    Loader {
        id: blurLoader
        active: Config.options.lock.blur.enable && lockBlurRoot.sourceReady && !lockBlurRoot.reloadRequested
            && (GlobalStates.screenLocked || opacityAnim.running) && !lockBlurRoot.wallpaperIsVideo
        anchors.fill: parent
        opacity: GlobalStates.screenLocked ? 1.0 : 0.0
        Behavior on opacity {
            SequentialAnimation {
                id: opacityAnim
                PauseAnimation { duration: GlobalStates.screenLocked ? Math.round(150 * Appearance.animMultiplier) : 0 }
                NumberAnimation {
                    duration: Math.round(350 * Appearance.animMultiplier)
                    easing.type: Easing.OutCubic
                }
            }
        }
        sourceComponent: MultiEffect {
            source: lockBlurRoot.sourceItem
            blurEnabled: true
            blurMax: 96
            blur: Math.min(1.0, (Config.options.lock.blur.radius ?? 40) / 100)

            Rectangle {
                opacity: 1.0
                anchors.fill: parent
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
            }
        }
    }
}
