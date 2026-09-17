pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

// Two decoded surfaces: never replace the displayed image with a loading one.
Item {
    id: root
    property size artSize: Qt.size(Math.ceil(width), Math.ceil(height))
    property string artSource: ""
    property string trackKey: ""
    property bool hasPlayer: false
    property bool playing: false
    property real wide: 0
    readonly property bool animationsEnabled: Config.options.media.albumArtBlurAnimations
    property bool initialized: false
    property bool firstVisible: true
    property bool waiting: false
    property real blurProgress: 0
    property real pauseBlur: root.animationsEnabled && root.hasPlayer && !root.playing ? 1 : 0
    readonly property real effectiveBlur: root.animationsEnabled ? Math.max(root.blurProgress, root.pauseBlur) : 0
    Behavior on pauseBlur {
        enabled: root.initialized && root.animationsEnabled
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
    }
    readonly property var displayed: firstVisible ? first : second
    readonly property var pending: firstVisible ? second : first

    onAnimationsEnabledChanged: {
        if (!root.initialized) return;
        if (!root.animationsEnabled) {
            obscure.stop();
            reveal.stop();
            root.blurProgress = 0;
            if (root.waiting) root.commitIfReady();
            else root.pending.art = "";
        } else if (root.waiting) {
            obscure.restart();
        }
    }

    function beginChange(): void {
        if (!root.initialized || !root.hasPlayer) return;
        reveal.stop();
        root.waiting = true;
        // Discard an older pending request before a rapid next/previous click.
        root.pending.art = "";
        if (root.animationsEnabled) obscure.restart();
    }
    function requestArt(allowSameCover = false): void {
        if (!root.initialized) return;
        if (!root.hasPlayer) {
            obscure.stop();
            reveal.stop();
            first.art = "";
            second.art = "";
            root.waiting = false;
            root.blurProgress = 0;
            return;
        }
        if (!root.waiting && root.displayed.art === root.artSource)
            return;
        if (!root.waiting) root.beginChange();
        // A title can arrive before art metadata. Do not sharpen the old URL
        // prematurely; postTrackChanged confirms intentionally shared covers.
        if (!allowSameCover && root.artSource === root.displayed.art && root.displayed.art !== "")
            return;
        // Empty metadata is not a reason to drop the previous cover.
        root.pending.art = root.artSource;
        root.commitIfReady();
    }
    function commitIfReady(): void {
        if (!root.waiting || (root.animationsEnabled && (obscure.running || root.blurProgress < 1))
                || !root.pending.ready || root.pending.art !== root.artSource)
            return;
        root.firstVisible = !root.firstVisible;
        root.waiting = false;
        // The new decoded surface starts with exactly the outgoing blur/zoom.
        if (root.animationsEnabled) {
            reveal.restart();
        } else {
            root.blurProgress = 0;
            root.pending.art = "";
        }
    }
    onTrackKeyChanged: {
        root.beginChange();
        Qt.callLater(root.requestArt);
    }
    onArtSourceChanged: {
        root.beginChange();
        Qt.callLater(root.requestArt);
    }
    onHasPlayerChanged: Qt.callLater(root.requestArt)
    Component.onCompleted: {
        root.initialized = true;
        root.requestArt();
    }

    NumberAnimation {
        id: obscure
        target: root
        property: "blurProgress"
        to: 1
        duration: Appearance.animation.elementMoveFast.duration
        easing.type: Appearance.animation.elementMoveFast.type
        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        onFinished: root.commitIfReady()
    }
    NumberAnimation {
        id: reveal
        target: root
        property: "blurProgress"
        to: 0
        duration: Appearance.animation.elementMove.duration
        easing.type: Appearance.animation.elementMove.type
        easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        onFinished: root.pending.art = ""
    }

    component Artwork: Item {
        id: surface
        property string art: ""
        readonly property bool ready: art !== "" && compact.status === Image.Ready && expanded.artReady
        onReadyChanged: root.commitIfReady()
        anchors.fill: parent

        Image {
            id: compact
            anchors.fill: parent
            source: surface.art
            asynchronous: true
            cache: true
            sourceSize: root.artSize
            fillMode: Image.PreserveAspectCrop
            opacity: 0.8 * (1 - root.wide)
            layer.enabled: surface.art !== ""
            layer.effect: StyledBlurEffect { blurMax: 32 }
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.6)
            }
        }
        AndroidMediaBackdrop {
            id: expanded
            anchors.fill: parent
            artSource: surface.art
            playing: root.playing
            opacity: root.wide
        }
    }

    Item {
        anchors.fill: parent
        // Modest optical push during the cover handoff, not a tile resize.
        scale: 1 + (root.animationsEnabled ? 0.055 * root.blurProgress : 0)
        layer.enabled: root.effectiveBlur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 48
            blur: root.effectiveBlur
        }
        Artwork { id: first; visible: root.firstVisible }
        Artwork { id: second; visible: !root.firstVisible }
    }
}
