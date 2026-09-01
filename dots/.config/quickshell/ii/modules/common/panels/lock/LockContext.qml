import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    // Whether to arm pam_fprintd at all. The Fingerprint service owns the
    // enrolled list and re-lists after every enrollment or deletion, so a print
    // added from settings works on the very next lock instead of only after a
    // shell restart. `busy` covers the reader being claimed by an enrollment or
    // a test scan — arming PAM against a claimed device just yields
    // PAM_AUTHINFO_UNAVAIL and starts the retry ladder for no reason.
    readonly property bool fingerprintEnabled: Config.options?.lock?.security?.fingerprint?.enable ?? true
    readonly property bool fingerprintsConfigured: root.fingerprintEnabled && Fingerprint.hasEnrolled && !Fingerprint.busy
    // Shown on the lock screen instead of silently falling back to the password
    // box: either the reader is gone, or the backoff ladder has given up on it.
    readonly property bool fingerprintUnavailable: !Fingerprint.deviceAvailable || (root.fingerRetries >= root.fingerMaxRetries && !fingerPam.active)
    readonly property bool fingerprintIndicatorVisible: root.fingerprintEnabled && (Config.options?.lock?.security?.fingerprint?.showIndicator ?? true) && Fingerprint.hasEnrolled
    // pam_fprintd default max-tries is 3 (pam/fprintd.conf passes no override)
    readonly property int fingerprintMaxTries: 3
    property int fingerprintTriesLeft: fingerprintMaxTries
    signal fingerprintFailed()
    // Held from hypridle's before_sleep_cmd until after_sleep_cmd, so nothing
    // re-arms the reader while the system is on its way into suspend.
    property bool fingerSuspendInhibit: false
    property int fingerRetries: 0
    readonly property int fingerMaxRetries: 5
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        stopFingerPam();
    }

    Timer {
        id: passwordClearTimer
        interval: 10000
        onTriggered: {
            root.reset();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        pam.start();
    }

    function tryFingerUnlock() {
        if (!root.fingerprintsConfigured || root.fingerSuspendInhibit)
            return;
        // Each start() is a fresh PAM transaction, so pam_fprintd's
        // internal try counter resets too.
        root.fingerprintTriesLeft = root.fingerprintMaxTries;
        fingerPam.start();
    }

    // hypridle's before_sleep_cmd calls this. Suspending with a verify in
    // flight crashes some readers' drivers (egismoc), and the lock itself may
    // still be arming the reader when this lands, so latch the inhibit rather
    // than just aborting: whichever order they arrive in, nothing re-arms.
    function suspendFingerUnlock() {
        root.fingerSuspendInhibit = true;
        stopFingerPam();
        fingerInhibitFailsafeTimer.restart();
    }

    // Failsafe for an aborted suspend, where after_sleep_cmd never runs and
    // would otherwise leave the reader inhibited until the next unlock.
    Timer {
        id: fingerInhibitFailsafeTimer
        interval: 20000
        onTriggered: root.restartFingerUnlock()
    }

    // The refocus signal also fires from hypridle's after_sleep_cmd. A verify
    // that was in flight across suspend is dead, so trade it for a fresh
    // transaction. No-op when unlocked or without fingerprints.
    onShouldReFocus: restartFingerUnlock()

    function restartFingerUnlock() {
        fingerInhibitFailsafeTimer.stop();
        root.fingerSuspendInhibit = false;
        root.fingerRetries = 0;
        // A resume is exactly when the reader may have gone away or come back,
        // so re-check it rather than trusting what was probed at startup.
        Fingerprint.probeDevice();
        if (!root.fingerprintsConfigured || !GlobalStates.screenLocked)
            return;
        stopFingerPam();
        scheduleFingerRetry();
    }

    // The reader USB-resets a second or two after "PM: suspend exit" and fprintd
    // may still be coming back, so a single fixed delay races them. Back off
    // instead, and give up rather than hammering a reader that is really gone.
    function scheduleFingerRetry() {
        if (!root.fingerprintsConfigured || !GlobalStates.screenLocked)
            return;
        if (root.fingerSuspendInhibit || root.fingerRetries >= root.fingerMaxRetries)
            return;
        fingerRestartTimer.interval = Math.min(1000 * Math.pow(2, root.fingerRetries), 8000);
        root.fingerRetries++;
        fingerRestartTimer.restart();
    }

    Timer {
        id: fingerRestartTimer
        interval: 1000
        onTriggered: {
            if (GlobalStates.screenLocked)
                root.tryFingerUnlock();
        }
    }

    function stopFingerPam() {
        fingerRestartTimer.stop();
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    // Turning fingerprint unlock off from settings, or claiming the reader for
    // an enrollment, has to take effect on an already-showing lock screen too.
    onFingerprintsConfiguredChanged: {
        if (!root.fingerprintsConfigured) {
            stopFingerPam();
            return;
        }
        if (GlobalStates.screenLocked)
            restartFingerUnlock();
    }

    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        // pam_fprintd sends an error-type conversation message per failed
        // scan; timeouts ("Verification timed out") must not count as tries.
        onPamMessage: {
            // Any message at all proves the reader came up and is armed, so the
            // backoff ladder starts over: idle timeouts must keep re-arming
            // forever, only a reader that never answers should give up.
            root.fingerRetries = 0;
            if (this.messageIsError && this.message.includes("Failed to match")) {
                root.fingerprintTriesLeft = Math.max(0, root.fingerprintTriesLeft - 1);
                root.fingerprintFailed();
            }
        }

        // pam_fprintd reports an unavailable or busy reader as
        // PAM_AUTHINFO_UNAVAIL, which Quickshell surfaces here and not on
        // completed(). Without this the prompt dies silently whenever a start
        // lands while the reader is mid-USB-reset after a resume.
        onError: root.scheduleFingerRetry()

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (result == PamResult.Error) { // if timeout or etc..
                root.scheduleFingerRetry();
            }
        }
    }
}
