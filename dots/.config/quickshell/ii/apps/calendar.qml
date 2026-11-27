//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Calendar: standalone shell app ported from CheatsheetTimetable.
// Runs in its own process so the shell keeps zero retained RAM after it closes:
//   qs -p ~/.config/quickshell/ii/apps/calendar.qml [ipc call calendar open [mode]]
// Imports resolve against apps/ (slim Appearance/Config/GlobalStates/CalendarService; see apps/README.md).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "./calendar"
import "./calendar/settings"

ApplicationWindow {
    id: root
    visible: true
    // Matches Cheatsheet's default screen-relative footprint (~90% x 80%, capped for ultrawide).
    width: Math.min(1820, Math.round((Screen.width || 1920) * 0.90))
    height: Math.min(960, Math.round((Screen.height || 1080) * 0.80))
    minimumWidth: 960
    minimumHeight: 620
    title: "Calendar"
    color: Config.options?.appearance?.transparency?.enable ? Appearance.colors.colLayer0 : Appearance.m3colors.m3background

    onClosing: Qt.quit()

    readonly property var supportedModes: ["day", "threeDay", "week", "month"]

    property string sessionMode: ""
    readonly property string persistedMode: root.supportedModes.includes(root.sessionMode)
        ? root.sessionMode
        : String(Persistent.states.cheatsheet?.timetableView ?? "")
    property string requestedMode: "week"
    property string activeMode: "week"
    property bool viewInitialised: false
    property bool settingsOpen: false
    readonly property bool authBannerDismissed: Persistent.states.cheatsheet.authBannerDismissed
    property bool ctrlPressed: false
    readonly property bool hintsVisible: root.ctrlPressed && root.active

    readonly property var activeViewItem: root.activeMode === "month" ? monthViewLoader.item : weekViewLoader.item
    readonly property bool activeViewReady: root.activeViewItem?.initialLoadComplete ?? false
    readonly property bool sportsRequested: Config.options?.calendar?.timetable?.sportsEvents ?? false
    property bool sportsSubscriberAcquired: false
    property bool sportsReady: false

    onActiveChanged: {
        if (!root.active)
            root.ctrlPressed = false;
    }

    onPersistedModeChanged: root.adoptPersistedMode()
    onSessionModeChanged: root.adoptPersistedMode()

    function setMode(mode: string): void {
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

    function adoptPersistedMode(): void {
        if (!root.supportedModes.includes(root.persistedMode))
            return;
        if (root.requestedMode === root.persistedMode)
            return;
        root.requestedMode = root.persistedMode;
    }

    function navigateToDate(dateStr: string): void {
        const text = String(dateStr ?? "").trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(text))
            return;
        GlobalStates.timetableRequestedDate = text;
        GlobalStates.timetableNavigationRequest++;
        root.setMode("month");
    }

    // One process for every window: the launcher reuses the running instance via IPC.
    IpcHandler {
        target: "calendar"
        function open(mode: string): void {
            const requested = String(mode ?? "").trim();
            if (requested.length > 0 && root.supportedModes.includes(requested)) {
                root.settingsOpen = false;
                root.setMode(requested);
            }
            root.raise();
            root.requestActivate();
        }
        function openDate(date: string): void {
            root.settingsOpen = false;
            root.navigateToDate(date);
            root.raise();
            root.requestActivate();
        }
        function onGoogleAuthComplete(): void {
            CalendarService.onGoogleAuthComplete();
        }
        function reload(): void {
            CalendarService.loadEvents();
        }
        function quit(): void {
            Qt.quit();
        }
    }

    Component.onCompleted: {
        CalendarService.activate();
        const initialDate = String(Quickshell.env("II_CALENDAR_INITIAL_DATE") ?? "").trim();
        const initialMode = String(Quickshell.env("II_CALENDAR_INITIAL_MODE") ?? "").trim();
        if (/^\d{4}-\d{2}-\d{2}$/.test(initialDate)) {
            GlobalStates.timetableRequestedDate = initialDate;
            GlobalStates.timetableNavigationRequest++;
            root.sessionMode = "month";
            root.requestedMode = "month";
            root.activeMode = "month";
        } else if (root.supportedModes.includes(initialMode)) {
            root.sessionMode = initialMode;
            root.requestedMode = initialMode;
            root.activeMode = initialMode;
        } else {
            root.adoptPersistedMode();
            root.activeMode = root.requestedMode;
        }
    }

    Connections {
        target: CalendarService
        function onGoogleSyncSucceeded() {
            Persistent.states.cheatsheet.authBannerDismissed = false;
        }
    }

    onActiveViewReadyChanged: {
        if (!root.activeViewReady)
            return;
        GoogleCalendarService.refreshColors();
    }

    // Mode switch depth animation (exact match to CheatsheetTimetable).
    property bool awaitingViewReveal: false
    readonly property Loader activeViewLoader: root.activeMode === "month" ? monthViewLoader : weekViewLoader

    onRequestedModeChanged: {
        if (root.requestedMode === root.activeMode)
            return;
        if (!root.viewInitialised) {
            root.activeMode = root.requestedMode;
            return;
        }
        revealWatchdog.stop();
        fadeInAnim.stop();
        fadeOutAnim.restart();
    }

    function handleViewLoaded(): void {
        root.viewInitialised = true;
        root.revealActiveView();
    }

    function commitModeSwap(): void {
        root.activeMode = root.requestedMode;
        if (root.activeViewLoader.status === Loader.Ready) {
            root.awaitingViewReveal = false;
            fadeInAnim.start();
            return;
        }
        root.awaitingViewReveal = true;
        revealWatchdog.restart();
    }

    function revealActiveView(): void {
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

    Timer {
        id: revealWatchdog
        interval: 900
        repeat: false
        onTriggered: root.revealActiveView()
    }

    function handleKey(event): bool {
        root.ctrlPressed = event.key === Qt.Key_Control || !!(event.modifiers & Qt.ControlModifier);

        if (event.key === Qt.Key_Escape) {
            if (root.settingsOpen) {
                root.settingsOpen = false;
                return true;
            }
            if (root.activeViewItem && typeof root.activeViewItem.handleEscape === "function") {
                if (root.activeViewItem.handleEscape())
                    return true;
            }
            return false;
        }

        if (root.settingsOpen)
            return false;

        if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_V && !event.isAutoRepeat) {
            timetableViewSwitch.cycleMode();
            return true;
        }

        if ((event.modifiers === (Qt.ControlModifier | Qt.ShiftModifier)) && !event.isAutoRepeat) {
            if (event.key === Qt.Key_D || event.key === Qt.Key_1) {
                root.setMode("day");
                return true;
            } else if (event.key === Qt.Key_3 || event.key === Qt.Key_2) {
                root.setMode("threeDay");
                return true;
            } else if (event.key === Qt.Key_W) {
                root.setMode("week");
                return true;
            } else if (event.key === Qt.Key_M || event.key === Qt.Key_4) {
                root.setMode("month");
                return true;
            }
            if (CalendarService.googleAuthRequired && !root.authBannerDismissed) {
                if (event.key === Qt.Key_X) {
                    Persistent.states.cheatsheet.authBannerDismissed = true;
                    return true;
                } else if (event.key === Qt.Key_R) {
                    CalendarService.startGoogleReauth();
                    return true;
                }
            }
        }

        if (!root.activeViewItem)
            return false;

        if (typeof root.activeViewItem.handleKey === "function" && root.activeViewItem.handleKey(event))
            return true;
        if (typeof root.activeViewItem.handleNavigationKey === "function" && root.activeViewItem.handleNavigationKey(event))
            return true;
        return false;
    }

    function releaseKey(event): void {
        if (event.key === Qt.Key_Control || !(event.modifiers & Qt.ControlModifier))
            root.ctrlPressed = false;
        if (root.activeViewItem && typeof root.activeViewItem.releaseKey === "function")
            root.activeViewItem.releaseKey(event);
    }

    Item {
        id: rootHost
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            if (root.handleKey(event))
                event.accepted = true;
        }
        Keys.onReleased: event => root.releaseKey(event)

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // Top bar: View switch on left, Settings button on right (mirrors Cheatsheet chrome).
            Item {
                id: topBar
                Layout.fillWidth: true
                implicitHeight: Math.max(timetableViewSwitch.implicitHeight, settingsButton.implicitHeight, 40)

                TimetableViewSwitch {
                    id: timetableViewSwitch
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    sessionMode: root.sessionMode
                    showShortcutHints: root.hintsVisible
                    enabled: !root.settingsOpen
                    animateIn: !root.settingsOpen
                    compact: root.width < 1100
                    onModeRequested: mode => root.setMode(mode)
                }

                AppSettingsButton {
                    id: settingsButton
                    anchors.right: closeButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    open: root.settingsOpen
                    label: Translation.tr("Calendar settings")
                    onClicked: root.settingsOpen = !root.settingsOpen
                }

                RippleButton {
                    id: closeButton
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: Qt.quit()

                    contentItem: TaskShortcutContent {
                        symbol: "close"
                        shortcut: "Esc"
                        showHint: root.hintsVisible
                        color: Appearance.colors.colOnSurface
                        iconSize: Appearance.font.pixelSize.title
                    }

                    StyledToolTip {
                        extraVisibleCondition: closeButton.hovered
                        text: Translation.tr("Close")
                    }
                }
            }

            // Main Calendar plate (exact match to CheatsheetTimetable surface).
            Item {
                id: calendarPlate
                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    anchors.fill: parent
                    color: Appearance.colors.colSurfaceContainer
                    radius: Appearance.rounding.large
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
                            onClicked: Persistent.states.cheatsheet.authBannerDismissed = true

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
                    opacity: viewHost.switchProgress * (1 - settingsHost.progress)
                    enabled: !root.settingsOpen

                    property real switchProgress: 1

                    transform: Translate {
                        y: (1 - viewHost.switchProgress) * (root.activeMode === "month" ? 18 : -18)
                    }

                    Loader {
                        id: weekViewLoader
                        anchors.fill: parent
                        active: root.activeMode !== "month"
                        asynchronous: false
                        onLoaded: root.handleViewLoaded()
                        sourceComponent: WeekView {
                            incubateAsync: false
                            maxHeight: calendarPlate.height
                            maxContentWidth: calendarPlate.width
                            sportsEnabled: root.sportsReady
                            viewMode: root.activeMode
                            showShortcutHints: root.hintsVisible
                        }
                    }

                    Loader {
                        id: monthViewLoader
                        anchors.fill: parent
                        active: root.activeMode === "month"
                        asynchronous: false
                        onLoaded: root.handleViewLoaded()
                        sourceComponent: MonthView {
                            incubateAsync: false
                            showUpcoming: Persistent.states.cheatsheet.timetableShowUpcoming
                            sportsEnabled: root.sportsReady
                            showShortcutHints: root.hintsVisible
                        }
                    }
                }

                AppSettingsHost {
                    id: settingsHost
                    anchors.fill: parent
                    z: 20
                    open: root.settingsOpen
                    source: open ? Qt.resolvedUrl("calendar/settings/TimetableSettings.qml") : ""
                    onCloseRequested: {
                        root.settingsOpen = false;
                        rootHost.forceActiveFocus();
                    }
                }
            }
        }
    }
}
