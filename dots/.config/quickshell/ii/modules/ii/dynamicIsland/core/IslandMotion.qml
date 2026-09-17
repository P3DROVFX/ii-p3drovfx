pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Motion tokens for the Dynamic Island.
 *
 * Geometry moves on springs, not on fixed-duration curves. The island is constantly
 * retargeted mid-flight - a hover that arrives while an activity is still detaching, a
 * notification landing during an expand - and a spring keeps the velocity it already had
 * when the target changes, which is what makes the movement read as one physical object.
 * A NumberAnimation restarts from zero velocity on every retarget and visibly stutters.
 *
 * Content (opacity, blur, small scales) keeps using the shell's own curves, so the island
 * still feels like the rest of the shell.
 */
Singleton {
    id: root

    // The user's animation multiplier scales a spring through its mass: period grows
    // with the square root of mass, so this stays proportional rather than exact, and
    // never reaches zero (a massless spring snaps and rings).
    readonly property real mass: Math.max(0.35, Appearance.animMultiplier)
    readonly property bool reduced: Appearance.reducedMotion

    // Morph: a surface changing size or shape in place.
    readonly property QtObject morph: QtObject {
        readonly property real spring: 4.2
        readonly property real damping: 0.30
        readonly property real epsilon: 0.25
    }

    // Push: a neighbour making room. Looser, so being pushed reads as a consequence.
    readonly property QtObject push: QtObject {
        readonly property real spring: 3.6
        readonly property real damping: 0.26
        readonly property real epsilon: 0.25
    }

    // Detach: a satellite separating from the centre. The loosest of the three, because
    // this is the moment the movement is *about*.
    readonly property QtObject detach: QtObject {
        readonly property real spring: 3.0
        readonly property real damping: 0.22
        readonly property real epsilon: 0.25
    }

    // Settle: growing into a large surface (the dashboard, search). Tight damping, since
    // a big panel that wobbles looks broken rather than lively.
    readonly property QtObject settle: QtObject {
        readonly property real spring: 5.0
        readonly property real damping: 0.42
        readonly property real epsilon: 0.25
    }

    // Content transitions borrow the shell's curves.
    readonly property QtObject effects: Appearance.animation.elementMoveFast
    readonly property QtObject enter: Appearance.animation.elementMoveEnter
    readonly property QtObject exit: Appearance.animation.elementMoveExit

    // Geometry, all derived from tokens or from the user's own sizing.
    // Until the new config block lands these fall back to their defaults, so the
    // engine does not depend on the migration having run.
    readonly property real pillHeight: Config.options.bar.floatingNotch.pillHeight ?? 38
    readonly property real orbSize: root.pillHeight
    readonly property real clusterGap: Config.options.bar.floatingNotch.pillGap ?? 8
    readonly property real compactRadius: root.pillHeight / 2
    readonly property real expandedRadius: Appearance.rounding.verylarge
    readonly property real dashboardRadius: Appearance.rounding.verylarge

    // The gap at which the liquid neck between two shapes breaks.
    readonly property real gooThreshold: root.clusterGap * 3.25
    readonly property real gooMaximum: root.pillHeight * 0.47
}
