pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The one thing a fresh tablet install has to get past.
 *
 * Two of this shell's capabilities are native helpers that ship as source: the daemon
 * that raises the keyboard when a text field is tapped, and the daemon that reads touch
 * gestures. Neither runs until someone compiles it, and on a tablet that was a closed
 * loop — the two things standing between a device with no keyboard and a usable shell
 * were exactly the two things whose fix required a keyboard to type.
 *
 * Nothing said so, either. The switches were on, the page looked complete, and tapping a
 * text field simply did nothing. So the family says it out loud, once, on the first
 * launch where something is missing, with the build as a button.
 *
 * Dismissal is remembered. This is a prompt, not a nag: "Do it later" means later, not
 * "ask me again in ninety seconds", and a new missing helper is what makes it return.
 */
Scope {
    id: root

    readonly property bool oskMissing: !OskAutoShow.binaryExists
    readonly property bool gesturesMissing: !TouchGestureService.binaryExists
    readonly property bool anythingMissing: root.oskMissing || root.gesturesMissing

    /**
     * Which helpers this window is about, latched.
     *
     * The rows have a built state — a check on the accent container — and binding their
     * visibility to "is missing" meant the row deleted itself the instant the build
     * succeeded, so the finished state it was drawn for could never be seen. What the
     * window is *about* is decided when it opens; whether each one is done is what the
     * rows then show.
     */
    property bool tracksOsk: false
    property bool tracksGestures: false

    // Latched when the window first opens, not at completion: `binaryExists` starts
    // false and is corrected a moment later by a `test -f`, so seeding at completion
    // tracked helpers that were there all along. By the time `shouldShow` is true the
    // settle timer has long since let those checks resolve.
    onShouldShowChanged: {
        if (!root.shouldShow)
            return;
        root.tracksOsk = root.tracksOsk || root.oskMissing;
        root.tracksGestures = root.tracksGestures || root.gesturesMissing;
    }

    /// What is missing right now, as a stable string. Dismissing remembers this, so a
    /// second helper going missing later is a different prompt and shows again.
    readonly property string missingSignature: `${root.oskMissing ? "osk" : ""}+${root.gesturesMissing ? "gestures" : ""}`

    readonly property bool dismissed: Persistent.ready
        && Persistent.states.tablet.helperSetupDismissed === root.missingSignature

    /// Held back until the shell has finished coming up. A modal over a half-drawn
    /// desktop reads as a crash report, not as a welcome.
    property bool settled: false

    /**
     * Whether a build has been started from here this session.
     *
     * Without this the window closed the instant the last build succeeded, so the one
     * thing the user pressed the button to find out — whether it worked — flashed past
     * on the way out. A result nobody sees is not a result.
     */
    readonly property bool sessionTouched: OskAutoShow.building || TouchGestureService.building
        || OskAutoShow.buildResult.length > 0 || TouchGestureService.buildResult.length > 0

    readonly property bool shouldShow: Config.ready && Persistent.ready && root.settled
        && (root.anythingMissing || root.sessionTouched)
        && !root.dismissed && !GlobalStates.screenLocked

    readonly property Timer _settleTimer: Timer {
        interval: 2500
        repeat: false
        running: true
        onTriggered: root.settled = true
    }

    function dismiss() {
        if (Persistent.ready)
            Persistent.states.tablet.helperSetupDismissed = root.missingSignature;
    }

    /// `qs -c ii ipc call tabletSetup open` — for anyone who dismissed it and wants it
    /// back without hunting for the Settings page.
    ///
    /// Named `open` rather than `show` because `qs ipc call <target> show` collides with
    /// the CLI's own `ipc show` and prints the target's signature instead of calling it.
    IpcHandler {
        target: "tabletSetup"

        function open(): string {
            if (!root.anythingMissing)
                return "Both helpers are built; nothing to set up.";
            if (Persistent.ready)
                Persistent.states.tablet.helperSetupDismissed = "";
            root.settled = true;
            return "Setup shown.";
        }

        /// Starts whichever helpers are missing, as the window's buttons do. Useful for
        /// a first-boot script, and for anyone who would rather not wait for the window.
        function build(): string {
            if (!root.anythingMissing)
                return "Both helpers are already built.";
            if (root.oskMissing)
                OskAutoShow.buildHelper();
            if (root.gesturesMissing)
                TouchGestureService.buildHelper();
            return "Building. Watch Settings › Tablet, or call status.";
        }

        function status(): string {
            const helper = (name, service) => {
                if (service.building)
                    return `${name}: building (${service.buildProgress}, ${service.buildUnits} crates, ${service.buildSeconds}s)`;
                if (service.buildResult === "failed")
                    return `${name}: build failed`;
                return `${name}: ${service.binaryExists ? "built" : "missing"}`;
            };
            return helper("on-screen keyboard helper", OskAutoShow)
                + ", " + helper("touch gesture daemon", TouchGestureService);
        }
    }

    /**
     * A real window, not an overlay.
     *
     * The first draft dimmed the whole screen behind a modal, which is the vocabulary of
     * something urgent and blocking — and this is neither. It is the same kind of thing
     * the Welcome window is: a piece of setup you deal with when you feel like it, in a
     * window you can move, with the desktop behind it untouched. So it is a
     * FloatingWindow, like Welcome, and it shades nothing.
     */
    FloatingWindow {
        id: setupWindow

        visible: root.shouldShow
        title: qsTr("Set up touch and pen · illogical-impulse")
        implicitWidth: 620
        implicitHeight: 500
        minimumSize: Qt.size(520, 440)
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer0

            TabletHelperSetupContent {
                anchors.fill: parent
                anchors.margins: 26
                tracksOsk: root.tracksOsk
                tracksGestures: root.tracksGestures
                onDismissed: root.dismiss()
            }
        }
    }
}
