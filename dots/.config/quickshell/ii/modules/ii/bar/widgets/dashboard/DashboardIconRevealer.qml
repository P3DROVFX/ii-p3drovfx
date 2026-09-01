pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/*
 * Two-stage indicator transition for dashboard buttons.
 *
 * Entry reserves the final layout slot before revealing the icon. Exit keeps
 * that slot in place until the icon has scaled away. This prevents clipping
 * the glyph against a container that is changing size at the same time.
 */
Item {
    id: root

    default property alias content: contentHost.data

    // AnimatedIcon walks its ancestors looking for this marker. Keeping the
    // cue queue here makes the glyph animation follow the same lifecycle as
    // the slot that is revealing it, without coupling every icon to the bar.
    readonly property bool dashboardIconPresenceController: true

    property bool reveal: false
    property bool vertical: false
    property real layoutSpacing: 0.0
    property real collapsedScale: 0.68

    property real layoutProgress: 0.0
    property real contentProgress: 0.0
    property bool animationsReady: false
    property bool exitHoldElapsed: false
    property Item pendingCueTarget: null
    property string pendingCue: ""

    readonly property real contentWidth: Math.max(0.0, contentHost.childrenRect.width)
    readonly property real contentHeight: Math.max(0.0, contentHost.childrenRect.height)
    readonly property real slotWidth: root.contentWidth + (root.vertical ? 0.0 : root.layoutSpacing)
    readonly property real slotHeight: root.contentHeight + (root.vertical ? root.layoutSpacing : 0.0)

    implicitWidth: root.vertical ? root.contentWidth : root.slotWidth * root.layoutProgress
    implicitHeight: root.vertical ? root.slotHeight * root.layoutProgress : root.contentHeight
    visible: root.reveal || root.layoutProgress > 0.001 || root.contentProgress > 0.001
    clip: true

    function stopAnimations(): void {
        layoutAnimation.stop();
        contentEnterAnimation.stop();
        contentExitAnimation.stop();
    }

    function queueIconCue(target: Item, cue: string): void {
        if (!target || cue.length === 0)
            return;

        const fullyHidden = root.layoutProgress <= 0.001 && root.contentProgress <= 0.001;
        if ((root.reveal || fullyHidden) && root.contentProgress <= 0.001) {
            // State signals can arrive before or after the reveal binding. In
            // either order, retain only the newest cue and play it once the
            // slot is ready, immediately before the content pop starts.
            root.pendingCueTarget = target;
            root.pendingCue = cue;
            if (root.animationsReady && root.reveal && root.layoutProgress >= 0.999) {
                // A cue may land in the tiny gap between starting the pop and
                // its first rendered frame. Stop that animation so the delay
                // still precedes the scale rather than running beside it.
                contentEnterAnimation.stop();
                root.continueSequence();
            }
            return;
        }

        // Exit cues start while the vector is still full-size. continueSequence
        // holds that frame briefly before scaling the icon away.
        target.play(cue);
    }

    function beginPendingCue(): void {
        if (!root.reveal || !root.pendingCueTarget || root.pendingCue.length === 0)
            return;
        const target = root.pendingCueTarget;
        const cue = root.pendingCue;
        root.pendingCueTarget = null;
        root.pendingCue = "";
        target.play(cue);
        entryCueTimer.restart();
    }

    function animateLayout(targetValue: real): void {
        const distance = Math.abs(targetValue - root.layoutProgress);
        if (distance <= 0.001) {
            root.layoutProgress = targetValue;
            root.continueSequence();
            return;
        }

        layoutAnimation.to = targetValue;
        layoutAnimation.duration = Math.max(1, Math.round(Appearance.animation.dashboardIndicatorResize.duration * distance));
        layoutAnimation.restart();
    }

    function animateContent(targetValue: real): void {
        const distance = Math.abs(targetValue - root.contentProgress);
        if (distance <= 0.001) {
            root.contentProgress = targetValue;
            root.continueSequence();
            return;
        }

        if (targetValue > root.contentProgress) {
            contentEnterAnimation.duration = Math.max(1, Math.round(Appearance.animation.dashboardIndicatorPop.enterDuration * distance));
            contentEnterAnimation.restart();
        } else {
            contentExitAnimation.duration = Math.max(1, Math.round(Appearance.animation.dashboardIndicatorPop.exitDuration * distance));
            contentExitAnimation.restart();
        }
    }

    function continueSequence(): void {
        if (!root.animationsReady)
            return;

        if (root.reveal) {
            if (root.layoutProgress < 0.999)
                root.animateLayout(1.0);
            else if (root.contentProgress < 0.999) {
                if (root.contentProgress <= 0.001 && root.pendingCueTarget)
                    root.beginPendingCue();
                else if (!entryCueTimer.running)
                    root.animateContent(1.0);
            }
            else {
                root.layoutProgress = 1.0;
                root.contentProgress = 1.0;
            }
        } else {
            if (root.contentProgress > 0.001) {
                if (root.exitHoldElapsed)
                    root.animateContent(0.0);
                else if (!exitHoldTimer.running)
                    exitHoldTimer.restart();
            }
            else if (root.layoutProgress > 0.001)
                root.animateLayout(0.0);
            else {
                root.contentProgress = 0.0;
                root.layoutProgress = 0.0;
            }
        }
    }

    onRevealChanged: {
        if (!root.animationsReady)
            return;
        root.stopAnimations();
        entryCueTimer.stop();
        exitHoldTimer.stop();
        root.exitHoldElapsed = false;
        if (!root.reveal) {
            root.pendingCueTarget = null;
            root.pendingCue = "";
        }
        root.continueSequence();
    }

    Component.onCompleted: {
        root.layoutProgress = root.reveal ? 1.0 : 0.0;
        root.contentProgress = root.layoutProgress;
        root.animationsReady = true;
    }

    Timer {
        id: entryCueTimer
        interval: Appearance.animation.dashboardIndicatorPop.cueDelay
        repeat: false
        onTriggered: root.continueSequence()
    }

    Timer {
        id: exitHoldTimer
        interval: Appearance.animation.dashboardIndicatorPop.exitHoldDuration
        repeat: false
        onTriggered: {
            root.exitHoldElapsed = true;
            root.continueSequence();
        }
    }

    NumberAnimation {
        id: layoutAnimation
        target: root
        property: "layoutProgress"
        easing.type: Appearance.animation.dashboardIndicatorResize.type
        easing.bezierCurve: Appearance.animation.dashboardIndicatorResize.bezierCurve
        onFinished: root.continueSequence()
    }

    NumberAnimation {
        id: contentEnterAnimation
        target: root
        property: "contentProgress"
        to: 1.0
        easing.type: Appearance.animation.dashboardIndicatorPop.enterType
        easing.overshoot: Appearance.animation.dashboardIndicatorPop.enterOvershoot
        onFinished: root.continueSequence()
    }

    NumberAnimation {
        id: contentExitAnimation
        target: root
        property: "contentProgress"
        to: 0.0
        easing.type: Appearance.animation.dashboardIndicatorPop.exitType
        easing.bezierCurve: Appearance.animation.dashboardIndicatorPop.exitCurve
        onFinished: root.continueSequence()
    }

    Item {
        id: contentHost
        width: childrenRect.width
        height: childrenRect.height
        anchors.centerIn: parent
        opacity: root.contentProgress
        scale: root.collapsedScale + (1.0 - root.collapsedScale) * root.contentProgress
        transformOrigin: Item.Center
    }
}
