// PhoneFooter.qml
// The phone-as-a-peripheral group at the bottom of the Phone tab: Mirror,
// Webcam and Microphone behind the dashboard bottom group's navigation rail.
// Collapsible like the dashboard's; the choice and the tab persist in
// Persistent.states.sidebar.policies.phone.peripherals.

pragma ComponentBehavior: Bound

// Performance fix: multi-arg .arg() doesn't work in this Qt/Quickshell version
// Use chained .arg(x).arg(y) instead.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.dashboardWidgets.calendar
import qs.services

/**
 * Expanded: a navigation rail (Mirror / Webcam / Mic) with the collapse
 * chevron above it, and the selected feature's panel on the right — state,
 * the one main action, quick toggles and shortcuts. Collapsed: the expand
 * chevron and one status pill per feature; a pill expands straight into its
 * tab. Each feature keeps the state machine of the old hero cards:
 * unavailable | offline | ready | connecting | active.
 */
Rectangle {
    id: root

    signal requestOpenSubPage(url target)

    visible: Config.options.phone.showPeripheralCards
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer3
    clip: true

    // Grows with the selected panel (a running session adds its facts and
    // controls), capped so notifications keep some room; past it, it scrolls.
    readonly property real expandedHeight: Math.min(440, Math.max(282, (panelLoader.item?.contentHeight ?? 0) + 20))
    readonly property real collapsedHeight: collapsedRow.implicitHeight + 16
    readonly property bool collapsed: Persistent.states.sidebar.policies.phone.peripherals.collapsed
    readonly property int selectedTab: Math.max(0, Math.min(2, Persistent.states.sidebar.policies.phone.peripherals.tab))
    implicitHeight: visible ? (collapsed ? collapsedHeight : expandedHeight) : 0

    Behavior on implicitHeight {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    function setCollapsed(state: bool): void {
        Persistent.states.sidebar.policies.phone.peripherals.collapsed = state;
    }
    function selectTab(index: int): void {
        Persistent.states.sidebar.policies.phone.peripherals.tab = index;
    }

    // ─── Feature state (shared by the rail, the pills and the panels) ───
    readonly property bool _scrcpyPresent: KdeConnectService.scrcpyAvailable
    readonly property bool _droidcamPresent: PhoneCameraService.available
    readonly property bool _micPresent: PhoneMicService.available
    readonly property bool _deviceOnline: KdeConnectService.activeReachable

    readonly property bool embedEnabled: Config.options?.phone?.scrcpy?.embed?.enabled ?? true
    readonly property bool mirrorRunning: KdeConnectService.scrcpyRunning || PhoneScrcpyService.mirrorRunning
    readonly property bool mirrorLaunching: KdeConnectService.scrcpyLaunching || PhoneScrcpyService.mirrorLaunching
    readonly property string mirrorError: PhoneScrcpyService.mirrorLaunchError || KdeConnectService.scrcpyLaunchError
    readonly property bool mirrorEmbedded: root.embedEnabled && PhoneMirrorService.running

    readonly property string mirrorState: !root._scrcpyPresent ? "unavailable"
        : !root._deviceOnline || root.mirrorError.length > 0 ? "offline"
        : (root.mirrorEmbedded || root.mirrorRunning) ? "active"
        : root.mirrorLaunching ? "connecting" : "ready"
    readonly property string webcamState: !root._droidcamPresent ? "unavailable"
        : !root._deviceOnline ? "offline"
        : PhoneCameraService.connecting ? "connecting"
        : PhoneCameraService.running ? "active" : "ready"
    readonly property string micState: !root._micPresent ? "unavailable"
        : !root._deviceOnline ? "offline"
        : PhoneMicService.connecting ? "connecting"
        : PhoneMicService.running ? "active" : "ready"
    readonly property var featureStates: [root.mirrorState, root.webcamState, root.micState]

    readonly property var tabs: [
        { "name": Translation.tr("Mirror"), "icon": "smart_display" },
        { "name": Translation.tr("Webcam"), "icon": "videocam" },
        { "name": Translation.tr("Mic"), "icon": "mic" }
    ]

    // ─── Install guide popup state ─────────────────────────
    property bool _installGuideVisible: false
    property var _installGuideDeps: []
    property string _installGuideTitle: Translation.tr("Missing Dependencies")

    function _openInstallGuide(deps, title) {
        root._installGuideDeps = deps || [];
        root._installGuideTitle = title || Translation.tr("Missing Dependencies");
        root._installGuideVisible = true;
    }

    /** Helper — formats milliseconds as "Xm Ys" or "Xs" for inline display. */
    function _fmtElapsed(ms): string {
        const s = Math.floor(ms / 1000);
        if (s < 60)
            return s + "s";
        const m = Math.floor(s / 60);
        const rem = s % 60;
        if (m < 60)
            return m + "m " + (rem < 10 ? "0" : "") + rem + "s";
        const h = Math.floor(m / 60);
        const rm = m % 60;
        return h + "h " + (rm < 10 ? "0" : "") + rm + "m";
    }

    // ─── Feature actions ───────────────────────────────────
    function mirrorMain(): void {
        if (!root._scrcpyPresent) {
            root._openInstallGuide(KdeConnectService.scrcpyMissingDeps, Translation.tr("scrcpy Mirror — Missing Dependencies"));
            return;
        }
        if (root.embedEnabled) {
            root.requestOpenSubPage(Qt.resolvedUrl("PhoneMirrorPage.qml"));
            return;
        }
        // Switched off, the mirror is a toggle for a scrcpy window of its own.
        if (root.mirrorRunning)
            PhoneScrcpyService.stopMirroring();
        else if (!root.mirrorLaunching)
            PhoneScrcpyService.openMirrorWindow();
    }
    function webcamMain(): void {
        if (!root._droidcamPresent) {
            root._openInstallGuide(PhoneCameraService.missingDeps, Translation.tr("Phone Webcam — Missing Dependencies"));
            return;
        }
        if (PhoneCameraService.connecting || PhoneCameraService.running)
            PhoneCameraService.stopCamera();
        else
            PhoneCameraService.startCamera();
    }
    function micMain(): void {
        if (!root._micPresent) {
            root._openInstallGuide(PhoneMicService.missingDeps, Translation.tr("Phone Microphone — Missing Dependencies"));
            return;
        }
        if (PhoneMicService.connecting || PhoneMicService.running)
            PhoneMicService.stopMic();
        else
            PhoneMicService.startMic();
    }

    // ─── Entrance ───────────────────────────────────────────
    property int entranceTrigger: -1
    onEntranceTriggerChanged: {
        if (entranceTrigger < 0 || !Config.options.sidebar.dashboardEntranceAnimations)
            return;
        entranceAnim.restart();
    }
    transform: Translate { id: entranceTranslate; y: 0 }
    ParallelAnimation {
        id: entranceAnim
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve }
        NumberAnimation { target: entranceTranslate; property: "y"; from: 24; to: 0; duration: Appearance.animation.elementMoveEnter.duration; easing.type: Appearance.animation.elementMoveEnter.type; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve }
    }

    // ─── Collapsed: expand chevron + one status pill per feature ───
    RowLayout {
        id: collapsedRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 8
        spacing: 6
        opacity: root.collapsed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        CalendarHeaderButton {
            id: expandButton
            implicitHeight: 40
            forceCircle: true
            colBackground: Appearance.colors.colLayer2
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            tooltipText: Translation.tr("Expand")
            onClicked: root.setCollapsed(false)
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "keyboard_arrow_up"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
            }
        }

        Repeater {
            model: root.tabs
            delegate: StatusPill {
                required property int index
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                symbol: modelData.icon
                label: modelData.name
                featureState: root.featureStates[index]
                onClicked: {
                    root.selectTab(index);
                    root.setCollapsed(false);
                }
            }
        }
    }

    // ─── Expanded: rail + selected panel ───
    RowLayout {
        id: expandedRow
        anchors.fill: parent
        spacing: 10
        opacity: root.collapsed ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Item {
            Layout.fillHeight: true
            Layout.leftMargin: 6
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            implicitWidth: tabBar.implicitWidth

            CalendarHeaderButton {
                id: collapseButton
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                forceCircle: true
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                tooltipText: Translation.tr("Collapse")
                onClicked: root.setCollapsed(true)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer3
                }
            }

            NavigationRailTabArray {
                id: tabBar
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                currentIndex: root.selectedTab
                Repeater {
                    model: root.tabs
                    NavigationRailButton {
                        required property int index
                        required property var modelData
                        // The group sits on Layer3: an unselected hover takes
                        // the next layer up, the selected tab is the secondary
                        // container, as on the dashboard.
                        showToggledHighlight: true
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colBackgroundActive: Appearance.colors.colLayer3Active
                        colBackgroundToggledActive: Appearance.colors.colSecondaryContainerActive
                        colRipple: Appearance.colors.colLayer3Active
                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                        colText: Appearance.colors.colOnLayer3
                        toggled: root.selectedTab === index
                        buttonText: modelData.name
                        buttonIcon: modelData.icon
                        onPressed: root.selectTab(index)
                    }
                }
            }
        }

        Item {
            id: panelArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            Layout.rightMargin: 10

            property int shownTab: root.selectedTab
            property int previousTab: root.selectedTab

            Loader {
                id: panelLoader
                anchors.left: parent.left
                anchors.right: parent.right
                height: parent.height
                sourceComponent: [mirrorPanel, webcamPanel, micPanel][panelArea.shownTab]
            }

            Connections {
                target: root
                function onSelectedTabChanged() {
                    if (Appearance.reducedMotion || root.collapsed) {
                        panelArea.shownTab = root.selectedTab;
                        panelArea.previousTab = root.selectedTab;
                        return;
                    }
                    panelSwitch.down = root.selectedTab > panelArea.previousTab;
                    panelSwitch.restart();
                }
            }

            // Same fade-and-shift swap as the dashboard's bottom group.
            SequentialAnimation {
                id: panelSwitch
                property bool down: false
                ParallelAnimation {
                    NumberAnimation { target: panelLoader; property: "opacity"; to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    NumberAnimation { target: panelLoader; property: "y"; to: 10 * (panelSwitch.down ? -1 : 1); duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
                ScriptAction { script: panelArea.shownTab = root.selectedTab }
                ParallelAnimation {
                    NumberAnimation { target: panelLoader; property: "y"; from: 10 * (panelSwitch.down ? 1 : -1); to: 0; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve }
                    NumberAnimation { target: panelLoader; property: "opacity"; to: 1; duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve }
                }
                ScriptAction { script: panelArea.previousTab = root.selectedTab }
            }
        }
    }

    // ─── Panels ─────────────────────────────────────────────
    Component {
        id: mirrorPanel
        FeaturePanel {
            symbol: "smart_display"
            shapeKind: MaterialShape.Shape.Cookie9Sided
            featureState: root.mirrorState
            title: !root._scrcpyPresent ? Translation.tr("Install scrcpy")
                : root.mirrorEmbedded ? Translation.tr("Phone screen")
                : root.mirrorLaunching ? Translation.tr("Connecting…")
                : root.mirrorRunning ? Translation.tr("Mirror window open")
                : Translation.tr("Phone screen")
            subtitle: {
                if (!root._scrcpyPresent)
                    return Translation.tr("See the missing dependencies");
                if (!root._deviceOnline)
                    return Translation.tr("Pair a reachable device");
                if (root.mirrorEmbedded)
                    return Translation.tr("Mirroring in the sidebar");
                if (root.mirrorRunning)
                    return Translation.tr("Active for %1").arg(root._fmtElapsed(PhoneScrcpyService.mirrorElapsedMs || KdeConnectService.scrcpyElapsedMs));
                return KdeConnectService.adbReachable
                    ? Translation.tr("ADB ready")
                    : Translation.tr("Connect USB debugging or wireless ADB");
            }
            mainLabel: !root._scrcpyPresent ? Translation.tr("How to install")
                : root.embedEnabled ? (root.mirrorEmbedded ? Translation.tr("Show here") : Translation.tr("Mirror here"))
                : root.mirrorRunning ? Translation.tr("Stop") : Translation.tr("Open window")
            mainSymbol: !root._scrcpyPresent ? "download"
                : root.embedEnabled ? "view_sidebar"
                : root.mirrorRunning ? "stop" : "open_in_new"
            mainEnabled: !root._scrcpyPresent || root._deviceOnline
            showStop: root.mirrorEmbedded || (root.embedEnabled && root.mirrorRunning)
            settingsPage: "PhoneScrcpyPage.qml"
            error: root._scrcpyPresent && root._deviceOnline ? root.mirrorError.split("\n")[0] : ""
            detail: root.mirrorEmbedded || root.mirrorRunning
                ? [root.mirrorEmbedded ? Translation.tr("In the sidebar") : Translation.tr("In a window"),
                   Config.options.phone.scrcpy.useWireless
                       ? (KdeConnectService.pinnedAdbHost || KdeConnectService.resolvedWirelessHost || Translation.tr("Wireless"))
                       : "USB",
                   Config.options.phone.scrcpy.noAudio ? Translation.tr("no audio") : Translation.tr("audio on")].join(" · ")
                : ""
            dropEnabled: (root.mirrorEmbedded || root.mirrorRunning) && root._deviceOnline
            onFilesDropped: urls => {
                for (const url of urls) {
                    const file = String(url).replace(/^file:\/\//, "");
                    if (file.length > 0)
                        KdeConnectService.shareUrl(KdeConnectService.activeDeviceId, file);
                }
            }
            onMainClicked: root.mirrorMain()
            onStopClicked: PhoneScrcpyService.stopMirroring()
            toggles: [
                { icon: "view_sidebar", label: Translation.tr("In sidebar"), checked: root.embedEnabled,
                  toggle: () => Config.options.phone.scrcpy.embed.enabled = !root.embedEnabled },
                { icon: "mobile_off", label: Translation.tr("Screen off"), checked: Config.options.phone.scrcpy.turnScreenOff,
                  toggle: () => Config.options.phone.scrcpy.turnScreenOff = !Config.options.phone.scrcpy.turnScreenOff },
                { icon: "coffee", label: Translation.tr("Stay awake"), checked: Config.options.phone.scrcpy.stayAwake,
                  toggle: () => Config.options.phone.scrcpy.stayAwake = !Config.options.phone.scrcpy.stayAwake },
                { icon: "volume_up", label: Translation.tr("Audio"), checked: !Config.options.phone.scrcpy.noAudio,
                  toggle: () => Config.options.phone.scrcpy.noAudio = !Config.options.phone.scrcpy.noAudio },
                { icon: "wifi", label: Translation.tr("Wireless"), checked: Config.options.phone.scrcpy.useWireless,
                  toggle: () => Config.options.phone.scrcpy.useWireless = !Config.options.phone.scrcpy.useWireless },
                { icon: "content_paste", label: Translation.tr("Clipboard"), checked: Config.options.phone.scrcpy.clipboardSync ?? true,
                  toggle: () => Config.options.phone.scrcpy.clipboardSync = !(Config.options.phone.scrcpy.clipboardSync ?? true) }
            ]
            actions: !(root._scrcpyPresent && root._deviceOnline) ? [] : (PhoneMirrorService.running ? [
                { icon: "arrow_back", label: Translation.tr("Back"), run: () => PhoneMirrorService.goBack() },
                { icon: "circle", label: Translation.tr("Home"), run: () => PhoneMirrorService.goHome() },
                { icon: "crop_square", label: Translation.tr("Recent apps"), run: () => PhoneMirrorService.goRecents() }
            ] : []).concat([
                { icon: "open_in_new", label: KdeConnectService.scrcpyRunning ? Translation.tr("Focus window") : Translation.tr("Window"),
                  run: () => KdeConnectService.scrcpyRunning ? KdeConnectService.focusScrcpyWindow() : PhoneScrcpyService.openMirrorWindow() },
                { icon: "keyboard", label: Translation.tr("Type"),
                  run: () => root.requestOpenSubPage(Qt.resolvedUrl("PhoneKeyboardPage.qml")) },
                { icon: "screenshot_monitor", label: Translation.tr("Screenshot"),
                  run: () => KdeConnectService.adbScreenshot() },
                { icon: "power_settings_new", label: Translation.tr("Power"),
                  run: () => KdeConnectService.adbTogglePower() }
            ])
        }
    }

    Component {
        id: webcamPanel
        FeaturePanel {
            symbol: "videocam"
            shapeKind: MaterialShape.Shape.Cookie7Sided
            featureState: root.webcamState
            title: root._droidcamPresent ? Translation.tr("Phone Webcam") : Translation.tr("Install DroidCam")
            subtitle: {
                if (!root._droidcamPresent)
                    return Translation.tr("See the missing dependencies");
                if (!root._deviceOnline)
                    return Translation.tr("Pair a reachable device");
                if (PhoneCameraService.connecting)
                    return Translation.tr("Connecting to %1…").arg(PhoneCameraService.activeIp || "?");
                if (PhoneCameraService.running)
                    return Translation.tr("Active for %1").arg(root._fmtElapsed(PhoneCameraService.elapsedMs))
                        + " · " + (PhoneCameraService.videoDevice || "/dev/videoN");
                return Translation.tr("DroidCam over %1").arg(Config.options.phone.webcam.connection === "usb" ? "USB" : "Wi-Fi");
            }
            mainLabel: !root._droidcamPresent ? Translation.tr("How to install")
                : root.webcamState === "active" ? Translation.tr("Stop") : Translation.tr("Start")
            mainSymbol: !root._droidcamPresent ? "download"
                : root.webcamState === "active" ? "stop" : "play_arrow"
            mainEnabled: !root._droidcamPresent || root._deviceOnline
            settingsPage: "PhoneWebcamPage.qml"
            error: root._droidcamPresent && !PhoneCameraService.running ? PhoneCameraService.lastError.split("\n")[0] : ""
            detail: PhoneCameraService.running
                ? (PhoneCameraService.activeIp || "USB") + ":" + String(PhoneCameraService.activePort)
                    + " · " + (PhoneCameraService.videoDevice || "/dev/videoN")
                    + " · " + (Config.options.phone.webcam.cameraFacing === "back" ? Translation.tr("back camera") : Translation.tr("front camera"))
                : ""
            onMainClicked: root.webcamMain()
            onStopClicked: PhoneCameraService.stopCamera()
            toggles: [
                { icon: "cameraswitch", label: Config.options.phone.webcam.cameraFacing === "back" ? Translation.tr("Back camera") : Translation.tr("Front camera"),
                  checked: Config.options.phone.webcam.cameraFacing === "back",
                  // Applies on the next start, like the webcam page's picker.
                  toggle: () => PhoneCameraService.flipCamera() },
                { icon: "flip", label: Translation.tr("Mirror"), checked: Config.options.phone.webcam.mirrorHorizontally,
                  toggle: () => PhoneCameraService.toggleMirror() },
                { icon: "usb", label: Translation.tr("USB"), checked: Config.options.phone.webcam.connection === "usb",
                  toggle: () => Config.options.phone.webcam.connection = Config.options.phone.webcam.connection === "usb" ? "wifi" : "usb" },
                { icon: "hd", label: Config.options.phone.webcam.resolution === "1920x1080" ? "1080p" : Config.options.phone.webcam.resolution === "640x480" ? "480p" : "720p",
                  checked: Config.options.phone.webcam.resolution !== "640x480",
                  toggle: () => {
                      const r = Config.options.phone.webcam.resolution;
                      Config.options.phone.webcam.resolution = r === "640x480" ? "1280x720" : r === "1280x720" ? "1920x1080" : "640x480";
                  } }
            ]
            actions: PhoneCameraService.running ? [
                { icon: "preview", label: Translation.tr("Preview"), run: () => PhoneCameraService.openExternalPreview() }
            ] : []
        }
    }

    Component {
        id: micPanel
        FeaturePanel {
            symbol: PhoneMicService.running && PhoneMicService.muted ? "mic_off" : "mic"
            shapeKind: MaterialShape.Shape.Sunny
            featureState: root.micState
            title: root._micPresent ? Translation.tr("Phone Microphone") : Translation.tr("Install scrcpy or DroidCam")
            subtitle: {
                if (!root._micPresent)
                    return Translation.tr("See the missing dependencies");
                if (!root._deviceOnline)
                    return Translation.tr("Pair a reachable device");
                if (PhoneMicService.connecting)
                    return Translation.tr("Setting up audio routing…");
                if (PhoneMicService.running)
                    return (PhoneMicService.muted ? Translation.tr("Muted") : Translation.tr("Active for %1").arg(root._fmtElapsed(PhoneMicService.elapsedMs)))
                        + " · " + String(PhoneMicService.micGain) + "%";
                return Translation.tr("Uses scrcpy or DroidCam");
            }
            mainLabel: !root._micPresent ? Translation.tr("How to install")
                : root.micState === "active" ? Translation.tr("Stop") : Translation.tr("Start")
            mainSymbol: !root._micPresent ? "download"
                : root.micState === "active" ? "stop" : "play_arrow"
            mainEnabled: !root._micPresent || root._deviceOnline
            settingsPage: "PhoneMicPage.qml"
            error: root._micPresent && !PhoneMicService.running ? PhoneMicService.lastError.split("\n")[0] : ""
            detail: PhoneMicService.running
                ? [(PhoneMicService.activeIp || "USB") + ":" + String(PhoneMicService.activePort),
                   Translation.tr("gain %1%").arg(String(PhoneMicService.micGain)),
                   PhoneMicService.defaultOverridden ? Translation.tr("default input") : ""].filter(x => x.length > 0).join(" · ")
                : ""
            onMainClicked: root.micMain()
            onStopClicked: PhoneMicService.stopMic()
            toggles: {
                const list = [
                    { icon: "star", label: Translation.tr("Default input"),
                      checked: PhoneMicService.running ? PhoneMicService.defaultOverridden : Config.options.phone.microphone.setAsDefault,
                      toggle: () => {
                          if (!PhoneMicService.running) {
                              Config.options.phone.microphone.setAsDefault = !Config.options.phone.microphone.setAsDefault;
                          } else if (PhoneMicService.defaultOverridden) {
                              PhoneMicService.restoreDefaultSource();
                          } else {
                              PhoneMicService.overrideDefaultSource();
                          }
                      } },
                    { icon: "usb", label: Translation.tr("USB"), checked: Config.options.phone.microphone.connection === "usb",
                      toggle: () => Config.options.phone.microphone.connection = Config.options.phone.microphone.connection === "usb" ? "wifi" : "usb" }
                ];
                if (PhoneMicService.running) {
                    list.unshift(
                        { icon: PhoneMicService.muted ? "mic_off" : "mic", label: Translation.tr("Muted"), checked: PhoneMicService.muted,
                          toggle: () => PhoneMicService.toggleMute() },
                        { icon: "hearing", label: Translation.tr("Hear yourself"), checked: PhoneMicService.monitorEnabled,
                          toggle: () => PhoneMicService.toggleMonitor() });
                }
                return list;
            }
            actions: PhoneMicService.running ? [
                { icon: "tune", label: Translation.tr("Gain %1%").arg(String(PhoneMicService.micGain)),
                  run: () => {
                      // Cycle gain: 100 → 150 → 200 → 50 → 100.
                      const g = PhoneMicService.micGain;
                      PhoneMicService.setGain(g < 100 ? 100 : g < 150 ? 150 : g < 200 ? 200 : 50);
                  } }
            ] : []
        }
    }

    // ─── Components ─────────────────────────────────────────
    /** Collapsed-state pill: the feature's icon, name and a state colour. */
    component StatusPill: RippleButton {
        id: pill
        property string symbol: ""
        property string label: ""
        property string featureState: "ready"
        readonly property bool active: featureState === "active" || featureState === "connecting"
        readonly property bool dimmed: featureState === "unavailable" || featureState === "offline"

        implicitHeight: 40
        buttonRadius: pill.active ? Appearance.rounding.small : Appearance.rounding.full
        colBackground: pill.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
        colBackgroundHover: pill.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
        colRipple: pill.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer2Active
        opacity: pill.dimmed ? 0.55 : 1

        contentItem: Item {
            implicitWidth: pillRow.implicitWidth
            implicitHeight: pillRow.implicitHeight
            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: 5
                MaterialSymbol {
                    text: pill.symbol
                    iconSize: Appearance.font.pixelSize.large
                    fill: pill.active ? 1 : 0
                    color: pill.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
                StyledText {
                    text: pill.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: pill.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
                }
            }
        }
    }

    /** One feature: state header, main action, quick toggles and shortcuts. */
    component FeaturePanel: StyledFlickable {
        id: panel
        property string symbol: ""
        property int shapeKind: MaterialShape.Shape.Cookie9Sided
        property string featureState: "ready"
        property string title: ""
        property string subtitle: ""
        property string mainLabel: ""
        property string mainSymbol: ""
        property bool mainEnabled: true
        property bool showStop: false
        property string settingsPage: ""
        property var toggles: []
        property var actions: []
        /** Live session facts (address, device, gain) shown while running. */
        property string detail: ""
        property string error: ""
        property bool dropEnabled: false
        signal mainClicked()
        signal stopClicked()
        signal filesDropped(var urls)

        readonly property bool active: featureState === "active"
        readonly property bool busy: featureState === "connecting"
        readonly property bool dimmed: featureState === "unavailable" || featureState === "offline"

        clip: true
        contentHeight: panelColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        // Files dropped on a running mirror go to the phone
        DropArea {
            anchors.fill: parent
            enabled: panel.dropEnabled
            onDropped: drop => {
                if (drop.hasUrls)
                    panel.filesDropped(drop.urls);
            }
        }

        ColumnLayout {
            id: panelColumn
            width: panel.width
            spacing: 10

            // State header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: panel.symbol
                    iconSize: 20
                    padding: 9
                    fill: panel.active ? 1 : 0
                    shape: panel.shapeKind
                    color: panel.active ? Appearance.colors.colPrimary
                        : panel.dimmed ? Appearance.colors.colLayer2 : Appearance.colors.colPrimaryContainer
                    colSymbol: panel.active ? Appearance.colors.colOnPrimary
                        : panel.dimmed ? Appearance.colors.colSubtext : Appearance.colors.colOnPrimaryContainer
                    rotation: panel.active ? 30 : 0
                    Behavior on rotation {
                        enabled: !Appearance.reducedMotion
                        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.title
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer3
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: panel.subtitle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: panel.featureState === "offline" && panel.subtitle.length > 40
                            ? Appearance.colors.colError : Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }

                // Live chip: the session is running
                Rectangle {
                    visible: panel.active
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: liveRow.implicitWidth + 16
                    implicitHeight: 24
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colPrimary
                    RowLayout {
                        id: liveRow
                        anchors.centerIn: parent
                        spacing: 4
                        Rectangle {
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            text: Translation.tr("Live")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                RippleButton {
                    visible: panel.settingsPage.length > 0
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    colRipple: Appearance.colors.colLayer3Active
                    onClicked: root.requestOpenSubPage(Qt.resolvedUrl(panel.settingsPage))
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "tune"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledToolTip {
                        text: Translation.tr("More options")
                    }
                }
            }

            // Session facts while running
            Rectangle {
                Layout.fillWidth: true
                visible: panel.detail.length > 0
                implicitHeight: detailRow.implicitHeight + 14
                radius: Appearance.rounding.small
                color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer3, 0.06)
                RowLayout {
                    id: detailRow
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6
                    MaterialSymbol {
                        text: "info"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.detail
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer3
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            // Last error
            Rectangle {
                Layout.fillWidth: true
                visible: panel.error.length > 0
                implicitHeight: errorRow.implicitHeight + 14
                radius: Appearance.rounding.small
                color: Appearance.colors.colErrorContainer
                RowLayout {
                    id: errorRow
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 6
                    MaterialSymbol {
                        text: "error"
                        iconSize: Appearance.font.pixelSize.normal
                        fill: 1
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.error
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnErrorContainer
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }
            }

            // Main action (+ stop when the main action is not the stop)
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                RippleButton {
                    id: mainButton
                    Layout.fillWidth: true
                    implicitHeight: 44
                    enabled: panel.mainEnabled || panel.busy
                    opacity: enabled ? 1 : 0.5
                    // While connecting the main action cancels the launch.
                    readonly property bool isStop: panel.busy || panel.mainSymbol === "stop"
                    buttonRadius: mainButton.isStop ? Appearance.rounding.small : Appearance.rounding.full
                    colBackground: mainButton.isStop ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimary
                    colBackgroundHover: mainButton.isStop ? Appearance.colors.colErrorContainerHover : Appearance.colors.colPrimaryHover
                    colRipple: mainButton.isStop ? Appearance.colors.colErrorContainerActive : Appearance.colors.colPrimaryActive
                    onClicked: panel.busy ? panel.stopClicked() : panel.mainClicked()

                    contentItem: Item {
                        implicitWidth: mainRow.implicitWidth
                        implicitHeight: mainRow.implicitHeight
                        RowLayout {
                            id: mainRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: panel.busy ? "close" : panel.mainSymbol
                                iconSize: Appearance.font.pixelSize.larger
                                fill: 1
                                color: mainButton.isStop ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                text: panel.busy ? Translation.tr("Cancel") : panel.mainLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: mainButton.isStop ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }

                RippleButton {
                    visible: panel.showStop && !panel.busy
                    implicitWidth: 44
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.small
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.colors.colErrorContainerActive
                    onClicked: panel.stopClicked()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "stop"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledToolTip {
                        text: Translation.tr("Stop")
                    }
                }
            }

            // Quick toggles: dashed until on, secondary container when on
            Flow {
                Layout.fillWidth: true
                visible: panel.toggles.length > 0
                spacing: 6
                Repeater {
                    model: panel.toggles
                    delegate: QuickChip {
                        required property var modelData
                        symbol: modelData.icon
                        label: modelData.label
                        selected: modelData.checked
                        onTriggered: modelData.toggle()
                    }
                }
            }

            // Shortcuts: tonal icon buttons tinted with the group's content colour
            RowLayout {
                Layout.fillWidth: true
                visible: panel.actions.length > 0
                spacing: 6
                Repeater {
                    model: panel.actions
                    delegate: RippleButton {
                        id: actionButton
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 36
                        buttonRadius: actionButton.hovered ? Appearance.rounding.small : Appearance.rounding.full
                        colBackground: ColorUtils.applyAlpha(Appearance.colors.colOnLayer3, 0.08)
                        colBackgroundHover: ColorUtils.applyAlpha(Appearance.colors.colOnLayer3, 0.16)
                        colRipple: ColorUtils.applyAlpha(Appearance.colors.colOnLayer3, 0.24)
                        onClicked: actionButton.modelData.run()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: actionButton.modelData.icon
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer3
                        }
                        StyledToolTip {
                            text: actionButton.modelData.label
                        }
                    }
                }
            }
        }
    }

    /** The timetable rail's chip (ClockFormChip): dashed when off, filled when on. */
    component QuickChip: Rectangle {
        id: chip
        property string label: ""
        property string symbol: ""
        property bool selected: false
        signal triggered()

        implicitWidth: chipRow.implicitWidth + 22
        implicitHeight: 32
        radius: Appearance.rounding.full
        color: chip.selected ? Appearance.colors.colSecondaryContainer
            : chipPointer.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08) : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        DashedBorder {
            anchors.fill: parent
            visible: !chip.selected
            color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
            borderWidth: 1
            dashLength: 4
            gapLength: 3
            radius: Appearance.rounding.full
        }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: chip.symbol
                iconSize: Appearance.font.pixelSize.normal
                fill: chip.selected ? 1 : 0
                color: chip.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            }
            StyledText {
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.Bold
                color: chip.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
            }
        }

        MouseArea {
            id: chipPointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.triggered()
        }
    }

    // ─── Install guide popup overlay ───────────────────────
    InstallGuidePopup {
        id: installGuidePopup
        anchors.fill: parent
        z: 10
        visible: root._installGuideVisible
        missingDeps: root._installGuideDeps
        detectedDistro: {
            // Prefer PhoneCameraService's detection, fall back to others.
            if (PhoneCameraService.detectedDistro && PhoneCameraService.detectedDistro !== "unknown")
                return PhoneCameraService.detectedDistro;
            if (PhoneMicService.detectedDistro && PhoneMicService.detectedDistro !== "unknown")
                return PhoneMicService.detectedDistro;
            if (KdeConnectService.detectedDistro && KdeConnectService.detectedDistro !== "unknown")
                return KdeConnectService.detectedDistro;
            return "unknown";
        }
        headerTitle: root._installGuideTitle
        onCloseRequested: {
            root._installGuideVisible = false;
        }
        onRefreshRequested: {
            // Re-check all 3 services — the user may have installed deps
            // for any of the features.
            PhoneCameraService.refresh();
            PhoneMicService.refresh();
            KdeConnectService.checkScrcpyProc.running = true;
            KdeConnectService.checkAdbProc.running = true;
            KdeConnectService.checkPythonDbusProc.running = true;
        }
    }
}
