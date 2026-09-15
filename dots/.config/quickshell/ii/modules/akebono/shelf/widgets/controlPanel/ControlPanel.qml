import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.lunae.widgets

import qs.modules.common.quickToggleDialogs.darkMode
import qs.modules.common.quickToggleDialogs.localSend
import qs.modules.common.quickToggleDialogs.vpn
import qs.modules.common.quickToggleDialogs.tailscale
import qs.modules.common.quickToggleDialogs.dnsOverTls
import qs.modules.common.quickToggleDialogs.idleInhibitor
import qs.modules.common.quickToggleDialogs.screenShader
import qs.modules.ii.sidebarDashboard.modes

Item {
    id: root
    property var shelf: null
    signal closeRequested()

    readonly property real mainW: shelf?.qsBaseW ?? 360
    // Inset for the panel body. The popup (qsR 32) rounds its rim more than the
    // window rounding alone suggests, so reserve real space: everything left- or
    // right-aligned (header pfp, notification row, session button, edit-mode
    // tiles) stays clear of the rounded edge on BOTH sides of the one body,
    // mirroring the clearance the quick-toggle grid already gets on its right.
    readonly property real edgePad: Math.max(14, Math.round(Math.max(0, Appearance.rounding.windowRounding) * 0.55))
    readonly property real dialogW: shelf?.qsDialogW ?? 300
    readonly property bool dialogOnLeft: shelf?.qsGrowLeft ?? false
    property string activeDialog: ""
    property bool editMode: false

    // Quick-toggle style for this control centre. It is owned by the Akebono
    // shelf ("abstract" = this control centre) and decoupled from the sidebar,
    // so flipping it never touches the main shell's quick toggles.
    readonly property string style: Config.options.akebono.shelf.quickSettings.style
    readonly property bool hasSharedPanel: root.style === "classic" || root.style === "android"

    // State owned by the shared-panel dialogues that the aqebono registry has no
    // entry for; the rest are routed through the push-out DialogPane instead.
    property bool showDarkModeDialog: false
    property bool showLocalSendDialog: false
    property bool showVpnDialog: false
    property bool showTailscaleDialog: false
    property bool showDnsOverTlsDialog: false
    property bool showIdleInhibitorDialog: false
    property bool showScreenShaderDialog: false
    property bool showModesDialog: false

    readonly property EntryRegistry registry: EntryRegistry {}
    readonly property var allToggleTypes: root.registry.toggleIds
    readonly property var enabledToggles: Config.options.akebono.shelf.quickSettings.toggles
    readonly property bool flickMode: Config.options.akebono.shelf.quickSettings.flickable
    readonly property var brightnessMonitor: Brightness.getMonitorForScreen(QsWindow.window?.screen)

    function hasDialog(type) {
        return root.registry.hasDetail(type);
    }

    onActiveDialogChanged: {
        if (root.shelf) root.shelf.qsDialogOpen = root.activeDialog !== "";
        if (root.activeDialog === "notifications") {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }
    onEditModeChanged: if (root.editMode) root.activeDialog = ""

    Connections {
        target: Notifications
        enabled: root.activeDialog === "notifications"
        function onUnreadChanged() {
            if (Notifications.unread > 0) {
                Notifications.timeoutAll();
                Notifications.markAllRead();
            }
        }
    }

    Binding {
        target: root.shelf
        property: "qsContentH"
        value: mainCol.implicitHeight + 36
        when: root.shelf !== null
    }

    Connections {
        target: root.shelf
        function onQsOpenChanged() {
            if (!root.shelf.qsOpen) {
                root.activeDialog = "";
                root.editMode = false;
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
    }

    Flickable {
        id: docScroll
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.topMargin: root.edgePad
        anchors.bottomMargin: root.edgePad
        anchors.left: root.dialogOnLeft ? undefined : parent.left
        anchors.leftMargin: root.edgePad
        anchors.right: root.dialogOnLeft ? parent.right : undefined
        anchors.rightMargin: root.edgePad
        width: root.mainW - root.edgePad * 2
        contentWidth: docScroll.width
        contentHeight: mainCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: mainCol
            width: docScroll.width
            spacing: 12

            Header { panel: root }

            TogglesSection {
                panel: root
                Layout.fillWidth: true
            }

            Card {
                Layout.fillWidth: true
                visible: !root.editMode && !root.hasSharedPanel

                SidebarSlider {
                    Layout.fillWidth: true
                    icon: "volume_up"
                    value: Audio.sink?.audio?.volume ?? 0
                    onMoved: if (Audio.sink?.audio) Audio.sink.audio.volume = value
                }
                SidebarSlider {
                    Layout.fillWidth: true
                    icon: "brightness_6"
                    value: root.brightnessMonitor?.brightness ?? 0
                    onMoved: root.brightnessMonitor?.setBrightness(value)
                }
            }

            NotificationRow {
                panel: root
                Layout.fillWidth: true
                visible: !root.editMode
            }
        }
    }

    Rectangle {
        anchors.left: root.dialogOnLeft ? dialogPane.right : undefined
        anchors.leftMargin: 9
        anchors.right: root.dialogOnLeft ? undefined : dialogPane.left
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: parent.height - 64
        color: Appearance.colors.colOnLayer0
        opacity: dialogPane.opacity * 0.14
        visible: dialogPane.visible
    }

    DialogPane {
        id: dialogPane
        panel: root
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: root.dialogOnLeft ? parent.left : docScroll.right
        anchors.leftMargin: 16
        anchors.right: root.dialogOnLeft ? docScroll.left : parent.right
        anchors.rightMargin: 16
        clip: true
    }

    // Shared-panel dialogues (classic / android styles) host as a push-out pane,
    // matching the aqebono popup pattern.
    DialogHostLoader {
        id: sharedDialog
        owner: root
        shownPropertyString: "showDarkModeDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: DarkModeDialog {}
    }
    DialogHostLoader {
        id: sharedDialog7
        owner: root
        shownPropertyString: "showLocalSendDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: LocalSendDialog {}
    }
    DialogHostLoader {
        id: sharedDialog8
        owner: root
        shownPropertyString: "showVpnDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: VpnDialog {}
    }
    DialogHostLoader {
        id: sharedDialog9
        owner: root
        shownPropertyString: "showTailscaleDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: TailscaleDialog {}
    }
    DialogHostLoader {
        id: sharedDialog10
        owner: root
        shownPropertyString: "showDnsOverTlsDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: DnsOverTlsDialog {}
    }
    DialogHostLoader {
        id: sharedDialog11
        owner: root
        shownPropertyString: "showIdleInhibitorDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: IdleInhibitorDialog {}
    }
    DialogHostLoader {
        id: sharedDialog12
        owner: root
        shownPropertyString: "showScreenShaderDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: ScreenShaderDialog {}
    }
    DialogHostLoader {
        id: sharedDialog13
        owner: root
        shownPropertyString: "showModesDialog"
        dialogRadius: Appearance.rounding.windowRounding
        dialog: ModesDialog {}
    }
}
