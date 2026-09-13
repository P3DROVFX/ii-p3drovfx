import QtQuick
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions as CF

Item {
    id: lockBlurRoot

    required property var sourceItem
    // False until the wallpaper plane has its final size and the image has decoded. Do not build
    // the blur before then: a lock that happens during an autologin boot can otherwise retain an
    // incomplete source texture and leave a blurred/sharp band on the wallpaper.
    required property bool sourceReady
    required property real baseScale
    required property bool lockAnimationActive

    property bool wallpaperIsVideo: false
    // The blur radius is animated independently from the layer opacity. This keeps the lock
    // entrance progressive even though the Gaussian effect is created lazily.
    property real blurProgress: 0.0

    readonly property real sourceWidth: sourceItem ? sourceItem.width : 0
    readonly property real sourceHeight: sourceItem ? sourceItem.height : 0
    readonly property real configuredBlurRadius: Math.max(0, Math.min(50, Config.options.lock.blur.radius ?? 40))

    function startBlurEntrance() {
        blurInAnimation.stop();
        blurOutAnimation.stop();
        blurProgress = 0.0;
        blurInAnimation.start();
    }

    // If the shell locks before the wallpaper has decoded, defer the entrance clock until the
    // source is actually available; otherwise the blur would finish invisibly and appear at full
    // strength in one frame when sourceReady eventually becomes true.
    onSourceReadyChanged: if (sourceReady && GlobalStates.lockLookActive)
        startBlurEntrance();

    SequentialAnimation {
        id: blurInAnimation
        PauseAnimation { duration: Math.round(150 * Appearance.animMultiplier) }
        NumberAnimation {
            target: lockBlurRoot
            property: "blurProgress"
            to: 1.0
            duration: Math.round(350 * Appearance.animMultiplier)
            easing.type: Easing.OutCubic
        }
    }

    NumberAnimation {
        id: blurOutAnimation
        target: lockBlurRoot
        property: "blurProgress"
        to: 0.0
        duration: Math.round(350 * Appearance.animMultiplier)
        easing.type: Easing.OutCubic
    }

    Connections {
        target: GlobalStates
        function onLockLookActiveChanged() {
            if (GlobalStates.lockLookActive) {
                lockBlurRoot.startBlurEntrance();
            } else {
                blurInAnimation.stop();
                blurOutAnimation.stop();
                blurOutAnimation.start();
            }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.lockLookActive && sourceReady)
            startBlurEntrance();
    }

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
            && (GlobalStates.lockLookActive || opacityAnim.running) && !lockBlurRoot.wallpaperIsVideo
        anchors.fill: parent
        opacity: GlobalStates.lockLookActive ? 1.0 : 0.0
        Behavior on opacity {
            SequentialAnimation {
                id: opacityAnim
                PauseAnimation { duration: GlobalStates.lockLookActive ? Math.round(150 * Appearance.animMultiplier) : 0 }
                NumberAnimation {
                    duration: Math.round(350 * Appearance.animMultiplier)
                    easing.type: Easing.OutCubic
                }
            }
        }
        sourceComponent: Item {
            anchors.fill: parent
            clip: true

            // MultiEffect's reduced blur levels are upsampled for large radii and can expose
            // their tile boundaries on a monitor-sized source. Capture the wallpaper at the exact
            // screen bounds and use the true GaussianBlur implementation. With transparentBorder
            // disabled below, the kernel clamps to the real edge pixels instead of sampling the
            // transparent area outside the source and exposing the sharp wallpaper underneath.
            ShaderEffectSource {
                id: blurSource
                anchors.fill: parent
                sourceItem: lockBlurRoot.sourceItem
                textureSize: Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2)))
                live: true
                smooth: true
                visible: false
            }

            GaussianBlur {
                anchors.fill: blurSource
                source: blurSource
                radius: lockBlurRoot.configuredBlurRadius * lockBlurRoot.blurProgress
                // Keep the kernel quality stable while radius animates, avoiding shader churn
                // and preserving smooth intermediate values throughout the lock transition.
                samples: Math.max(3, Math.round(lockBlurRoot.configuredBlurRadius * 2 + 1))
                transparentBorder: false
            }

            Rectangle {
                anchors.fill: parent
                color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0, 0.7)
            }
        }
    }
}
