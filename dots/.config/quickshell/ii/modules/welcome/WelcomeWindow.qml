pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.ii.sidebarDashboard.wifiNetworks
import qs.modules.ii.sidebarDashboard.bluetoothDevices
import qs.modules.ii.sidebarDashboard.volumeMixer

FloatingWindow {
    id: root

    // Hidden, not closed, while the guide is stepped aside: the flow, the page
    // that is loaded and everything Edit Mode is doing carry straight through.
    visible: GlobalStates.welcomeOpen && !GlobalStates.welcomeCollapsed
    title: WelcomePageRegistry.titleFor(flow.currentPageId) + " · Welcome"
    implicitWidth: 1080
    implicitHeight: 780
    minimumSize: Qt.size(900, 640)
    color: "transparent"

    Rectangle {
        id: surface
        anchors.fill: parent
        clip: false
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        scale: (root.opening ? 0.992 : 1)
            * (root.welcomeDialogOpen && WelcomeMotion.level >= 2 ? 0.99 : 1)
        focus: root.visible

        layer.enabled: root.welcomeDialogOpen && WelcomeMotion.blurAllowed
        layer.effect: MultiEffect {
            blurEnabled: root.welcomeDialogOpen && WelcomeMotion.blurAllowed
            blurMax: WelcomeMotion.blurMax
            blur: root.welcomeDialogOpen ? WelcomeMotion.blurProgress : 0
        }

        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(surface)
        }

        // Driven by `collapseProgress` rather than by `scale`, which already
        // has a Behavior of its own: two animations on one property is one
        // animation chasing another's intermediate frames.
        opacity: 1 - root.collapseProgress
        transform: [
            Scale {
                // Toward the top-right corner, which is the direction the pill
                // is in.
                origin.x: surface.width
                origin.y: 0
                xScale: 1 - 0.32 * root.collapseProgress
                yScale: 1 - 0.32 * root.collapseProgress
            },
            Translate {
                x: root.collapseProgress * Appearance.rounding.verylarge * 2
                y: -root.collapseProgress * Appearance.rounding.verylarge * 2
            }
        ]

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: Appearance.rounding.small

            WelcomeHeader {
                id: header
                // Page decorations may overhang their stage; chrome stays on top.
                z: 2
                Layout.fillWidth: true
                currentPageId: flow.currentPageId
                outgoingPageId: flow.outgoingPageId
                incomingPageId: flow.incomingPageId
                transitionDirection: flow.transitionDirection
                transitionRunning: flow.transitionRunning
                transitionReady: flow.transitionReady
                collapsible: root.collapsible
                onCollapseRequested: root.collapse()
                onCloseRequested: root.closeWhenNavigationUnlocked()
            }

            WelcomeProgress {
                z: 2
                Layout.fillWidth: true
                currentPageIndex: WelcomePageRegistry.pageIndexById(flow.currentPageId)
                pageCount: WelcomePageRegistry.pages.length
            }

            Item {
                id: pageStage
                z: 1
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: -Appearance.rounding.verysmall
                clip: false

                WelcomeFlow {
                    id: flow
                    anchors.fill: parent
                    nextButtonHovered: navigation.nextButtonHovered
                    transform: Translate {
                        y: root.bodyEntranceY
                    }
                    navigationSafeArea: navigation.implicitHeight
                        + Appearance.rounding.large
                        + Appearance.rounding.normal

                    onOpenWifi: root.showWifiDialog = true
                    onOpenBluetooth: root.showBluetoothDialog = true
                    onOpenAudioOutput: root.showAudioOutputDialog = true
                    onTrySidebar: root.trySidebarPreview()
                    onTrySearch: root.trySearchPreview()
                    onOpenEditMode: root.tryEditModePreview()

                    onOpenSettingsPage: pageId => {
                        GlobalStates.openSettingsPage(pageId);
                    }

                    onOpenSettingsTarget: (pageId, subPageId, sectionId) => {
                        root.openSettingsTarget(pageId, subPageId, sectionId);
                    }
                }
            }
        }

        WelcomeNavigation {
            id: navigation
            visible: !flow.nestedPageOpen
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 32
            anchors.rightMargin: 32
            anchors.bottomMargin: Appearance.rounding.normal
            z: 5
            pageIndex: WelcomePageRegistry.pageIndexById(flow.currentPageId)
            pageCount: WelcomePageRegistry.pages.length
            transitionRunning: flow.transitionRunning
            nextLabel: flow.currentNextLabel
            nextIcon: flow.currentNextIcon
            skipVisible: flow.currentSkipLabel.length > 0
            skipLabel: flow.currentSkipLabel
            restoreVisible: flow.currentPageId === "hello"
            onPreviousRequested: flow.goPrevious()
            onNextRequested: flow.goNext()
            onSkipRequested: flow.skipCurrentPage()
            onRestoreRequested: root.showRestoreDialog = true
            onFinishRequested: GlobalStates.closeWelcome()
        }
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                if (!flow.closeNestedPage())
                    root.closeWhenNavigationUnlocked();
                event.accepted = true;
            } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left) {
                flow.goPrevious();
                event.accepted = true;
            } else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right) {
                flow.goNext();
                event.accepted = true;
            }
        }
    }

    // The Welcome host owns these loaders, so opening a quick control does not
    // mutate or close the Dashboard sidebar. Dialog implementations remain the
    // same ones used by Dashboard.
    property bool showWifiDialog: false
    property bool showBluetoothDialog: false
    property bool showAudioOutputDialog: false
    property bool showRestoreDialog: false
    property bool previewSidebarWasOpen: false
    property bool previewSearchWasOpen: false
    property bool previewSidebarOwned: false
    property bool previewSearchOwned: false
    property bool previewEditModeOwned: false

    /**
     * The bar step is the one that hands the screen over to Edit Mode, so it
     * is the only one that can be stepped aside for.
     */
    readonly property bool collapsible: flow.currentPageId === "bar" && GlobalStates.editMode

    /**
     * Whether the step has already stepped aside by itself. The timer is an
     * introduction, not a policy: someone who brought the window back has said
     * they want it, and a second automatic collapse would be the guide
     * arguing with them.
     */
    property bool autoCollapsedOnce: false

    /**
     * How far along the step-aside is: 0 is the full window, 1 is gone.
     *
     * The window cannot become the pill — one is a toplevel, the other a layer
     * surface — so the two halves are stitched instead. On the way out the
     * window shrinks toward the corner the pill lives in and only then hands
     * over; on the way back it is already on screen at the pill's size when
     * the pill disappears. What the eye follows is one object moving.
     */
    property real collapseProgress: 0

    NumberAnimation {
        id: collapseAnimation
        target: root
        property: "collapseProgress"
        to: 1
        duration: Appearance.animation.elementMoveExit.duration
        easing.type: Appearance.animation.elementMoveExit.type
        easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
        onFinished: GlobalStates.welcomeCollapsed = true
    }

    NumberAnimation {
        id: expandAnimation
        target: root
        property: "collapseProgress"
        to: 0
        duration: Appearance.animation.elementMoveEnter.duration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    function collapse(): void {
        if (!root.collapsible || GlobalStates.welcomeCollapsed)
            return;
        expandAnimation.stop();
        if (!WelcomeMotion.motionEnabled) {
            root.collapseProgress = 1;
            GlobalStates.welcomeCollapsed = true;
            return;
        }
        collapseAnimation.start();
    }

    function expand(): void {
        collapseAnimation.stop();
        GlobalStates.welcomeCollapsed = false;
        if (!WelcomeMotion.motionEnabled) {
            root.collapseProgress = 0;
            return;
        }
        expandAnimation.start();
    }
    property bool opening: false
    property real bodyEntranceY: 0

    function closeWhenNavigationUnlocked(): void {
        if (!flow.currentPageLocksNavigation())
            GlobalStates.closeWelcome();
    }

    Behavior on bodyEntranceY {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(root)
    }
    readonly property bool welcomeDialogOpen: showWifiDialog
        || showBluetoothDialog
        || showAudioOutputDialog
        || showRestoreDialog
        || wifiDialogHost.closing
        || bluetoothDialogHost.closing
        || audioDialogHost.closing
        || restoreDialogHost.closing

    function openCheatsheetGuide(sectionId: string): void {
        const icons = [];
        if (Config.options.cheatsheet.enableTimetable)
            icons.push("calendar_month");
        icons.push("keyboard");
        if (Config.options.cheatsheet.enablePeriodicTable)
            icons.push("experiment");
        if (Config.options.cheatsheet.enableAminoAcids)
            icons.push("biotech");
        if (Config.options.cheatsheet.enableCommands)
            icons.push("terminal");
        if (Config.options.cheatsheet.enableWorkspaceProfiles)
            icons.push("dashboard");
        if (Config.options.cheatsheet.enableGmail)
            icons.push("mail");

        const index = icons.indexOf(sectionId);
        if (index >= 0)
            Persistent.states.cheatsheet.tabIndex = index;
        GlobalStates.openCheatsheet();
    }

    function openSettingsTarget(pageId: string, subPageId: string, sectionId: string): void {
        if (pageId === "cheatSheet") {
            root.openCheatsheetGuide(sectionId);
            return;
        }

        const subPage = subPageId.length > 0
            ? Qt.resolvedUrl("../settings/configs/" + subPageId)
            : "";
        GlobalStates.openSettingsPage(pageId, subPage, "");
    }

    function trySidebarPreview(): void {
        if (!root.previewSidebarOwned && !root.previewSearchOwned) {
            root.previewSidebarWasOpen = GlobalStates.sidebarRightOpen;
            root.previewSearchWasOpen = GlobalStates.overviewOpen;
        }
        if (!GlobalStates.sidebarRightOpen) {
            GlobalStates.openRightSidebar();
            root.previewSidebarOwned = !root.previewSidebarWasOpen;
        }
    }

    function trySearchPreview(): void {
        if (!root.previewSidebarOwned && !root.previewSearchOwned) {
            root.previewSidebarWasOpen = GlobalStates.sidebarRightOpen;
            root.previewSearchWasOpen = GlobalStates.overviewOpen;
        }
        if (!GlobalStates.overviewOpen) {
            GlobalStates.openSearch();
            root.previewSearchOwned = !root.previewSearchWasOpen;
        }
    }

    /**
     * Edit Mode, plain. No catalogue and no panel: the tour walks through the
     * toolbar, and a drawer already slid out would be answering a question the
     * reader has not been shown how to ask yet.
     *
     * `keepWorkspace` is the whole reason this is not the keybind's own entry
     * point: the mode parks the desktop on an empty workspace when windows are
     * covering it, and the window covering it here is the Welcome doing the
     * asking.
     */
    function tryEditModePreview(): void {
        if (GlobalStates.editMode)
            return;
        GlobalStates.openEditMode("", true);
        // The mode refuses to open without a desktop to edit, so ownership is
        // what actually happened rather than what was asked for.
        root.previewEditModeOwned = GlobalStates.editMode;
    }

    function cleanupEditModePreview(): void {
        if (root.previewEditModeOwned && GlobalStates.editMode)
            GlobalStates.closeEditMode();
        root.previewEditModeOwned = false;
    }

    function cleanupPreviews(): void {
        if (root.previewSidebarOwned && !root.previewSidebarWasOpen)
            GlobalStates.sidebarRightOpen = false;
        if (root.previewSearchOwned && !root.previewSearchWasOpen)
            GlobalStates.overviewOpen = false;
        root.previewSidebarOwned = false;
        root.previewSearchOwned = false;
    }

    function restoreFocus(): void {
        surface.forceActiveFocus();
    }

    DialogHostLoader {
        id: restoreDialogHost
        owner: root
        shownPropertyString: "showRestoreDialog"
        focusTarget: surface
        z: 10
        dialog: WelcomeRestoreDialog {
            preferredDialogWidth: Math.min(560, root.width - 120)
        }
    }

    DialogHostLoader {
        id: wifiDialogHost
        owner: root
        shownPropertyString: "showWifiDialog"
        focusTarget: surface
        z: 10
        dialog: WifiDialog {
            closeOwningSidebarOnDetails: false
            showDetailsAction: false
            preferredDialogWidth: Math.min(760, root.width - 120)
        }
    }

    DialogHostLoader {
        id: bluetoothDialogHost
        owner: root
        shownPropertyString: "showBluetoothDialog"
        focusTarget: surface
        z: 10
        dialog: BluetoothDialog {
            closeOwningSidebarOnDetails: false
            showDetailsAction: false
            preferredDialogWidth: Math.min(760, root.width - 120)
        }
    }

    DialogHostLoader {
        id: audioDialogHost
        owner: root
        shownPropertyString: "showAudioOutputDialog"
        focusTarget: surface
        z: 10
        dialog: VolumeDialog {
            isSink: true
            closeOwningSidebarOnDetails: false
            showDetailsAction: false
            preferredDialogWidth: Math.min(760, root.width - 120)
        }
    }

    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            if (!GlobalStates.settingsOpen && root.visible)
                Qt.callLater(() => root.restoreFocus());
        }
    }

    Connections {
        target: GlobalStates
        function onCheatsheetOpenChanged() {
            if (!GlobalStates.cheatsheetOpen && root.visible)
                Qt.callLater(() => root.restoreFocus());
        }
    }

    Connections {
        target: flow
        function onPageChanged(pageId) {
            // The Search step opens a real panel over the Welcome and should
            // still have it when the page finishes arriving.
            if (pageId !== "search")
                root.cleanupPreviews();
            // The bar step is Edit Mode: it opens on arrival rather than
            // behind a button, because the page has nothing else to show.
            if (pageId === "bar") {
                GlobalStates.editGuideActive = true;
                root.tryEditModePreview();
            } else {
                GlobalStates.editGuideActive = false;
                root.autoCollapsedOnce = false;
                root.expand();
                root.cleanupEditModePreview();
            }
            if (root.visible)
                Qt.callLater(() => root.restoreFocus());
        }
    }

    // The window now goes invisible for two very different reasons — the
    // Welcome closing, and the guide stepping aside for Edit Mode — so only
    // the arrival is handled here. Teardown belongs to the destruction of the
    // window, which is what closing actually does: `shell.qml` keeps this
    // whole tree behind a Loader.
    onVisibleChanged: {
        if (visible) {
            root.opening = WelcomeMotion.motionEnabled;
            root.bodyEntranceY = root.opening
                ? Appearance.rounding.small * 2
                : 0;
            if (root.opening)
                Qt.callLater(() => root.opening = false);
            Qt.callLater(() => root.restoreFocus());
        } else {
            root.opening = false;
            root.bodyEntranceY = 0;
        }
    }

    // Closing the Welcome destroys this tree, so this is the one place that
    // runs exactly once per session and only on the way out.
    Component.onDestruction: {
        root.cleanupPreviews();
        root.cleanupEditModePreview();
        GlobalStates.editGuideActive = false;
        GlobalStates.welcomeCollapsed = false;
    }

    /**
     * The guide steps aside on its own.
     *
     * Someone who has just been dropped into Edit Mode looks at the toolbar,
     * not at the card explaining it, and the card is sitting on the desktop
     * they are being told to rearrange. The timer is generous enough to read
     * the page first, and the header's button is there for anyone faster.
     */
    Timer {
        interval: 9000
        repeat: false
        running: root.collapsible && root.visible
            && !root.autoCollapsedOnce && !GlobalStates.welcomeCollapsed
        onTriggered: {
            root.autoCollapsedOnce = true;
            root.collapse();
        }
    }

    Connections {
        target: GlobalStates

        // Done, on a guided session. The mode is finished with; the guide is
        // not, so it comes back and moves on rather than leaving the user on a
        // step whose whole content has just closed.
        function onEditGuideDoneRequested() {
            if (flow.currentPageId !== "bar")
                return;
            root.expand();
            flow.goNext();
        }

        // The mode ending any other way - Escape, the keybind - has the same
        // consequence for the pill: there is no toolbar left to sit beside.
        function onEditModeChanged() {
            if (!GlobalStates.editMode)
                root.expand();
        }
    }
}
