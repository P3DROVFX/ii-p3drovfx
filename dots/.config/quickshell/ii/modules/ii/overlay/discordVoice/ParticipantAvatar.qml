pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import "ParticipantVisualState.js" as ParticipantVisualState

Item {
    id: root
    required property var participant
    property real avatarSize: 44
    property bool showName: false
    property bool horizontalLayout: false
    property bool nameOnLeft: false
    property real maxNameWidth: 88
    property string backgroundMode: "none"
    property real backgroundOpacity: 0.72
    property bool speaking: participant?.speaking === true
    property real transitionScale: 1
    property real transitionRotation: 0
    property bool componentReady: false
    property var displayedShape: MaterialShape.Shape.Circle

    // A desaturated version of the theme accent reads as a calm status cue.
    // Saturation alone isn't enough to tame it though: colPrimary is a light
    // token by design, so it stays high-luminance (bright) against the dark
    // overlay even fully desaturated. Pull lightness toward the background
    // token too so the actual brightness, not just the colorfulness, drops.
    function mutedAccent(base, bg) {
        const c = Qt.color(base)
        const b = Qt.color(bg)
        const sat = c.hslSaturation * 0.35
        const light = c.hslLightness * 0.45 + b.hslLightness * 0.55
        return Qt.hsla(c.hslHue, sat, light, c.a)
    }
    readonly property color speakingColor: mutedAccent(Appearance.colors.colPrimary, Appearance.colors.colLayer2)
    readonly property bool pulseContinuous: Config.options.overlay.discordVoice.speakingPulseContinuous

    // Plain (unbound) property so both the one-shot transition Behavior and
    // the looping pulse Animation below can drive it without fighting a
    // binding on ring.scale itself.
    property real speakingScale: 1

    Behavior on speakingScale {
        enabled: !speakingPulse.running
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack }
    }

    readonly property real speakingRingShrink: 1
    property real ringShrink: 1

    Behavior on ringShrink {
        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack }
    }

    onSpeakingChanged: {
        root.ringShrink = root.speaking ? root.speakingRingShrink : 1
        if (!root.speaking) {
            speakingPulse.stop()
            root.speakingScale = 1
        } else if (root.pulseContinuous) {
            speakingPulse.restart()
        } else {
            root.speakingScale = 1.03
        }
    }

    SequentialAnimation {
        id: speakingPulse
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "speakingScale"; to: 1.035; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "speakingScale"; to: 1; duration: 900; easing.type: Easing.InOutSine }
    }
    readonly property var avatarShape: participant?.deaf
        ? MaterialShape.Shape.Boom
        : (participant?.mute
            ? MaterialShape.Shape.Cookie4Sided
            : MaterialShape.Shape.Circle)

    implicitWidth: root.horizontalLayout
        ? Math.max(176, root.avatarSize + root.maxNameWidth + 16)
        : (root.showName
            ? Math.max(root.avatarSize, root.maxNameWidth + 16)
            : root.avatarSize)
    implicitHeight: root.horizontalLayout ? root.avatarSize + 12
        : root.avatarSize + (root.showName ? nameText.implicitHeight + 16 : 12)

    function transitionToCurrentShape() {
        ParticipantVisualState.remember(root.participant?.id, root.avatarShape)
        if (root.displayedShape === root.avatarShape)
            return
        root.displayedShape = root.avatarShape
        stateTransition.restart()
    }

    onAvatarShapeChanged: if (componentReady) transitionToCurrentShape()
    Component.onCompleted: {
        const previousShape = ParticipantVisualState.previous(root.participant?.id, root.avatarShape)
        root.displayedShape = previousShape
        root.componentReady = true
        ParticipantVisualState.remember(root.participant?.id, root.avatarShape)
        if (previousShape !== root.avatarShape)
            Qt.callLater(root.transitionToCurrentShape)
    }

    SequentialAnimation {
        id: stateTransition
        ParallelAnimation {
            NumberAnimation { target: root; property: "transitionScale"; to: 0.82; duration: 90; easing.type: Easing.InCubic }
            NumberAnimation { target: root; property: "transitionRotation"; to: -7; duration: 90; easing.type: Easing.InCubic }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "transitionScale"; to: 1; duration: 280; easing.type: Easing.OutBack }
            NumberAnimation { target: root; property: "transitionRotation"; to: 0; duration: 280; easing.type: Easing.OutBack }
        }
    }

    Rectangle {
        visible: root.backgroundMode === "card"
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: ColorUtils.transparentize(Appearance.colors.colLayer2, 1 - root.backgroundOpacity)
        border.width: Appearance.borderWidth.standard
        border.color: Appearance.colors.colLayer0Border
    }

    MaterialShape {
        id: glowSource
        anchors.centerIn: ring
        width: ring.width
        height: ring.height
        shape: root.displayedShape
        color: root.speakingColor
        visible: false
    }
    Glow {
        anchors.fill: glowSource
        source: glowSource
        color: root.speakingColor
        radius: 12
        samples: 25
        spread: 0.25
        transparentBorder: true
        opacity: root.speaking ? 0.45 : 0
        scale: root.speakingScale
        Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration } }
    }

    MaterialShape {
        id: ring
        x: root.horizontalLayout
            ? (root.nameOnLeft ? root.width - width - 6 : 6)
            : Math.round((root.width - width) / 2)
        y: root.horizontalLayout ? Math.round((root.height - height) / 2) : 8
        width: root.avatarSize
        height: root.avatarSize
        shape: root.displayedShape
        color: root.speaking ? root.speakingColor : Appearance.colors.colLayer2
        scale: root.speakingScale * root.transitionScale * root.ringShrink
        rotation: root.transitionRotation

        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

        Image {
            id: avatar
            anchors.fill: parent
            anchors.margins: 2
            source: DiscordVoice.avatarUrl(root.participant, 128)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MaterialShape {
            id: avatarMask
            anchors.fill: avatar
            shape: root.displayedShape
            visible: false
        }
        OpacityMask {
            anchors.fill: avatar
            source: avatar
            maskSource: avatarMask
            visible: avatar.status === Image.Ready
        }
        MaterialSymbol {
            anchors.centerIn: parent
            visible: avatar.status !== Image.Ready
            text: "person"
            iconSize: root.avatarSize * 0.52
            color: Appearance.colors.colOnLayer2
        }

        MaterialShapeWrappedMaterialSymbol {
            visible: root.participant?.mute || root.participant?.deaf
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            implicitSize: 20
            shape: root.participant?.deaf
                ? MaterialShape.Shape.Boom : MaterialShape.Shape.Cookie4Sided
            color: Appearance.colors.colErrorContainer
            text: root.participant?.deaf ? "headset_off" : "mic_off"
            iconSize: 12
            padding: 2
            colSymbol: Appearance.colors.colOnErrorContainer
        }

        // Your local setting for this person, not theirs: muted for you, or
        // turned away from Discord's 100%.
        MaterialShapeWrappedMaterialSymbol {
            readonly property real volume: root.participant?.volume ?? 100
            readonly property bool localMuted: root.participant?.localMute === true
            visible: localMuted || Math.abs(volume - 100) >= 1
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            implicitSize: 20
            shape: localMuted ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Pill
            color: localMuted ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
            text: localMuted || volume <= 0 ? "volume_off" : (volume < 100 ? "volume_down" : "volume_up")
            iconSize: 12
            padding: 2
            colSymbol: localMuted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
        }
    }

    StyledText {
        id: nameText
        z: 2
        visible: root.showName
        x: root.horizontalLayout
            ? (root.nameOnLeft
                ? ring.x - 8 - width
                : ring.x + root.avatarSize + 8)
            : Math.round((root.width - width) / 2)
        y: root.horizontalLayout
            ? Math.round((root.avatarSize - height) / 2)
            : ring.y + root.avatarSize + 4
        width: root.horizontalLayout
            ? Math.min(root.maxNameWidth, implicitWidth)
            : Math.min(root.width - 8, root.maxNameWidth)
        text: root.participant?.nick || root.participant?.username || "Unknown"
        elide: Text.ElideRight
        horizontalAlignment: root.horizontalLayout
            ? (root.nameOnLeft ? Text.AlignRight : Text.AlignLeft)
            : Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer1
    }

    Rectangle {
        visible: root.showName && root.backgroundMode === "name"
        z: 1
        x: nameText.x - 8
        y: nameText.y - 3
        width: nameText.width + 16
        height: nameText.height + 6
        radius: Appearance.rounding.verysmall
        color: ColorUtils.transparentize(Appearance.colors.colLayer2, 1 - root.backgroundOpacity)
        border.width: Appearance.borderWidth.standard
        border.color: Appearance.colors.colLayer0Border
    }
}
