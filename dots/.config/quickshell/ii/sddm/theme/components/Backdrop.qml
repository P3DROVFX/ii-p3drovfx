import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects

/**
 * The lock's wallpaper stack, in the shell's order:
 * wallpaper → blur (+ 30 % layer-0 dim) → desaturate → colour wash → vignette.
 * Each layer eases in when `active` turns on, with the lock's own timings,
 * and back out when it turns off (after a successful login).
 */
Item {
    id: root

    property bool active: false

    Rectangle {
        anchors.fill: parent
        color: Theme.colLayer0
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: Theme.wallpaper
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(root.width * Screen.devicePixelRatio, root.height * Screen.devicePixelRatio)
        asynchronous: false
        cache: false
        smooth: true
        mipmap: true
        visible: status === Image.Ready
    }

    // ── blur ───────────────────────────────────────────────────────────────
    property real blurProgress: 0
    SequentialAnimation {
        id: blurIn
        PauseAnimation { duration: Theme.ms(150) }
        NumberAnimation {
            target: root
            property: "blurProgress"
            to: 1
            duration: Theme.ms(350)
            easing.type: Easing.OutCubic
        }
    }
    NumberAnimation {
        id: blurOut
        target: root
        property: "blurProgress"
        to: 0
        duration: Theme.ms(350)
        easing.type: Easing.OutCubic
    }
    onActiveChanged: {
        blurIn.stop();
        blurOut.stop();
        (root.active ? blurIn : blurOut).start();
    }

    Item {
        id: blurLayer
        anchors.fill: parent
        clip: true
        visible: Theme.blurEnable && wallpaper.visible
        opacity: root.active ? 1 : 0
        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: root.active ? Theme.ms(150) : 0 }
                NumberAnimation {
                    duration: Theme.ms(350)
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Half-resolution capture and the true Gaussian kernel, as the shell does:
        // MultiEffect's blur shows tile seams at these radii on a monitor-sized source.
        ShaderEffectSource {
            id: blurSource
            anchors.fill: parent
            sourceItem: wallpaper
            textureSize: Qt.size(Math.max(1, Math.round(width / 2)), Math.max(1, Math.round(height / 2)))
            live: true
            smooth: true
            visible: false
        }

        GaussianBlur {
            anchors.fill: blurSource
            source: blurSource
            radius: Theme.blurRadius * root.blurProgress
            samples: Math.max(3, Math.round(Theme.blurRadius * 2 + 1))
            transparentBorder: false
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.transparentize(Theme.colLayer0, 0.7)
        }
    }

    // ── desaturate ─────────────────────────────────────────────────────────
    MultiEffect {
        anchors.fill: parent
        source: blurLayer.visible ? blurLayer : wallpaper
        visible: Theme.desaturateEnable && wallpaper.visible
        saturation: root.active ? -Theme.desaturateAmount : 0
        Behavior on saturation {
            NumberAnimation {
                duration: Theme.ms(600)
                easing.type: Easing.OutCubic
            }
        }
    }

    // ── colour wash ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: Theme.colorWashEnable
        color: Theme.m3primary
        opacity: root.active ? Theme.colorWashAmount : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.ms(600)
                easing.type: Easing.OutCubic
            }
        }
    }

    // ── vignette ───────────────────────────────────────────────────────────
    Canvas {
        id: vignette
        anchors.fill: parent
        visible: Theme.vignetteEnable
        opacity: root.active ? Theme.vignetteAmount : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.ms(700)
                easing.type: Easing.OutCubic
            }
        }
        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height;
            if (w <= 0 || h <= 0)
                return;
            ctx.clearRect(0, 0, w, h);
            const cx = w / 2, cy = h / 2;
            const outer = Math.hypot(cx, cy);
            const grad = ctx.createRadialGradient(cx, cy, outer * 0.35, cx, cy, outer);
            grad.addColorStop(0.0, "rgba(0, 0, 0, 0)");
            grad.addColorStop(0.5, "rgba(0, 0, 0, 0.3)");
            grad.addColorStop(0.8, "rgba(0, 0, 0, 0.7)");
            grad.addColorStop(1.0, "rgba(0, 0, 0, 0.95)");
            ctx.fillStyle = grad;
            ctx.fillRect(0, 0, w, h);
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
}
