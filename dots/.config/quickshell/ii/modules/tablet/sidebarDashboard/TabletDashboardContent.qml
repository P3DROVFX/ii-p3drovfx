import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

import qs.modules.common.quickToggles
import qs.modules.common.notifications
import qs.modules.common.quickToggleDialogs.bluetoothDevices
import qs.modules.common.quickToggleDialogs.nightLight
import qs.modules.common.quickToggleDialogs.volumeMixer
import qs.modules.common.quickToggleDialogs.wifiNetworks
import qs.modules.common.quickToggleDialogs.darkMode
import qs.modules.common.quickToggleDialogs.localSend
import qs.modules.common.quickToggleDialogs.vpn
import qs.modules.common.quickToggleDialogs.tailscale
import qs.modules.common.quickToggleDialogs.dnsOverTls
import qs.modules.common.quickToggleDialogs.idleInhibitor
import qs.modules.common.quickToggleDialogs.screenShader

/**
 * Landscape shade contents, laid out like Android's: one status line across the top, quick
 * toggles and the system actions on the left, notifications on the right.
 *
 * Everything is sized off the screen height rather than fixed pixels, so the same layout is
 * usable with a finger on a small tablet and on a large scaled display.
 */
Item {
    id: root

    signal dismissRequested

    // ── Touch metrics ───────────────────────────────────────────────────────
    // One grid cell is the unit the whole shade is built from. The clamps keep tiles
    // thumb-sized on a short screen without letting them balloon on a tall one.
    readonly property real touchCellHeight: Math.max(64, Math.min(116, Math.round(root.height * 0.088)))
    readonly property real gridSpacing: Math.max(6, Math.round(root.touchCellHeight * 0.12))
    readonly property real actionRowHeight: Math.max(50, Math.min(68, Math.round(root.height * 0.055)))
    readonly property real headerHeight: Math.max(44, Math.min(68, Math.round(root.height * 0.05)))
    readonly property real outerMargin: Math.max(16, Math.min(32, Math.round(root.height * 0.022)))
    // The ii dialogs are sized for a 460px sidebar; here they float over the whole screen.
    readonly property real dialogWidth: Math.max(560, Math.min(980, Math.round(root.width * 0.38)))

    // The calendar / to-do / timer group is deliberately absent. It used to be wired up
    // behind a `false` switch, which cost the tablet an import of ii's sidebar module for
    // code that never ran. Those widgets return as tiles in the quick-toggles grid (Fase 3),
    // which is a different construction, not this Loader revived. Notifications take the space.

    // ── Dialog state ────────────────────────────────────────────────────────
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
    property bool showTrayDialog: false
    readonly property bool anyDialogVisible: showAudioOutputDialog || showAudioInputDialog || showBluetoothDialog || showNightLightDialog || showWifiDialog || showDarkModeDialog || showLocalSendDialog || showVpnDialog || showTailscaleDialog || showDnsOverTlsDialog || showIdleInhibitorDialog || showScreenShaderDialog || showTrayDialog

    property bool editMode: false

    // Content reveal rides the drag instead of the ii sidebar's entrance animations, which
    // only started once the finger was released. Sections slide down from the top edge and
    // grow a touch as the sheet comes out; it finishes before the sheet does so the shade is
    // fully readable while it is still moving.
    readonly property real revealProgress: {
        const t = Math.max(0, Math.min(1, (TabletDashboardGestureController.progress - 0.02) / 0.45));
        return 1 - Math.pow(1 - t, 3);
    }

    function sectionReveal(delay) {
        const span = Math.max(0.001, 1 - delay);
        return Math.max(0, Math.min(1, (root.revealProgress - delay) / span));
    }

    function closeAllDialogs() {
        root.showWifiDialog = false;
        root.showBluetoothDialog = false;
        root.showAudioOutputDialog = false;
        root.showAudioInputDialog = false;
        root.showNightLightDialog = false;
        root.showDarkModeDialog = false;
        root.showLocalSendDialog = false;
        root.showVpnDialog = false;
        root.showTailscaleDialog = false;
        root.showDnsOverTlsDialog = false;
        root.showIdleInhibitorDialog = false;
        root.showScreenShaderDialog = false;
        root.showTrayDialog = false;
    }

    Connections {
        target: TabletDashboardGestureController
        function onProgressChanged() {
            if (TabletDashboardGestureController.progress <= 0.05)
                root.closeAllDialogs();
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

    // ── MAIN CONTENT ────────────────────────────────────────────────────────
    Item {
        id: contentContainer
        anchors {
            fill: parent
            margins: root.outerMargin
        }

        property real dialogBlurProgress: root.anyDialogVisible ? 1.0 : 0.0
        Behavior on dialogBlurProgress {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            id: shadeLayout
            anchors.fill: parent
            spacing: root.outerMargin

            layer.enabled: contentContainer.dialogBlurProgress > 0.01
            layer.effect: MultiEffect {
                blurEnabled: true
                blurMax: 32
                blur: contentContainer.dialogBlurProgress
            }

            // ── STATUS LINE ─────────────────────────────────────────────────
            TabletStatusHeader {
                id: statusHeader
                Layout.fillWidth: true
                Layout.preferredHeight: root.headerHeight
                barHeight: root.headerHeight

                readonly property real reveal: root.sectionReveal(0)
                opacity: reveal
                transform: Translate {
                    y: -(1 - statusHeader.reveal) * root.headerHeight * 0.4
                }
            }

            // ── TWO COLUMNS ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.outerMargin

                // ── LEFT: quick toggles + system actions ────────────────────
                ColumnLayout {
                    id: leftColumn
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: root.outerMargin

                    // Touch-sized tiles plus the edit-mode drawer can outgrow the column, so
                    // the grid scrolls instead of spilling over the action row. The panel's own
                    // paging flickable is horizontal only, so the two axes don't fight.
                    StyledFlickable {
                        id: quickTogglesScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: quickTogglesColumn.implicitHeight
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.StopAtBounds

                        readonly property real reveal: root.sectionReveal(0.08)
                        opacity: reveal
                        transform: Translate {
                            y: -(1 - quickTogglesScroll.reveal) * root.touchCellHeight * 0.4
                        }

                        ColumnLayout {
                            id: quickTogglesColumn
                            width: quickTogglesScroll.width
                            spacing: root.outerMargin

                            // No card behind the toggles: on Android the grid sits directly on
                            // the shade background, and a nested surface only eats touch space.
                            LoaderedQuickPanelImplementation {
                                id: classicQuickPanelLoader
                                styleName: "classic"
                                sourceComponent: ClassicQuickPanel {
                                    onOpenVpnDialog: root.showVpnDialog = true
                                    onOpenTailscaleDialog: root.showTailscaleDialog = true
                                }
                            }

                            LoaderedQuickPanelImplementation {
                                id: androidQuickPanelLoader
                                styleName: "android"
                                sourceComponent: AndroidQuickPanel {
                                    revealProgress: root.sectionReveal(0.08)
                                    color: "transparent"
                                    padding: 0
                                    spacing: root.gridSpacing
                                    baseCellHeight: root.touchCellHeight
                                    editMode: root.editMode
                                    onOpenVpnDialog: root.showVpnDialog = true
                                    onOpenTailscaleDialog: root.showTailscaleDialog = true
                                    onOpenDnsOverTlsDialog: root.showDnsOverTlsDialog = true
                                    onOpenScreenShaderDialog: root.showScreenShaderDialog = true
                                }
                            }
                        }
                    }

                    TabletSystemActionRow {
                        id: systemActionRow
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.actionRowHeight
                        rowHeight: root.actionRowHeight
                        editMode: root.editMode

                        readonly property real reveal: root.sectionReveal(0.22)
                        opacity: reveal
                        transform: Translate {
                            y: -(1 - systemActionRow.reveal) * root.actionRowHeight * 0.6
                        }

                        onEditModeToggled: newEditMode => root.editMode = newEditMode
                        onTrayRequested: root.showTrayDialog = true
                        onDismissRequested: root.dismissRequested()
                    }
                }

                // ── RIGHT: notifications ────────────────────────────────────
                ColumnLayout {
                    id: rightColumn
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: root.outerMargin

                    Rectangle {
                        id: notificationsCard
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer1
                        clip: true

                        readonly property real reveal: root.sectionReveal(0.14)
                        opacity: reveal
                        transform: Translate {
                            y: -(1 - notificationsCard.reveal) * root.touchCellHeight * 0.4
                        }

                        NotificationList {
                            anchors.fill: parent
                            anchors.margins: Math.round(root.gridSpacing * 0.8)
                            zoom: 1.12
                            placeholderScale: 1.4
                        }
                    }

                }
            }
        }
    }

    // ── DIALOGS ─────────────────────────────────────────────────────────────
    DialogHostLoader {
        owner: root
        shownPropertyString: "showTrayDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: TabletTrayDialog {
            rowHeight: root.actionRowHeight
            onItemActivated: {
                root.showTrayDialog = false;
                root.dismissRequested();
            }
        }
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showAudioOutputDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: VolumeDialog {
            isSink: true
        }
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showAudioInputDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: VolumeDialog {
            isSink: false
        }
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showBluetoothDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: BluetoothDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showNightLightDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: NightLightDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showWifiDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: WifiDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showDarkModeDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: DarkModeDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showLocalSendDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: LocalSendDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showVpnDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: VpnDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showTailscaleDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
        dialog: TailscaleDialog {}
    }

    DialogHostLoader {
        owner: root
        shownPropertyString: "showDnsOverTlsDialog"
        dialogRadius: Appearance.rounding.normal
        dialogWidth: root.dialogWidth
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
            if (!item)
                return;
            if (item.hasOwnProperty("radius"))
                item.radius = Appearance.rounding.normal;
            if (item.hasOwnProperty("preferredDialogWidth"))
                item.preferredDialogWidth = root.dialogWidth;
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
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.alignment: Qt.AlignTop
        visible: active
        active: Config.options.sidebar.quickToggles.style === styleName
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
        }
    }
}
