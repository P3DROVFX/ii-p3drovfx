import QtQuick
import QtQuick.Window
import qs.services

/**
 * A texture of fine contour lines behind a surface (see shaders/topography.frag). While
 * `running` the field drifts slowly; when it stops it holds still, so a bypassed preset
 * keeps its texture and loses only the motion. Nothing ticks while the window is hidden
 * or motion is reduced.
 *
 * It listens to the music (CavaService, already running whenever a player plays): the
 * drift speeds up with the overall level and the field breathes with the bass, both
 * smoothed (quick to rise, slow to settle) so a beat swells the lines instead of flickering
 * them. With nothing playing the envelopes settle and the slow drift is all that is left.
 *
 * Cut to the surface's rounded corners by the shader itself, so the card needs neither a
 * clip nor a mask.
 */
ShaderEffect {
    id: root

    property bool running: false
    /// The lines' colour, and how opaque they are.
    property color baseColor: EasyEffectsStyle.colOnSurface
    property real lineOpacity: EasyEffectsStyle.opacityTopography
    property real cornerRadius: EasyEffectsStyle.radiusPane
    property real speed: EasyEffectsStyle.topographySpeed

    /// Follow the music; off, the field only drifts.
    property bool reactive: true
    /// Smoothed loudness and bass of what is playing, 0..1.
    property real level: 0
    property real pulse: 0
    /// A short swell on each beat: how fast the bass just rose, easing back down.
    property real beat: 0
    property real _lastBass: 0

    property real time: 0
    property vector2d resolution: Qt.vector2d(width, height)

    // Uniforms of topography.frag, by name (`scale` is taken: Item has one).
    property color lineColor: Qt.rgba(root.baseColor.r, root.baseColor.g, root.baseColor.b, root.lineOpacity)
    property real levels: EasyEffectsStyle.topographyLevels
    property real hillSize: EasyEffectsStyle.topographyScale
    property real radius: root.cornerRadius
    property real thinWidth: EasyEffectsStyle.topographyThin
    property real indexWidth: EasyEffectsStyle.topographyIndex
    // (`pulse` above is also the shader's uniform.)

    readonly property bool active: root.running && root.visible && (Window.window?.visible ?? false)
        && !EasyEffectsStyle.reducedMotion

    Behavior on lineOpacity {
        enabled: !EasyEffectsStyle.reducedMotion
        animation: EasyEffectsStyle.motionDefault.numberAnimation.createObject(root)
    }

    Timer {
        // About 30 frames a second: the field moves too slowly to need more, and every tick
        // is a frame the compositor has to present.
        interval: EasyEffectsStyle.topographyTick
        repeat: true
        running: root.active
        onTriggered: {
            root.listen();
            root.time += interval / 1000 * root.speed * (1 + EasyEffectsStyle.topographyReactivity * root.level
                + EasyEffectsStyle.topographyBeatBoost * root.beat);
        }
    }

    // One reading of the spectrum per tick, folded into the two envelopes.
    function listen(): void {
        const points = root.reactive && CavaService.active ? CavaService.visualizerPoints : [];
        let low = 0;
        let all = 0;
        const lowBars = Math.min(points.length, EasyEffectsStyle.topographyBassBars);
        for (let i = 0; i < points.length; i++) {
            all += points[i];
            if (i < lowBars)
                low += points[i];
        }
        const loudness = points.length > 0 ? Math.min(1, all / points.length / EasyEffectsStyle.cavaPeak) : 0;
        const bass = lowBars > 0 ? Math.min(1, low / lowBars / EasyEffectsStyle.cavaPeak) : 0;
        // What moves the field is the music's change, not its volume: a beat is the bass
        // rising fast, so a driving track swells it constantly and a calm one hardly at all.
        const rise = Math.max(0, bass - root._lastBass);
        root._lastBass = bass;
        root.beat = Math.max(root.beat * EasyEffectsStyle.beatDecay, Math.min(1, rise * EasyEffectsStyle.beatGain));
        // The square root lifts quiet passages out of the floor without capping loud ones.
        root.level = root.follow(root.level, Math.sqrt(loudness));
        root.pulse = root.follow(root.pulse, Math.min(1, Math.sqrt(bass) * 0.6 + root.beat * 0.8));
    }

    function follow(current: real, target: real): real {
        return current + (target - current) * (target > current ? EasyEffectsStyle.envelopeAttack : EasyEffectsStyle.envelopeRelease);
    }

    fragmentShader: Qt.resolvedUrl("shaders/topography.frag.qsb")
}
