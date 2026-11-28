//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=2200

// Gallery: standalone Material 3 Expressive media gallery integrated into the ii shell.
// Runs in its own qs -p process so closing it returns 100% of its RAM to the OS:
//   qs -p ~/.config/quickshell/ii/apps/gallery.qml [ipc call gallery open [tab]]
// Imports resolve against apps/ (slim Appearance/Config/GlobalStates; see apps/README.md).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "./gallery"

ApplicationWindow {
    id: root

    visible: true
    width: Math.min(1320, Math.round((Screen.width || 1920) * 0.78))
    height: Math.min(820, Math.round((Screen.height || 1080) * 0.78))
    minimumWidth: 820
    minimumHeight: 560
    title: "Gallery"
    color: Config.options?.appearance?.transparency?.enable
        ? Appearance.colors.colLayer0
        : Appearance.m3colors.m3background

    onClosing: Qt.quit()

    property bool isFullscreenState: root.visibility === Window.FullScreen

    onVisibilityChanged: {
        root.isFullscreenState = (root.visibility === Window.FullScreen);
    }

    function toggleFullscreenState(): void {
        if (root.isFullscreenState) {
            root.showNormal();
            root.isFullscreenState = false;
        } else {
            root.showFullScreen();
            root.isFullscreenState = true;
        }
    }

    GalleryStore {
        id: galleryStore
        activeTab: {
            const init = String(Quickshell.env("II_GALLERY_INITIAL_TAB") ?? "").trim().toLowerCase();
            if (init === "albums" || init === "phone" || init === "settings")
                return init;
            return "home";
        }
        onActiveTabChanged: {
            galleryStore.clearSelection();
            root.triggerPageSlide(galleryStore.activeTab);
            gcTimer.restart();
        }
        onViewerOpenChanged: if (!viewerOpen) gcTimer.restart()
    }

    // Lightweight GPU-only directional slide + fade on tab switches (0 extra RAM)
    property int _lastTabIdx: 0
    readonly property var _tabOrder: ({ home: 0, albums: 1, phone: 2, settings: 3 })

    function triggerPageSlide(tabId): void {
        const nextIdx = root._tabOrder[tabId] ?? 0;
        const dir = nextIdx >= root._lastTabIdx ? 1 : -1;
        root._lastTabIdx = nextIdx;
        pageSlideAnim.stop();
        pageSlideTranslate.x = dir * 28;
        pageSlideHost.opacity = 0.0;
        pageSlideAnim.start();
    }

    ParallelAnimation {
        id: pageSlideAnim
        NumberAnimation {
            target: pageSlideTranslate
            property: "x"
            to: 0
            duration: 220
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageSlideHost
            property: "opacity"
            to: 1.0
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    // Reclaim destroyed Loader subtrees, Image textures, and MediaPlayer buffers promptly
    Timer {
        id: gcTimer
        interval: 280
        repeat: false
        onTriggered: gc()
    }

    PhoneGalleryBridge {
        id: phoneGalleryBridge
        onSendToPhoneFinished: (ok, msg) => galleryStore.showSnack(msg, "", null)
        onSaveToPcFinished: (ok, msg) => galleryStore.showSnack(msg, "", null)
    }

    // Single-instance IPC handler
    IpcHandler {
        target: "gallery"

        function open(tab: string): void {
            const req = String(tab ?? "").trim().toLowerCase();
            if (req === "home" || req === "albums" || req === "phone" || req === "settings") {
                if (galleryStore.viewerOpen)
                    galleryStore.closeViewer();
                galleryStore.activeTab = req;
                if (req === "albums")
                    galleryStore.activeAlbum = "";
            }
            root.raise();
            root.requestActivate();
        }

        function openPath(path: string): void {
            const target = String(path ?? "").trim();
            if (target.length > 0) {
                const hit = galleryStore.items.find(it => it.path === target);
                if (hit) {
                    galleryStore.openLocalViewer(hit.path, galleryStore.items);
                } else {
                    galleryStore.openLocalViewer(target, [{
                        id: target,
                        path: target,
                        file: target.split("/").pop(),
                        title: target.split("/").pop(),
                        ext: target.split(".").pop().toUpperCase(),
                        type: /\.(mp4|mkv|webm|mov|avi|m4v|3gp)$/i.test(target) ? "video" : "photo",
                        root: "",
                        folder: target.split("/").slice(0, -1).join("/"),
                        isSub: false,
                        mtime: Date.now(),
                        size: 0,
                        w: 0,
                        h: 0,
                        dur: 0,
                        thumb: ""
                    }]);
                }
            }
            root.raise();
            root.requestActivate();
        }

        function rescan(): void {
            galleryStore.rescan();
        }

        function quit(): void {
            Qt.quit();
        }
    }

    // Global keyboard shortcut `/` for search, `Esc` for side sheet
    Shortcut {
        sequence: "/"
        enabled: !galleryStore.viewerOpen
        onActivated: appBar.focusSearch()
    }

    Shortcut {
        sequence: "Escape"
        enabled: !galleryStore.viewerOpen && (galleryStore.addSheetOpen || galleryStore.selectionMode)
        onActivated: {
            if (galleryStore.selectionMode)
                galleryStore.clearSelection();
            else
                galleryStore.addSheetOpen = false;
        }
    }

    Item {
        anchors.fill: parent

        // Subtle outer border matching standalone shell apps
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: Appearance.rounding.windowRounding
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            z: 50
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top App Bar
            GalleryAppBar {
                id: appBar
                Layout.fillWidth: true
                store: galleryStore
                phoneBridge: phoneGalleryBridge
                isMaximized: root.isFullscreenState
                onCloseWindowRequested: Qt.quit()
                onToggleMaximizeRequested: root.toggleFullscreenState()
            }

            // Main Body: Page surface + Clock-style smooth sliding Add-Folder side sheet
            RowLayout {
                id: bodyRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 12
                spacing: 0

                // Settled page width (prevents 60fps grid reflow/lag while side sheet slides!)
                readonly property real settledPageWidth: Math.max(400, bodyRow.width - (galleryStore.addSheetOpen ? 364 : 0))

                // Page container (surface layer 1, concentric with windowRounding - 12px margin)
                Rectangle {
                    id: pageContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Math.max(8, Appearance.rounding.windowRounding - 12)
                    color: Appearance.colors.colLayer1
                    clip: true

                    // GPU-only slide host wrapping active page Loaders
                    Item {
                        id: pageSlideHost
                        anchors.fill: parent
                        transform: Translate { id: pageSlideTranslate; x: 0 }

                        // Home Timeline (unloaded when switching to other tabs so tile textures are freed!)
                        Loader {
                            id: homeLoader
                            anchors.fill: parent
                            active: galleryStore.activeTab === "home"
                            visible: active
                            sourceComponent: GalleryHomePage {
                                store: galleryStore
                                layoutWidth: bodyRow.settledPageWidth
                            }
                        }

                        // Albums Page (lazy-loaded only while active to keep RAM low)
                        Loader {
                            id: albumsLoader
                            anchors.fill: parent
                            active: galleryStore.activeTab === "albums"
                            visible: active
                            sourceComponent: GalleryAlbumsPage {
                                store: galleryStore
                                layoutWidth: bodyRow.settledPageWidth
                            }
                        }

                        // Phone Gallery Page (lazy-loaded only while active so polling stops when away)
                        Loader {
                            id: phoneLoader
                            anchors.fill: parent
                            active: galleryStore.activeTab === "phone"
                            visible: active
                            sourceComponent: GalleryPhonePage {
                                store: galleryStore
                                phoneBridge: phoneGalleryBridge
                            }
                        }

                        // Settings Page (lazy-loaded on demand)
                        Loader {
                            id: settingsLoader
                            anchors.fill: parent
                            active: galleryStore.activeTab === "settings"
                            visible: active
                            sourceComponent: GallerySettingsPage {
                                store: galleryStore
                            }
                        }
                    }

                    // Extended FAB (unfolds label on hover; visible on Home & Albums when not selecting)
                    Rectangle {
                        id: fabBtn
                        visible: (galleryStore.activeTab === "home" || galleryStore.activeTab === "albums") && !galleryStore.selectionMode
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.rightMargin: 24
                        anchors.bottomMargin: 22
                        z: 10
                        height: 60
                        width: fabMouse.containsMouse ? (fabLabel.implicitWidth + 78) : 60
                        radius: 20
                        color: fabMouse.containsMouse
                            ? Appearance.colors.colPrimaryContainerHover
                            : Appearance.colors.colPrimaryContainer
                        clip: true

                        Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            StyledText {
                                id: fabLabel
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: 18
                                text: Translation.tr("Add folder")
                                font.pixelSize: 15
                                font.variableAxes: ({ "wght": 650, "wdth": 108, "ROND": 100 })
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: fabMouse.containsMouse ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                            }

                            Item {
                                width: 60
                                height: 60
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "create_new_folder"
                                    iconSize: 26
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                        }

                        MouseArea {
                            id: fabMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: galleryStore.addSheetOpen = !galleryStore.addSheetOpen
                        }
                    }

                    // Floating bottom navbar (hidden smoothly when multi-selection bar is active)
                    GalleryNavBar {
                        visible: !galleryStore.selectionMode
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20
                        z: 10
                        activeTab: galleryStore.activeTab
                        todayCount: galleryStore.todayCount
                        phoneConnected: phoneGalleryBridge.connected
                        onTabSelected: tabId => {
                            if (tabId === galleryStore.activeTab && tabId === "albums" && galleryStore.activeAlbum !== "") {
                                galleryStore.activeAlbum = "";
                                return;
                            }
                            galleryStore.addSheetOpen = false;
                            galleryStore.activeTab = tabId;
                        }
                    }

                    // Floating multi-selection action bar (lazy-loaded only while selecting)
                    Loader {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 20
                        z: 12
                        active: galleryStore.selectionMode
                        visible: active
                        sourceComponent: GallerySelectionBar {
                            store: galleryStore
                            phoneBridge: phoneGalleryBridge
                        }
                    }
                }

                // Clock-style clipping slot: inner sheet keeps fixed 352px width pinned right (zero reflow!)
                Item {
                    id: addSheetDrawer
                    Layout.fillHeight: true
                    Layout.preferredWidth: galleryStore.addSheetOpen ? 364 : 0
                    clip: true
                    visible: Layout.preferredWidth > 1

                    Behavior on Layout.preferredWidth {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }

                    Loader {
                        id: addSheetLoader
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        width: 352
                        active: addSheetDrawer.Layout.preferredWidth > 1
                        sourceComponent: GalleryAddFolderSheet {
                            store: galleryStore
                            onCloseRequested: galleryStore.addSheetOpen = false
                        }
                    }
                }
            }
        }

        // Fullscreen Media Viewer overlay (lazy-loaded only while open -> 0 RAM when closed!)
        Loader {
            id: viewerLoader
            anchors.fill: parent
            z: 40
            active: galleryStore.viewerOpen
            visible: active
            sourceComponent: GalleryViewer {
                store: galleryStore
                phoneBridge: phoneGalleryBridge
                isFullscreen: root.isFullscreenState
                onToggleFullscreenRequested: root.toggleFullscreenState()
            }
        }

        // M3 Inverse-Surface Snackbar
        Rectangle {
            visible: galleryStore.snackVisible
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: galleryStore.viewerOpen ? 92 : 96
            z: 60
            implicitWidth: Math.min(root.width - 48, snackRow.implicitWidth + 28)
            implicitHeight: 48
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3inverseSurface

            RowLayout {
                id: snackRow
                anchors.centerIn: parent
                spacing: 14

                StyledText {
                    text: galleryStore.snackText
                    font.pixelSize: 14
                    color: Appearance.m3colors.m3inverseOnSurface
                    elide: Text.ElideRight
                    Layout.maximumWidth: root.width - 160
                }

                RippleButton {
                    visible: galleryStore.snackActionLabel.length > 0
                    implicitHeight: 34
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: 17
                    colBackground: "transparent"
                    colBackgroundHover: Qt.rgba(0, 0, 0, 0.08)
                    onClicked: galleryStore.triggerSnackAction()
                    contentItem: StyledText {
                        anchors.centerIn: parent
                        text: galleryStore.snackActionLabel
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        color: Appearance.m3colors.m3inversePrimary
                    }
                }
            }
        }
    }
}
