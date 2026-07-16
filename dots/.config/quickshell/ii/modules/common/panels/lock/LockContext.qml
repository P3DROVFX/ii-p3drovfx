import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
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
    property bool fingerprintsConfigured: false
    // pam_fprintd default max-tries is 3 (pam/fprintd.conf passes no override)
    readonly property int fingerprintMaxTries: 3
    property int fingerprintTriesLeft: fingerprintMaxTries
    signal fingerprintFailed()
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
        if (root.fingerprintsConfigured) {
            // Each start() is a fresh PAM transaction, so pam_fprintd's
            // internal try counter resets too.
            root.fingerprintTriesLeft = root.fingerprintMaxTries;
            fingerPam.start();
        }
    }

    // The refocus signal also fires from hypridle's after_sleep_cmd. A verify
    // that was in flight across suspend is dead (some readers even crash
    // fprintd), so trade it for a fresh transaction. No-op when unlocked or
    // without fingerprints.
    onShouldReFocus: restartFingerUnlock()

    function restartFingerUnlock() {
        if (!root.fingerprintsConfigured || !GlobalStates.screenLocked)
            return;
        stopFingerPam();
        fingerRestartTimer.restart();
    }

    Timer {
        id: fingerRestartTimer
        // Long enough for the aborted transaction to end and a crashed
        // fprintd to be restarted by systemd
        interval: 1000
        onTriggered: {
            if (GlobalStates.screenLocked)
                root.tryFingerUnlock();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
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
            if (this.messageIsError && this.message.includes("Failed to match")) {
                root.fingerprintTriesLeft = Math.max(0, root.fingerprintTriesLeft - 1);
                root.fingerprintFailed();
            }
        }

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (result == PamResult.Error) { // if timeout or etc..
                tryFingerUnlock()
            }
        }
    }
}
