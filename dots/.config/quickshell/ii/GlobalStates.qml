pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Singleton {
    id: root

    property alias sidebarLeftOpen: root.policiesPanelOpen // Until all sidebars naming is fixed
    property alias sidebarRightOpen: root.dashboardPanelOpen // Until all sidebars naming is fixed

    property bool barOpen: true
    property bool cheatsheetOpen: false
    property bool crosshairOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool searchOnlyMode: false

    // Published by Background.qml for the window-zoom transition layer
    // scaleValue: animated 1.0 → ~0.85 during overview open (zoomOutStyle 0 only)
    // originX/Y: scale transform center in screen coordinates
    property real overviewZoomScale: 1.0
    property real overviewZoomOriginX: 0.5
    property real overviewZoomOriginY: 0.5
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false
    property bool filePickerOpen: false
    property bool videoEditorPopupOpen: false
    property bool videoEditorOpen: false
    property string videoEditorPath: ""

    // Bluetooth connection popup
    property bool bluetoothConnectionPopupOpen: false
    property var bluetoothConnectionPopupDevice: null

    // LocalSend transfer popup
    property bool localSendPopupOpen: false
    property var localSendPopupTransfer: null

    // Media Popup placement (transient, non-persistent)
    property rect mediaPopupRect: Qt.rect(0, 0, 0, 0)


    // Color Picker Popup
    property bool colorPickerPopupOpen: false
    property string colorPickerPopupColor: ""

    function pickColor(hex) {
        if (hex && hex.startsWith("#")) {
            root.colorPickerPopupColor = hex;
            if (Config.options && Config.options.bar && Config.options.bar.tooltips && Config.options.bar.tooltips.enableColorPickerPopup) {
                root.colorPickerPopupOpen = false;
                Qt.callLater(() => {
                    root.colorPickerPopupOpen = true;
                });
            }
        }
    }

    function launchColorPicker() {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "colorPickerLaunch", "trigger"]);
    }

    IpcHandler {
        target: "pickColor"
        function handle(hex: string): void {
            root.pickColor(hex);
        }
    }

    function launchVideoEditor(path) {
        root.videoEditorPath = path;
        root.videoEditorPopupOpen = true;
    }

    IpcHandler {
        target: "launchVideoEditor"
        function handle(path: string): void {
            root.launchVideoEditor(path);
        }
    }

    property bool dashboardPanelOpen: false // formerly sidebarRightOpen
    property bool policiesPanelOpen: false  // formerly sidebarLeftOpen

    readonly property bool effectiveLeftOpen: {
        switch (Config.options.sidebar.position) {
        case "default":
            return policiesPanelOpen;
        case "inverted":
            return dashboardPanelOpen;
        case "left":
            return dashboardPanelOpen || policiesPanelOpen;
        case "right":
            return false;
        default:
            return policiesPanelOpen;
        }
    }
    readonly property bool effectiveRightOpen: {
        switch (Config.options.sidebar.position) {
        case "default":
            return dashboardPanelOpen;
        case "inverted":
            return policiesPanelOpen;
        case "left":
            return false;
        case "right":
            return dashboardPanelOpen || policiesPanelOpen;
        default:
            return dashboardPanelOpen;
        }
    }

    onPoliciesPanelOpenChanged: {
        if (policiesPanelOpen) {
            if (Config.options.sidebar.position == "right" || Config.options.sidebar.position == "left") {
                GlobalStates.dashboardPanelOpen = false;
            }
        }
    }

    onDashboardPanelOpenChanged: {
        if (dashboardPanelOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
            if (Config.options.sidebar.position == "right" || Config.options.sidebar.position == "left") {
                GlobalStates.policiesPanelOpen = false;
            }
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"
        onPressed: {
            root.superDown = true;
        }
        onReleased: {
            root.superDown = false;
        }
    }
}
