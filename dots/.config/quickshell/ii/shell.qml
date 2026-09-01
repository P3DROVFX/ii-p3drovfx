//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// Qt allocates a depth-stencil renderbuffer per window (and per layer) for 2D opaque batching. The rendered
// output is identical without it; it only trades a little GPU time on heavy overdraw for ~20 MB per
// fullscreen window on HiDPI.
//@ pragma Env QSG_NO_DEPTH_BUFFER=1

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root
    property string openRgbApplyScript: Quickshell.shellPath("scripts/colors/openRGB/apply_openrgb.py")
    property bool openRgbStartupApplied: false

    // Stuff for every panel family
    ReloadPopup {}

    Component.onCompleted: {
        if (Qt.application) {
            Qt.application.applicationName = "quickshell";
            Qt.application.organizationName = "Unknown Organization";
            Qt.application.organizationDomain = "unknown.organization";
        }
        MaterialThemeLoader.reapplyTheme();
        Hyprsunset.load();
        DisplayColorFilter.load();
        ConflictKiller.load();
        Cliphist.refresh();
        Wallpapers.load();
        Updates.load();
        ShellUpdates.load(); // Touch singleton: the fork-update probe must run whether or not Settings is open
        DarkModeService.automatic;
        ChangelogService.load();
        SoundService.indexReady; // Instantiate: scans sound themes, plays login sound if enabled
        VideoColorSampler.active; // Touch singleton to initialize
        WaterReminderService.enabled; // Touch singleton: drives water reminder notifications
        CalendarNotifier.enabled; // Touch singleton: evaluates calendar VALARMs every minute
        CalendarSubscriptions.enabled; // Touch singleton: keeps managed read-only ICS subscriptions reconciled
        GmailCalendarImport.enabled; // Touch singleton: imports opted-in Gmail ICS attachments idempotently
        OutlookCalendarImport.enabled; // Touch singleton: mirrors opted-in Outlook events into a read-only calendar
        OutlookIcsImport.enabled; // Touch singleton: imports opted-in Outlook ICS attachments idempotently
        BirthdaysService.enabled; // Touch singleton: projects contact birthdays into timetable items
        GoogleDriveService.configured; // Touch singleton: keeps scheduled backups independent of Settings
        AppStats.stateDir; // Instantiate: starts the usage sampler, which must collect whether or not the overlay is open
        Modes.ready; // Touch singleton: the modes engine must watch triggers whether or not its overlay is open
        TilingAssistant.enabled; // Touch singleton: watches for window drags, does nothing while disabled
        TouchGestureService.enabled; // Touch singleton: starts passive touch input helper daemon
        WorkspaceCompactor.enabled; // Touch singleton: auto-compacts workspace gaps, does nothing while disabled
        IconThemes.availableThemes; // Touch singleton: arms the DynamicTheme watcher for live icon refresh
        DictationService.installed; // Touch singleton: registers the dictation keybind, whose surfaces are all optional
        BudsLinkService.serviceAvailable; // Touch singleton: candidate-aware BudsLink lifecycle
        EarbudsControlService.connected; // Touch singleton: provider-priority earbuds router
        if (Config.options && Config.options.policies && Config.options.policies.phone !== 0) {
            KdeConnectService.available;
            PhoneContactsService.available;
            PhoneScrcpyService.available;
        }
        root.applyOpenRgbIfEnabled();
    }

    // Panel families
    property var families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily);
        const nextIndex = (currentIndex + 1) % families.length;
        Config.options.panelFamily = families[nextIndex];
    }

    function applyOpenRgbIfEnabled() {
        if (openRgbStartupApplied)
            return;
        if (!Config.ready)
            return;
        if (!(Config.options && Config.options.appearance && Config.options.appearance.openrgb && Config.options.appearance.openrgb.enable))
            return;
        if (!(Config.options && Config.options.appearance && Config.options.appearance.openrgb && Config.options.appearance.openrgb.applyOnStartup))
            return;
        openRgbStartupApplied = true;
        openRgbApplyProc.command = ["python3", openRgbApplyScript];
        openRgbApplyProc.running = false;
        openRgbApplyProc.running = true;
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root.applyOpenRgbIfEnabled();
        }
    }

    Process {
        id: openRgbApplyProc
    }

    // Families are loaded by URL rather than as inline components: an inline `component: X {}`
    // compiles X and its whole import closure (for Waffle: 144 files plus the FluentWinUI3/Fusion
    // style and Kirigami plugins) at startup even when that family is never active. With a URL,
    // nothing is compiled until the family is wanted.
    //
    // LazyLoader.setSource() compiles the component but never incubates it, and setActive(true)
    // before a component exists is a silent no-op, so `active` must depend on `source` to avoid
    // the family never loading when the two bindings settle in the wrong order.
    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        required property string familyUrl
        property bool extraCondition: true
        readonly property bool wanted: Config.ready && Config.options.panelFamily === identifier && extraCondition
        source: wanted ? familyUrl : ""
        active: wanted && source !== ""
    }

    PanelFamilyLoader {
        identifier: "ii"
        familyUrl: Qt.resolvedUrl("panelFamilies/IllogicalImpulseFamily.qml")
    }

    PanelFamilyLoader {
        identifier: "waffle"
        familyUrl: Qt.resolvedUrl("panelFamilies/WaffleFamily.qml")
    }

    // Settings app loaded in-process once requested, then kept alive briefly
    // for fast re-opens. After the delay we drop the component to recover
    // its QML memory. Positive configured delays are capped at five seconds;
    // 0 still means keep it warm explicitly.
    readonly property int settingsUnloadCapSeconds: 5

    function settingsUnloadDelaySeconds() {
        const settingsApp = Config.options && Config.options.settingsApp;
        let configured = settingsApp && settingsApp.unloadAfterSeconds !== undefined
            ? settingsApp.unloadAfterSeconds
            : settingsUnloadCapSeconds;

        if (configured <= 0)
            return 0;
        return Math.min(configured, settingsUnloadCapSeconds);
    }

    Loader {
        id: settingsLoader
        property bool loadedOnce: false
        active: loadedOnce || GlobalStates.settingsOpen
        asynchronous: true
        source: "SettingsWindow.qml"

        // When settings closes, schedule an unload pass. If the user
        // reopens before the timer fires, the timer is reset and we
        // keep the warm component.
        Timer {
            id: settingsUnloadTimer
            interval: root.settingsUnloadDelaySeconds() * 1000
            repeat: false
            onTriggered: {
                if (GlobalStates.settingsOpen)
                    return
                // The visual Loader only owns the Settings object tree. These
                // singletons outlive it, so release their page-specific data
                // before dropping the component as well.
                SearchRegistry.clearIndex()
                ThemePreviewCache.release()
                WallpaperPreviewCache.release()
                settingsLoader.loadedOnce = false
            }
        }

        Connections {
            target: GlobalStates
            function onSettingsOpenChanged() {
                if (GlobalStates.settingsOpen) {
                    settingsUnloadTimer.stop()
                    if (!settingsLoader.loadedOnce)
                        settingsLoader.loadedOnce = true
                } else {
                    const s = root.settingsUnloadDelaySeconds()
                    if (s > 0) {
                        settingsUnloadTimer.interval = s * 1000
                        settingsUnloadTimer.restart()
                    }
                }
            }
        }
    }

    // Welcome runs in-process so it shares Config, GlobalStates and the same
    // Quickshell lifecycle as Settings. Unlike Settings, the onboarding is
    // destroyed as soon as it closes so costly page trees do not stay warm.
    Loader {
        id: welcomeLoader
        active: Config.ready && GlobalStates.welcomeOpen
        asynchronous: true
        source: "modules/welcome/WelcomeWindow.qml"
    }

    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle() {
            root.cyclePanelFamily();
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}
