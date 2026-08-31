import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar as Bar
import qs.modules.ii.bar.shared
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects

import qs.modules.ii.sidebarDashboard.quickToggles
import qs.modules.ii.sidebarDashboard.quickToggles.classicStyle

import qs.modules.ii.sidebarDashboard.bluetoothDevices
import qs.modules.ii.sidebarDashboard.nightLight
import qs.modules.ii.sidebarDashboard.volumeMixer
import qs.modules.ii.sidebarDashboard.wifiNetworks
import qs.modules.ii.sidebarDashboard.darkMode
import qs.modules.ii.sidebarDashboard.localSend
import qs.modules.ii.sidebarDashboard.vpn
import qs.modules.ii.sidebarDashboard.tailscale
import qs.modules.ii.sidebarDashboard.dnsOverTls
import qs.modules.ii.sidebarDashboard.idleInhibitor
import qs.modules.ii.sidebarDashboard.screenShader
import qs.modules.ii.sidebarDashboard.modes
import "SidebarSpaceArbitration.js" as SpaceArbitration
import "SidebarPerformancePolicy.js" as PerformancePolicy

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool showDarkModeDialog: false
    property bool showLocalSendDialog: false
    property bool showVpnDialog: false
    property bool showTailscaleDialog: false
    property bool showDnsOverTlsDialog: false
    property bool showIdleInhibitorDialog: false
    property bool showScreenShaderDialog: false
    property bool showModesDialog: false
    readonly property bool anyDialogVisible: showAudioOutputDialog || showAudioInputDialog || showBluetoothDialog || showNightLightDialog || showWifiDialog || showDarkModeDialog || showLocalSendDialog || showVpnDialog || showTailscaleDialog || showDnsOverTlsDialog || showIdleInhibitorDialog || showScreenShaderDialog || showModesDialog
    property bool editMode: false
    property bool isLoadedOnLeft: false
    readonly property bool dashboardSidebarAnimating: isLoadedOnLeft
        ? GlobalStates.leftSidebarAnimating
        : GlobalStates.rightSidebarAnimating
    readonly property bool entranceAnimationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
    property int entranceTrigger: -1
    property bool entrancePending: false

    function queueContentEntrance() {
        if (!PerformancePolicy.shouldQueueEntranceAnimations(
                root.entranceAnimationsEnabled, GlobalStates.sidebarRightOpen))
            return;
        root.entrancePending = true;
        root.activateDeferredContent();
        root.triggerContentEntranceIfReady();
    }

    function triggerContentEntranceIfReady() {
        if (!PerformancePolicy.canTriggerEntranceAnimations(
                root.entrancePending,
                root.entranceAnimationsEnabled,
                GlobalStates.sidebarRightOpen,
                root.dashboardSidebarAnimating
            ))
            return;
        root.activateDeferredContent();
        root.entrancePending = false;
        root.entranceTrigger++;
    }

    onEntranceAnimationsEnabledChanged: {
        if (entranceAnimationsEnabled)
            root.queueContentEntrance();
        else
            root.entrancePending = false;
    }

    // Compact-space arbitration is runtime-only. When the height that the
    // notification center would receive with the bottom group expanded falls
    // below its useful minimum, exactly one of the two groups stays expanded.
    // Notifications win when compact mode first activates; a manual expansion
    // request from the bottom group hands the space to it until it is collapsed.
    property bool compactBottomRequestedExpanded: false
    readonly property real expandedNotificationsHeightBudget: SpaceArbitration.expandedCenterBudget(
        adaptiveGroups.availableHeight,
        bottomGroup.expandedHeight,
        sidebarPadding
    )
    readonly property real minimumExpandedNotificationsHeight: centerGroup.item?.minimumExpandedHeight ?? 0
    readonly property bool compactModeRequired: SpaceArbitration.requiresCompactMode(
        expandedNotificationsHeightBudget,
        minimumExpandedNotificationsHeight,
        !editMode && centerGroup.visible && bottomGroup.visible
    )
    readonly property var compactSpaceResolution: SpaceArbitration.resolve(
        compactModeRequired,
        compactBottomRequestedExpanded,
        bottomGroup.collapsed,
        editMode
    )
    readonly property bool notificationsCollapsed: compactSpaceResolution.notificationsCollapsed
    readonly property bool bottomForceCollapsed: compactSpaceResolution.bottomForcedCollapsed

    onCompactModeRequiredChanged: compactBottomRequestedExpanded = false

    // The optimized default incubates heavy delegates after the outer motion.
    // The explicit animation opt-in instead loads them with the open request,
    // so their entrance choreography starts while the sidebar itself slides.
    property bool deferredContentReady: false
    function activateDeferredContent() {
        deferredContentReady = PerformancePolicy.nextDeferredContentReady(
            deferredContentReady,
            GlobalStates.sidebarRightOpen,
            root.dashboardSidebarAnimating,
            root.entranceAnimationsEnabled
        );
    }

    onDashboardSidebarAnimatingChanged: {
        if (!dashboardSidebarAnimating) {
            root.activateDeferredContent();
            root.triggerContentEntranceIfReady();
        }
    }

    readonly property bool isDynamicIslandTop: !Config.options.bar.vertical && !Config.options.bar.bottom && Config.options.bar.cornerStyle === 3
    readonly property bool isDynamicIslandBottom: !Config.options.bar.vertical && Config.options.bar.bottom && Config.options.bar.cornerStyle === 3

    Component.onCompleted: {
        if (GlobalStates.requestVolumeDialog) {
            root.showAudioOutputDialog = true;
            GlobalStates.requestVolumeDialog = false;
        }
        root.activateDeferredContent();
        if (GlobalStates.sidebarRightOpen)
            root.queueContentEntrance();
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen) {
                // Let target-width bindings start the outer animation first.
                Qt.callLater(root.activateDeferredContent);
                root.queueContentEntrance();
            } else {
                root.entrancePending = false;
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.showDarkModeDialog = false;
                root.showLocalSendDialog = false;
                root.showVpnDialog = false;
                root.showTailscaleDialog = false;
                root.showDnsOverTlsDialog = false;
                root.showIdleInhibitorDialog = false;
                root.showScreenShaderDialog = false;
                root.showModesDialog = false;
                pomodoroTimePicker.close();
            }
        }
    }

    Connections {
        target: GlobalStates
        function onRequestVolumeDialogChanged() {
            if (GlobalStates.requestVolumeDialog) {
                root.showAudioOutputDialog = true;
                GlobalStates.requestVolumeDialog = false;
            }
        }
    }

    BarThemes {
        id: barThemes
    }
    readonly property var activeTheme: barThemes.getTheme(Config.options.bar.expressiveColorTheme)

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    // Edit mode grows the quick panel by a tray of every toggle that is not on a
    // page, which has no natural cap and runs straight past the bottom of the
    // sidebar. Hand the panel the height the column can actually give it, so it
    // can cap and scroll that tray itself.
    readonly property real quickPanelMaxHeight: {
        let available = mainColumn.height;
        const fixedHeights = [
            sidebarBanner.visible ? sidebarBanner.Layout.preferredHeight : -1,
            headerRow.visible ? headerRow.implicitHeight + headerRow.Layout.topMargin : -1,
            centerGroup.visible ? centerGroup.implicitHeight : -1,
            bottomGroup.visible
                ? (bottomGroup.effectivelyCollapsed
                    ? bottomGroup.collapsedHeight
                    : bottomGroup.expandedHeight)
                : -1
        ];
        for (let i = 0; i < fixedHeights.length; i++) {
            if (fixedHeights[i] < 0)
                continue;
            available -= fixedHeights[i] + mainColumn.spacing;
        }
        return Math.max(0, available);
    }

    Loader {
        id: sidebarRightShadowLoader
        active: (!GlobalStates.connectModeActive || GlobalStates.connectSidebarsSeparate || root.isDynamicIslandTop || root.isDynamicIslandBottom) && !root.anyDialogVisible
        sourceComponent: Component {
            StyledRectangularShadow {
                target: sidebarRightBackground
                radius: sidebarRightBackground.radius
            }
        }
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        clip: true
        implicitHeight: Math.max(0, parent.height - Appearance.sizes.hyprlandGapsOut * 2)
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate) ? "transparent" : (Config.options.bar.expressiveColors ? activeTheme.barBackground : Appearance.colors.colLayer0)
        border.width: (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate) ? 0 : 1
        border.color: (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate) ? "transparent" : Appearance.colors.colLayer0Border
        readonly property bool isConnectDynamicIslandTop: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && root.isDynamicIslandTop
        readonly property bool isConnectDynamicIslandBottom: GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && root.isDynamicIslandBottom
        readonly property real defaultRadius: (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && !root.isDynamicIslandTop && !root.isDynamicIslandBottom) ? 0 : Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
        radius: isConnectDynamicIslandTop ? 0 : defaultRadius
        topRightRadius: ((isConnectDynamicIslandTop && !root.isLoadedOnLeft) || (isConnectDynamicIslandBottom && root.isLoadedOnLeft)) ? 0 : defaultRadius
        topLeftRadius: ((isConnectDynamicIslandTop && root.isLoadedOnLeft) || (isConnectDynamicIslandBottom && !root.isLoadedOnLeft)) ? 0 : defaultRadius
        bottomRightRadius: (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && !isConnectDynamicIslandBottom) ? 0 : ((isConnectDynamicIslandBottom && !root.isLoadedOnLeft) ? 0 : defaultRadius)
        bottomLeftRadius: (GlobalStates.connectModeActive && !GlobalStates.connectSidebarsSeparate && !isConnectDynamicIslandBottom) ? 0 : ((isConnectDynamicIslandBottom && root.isLoadedOnLeft) ? 0 : defaultRadius)

        property real dialogBlurProgress: root.anyDialogVisible ? 1.0 : 0.0
        Behavior on dialogBlurProgress {
            NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: mainColumn
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            layer.enabled: sidebarRightBackground.dialogBlurProgress > 0.01
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 32
                blur: sidebarRightBackground.dialogBlurProgress
            }

            // SIDEBAR BANNER
            SidebarBanner {
                id: sidebarBanner
                Layout.fillWidth: true
                Layout.preferredHeight: 220
                visible: Config.options.sidebar.enableBanner
                enabled: visible
                editMode: root.editMode
                onEditModeToggled: (newEditMode) => root.editMode = newEditMode
            }

            // DEFAULT
            SystemButtonRow {
                id: headerRow
                Layout.fillHeight: false
                Layout.fillWidth: true
                // Layout.margins: 10
                Layout.topMargin: 5
                Layout.bottomMargin: 0
                visible: !Config.options.sidebar.enableBanner
                enabled: visible
                entranceTrigger: root.entranceTrigger
                editMode: root.editMode
                onEditModeToggled: (newEditMode) => root.editMode = newEditMode
            }

            LoaderedQuickPanelImplementation {
                id: classicQuickPanelLoader
                styleName: "classic"
                sourceComponent: ClassicQuickPanel {
                    editMode: root.editMode
                    onOpenVpnDialog: root.showVpnDialog = true
                    onOpenTailscaleDialog: root.showTailscaleDialog = true
                }
            }

            LoaderedQuickPanelImplementation {
                id: androidQuickPanelLoader
                styleName: "android"
                sourceComponent: AndroidQuickPanel {
                    editMode: root.editMode
                    maxContentHeight: root.quickPanelMaxHeight
                    entranceTrigger: root.entranceTrigger
                    onOpenVpnDialog: root.showVpnDialog = true
                    onOpenTailscaleDialog: root.showTailscaleDialog = true
                    onOpenDnsOverTlsDialog: root.showDnsOverTlsDialog = true
                    onOpenScreenShaderDialog: root.showScreenShaderDialog = true
                }
            }

            Item {
                id: adaptiveGroups
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.minimumHeight: containmentHeight
                // This boundary lies inside the dashboard's rounded silhouette
                // and contains Bottom overshoot without clipping unrelated
                // header/quick-toggle shadows or allocating an FBO.
                clip: true
                readonly property real availableHeight: Math.max(0, mainColumn.height - y)
                readonly property real packedTakeoverHeight: SpaceArbitration.packedGroupsMinimumHeight(
                        bottomGroup.expandedHeight,
                        centerGroup.collapsedHeight,
                        targetSpacing
                    )
                readonly property real targetContainmentHeight: root.notificationsCollapsed
                    ? packedTakeoverHeight
                    : availableHeight
                property real containmentHeight: targetContainmentHeight
                readonly property real targetSpacing: SpaceArbitration.dashboardSpacing(
                    root.notificationsCollapsed,
                    root.sidebarPadding
                )
                readonly property real targetBottomHeight: bottomGroup.effectivelyCollapsed
                    ? bottomGroup.collapsedHeight
                    : root.notificationsCollapsed
                        ? SpaceArbitration.expandedBottomFillHeight(
                            availableHeight,
                            bottomGroup.expandedHeight,
                            centerGroup.collapsedHeight,
                            targetSpacing
                        )
                        : bottomGroup.expandedHeight
                readonly property real expandedCenterTargetHeight: Math.max(
                    0,
                    availableHeight - targetBottomHeight - targetSpacing
                )
                property real groupSpacing: targetSpacing
                property real animatedBottomHeight: targetBottomHeight

                Behavior on containmentHeight {
                    SidebarGroupAnimation {
                        animationSpec: Appearance.animation.elementMove
                    }
                }

                Behavior on groupSpacing {
                    SidebarGroupAnimation {
                        animationSpec: Appearance.animation.elementMove
                    }
                }

                Behavior on animatedBottomHeight {
                    SidebarGroupAnimation {
                        animationSpec: Appearance.animation.elementMove
                    }
                }

                Loader {
                    id: centerGroup
                    // Notifications remain backed by their global service; only the
                    // heavy visual center group is incubated after the sidebar
                    // slide and then kept warm for this dashboard instance.
                    active: root.deferredContentReady
                    asynchronous: true
                    sourceComponent: CenterWidgetGroup {
                        collapsed: root.notificationsCollapsed
                        entranceTrigger: root.entranceTrigger
                    }
                    readonly property real collapsedHeight: item?.collapsedHeight ?? 0
                    property real animatedHeight: SpaceArbitration.notificationMaximumHeight(
                        root.notificationsCollapsed,
                        collapsedHeight,
                        adaptiveGroups.expandedCenterTargetHeight
                    )

                    Behavior on animatedHeight {
                        SidebarGroupAnimation {
                            animationSpec: Appearance.animation.elementMove
                        }
                    }

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: bottomGroup.top
                    anchors.bottomMargin: adaptiveGroups.groupSpacing
                    height: animatedHeight
                    visible: !root.editMode
                }

                BottomWidgetGroup {
                    id: bottomGroup
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: adaptiveGroups.animatedBottomHeight
                    forceCollapsed: root.bottomForceCollapsed
                    outerSidebarAnimating: root.dashboardSidebarAnimating
                    entranceTrigger: root.entranceTrigger
                    onCollapseRequested: shouldCollapse => {
                        if (root.compactModeRequired)
                            root.compactBottomRequestedExpanded = !shouldCollapse;
                    }
                }
            }
        }
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showAudioOutputDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: VolumeDialog {
            isSink: true
        }
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showAudioInputDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: VolumeDialog {
            isSink: false
        }
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showBluetoothDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: BluetoothDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showNightLightDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: NightLightDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showWifiDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: WifiDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showDarkModeDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: DarkModeDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showLocalSendDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: LocalSendDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showVpnDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: VpnDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showTailscaleDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: TailscaleDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showDnsOverTlsDialog"
        dialogRadius: sidebarRightBackground.defaultRadius
        dialog: DnsOverTlsDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showIdleInhibitorDialog"
        dialog: IdleInhibitorDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showScreenShaderDialog"
        dialog: ScreenShaderDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showModesDialog"
        dialog: ModesDialog {}
    }

    TimePickerPopup {
        id: pomodoroTimePicker
        anchors.fill: parent
        z: 999
        onAccepted: (pickedHour, pickedMinute) => {
            TimerService.setPomodoroTime(pickedHour, pickedMinute);
        }
    }

    Connections {
        target: TimerService
        function onCustomTimeRequested(currentHour, currentMinute, title) {
            pomodoroTimePicker.open(currentHour, currentMinute, title);
        }
    }

    component SidebarBanner: Item {
        id: headerRoot
        property bool editMode: false
        signal editModeToggled(bool newEditMode)
        implicitHeight: 220

        Rectangle {
            id: bannerBackground
            anchors.fill: parent
            radius: 15
            color: Appearance.colors.colLayer1

            // wallpaper section (top 70%)
            Item {
                id: wallpaperArea
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                height: parent.height * 0.7

                readonly property string rawBannerSource: {
                    if (Config.options.sidebar.useCustomBanner) {
                        return Config.options.sidebar.bannerImage || `${Directories.assetsPath}/images/default_wallpaper.png`;
                    }
                    return Config.options.background.wallpaperPath || "";
                }

                readonly property string cleanBannerSource: {
                    let p = wallpaperArea.rawBannerSource;
                    if (!p) return "";
                    const qIdx = p.indexOf("?");
                    if (qIdx !== -1) p = p.substring(0, qIdx);
                    return p.startsWith("file://") ? p : ("file://" + p);
                }

                readonly property bool isBannerAnimated: {
                    const lower = wallpaperArea.cleanBannerSource.toLowerCase();
                    return lower.includes(".gif") || lower.includes(".webp");
                }

                readonly property bool shouldPlayBanner: {
                    return GlobalStates.dashboardPanelOpen && wallpaperArea.isBannerAnimated;
                }
                
                Rectangle {
                    id: imageMask
                    anchors.fill: parent
                    radius: 15
                    visible: false
                }

                // Static Image Banner (zero QMovie overhead)
                Image {
                    id: bannerImage
                    anchors.fill: parent
                    readonly property real windowDpr: (QsWindow.window as QsWindow)?.devicePixelRatio ?? 0
                    property size decodeBox: Qt.size(0, 0)
                    onWindowDprChanged: bannerImage.growDecodeBox()
                    onWidthChanged: bannerImage.growDecodeBox()
                    onHeightChanged: bannerImage.growDecodeBox()
                    function growDecodeBox() {
                        if (bannerImage.windowDpr <= 0 || bannerImage.width <= 0 || bannerImage.height <= 0)
                            return;
                        const boxWidth = Math.ceil(bannerImage.width * bannerImage.windowDpr);
                        const boxHeight = Math.ceil(bannerImage.height * bannerImage.windowDpr);
                        if (boxWidth <= bannerImage.decodeBox.width && boxHeight <= bannerImage.decodeBox.height)
                            return;
                        bannerImage.decodeBox = Qt.size(Math.max(boxWidth, bannerImage.decodeBox.width),
                            Math.max(boxHeight, bannerImage.decodeBox.height));
                    }

                    source: (!wallpaperArea.isBannerAnimated && bannerImage.decodeBox.width > 0)
                        ? wallpaperArea.cleanBannerSource
                        : ""
                    sourceSize: bannerImage.decodeBox
                    fillMode: Image.PreserveAspectCrop
                    cache: false
                    asynchronous: true
                    visible: !wallpaperArea.isBannerAnimated
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: imageMask
                    }
                }

                // Animated GIF Banner (only active when isBannerAnimated is true, paused when sidebar is closed)
                AnimatedImage {
                    id: bannerAnimatedImage
                    anchors.fill: parent
                    source: wallpaperArea.isBannerAnimated ? wallpaperArea.cleanBannerSource : ""
                    fillMode: Image.PreserveAspectCrop
                    playing: wallpaperArea.shouldPlayBanner
                    paused: !wallpaperArea.shouldPlayBanner
                    cache: false
                    asynchronous: true
                    visible: wallpaperArea.isBannerAnimated && status === Image.Ready
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: imageMask
                    }
                }
            }

            // Button section
            Rectangle {
                id: buttonArea

                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }

                height: parent.height * 0.3
                color: Appearance.colors.colLayer1
                bottomLeftRadius: bannerBackground.bottomLeftRadius
                bottomRightRadius: bannerBackground.bottomRightRadius
            }

            // pfp overlaps both sections
            Item {
                id: profilePicContainer

                anchors {
                    left: parent.left
                    bottom: buttonArea.bottom

                    leftMargin: 16
                    bottomMargin: 55
                }

                width: 70
                height: 70
                visible: Config.options.sidebar.dashboardHeader.profileImageType !== "none"

                // DISTRO ICON
                Loader {
                    anchors.fill: parent
                    active: Config.options.sidebar.dashboardHeader.profileImageType === "distro"
                    sourceComponent: CustomIcon {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        height: parent.height - 8
                        source: SystemInfo.distroIcon
                        colorize: true
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // USER PROFILE
                UserProfileAvatar {
                    anchors.fill: parent
                    active: GlobalStates.dashboardPanelOpen
                    visible: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile"
                    avatarShape: Config.options.sidebar.dashboardHeader.avatarShape
                    fontPixelSize: 32
                    fontWeight: Font.Black
                    borderWidth: 4
                    borderColor: Appearance.colors.colLayer1
                }
            }

            // sidebar banner text
            Column {
                id: greetingTextColumn
                anchors {
                    left: parent.left
                    leftMargin: 20   // matches systemButtonsRow's rightMargin
                    verticalCenter: buttonArea.verticalCenter
                }
                spacing: 2

                // greeting text
                Text {
                    id: greetingText
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: 14
                    font.weight: Font.Normal
                    horizontalAlignment: Text.AlignLeft
                    width: 210
                    elide: Text.ElideRight

                    text: {
                        const mode = Config.options.sidebar.dashboardHeader.textMode;
                        const hour = (DateTime.clock?.date ?? new Date()).getHours();
                        const timeGreeting = hour < 5 ? Translation.tr("Good Night,")
                            : hour < 12 ? Translation.tr("Good Morning,")
                                : hour < 18 ? Translation.tr("Good Afternoon,")
                                    : hour < 22 ? Translation.tr("Good Evening,")
                                        : Translation.tr("Good Night,");
                        return mode === "username"
                            ? (Config.options.userProfile.customGreeting !== "" ? Config.options.userProfile.customGreeting : timeGreeting) + " " + (Config.options.userProfile.customName !== "" ? Config.options.userProfile.customName : SystemInfo.username.charAt(0).toUpperCase() + SystemInfo.username.slice(1))
                            : mode === "uptime"
                                ? Translation.tr("Uptime") + ": " + DateTime.uptime
                                : mode === "custom"
                                    ? Config.options.sidebar.dashboardHeader.customText
                                    : "";
                    }
                }

                // subtext under greeting
                Text {
                    id: greetingSubtextText
                    color: "#888888"
                    font.pixelSize: 12
                    font.weight: Font.Normal
                    horizontalAlignment: Text.AlignLeft
                    width: 220
                    elide: Text.ElideRight

                    visible: Config.options.sidebar.dashboardSubHeader.greetingSubtextMode !== "none"
                    text: {
                        const mode = Config.options.sidebar.dashboardSubHeader.greetingSubtextMode;
                        return mode === "uptime"
                            ? Translation.tr("Up • ") + DateTime.uptime
                            : mode === "custom"
                                ? Config.options.sidebar.dashboardSubHeader.customText
                                : "";
                    }
                }
            }
        }

        // sidebar banner buttons
        Item {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: 10
            }

            height: systemButtonsRow.implicitHeight

            ButtonGroup {
                id: systemButtonsRow
                anchors {
                    right: parent.right
                    rightMargin: 10
                    verticalCenter: buttonArea.verticalCenter
                }
                color: Appearance.colors.colLayer1
                padding: 4

                QuickToggleButton {
                    id: editButton
                    toggled: headerRoot.editMode

                    visible:
                        Config.options.sidebar.quickToggles.style === "android"

                    buttonIcon: "edit"
                    onClicked: {
                        headerRoot.editMode = !headerRoot.editMode
                        headerRoot.editModeToggled(headerRoot.editMode)
                    }
                }

                QuickToggleButton {
                    buttonIcon: "restart_alt"
                    onClicked: {
                        Quickshell.execDetached(["hyprctl", "reload"])
                        Quickshell.reload(true)
                    }
                }

                QuickToggleButton {
                    buttonIcon: "settings"
                    onClicked: {
                        GlobalStates.sidebarRightOpen = false
                        GlobalStates.toggleSettings()
                    }
                }

                QuickToggleButton {
                    buttonIcon: "power_settings_new"
                    onClicked: {
                        GlobalStates.sessionOpen = true
                    }
                }
            }
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown)
            toggleDialogLoader.active = true
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        onLoaded: {
            if (item && item.hasOwnProperty("radius")) {
                item.radius = sidebarRightBackground.defaultRadius;
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false;
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString])
                    toggleDialogLoader.active = false;
            }
        }
    }

    component LoaderedQuickPanelImplementation: Loader {
        id: quickPanelImplLoader
        required property string styleName
        Layout.alignment: item?.Layout.alignment ?? Qt.AlignHCenter
        Layout.fillWidth: item?.Layout.fillWidth ?? false
        Layout.preferredHeight: animatedPanelHeight
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
        clip: true
        property real animatedPanelHeight: item?.implicitHeight ?? 0

        // Animate the panel at its single layout boundary. Animating nested
        // heights makes the outer target move on every frame and stretches the
        // perceived transition beyond the configured duration.
        Behavior on animatedPanelHeight {
            SidebarGroupAnimation {
                animationSpec: Appearance.animation.elementMove
            }
        }

        Connections {
            target: quickPanelImplLoader.item
            function onOpenAudioOutputDialog() {
                root.showAudioOutputDialog = true;
            }
            function onOpenAudioInputDialog() {
                root.showAudioInputDialog = true;
            }
            function onOpenBluetoothDialog() {
                root.showBluetoothDialog = true;
            }
            function onOpenNightLightDialog() {
                root.showNightLightDialog = true;
            }
            function onOpenWifiDialog() {
                root.showWifiDialog = true;
            }
            function onOpenDarkModeDialog() {
                root.showDarkModeDialog = true;
            }
            function onOpenLocalSendDialog() {
                root.showLocalSendDialog = true;
            }
            function onOpenIdleInhibitorDialog() {
                root.showIdleInhibitorDialog = true;
            }
            function onOpenModesDialog() {
                root.showModesDialog = true;
            }
        }
    }

    component SystemButtonRow: Item {
        id: systemButtonRowRoot
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)
        property int entranceTrigger: -1
        property bool editMode: false
        signal editModeToggled(bool newEditMode)

        DashboardEntranceProgress {
            id: headerEntranceProgress
            animationSpec: Appearance.animation.elementMove
            animationsEnabled: Config.options.sidebar.dashboardEntranceAnimations
            trigger: systemButtonRowRoot.entranceTrigger
        }

        Rectangle {
            id: uptimeContainer
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            opacity: headerEntranceProgress.progress
            transform: Translate {
                x: -30 * (1 - headerEntranceProgress.progress)
                y: -15 * (1 - headerEntranceProgress.progress)
            }
            readonly property int fullRadius: Config.options.appearance.sharpMode ? Appearance.rounding.full : height / 2
            radius: fullRadius

            visible: Config.options.sidebar.dashboardHeader.profileImageType !== "none" || Config.options.sidebar.dashboardHeader.textMode !== "none"

            property int rowLeftMargin: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile" ? 6 : 14
            readonly property bool _hasText: Config.options.sidebar.dashboardHeader.textMode !== "none"
            readonly property int rowRightMargin: _hasText ? 14 : rowLeftMargin

            implicitWidth: uptimeRow.implicitWidth + rowLeftMargin + rowRightMargin
            implicitHeight: Math.max(32, uptimeRow.implicitHeight + (Config.options.sidebar.dashboardHeader.profileImageType === "user_profile" ? 4 : 12))

            Row {
                id: uptimeRow
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                    leftMargin: uptimeContainer.rowLeftMargin
                }
                spacing: 8

                // PROFILE PICTURE
                Item {
                    id: profilePicContainer

                    anchors.verticalCenter: parent.verticalCenter
                    width: Config.options.sidebar.dashboardHeader.profileImageType === "distro" ? 24 : 40
                    height: Config.options.sidebar.dashboardHeader.profileImageType === "distro" ? 24 : 40
                    visible: Config.options.sidebar.dashboardHeader.profileImageType !== "none"

                    Loader {
                        anchors.fill: parent
                        active: Config.options.sidebar.dashboardHeader.profileImageType === "distro"
                        sourceComponent: CustomIcon {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            source: SystemInfo.distroIcon
                            colorize: true
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    UserProfileAvatar {
                        anchors.fill: parent
                        active: GlobalStates.dashboardPanelOpen
                        visible: Config.options.sidebar.dashboardHeader.profileImageType === "user_profile"
                        avatarShape: Config.options.sidebar.dashboardHeader.avatarShape
                    }
                }

                ColumnLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    visible: Config.options.sidebar.dashboardHeader.textMode !== "none"

                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colOnLayer0
                        text: {
                            const mode = Config.options.sidebar.dashboardHeader.textMode;
                            if (mode === "username") {
                                const greeting = Config.options.userProfile.customGreeting;
                                return (greeting !== "" ? greeting : Translation.tr("Hello,")) + " " + (Config.options.userProfile.customName !== "" ? Config.options.userProfile.customName : SystemInfo.username);
                            }
                            if (mode === "uptime")
                                return Translation.tr("Uptime") + ": " + DateTime.uptime;
                            if (mode === "custom")
                                return Config.options.sidebar.dashboardHeader.customText;
                            return "";
                        }
                        font.bold: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        text: Config.options.userProfile.customBio
                        visible: Config.options.sidebar.dashboardHeader.textMode === "username" && text !== ""
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4
            opacity: headerEntranceProgress.progress
            transform: Translate {
                x: 30 * (1 - headerEntranceProgress.progress)
                y: -15 * (1 - headerEntranceProgress.progress)
            }

            QuickToggleButton {
                id: editButton
                rotation: -180 * (1 - headerEntranceProgress.progress)
                toggled: systemButtonRowRoot.editMode
                buttonIcon: "edit"
                onClicked: {
                    systemButtonRowRoot.editMode = !systemButtonRowRoot.editMode;
                    systemButtonRowRoot.editModeToggled(systemButtonRowRoot.editMode);
                }
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (!systemButtonRowRoot.editMode ? "" : Config.options.sidebar.quickToggles.style === "android" ? Translation.tr("\nLMB to enable/disable\nDrag handles to resize\nDrag icon to swap position") : Translation.tr("\nLMB to show/hide a toggle"))
                }

            }
            QuickToggleButton {
                id: reloadButton
                rotation: -360 * (1 - headerEntranceProgress.progress)
                toggled: false
                buttonIcon: "restart_alt"
                onClicked: {
                    Quickshell.execDetached(["hyprctl", "reload"]);
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: Translation.tr("Reload Hyprland & Quickshell")
                }

            }
            QuickToggleButton {
                id: settingsButton
                rotation: 90 * (1 - headerEntranceProgress.progress)
                toggled: false
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    GlobalStates.toggleSettings();
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }

            }

            QuickToggleButton {
                id: powerButton
                rotation: -90 * (1 - headerEntranceProgress.progress)
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }

            }
        }
    }
}
