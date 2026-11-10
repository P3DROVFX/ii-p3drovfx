import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "timetable"

/**
 * Host for the timetable calendar shapes.
 *
 * Owns the plate both views sit on, and nothing else: the week grid and the
 * month grid are independent trees, and only the selected one exists. The
 * selector itself lives in the cheatsheet header, so this file never has to
 * know how the choice is made — it just follows the persisted state.
 */
Item {
    id: root

    focus: true

    property real maxContentWidth: 1600
    property real maxHeight: 700
    // The cheatsheet clears this while it is on screen: a view asked for
    // there is built in one pass instead of incubated a few ms per frame.
    property bool incubateAsync: true

    implicitWidth: root.maxContentWidth
    implicitHeight: root.maxHeight

    readonly property var supportedModes: ["day", "threeDay", "week", "month"]

    // The persisted value reads back invalid for a moment whenever Persistent
    // loads or reloads the file it watches — and opening this tab writes to
    // that file. Treating the gap as a real mode change cost a whole fade out
    // and back in for a value that never changed, twice over, which is the
    // blink that went away once the state settled. The last valid mode stays.
    // A recent header selection wins over a stale FileView reload for the
    // lifetime of the open Cheatsheet. Only this string is retained; the view
    // tree is still destroyed when its tab is unloaded.
    property string sessionMode: ""
    readonly property string persistedMode: root.supportedModes.includes(root.sessionMode)
        ? root.sessionMode
        : String(Persistent.states.cheatsheet?.timetableView ?? "")
    property string requestedMode: "week"
    property string activeMode: "week"
    property bool viewInitialised: false

    onPersistedModeChanged: root.adoptPersistedMode()
    onSessionModeChanged: root.adoptPersistedMode()

    function setMode(mode) {
        if (!root.supportedModes.includes(mode))
            return;
        if (root.sessionMode === mode && root.requestedMode === mode)
            return;
        root.sessionMode = mode;
        root.requestedMode = mode;
        if (Persistent.states.cheatsheet?.timetableView !== mode)
            Persistent.states.cheatsheet.timetableView = mode;
        if (!root.viewInitialised) {
            root.activeMode = mode;
        } else if (root.requestedMode !== root.activeMode) {
            revealWatchdog.stop();
            fadeInAnim.stop();
            fadeOutAnim.restart();
        }
    }

    function adoptPersistedMode() {
        if (!root.supportedModes.includes(root.persistedMode))
            return;
        if (root.requestedMode === root.persistedMode)
            return;
        root.requestedMode = root.persistedMode;
    }

    property bool sportsSubscriberAcquired: false
    property bool sportsReady: false
    readonly property bool sportsRequested: Config.options.calendar.timetable.sportsEvents
    // keepLastTabLoaded may retain this QML tree while the cheatsheet window
    // is hidden. That cache is a visual warm-start only; it must not keep the
    // ESPN subscriber, weekly cache or live refresh alive in the background.
    readonly property bool sportsSurfaceActive: GlobalStates.cheatsheetOpen
    readonly property var activeViewItem: root.activeMode === "month" ? monthViewLoader.item : weekViewLoader.item
    readonly property bool activeViewReady: root.activeViewItem?.initialLoadComplete ?? false
    readonly property bool timetableDragActive: root.activeViewItem?.timetableDragActive === true
    property bool authBannerDismissed: false

    Connections {
        target: CalendarService
        function onGoogleAuthRequiredChanged() {
            if (!CalendarService.googleAuthRequired)
                root.authBannerDismissed = false;
        }
    }

    property bool showShortcutHints: false
    property bool ctrlPressed: false
    readonly property bool hintsVisible: (root.showShortcutHints || root.ctrlPressed)
        && (root.Window.window?.active ?? false)

    Connections {
        target: root.Window.window
        function onActiveChanged() {
            root.ctrlPressed = false;
        }
    }

    function handleKey(event) {
        root.ctrlPressed = event.key === Qt.Key_Control || !!(event.modifiers & Qt.ControlModifier);

        if (CalendarService.googleAuthRequired && !root.authBannerDismissed && (event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier))) {
            if (event.key === Qt.Key_X) {
                root.authBannerDismissed = true;
                return true;
            } else if (event.key === Qt.Key_R) {
                CalendarService.startGoogleReauth();
                return true;
            }
        }

        if (!root.activeViewItem)
            return false;

        if (typeof root.activeViewItem.handleKey === "function") {
            if (root.activeViewItem.handleKey(event)) {
                return true;
            }
        }
        if (typeof root.activeViewItem.handleNavigationKey === "function") {
            if (root.activeViewItem.handleNavigationKey(event)) {
                return true;
            }
        }
        return false;
    }

    function releaseKey(event) {
        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier))
            root.ctrlPressed = false;
        if (root.activeViewItem && typeof root.activeViewItem.releaseKey === "function")
            root.activeViewItem.releaseKey(event);
    }

    Keys.priority: Keys.AfterItem
    Keys.onPressed: event => {
        if (root.handleKey(event))
            event.accepted = true;
    }

    Keys.onReleased: event => {
        root.releaseKey(event);
    }

    function handleEscape() {
        if (root.activeViewItem && typeof root.activeViewItem.handleEscape === "function")
            return root.activeViewItem.handleEscape();
        return false;
    }

    function openRequestedDate() {
        if (GlobalStates.timetableNavigationRequest <= 0)
            return;
        // Opening a concrete date uses the month grid, where the selected day
        // and its event rail are visible together. This is an explicit action,
        // so persisting the mode also keeps the header selector truthful.
        if (Persistent.states.cheatsheet.timetableView !== "month")
            Persistent.states.cheatsheet.timetableView = "month";
    }

    Component.onCompleted: {
        root.adoptPersistedMode();
        root.activeMode = root.requestedMode;
        root.openRequestedDate();
    }

    Connections {
        target: GlobalStates
        function onTimetableNavigationRequestChanged() {
            root.openRequestedDate();
        }
    }

    function syncSportsSubscription() {
        if (!root.sportsRequested || !root.sportsSurfaceActive) {
            sportsActivationTimer.stop();
            if (root.sportsSubscriberAcquired) {
                SportsService.releaseTimetableSubscriber();
                root.sportsSubscriberAcquired = false;
            }
            root.sportsReady = false;
            return;
        }

        if (root.activeViewReady && !root.sportsSubscriberAcquired)
            sportsActivationTimer.restart();
    }

    onActiveViewReadyChanged: {
        if (!root.activeViewReady)
            return;
        // Google colours are cached on disk, so this only reaches the network
        // once the cache is older than the configured window. It is independent
        // from the optional ESPN projection below.
        GoogleCalendarService.refreshColors();
        root.syncSportsSubscription();
    }

    onSportsRequestedChanged: {
        root.syncSportsSubscription();
    }

    Connections {
        target: GlobalStates
        function onCheatsheetOpenChanged() {
            root.syncSportsSubscription();
        }
    }

    Timer {
        id: sportsActivationTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (!root.sportsRequested || !root.sportsSurfaceActive || !root.activeViewReady || root.sportsSubscriberAcquired)
                return;
            SportsService.acquireTimetableSubscriber();
            root.sportsSubscriberAcquired = true;
            root.sportsReady = true;
        }
    }

    Component.onDestruction: {
        sportsActivationTimer.stop();
        if (root.sportsSubscriberAcquired)
            SportsService.releaseTimetableSubscriber();
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colSurfaceContainer
        radius: Appearance.rounding.large
    }

    // Fade out, swap, fade in. Keeping both trees alive for a cross-fade would
    // mean paying for a month grid while the week grid is on screen, and the
    // cheatsheet already releases its whole tab tree on close for that reason.
    //
    // The fade in waits for the incoming Loader rather than following the fade
    // out on a fixed schedule: both views incubate asynchronously, so a timed
    // fade animates an empty host and the tree then appears at full opacity.
    property bool awaitingViewReveal: false
    readonly property Loader activeViewLoader: root.activeMode === "month" ? monthViewLoader : weekViewLoader

    onRequestedModeChanged: {
        if (root.requestedMode === root.activeMode)
            return;
        // Nothing has been shown yet, so there is no outgoing view to fade.
        if (!root.viewInitialised) {
            root.activeMode = root.requestedMode;
            return;
        }
        revealWatchdog.stop();
        fadeInAnim.stop();
        fadeOutAnim.restart();
    }

    function handleViewLoaded() {
        root.viewInitialised = true;
        root.revealActiveView();
    }

    function commitModeSwap() {
        root.activeMode = root.requestedMode;
        // A small tree can incubate synchronously, in which case onLoaded has
        // already fired and found nothing pending — hence the status check
        // before arming the wait.
        if (root.activeViewLoader.status === Loader.Ready) {
            root.awaitingViewReveal = false;
            fadeInAnim.start();
            return;
        }
        root.awaitingViewReveal = true;
        revealWatchdog.restart();
    }

    function revealActiveView() {
        if (!root.awaitingViewReveal)
            return;
        root.awaitingViewReveal = false;
        revealWatchdog.stop();
        fadeInAnim.start();
    }

    NumberAnimation {
        id: fadeOutAnim
        target: viewHost
        property: "switchProgress"
        to: 0
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        onFinished: root.commitModeSwap()
    }

    NumberAnimation {
        id: fadeInAnim
        target: viewHost
        property: "switchProgress"
        to: 1
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    // A Loader that fails to instantiate would otherwise leave the host
    // invisible for good; an unexplained pop is recoverable, a blank tab is not.
    Timer {
        id: revealWatchdog
        interval: 900
        repeat: false
        onTriggered: root.revealActiveView()
    }

    // Reauthorization warning banner (Google Calendar token expired/revoked)
    Rectangle {
        id: authBanner
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        z: 99
        height: visible ? bannerLayout.implicitHeight + 16 : 0
        visible: CalendarService.googleAuthRequired && !root.authBannerDismissed
        color: Appearance.colors.colErrorContainer
        radius: Appearance.rounding.normal
        clip: true

        Behavior on height {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        RowLayout {
            id: bannerLayout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            spacing: 12

            MaterialSymbol {
                text: "sync_problem"
                iconSize: 24
                color: Appearance.colors.colOnErrorContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: Translation.tr("Google Calendar disconnected")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledText {
                    text: Translation.tr("Your authorization token expired or was revoked. Reconnect to resume synchronization.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnErrorContainer
                    opacity: 0.85
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                }
            }

            RippleButton {
                id: dismissButton
                implicitHeight: 36
                implicitWidth: Math.max(80, dismissShortcutContent.implicitWidth + 24)
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colOnErrorContainer
                onClicked: root.authBannerDismissed = true

                contentItem: TaskShortcutContent {
                    id: dismissShortcutContent
                    labelText: Translation.tr("Dismiss")
                    shortcut: "Ctrl+⇧X"
                    showHint: root.hintsVisible
                    labelPixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnErrorContainer
                }

                StyledToolTip {
                    extraVisibleCondition: dismissButton.hovered
                    text: Translation.tr("Dismiss") + " (Ctrl+Shift+X)"
                }
            }

            RippleButton {
                id: reauthButton
                implicitHeight: 36
                implicitWidth: Math.max(120, reauthShortcutContent.implicitWidth + 28)
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colError
                colBackgroundHover: Appearance.colors.colErrorHover
                colRipple: Appearance.colors.colOnError
                enabled: !CalendarService.reauthenticatingGoogle
                onClicked: CalendarService.startGoogleReauth()

                contentItem: TaskShortcutContent {
                    id: reauthShortcutContent
                    symbol: CalendarService.reauthenticatingGoogle ? "progress_activity" : "open_in_new"
                    labelText: CalendarService.reauthenticatingGoogle
                        ? Translation.tr("Waiting for browser…")
                        : Translation.tr("Reconnect Google")
                    shortcut: "Ctrl+⇧R"
                    showHint: root.hintsVisible
                    iconSize: 18
                    labelPixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnError
                }

                StyledToolTip {
                    extraVisibleCondition: reauthButton.hovered
                    text: Translation.tr("Reconnect Google") + " (Ctrl+Shift+R)"
                }
            }
        }
    }

    Item {
        id: viewHost
        anchors.top: authBanner.visible ? authBanner.bottom : parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.activeMode === "month" ? 16 : 0
        anchors.rightMargin: root.activeMode === "month" ? 16 : 0
        anchors.bottomMargin: root.activeMode === "month" ? 16 : 0
        anchors.topMargin: root.activeMode === "month" ? (authBanner.visible ? 8 : 16) : 0

        property real switchProgress: 1

        opacity: viewHost.switchProgress
        transform: Translate {
            // Month sits "further in" than week, so the swap reads as depth
            // rather than a sideways page flip.
            y: (1 - viewHost.switchProgress) * (root.activeMode === "month" ? 18 : -18)
        }

        Loader {
            id: weekViewLoader
            anchors.fill: parent
            active: root.activeMode !== "month"
            asynchronous: root.incubateAsync
            onLoaded: root.handleViewLoaded()
            sourceComponent: WeekView {
                incubateAsync: root.incubateAsync
                maxHeight: root.maxHeight
                maxContentWidth: root.maxContentWidth
                sportsEnabled: root.sportsReady
                viewMode: root.activeMode
                showShortcutHints: root.hintsVisible
            }
        }

        Loader {
            id: monthViewLoader
            anchors.fill: parent
            active: root.activeMode === "month"
            asynchronous: root.incubateAsync
            onLoaded: root.handleViewLoaded()
            sourceComponent: MonthView {
                incubateAsync: root.incubateAsync
                showUpcoming: Persistent.states.cheatsheet.timetableShowUpcoming
                sportsEnabled: root.sportsReady
                showShortcutHints: root.hintsVisible
            }
        }
    }
}
