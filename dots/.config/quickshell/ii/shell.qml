//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

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
        MaterialThemeLoader.reapplyTheme();
        Hyprsunset.load();
        FirstRunExperience.load();
        ConflictKiller.load();
        Cliphist.refresh();
        Wallpapers.load();
        Updates.load();
        DarkModeService.automatic;
        ChangelogService.load();
        SoundService.indexReady; // Instantiate: scans sound themes, plays login sound if enabled
        // Only spin up KdeConnectService if the Phone tab is enabled in
        // config. Touching the singleton forces QML to instantiate it and
        // runs its Component.onCompleted, which starts the DBus monitor,
        // pgrep polling, and ADB probing. For users who don't use phone
        // integration this is pure overhead.
        if (Config.options && Config.options.policies && Config.options.policies.phone !== 0) {
            KdeConnectService.available;
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
        openRgbApplyProc.command = ["python", openRgbApplyScript];
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

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }

    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }

    // Settings app loaded in-process once requested, then kept alive
    // for fast re-opens. After `unloadAfterSeconds` of inactivity we
    // drop the component to recover ~70 MB of QML memory. Set to 0 in
    // Config.options.settingsApp.unloadAfterSeconds to keep it warm.
    Loader {
        id: settingsLoader
        property bool loadedOnce: false
        active: loadedOnce || GlobalStates.settingsOpen
        source: "SettingsWindow.qml"

        // When settings closes, schedule an unload pass. If the user
        // reopens before the timer fires, the timer is reset and we
        // keep the warm component.
        Timer {
            id: settingsUnloadTimer
            interval: Math.max(0, (Config.options && Config.options.settingsApp && Config.options.settingsApp.unloadAfterSeconds !== undefined ? Config.options.settingsApp.unloadAfterSeconds : 300)) * 1000
            repeat: false
            onTriggered: {
                if (GlobalStates.settingsOpen)
                    return
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
                    const s = Config.options && Config.options.settingsApp && Config.options.settingsApp.unloadAfterSeconds !== undefined ? Config.options.settingsApp.unloadAfterSeconds : 300
                    if (s > 0) {
                        settingsUnloadTimer.interval = s * 1000
                        settingsUnloadTimer.restart()
                    }
                }
            }
        }
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







