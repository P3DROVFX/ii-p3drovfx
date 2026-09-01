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

    visible: GlobalStates.welcomeOpen
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
            skipVisible: flow.currentPageId === "keyboard"
            skipLabel: Translation.tr("Skip")
            onPreviousRequested: flow.goPrevious()
            onNextRequested: flow.goNext()
            onSkipRequested: flow.skipCurrentPage()
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
    property bool previewSidebarWasOpen: false
    property bool previewSearchWasOpen: false
    property bool previewSidebarOwned: false
    property bool previewSearchOwned: false
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
        || wifiDialogHost.closing
        || bluetoothDialogHost.closing
        || audioDialogHost.closing

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
            if (pageId !== "experience")
                root.cleanupPreviews();
            if (root.visible)
                Qt.callLater(() => root.restoreFocus());
        }
    }

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
            root.cleanupPreviews();
            root.showWifiDialog = false;
            root.showBluetoothDialog = false;
            root.showAudioOutputDialog = false;
            flow.reset();
        }
    }
}
