import qs
import qs.modules.common
import qs.services
import QtQuick

/**
 * The context Edit Mode's Lockscreen tab hands to `LockSurface`: the whole
 * property surface of `LockContext`, and none of its behaviour.
 *
 * A separate component on purpose, not the real context with a flag - a
 * preview that shares the real context is a preview that can authenticate.
 * `LockContext` constructs PAM contexts and drives the fingerprint daemon the
 * moment it is built; this is a plain object that constructs nothing and
 * whose unlock functions are empty by contract. It writes none of the
 * `GlobalStates.screenLock*` flags either: those describe the real session.
 *
 * The read-only fingerprint facts mirror the real context so the indicator
 * shows exactly where it would on the lock; reading the daemon's cached
 * state costs nothing and starts nothing.
 */
QtObject {
    id: root

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()
    signal fingerprintFailed()

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false

    readonly property bool fingerprintEnabled: Config.options?.lock?.security?.fingerprint?.enable ?? true
    readonly property bool fingerprintsConfigured: false
    readonly property bool fingerprintUnavailable: !Fingerprint.deviceAvailable
    readonly property bool fingerprintIndicatorVisible: root.fingerprintEnabled
        && (Config.options?.lock?.security?.fingerprint?.showIndicator ?? true) && Fingerprint.hasEnrolled
    readonly property int fingerprintMaxTries: 3
    property int fingerprintTriesLeft: fingerprintMaxTries
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
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
    }

    function tryUnlock(alsoInhibitIdle = false) {
    }

    function tryFingerUnlock() {
    }

    function suspendFingerUnlock() {
    }

    function restartFingerUnlock() {
    }

    function scheduleFingerRetry() {
    }

    function stopFingerPam() {
    }
}
