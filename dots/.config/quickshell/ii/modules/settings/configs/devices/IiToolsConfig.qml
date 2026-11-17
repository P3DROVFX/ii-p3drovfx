pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.tablet.setup
import qs.modules.settings.configs.colors

/**
 * Settings → Devices & Phone → ii tools:
 * Google Material 3 Expressive subpage with MultiEffect-clipped hero, Flow-sized
 * ColorsFeatureTile grids, DND sync, deck commands, and live diagnostics.
 */
Item {
    id: root
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack()
    property alias contentY: page.contentY
    property bool notifAppsExpanded: false
    /// Linking without the phone: "" | "show" | "enter", and the PC picked to enter a code for.
    property string pcCodeMode: ""
    property var pcCodeTarget: null
    property string notifAppsQuery: ""

    readonly property bool isSelected: KdeConnectService.activePhoneService === "iiTools"
    readonly property var moduleFlags: {
        const o = Config.options.iiTools;
        return [
            o.remote.enable, o.audio.enable, o.liveUpdates.enable, o.pcLive.enable,
            o.media.enable, o.pcMedia.enable, o.files.enable, o.gallery.enable, o.camera.enable, o.mic.enable, o.touchpad.enable, o.draw.enable, o.present.enable, o.screen.enable,
            o.perf.enable, o.phoneData.enable, o.calendar.enable, o.screenshots.enable, o.clipboard.enable,
            o.share.enable, o.notifications.enable, o.calls.enable, o.callAudio.enable, o.wallpaper.enable, o.look.enable,
            o.deck.enable, o.wol.enable, o.tailscale.enable
        ];
    }
    readonly property int enabledModuleCount: moduleFlags.filter(Boolean).length

    Component.onCompleted: {
        if (!IiLinkService.probed)
            IiLinkService.checkBinary();
        if (Config.options.iiTools.camera.enable && !Config.options.iiTools.camera.useDroidcam && !IiCameraService._depsChecked)
            IiCameraService.refresh();
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        ConfigSubPageHeader {
            visible: root.showBackButton
            title: Translation.tr("ii tools")
            onBack: root.goBack()
        }

        // ── Expressive Hero (MultiEffect-clipped, high-contrast surface) ─
        Item {
            id: hero
            Layout.fillWidth: true
            Layout.bottomMargin: 6
            implicitHeight: heroCol.implicitHeight + 44

            Rectangle {
                id: heroMask
                width: heroSurface.width
                height: heroSurface.height
                radius: Appearance.rounding.verylarge
                visible: false
                layer.enabled: true
            }

            Item {
                id: heroSurface
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: heroMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Rectangle {
                    anchors.fill: parent
                    color: Appearance.colors.colLayer1
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.isSelected
                    color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
                }

                MaterialShape {
                    implicitSize: hero.height * 1.45
                    x: hero.width - implicitSize * 0.45
                    y: hero.height - implicitSize * 0.58
                    shape: IiLinkService.phoneConnected
                        ? MaterialShape.Shape.Cookie7Sided
                        : MaterialShape.Shape.SoftBurst
                    color: Appearance.colors.colPrimary
                    opacity: 0.07
                }
            }

            ColumnLayout {
                id: heroCol
                anchors.fill: parent
                anchors.margins: 22
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    MaterialShapeWrappedMaterialSymbol {
                        shape: IiLinkService.phoneConnected
                            ? MaterialShape.Shape.Cookie7Sided
                            : (root.isSelected ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Circle)
                        implicitSize: 54
                        padding: 8
                        iconSize: 24
                        text: IiLinkService.phoneConnected ? "phonelink" : "smartphone"
                        fill: root.isSelected ? 1 : 0
                        color: root.isSelected
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colLayer2
                        colSymbol: root.isSelected
                            ? Appearance.colors.colOnPrimary
                            : Appearance.colors.colOnLayer2
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            StyledText {
                                text: Translation.tr("COMPANION BRIDGE")
                                font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                font.variableAxes: ({ "wght": 800, "wdth": 115, "ROND": 0 })
                                font.letterSpacing: 1.5
                                color: root.isSelected
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }

                            Rectangle {
                                implicitWidth: appBadgeText.implicitWidth + 16
                                implicitHeight: 22
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSecondaryContainer

                                StyledText {
                                    id: appBadgeText
                                    anchors.centerIn: parent
                                    text: Translation.tr("Android app · v1.0 out now")
                                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnSecondaryContainer
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/P3DROVFX/ii-tools/releases/latest")
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Translation.tr("ii tools")
                            font.pixelSize: 26
                            font.variableAxes: ({ "wght": 800, "wdth": 110, "ROND": 0 })
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    StyledSwitch {
                        checked: root.isSelected
                        onToggled: value => KdeConnectService.selectPhoneService(value ? "iiTools" : "off")
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: {
                        if (KdeConnectService.activePhoneService === "kdeconnect")
                            return Translation.tr("Standby while KDE Connect is selected. Toggle on to switch active phone integration to ii tools.");
                        if (!root.isSelected)
                            return Translation.tr("Off. Toggle on to activate the companion bridge for your phone.");
                        if (IiLinkService.phoneConnected)
                            return Translation.tr("Connected to %1").arg(IiLinkService.connectedList.map(c => c.name || c.model).join(", "));
                        if (IiLinkService.hasPeers)
                            return Translation.tr("Paired · listening for your phone on LAN or Tailscale.");
                        return Translation.tr("Encrypted local TLS bridge for live updates, remote control, clipboard, media, and calls.");
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    HeroPill {
                        symbol: IiLinkService.phoneConnected ? "check_circle" : (root.isSelected ? "sensors" : "sync_disabled")
                        label: IiLinkService.phoneConnected
                            ? Translation.tr("Connected")
                            : (root.isSelected ? Translation.tr("Active · Standby") : Translation.tr("Standby"))
                        primaryStyle: IiLinkService.phoneConnected
                        secondaryStyle: !IiLinkService.phoneConnected && root.isSelected
                    }

                    HeroPill {
                        symbol: "widgets"
                        label: Translation.tr("%1 / %2 modules").arg(root.enabledModuleCount).arg(root.moduleFlags.length)
                    }

                    HeroPill {
                        visible: IiLinkService.phoneConnected && (IiLinkService.phoneStatus?.battery?.level ?? -1) >= 0
                        symbol: IiLinkService.phoneStatus?.battery?.charging ? "battery_charging_full" : "battery_5_bar"
                        label: `${IiLinkService.phoneStatus?.battery?.level ?? 0}%`
                        secondaryStyle: true
                    }

                    Repeater {
                        model: IiLinkService.phoneConnected ? (IiLinkService.phoneStatus?.peripherals ?? []) : []
                        delegate: HeroPill {
                            required property var modelData
                            symbol: IiLinkService.peripheralIcon(modelData.kind)
                            label: modelData.level >= 0 ? `${modelData.name} · ${modelData.level}%` : modelData.name
                            secondaryStyle: true
                        }
                    }

                    HeroPill {
                        visible: IiLinkService.running && stats.text !== "—"
                        symbol: "memory"
                        label: stats.text
                    }
                }
            }
        }

        // ── Phone pairing & devices ─────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 4
            symbol: "smartphone"
            title: Translation.tr("Paired phones")
            description: Translation.tr("Manage the local link helper binary and pair an Android device over LAN.")

            HelperCard {
                Layout.fillWidth: true
            }

            PairBanner {
                Layout.fillWidth: true
            }

            // A firewall that drops the link's port makes the phone say only "can't reach
            // the PC". Checked when this page opens and when pairing starts, never in the
            // background: firewalld answers without root; ufw does not, so it gets a hint.
            Process {
                id: firewallCheck
                property string verdict: ""
                command: ["sh", "-c", `p=${IiLinkService.port}
if systemctl is-active -q firewalld; then
  firewall-cmd --state >/dev/null 2>&1 || { echo unknown; exit; }
  for z in $(firewall-cmd --get-active-zones 2>/dev/null | grep -v '^ ' | sed 's/ (.*//'); do
    [ "$z" = trusted ] && continue
    firewall-cmd --zone="$z" --query-port=$p/tcp >/dev/null 2>&1 || { echo "firewalld $z"; exit; }
  done
  echo ok
elif systemctl is-active -q ufw; then
  ufw status 2>/dev/null | grep -q "^$p" && echo ok || echo ufw
else
  echo ok
fi`]
                stdout: StdioCollector {
                    onStreamFinished: firewallCheck.verdict = text.trim()
                }
                Component.onCompleted: running = true
            }
            Connections {
                target: IiLinkService
                function onPairingRequestedChanged() {
                    if (IiLinkService.pairingRequested && !firewallCheck.running)
                        firewallCheck.running = true;
                }
            }

            AppSettingRow {
                Layout.fillWidth: true
                readonly property string zone: firewallCheck.verdict.startsWith("firewalld ") ? firewallCheck.verdict.slice(10) : ""
                readonly property string fix: firewallCheck.verdict === "ufw"
                    ? `sudo ufw allow ${IiLinkService.port}/tcp && sudo ufw allow ${IiLinkService.port}/udp`
                    : `sudo firewall-cmd --permanent --zone=${zone} --add-port=${IiLinkService.port}/tcp --add-port=${IiLinkService.port}/udp && sudo firewall-cmd --reload`
                visible: firewallCheck.verdict === "ufw" || zone !== ""
                symbol: "shield"
                title: firewallCheck.verdict === "ufw"
                    ? Translation.tr("ufw may block the phone")
                    : Translation.tr("The firewall blocks the phone")
                description: (firewallCheck.verdict === "ufw"
                    ? Translation.tr("ufw is on and its rules need root to read. Unless port %1 is allowed, the phone only says it can't reach the PC. Tap to copy:").arg(IiLinkService.port)
                    : Translation.tr("firewalld's %1 zone doesn't allow port %2, so the phone can't reach the PC. Tap to copy:").arg(zone).arg(IiLinkService.port))
                    + "\n" + fix
                clickable: true
                onClicked: {
                    Quickshell.clipboardText = fix;
                    firewallCheck.running = true;
                }
            }

            PairingPanel {
                Layout.fillWidth: true
                visible: IiLinkService.pairingRequested || IiLinkService.pairing !== null
            }

            // Conditional inline paired / error feedback pills
            Rectangle {
                Layout.fillWidth: true
                visible: IiLinkService.lastPaired !== null && !IiLinkService.pairingRequested
                implicitHeight: pairedMsgRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer

                RowLayout {
                    id: pairedMsgRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    MaterialSymbol {
                        text: "check_circle"
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                        text: Translation.tr("Paired with %1.").arg(IiLinkService.lastPaired?.name ?? "")
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: IiLinkService.lastError !== ""
                implicitHeight: linkErrRow.implicitHeight + 16
                radius: Appearance.rounding.normal
                color: Appearance.colors.colErrorContainer

                RowLayout {
                    id: linkErrRow
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 8

                    MaterialSymbol {
                        text: "error"
                        iconSize: 18
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnErrorContainer
                        text: IiLinkService.lastError
                    }
                }
            }

        }

        // ── Featured Stream Deck & Commands workspace ───────────────────
        DeckCommandsSection {
            Layout.fillWidth: true
            Layout.topMargin: 6
        }

        // ── Sync integrations (6 tiles via explicit-height Flow) ────────
        AppSettingsSection {
            Layout.topMargin: 6
            symbol: "sync"
            title: Translation.tr("Phone sync")
            description: Translation.tr("Live updates, notifications, calls and their audio, battery status, and screenshots.")

            Item {
                id: syncTilesBox
                Layout.fillWidth: true
                implicitHeight: syncFlow.implicitHeight
                readonly property int gap: 12
                readonly property int columns: width >= 3 * 220 + 2 * gap ? 3 : (width >= 2 * 210 + gap ? 2 : 1)
                readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)

                Flow {
                    id: syncFlow
                    width: parent.width
                    spacing: syncTilesBox.gap

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "notifications_active"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Live updates")
                        summary: Translation.tr("Ongoing deliveries, rides, and timers on desktop")
                        checked: Config.options.iiTools.liveUpdates.enable
                        onToggled: value => Config.options.iiTools.liveUpdates.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "timer"
                        shapeOn: MaterialShape.Shape.Sunny
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("PC live updates")
                        summary: Translation.tr("Show timers, alarms, and recording status on phone")
                        checked: Config.options.iiTools.pcLive.enable
                        onToggled: value => Config.options.iiTools.pcLive.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "notifications"
                        shapeOn: MaterialShape.Shape.Flower
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Notifications")
                        summary: Translation.tr("Phone alerts with images, actions, and inline reply")
                        checked: Config.options.iiTools.notifications.enable
                        onToggled: value => Config.options.iiTools.notifications.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "call"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Calls")
                        summary: Translation.tr("Answer, decline, and dial without needing ADB")
                        checked: Config.options.iiTools.calls.enable
                        onToggled: value => Config.options.iiTools.calls.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "headset_mic"
                        shapeOn: MaterialShape.Shape.Cookie9Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Call audio on PC")
                        summary: Translation.tr("Talk through this PC: it becomes the phone's headset for the call")
                        checked: Config.options.iiTools.callAudio.enable
                        onToggled: value => Config.options.iiTools.callAudio.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "contacts"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone data")
                        summary: Translation.tr("Next alarm, contacts, battery, and signal telemetry")
                        checked: Config.options.iiTools.phoneData.enable
                        onToggled: value => Config.options.iiTools.phoneData.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "event_available"
                        shapeOn: MaterialShape.Shape.Clover8Leaf
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone calendar")
                        summary: Translation.tr("Google, Samsung and Outlook events in the Timetable")
                        checked: Config.options.iiTools.calendar.enable
                        onToggled: value => Config.options.iiTools.calendar.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "screenshot_region"
                        shapeOn: MaterialShape.Shape.Pill
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Screenshots")
                        summary: Translation.tr("Exchange captures between phone gallery and desktop")
                        checked: Config.options.iiTools.screenshots.enable
                        onToggled: value => Config.options.iiTools.screenshots.enable = value
                    }

                    ColorsFeatureTile {
                        width: syncTilesBox.tileWidth
                        height: 152
                        symbol: "smartphone"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone screen time")
                        summary: Translation.tr("Include phone app usage and last-used bedtime in App usage")
                        checked: Config.options.iiTools.usage.enable
                        onToggled: value => Config.options.iiTools.usage.enable = value
                    }
                }
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.callAudio.enable
                symbol: "phone_in_talk"
                title: Translation.tr("Calls on this PC automatically")
                description: Translation.tr("While the phone is connected, every call talks through this PC; move it back from the call card")
                checked: Config.options.iiTools.callAudio.auto
                onToggled: value => Config.options.iiTools.callAudio.auto = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                symbol: "pause_circle"
                title: Translation.tr("Pause media during calls")
                description: Translation.tr("Pause playing PC media while a call rings or is active, and resume it when the call ends")
                help: Translation.tr("Only players paused by this feature are resumed, and only if they are still paused when the call ends. Works with both ii tools and the ADB fallback.")
                checked: Config.options.iiTools.calls.pauseMedia
                onToggled: value => Config.options.iiTools.calls.pauseMedia = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                symbol: "wallpaper"
                title: Translation.tr("Share the wallpaper with the phone")
                description: Translation.tr("A phone that turns \"Use the PC's wallpaper\" on gets this wallpaper as its home and lock screen, and each new one after it")
                help: Translation.tr("Off, the PC never sends it. Material You on the phone draws its colours from the same picture, so both end up close, though Android and the shell pick their accents separately.")
                checked: Config.options.iiTools.wallSync.enable
                onToggled: value => Config.options.iiTools.wallSync.enable = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.pcMedia.enable
                symbol: "smartphone"
                title: Translation.tr("Continue on the phone when locking")
                description: Translation.tr("Locking the PC while a web page plays (YouTube, Twitch…) offers to continue it on the phone at the same point")
                help: Translation.tr("A notification on the phone opens the page and pauses the PC's player. The phone's media card also has a Continue on phone button whenever the player has a web page.")
                checked: Config.options.iiTools.handoff.onLock
                onToggled: value => Config.options.iiTools.handoff.onLock = value
            }

            // Call audio needs the phone paired over Bluetooth, which ii tools cannot do.
            AppSettingRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.callAudio.enable && IiLinkService.hasPeers && PhoneCallService.phoneBluetooth === null
                symbol: "bluetooth_searching"
                title: Translation.tr("Pair the phone over Bluetooth for call audio")
                description: Translation.tr("Pair \"%1\" with this PC in Bluetooth settings; ii tools connects it only during calls.").arg(IiLinkService.peers[0]?.name ?? "")
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.screenshots.enable
                symbol: "send_to_mobile"
                title: Translation.tr("Send PC screenshots automatically")
                description: IiLinkService.phoneTakesShots
                    ? Translation.tr("Off: keep manual \"Save to phone\" button in the screenshot preview")
                    : Translation.tr("The phone takes them only with \"Receive the PC's screenshots\" on in ii tools (off by default)")
                checked: Config.options.iiTools.screenshots.autoToPhone
                onToggled: value => Config.options.iiTools.screenshots.autoToPhone = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.notifications.enable
                symbol: "password"
                title: Translation.tr("Verification codes")
                description: Translation.tr("A code in a phone notification (SMS or app) is copied here and shown in a popup with Copy")
                help: Translation.tr("The copy stays out of the clipboard history and is cleared after a minute if it is still there. Works under Do Not Disturb; only the popup is held back.")
                checked: Config.options.iiTools.otp.enable
                onToggled: value => Config.options.iiTools.otp.enable = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.notifications.enable && Config.options.iiTools.otp.enable
                symbol: "content_copy"
                title: Translation.tr("Copy codes automatically")
                description: Translation.tr("Off: the popup only offers Copy")
                checked: Config.options.iiTools.otp.autoCopy
                onToggled: value => Config.options.iiTools.otp.autoCopy = value
            }

            AppSettingRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.notifications.enable
                symbol: "apps"
                title: Translation.tr("Notification apps")
                description: {
                    const apps = IiLinkService.notifApps ?? [];
                    const blocked = apps.filter(a => a.blocked).length;
                    if (!IiLinkService.phoneConnected)
                        return Translation.tr("Connect the phone to change which apps mirror");
                    if (apps.length === 0)
                        return Translation.tr("No apps seen yet — new notifications will show up here");
                    if (blocked > 0)
                        return Translation.tr("%1 of %2 apps blocked on this PC").arg(blocked).arg(apps.length);
                    return Translation.tr("%1 apps allowed — choose which ones mirror to this PC").arg(apps.length);
                }
                clickable: true
                onClicked: root.notifAppsExpanded = !root.notifAppsExpanded
                control: MaterialSymbol {
                    text: root.notifAppsExpanded ? "expand_less" : "expand_more"
                    iconSize: 22
                    color: Appearance.colors.colSubtext
                }
            }

            AppSettingRow {
                visible: Config.options.iiTools.notifications.enable && root.notifAppsExpanded
                below: Loader {
                    Layout.fillWidth: true
                    active: Config.options.iiTools.notifications.enable && root.notifAppsExpanded
                    sourceComponent: Component {
                        ColumnLayout {
                            id: appsPanel
                            width: parent ? parent.width : 0
                            spacing: 8

                            readonly property var allApps: IiLinkService.notifApps ?? []
                            readonly property string trimmedQuery: root.notifAppsQuery.trim().toLowerCase()
                            readonly property var filteredApps: {
                                if (appsPanel.allApps.length <= 12 || appsPanel.trimmedQuery === "")
                                    return appsPanel.allApps;
                                return appsPanel.allApps.filter(a =>
                                    String(a.name ?? "").toLowerCase().includes(appsPanel.trimmedQuery)
                                    || String(a.pkg ?? "").toLowerCase().includes(appsPanel.trimmedQuery)
                                );
                            }

                            StyledText {
                                visible: !IiLinkService.phoneConnected
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("Phone is not connected. Showing the last synced list — switches are disabled.")
                            }

                            MaterialTextField {
                                visible: appsPanel.allApps.length > 12
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Search apps")
                                text: root.notifAppsQuery
                                onTextChanged: root.notifAppsQuery = text
                            }

                            StyledText {
                                visible: appsPanel.allApps.length === 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("No apps seen yet — new notifications from the phone will appear here.")
                            }

                            StyledText {
                                visible: appsPanel.allApps.length > 0 && appsPanel.filteredApps.length === 0
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("No matching apps")
                            }

                            ColumnLayout {
                                visible: appsPanel.filteredApps.length > 0
                                Layout.fillWidth: true
                                spacing: 2

                                Repeater {
                                    model: appsPanel.filteredApps
                                    delegate: RippleButton {
                                        id: appRow
                                        required property var modelData

                                        readonly property string pkg: String(modelData.pkg ?? "")
                                        readonly property string appName: String(modelData.name ?? appRow.pkg)
                                        readonly property bool allowed: !Boolean(modelData.blocked)
                                        readonly property string iconPath: IiLinkService.iconFor(appRow.pkg)
                                        property bool _reloadingIcon: false

                                        Layout.fillWidth: true
                                        implicitHeight: Math.max(54, rowLayout.implicitHeight + 16)
                                        enabled: IiLinkService.phoneConnected
                                        opacity: enabled ? 1 : 0.6
                                        colBackground: Appearance.colors.colLayer2
                                        colBackgroundHover: Appearance.colors.colLayer2Hover
                                        colRipple: Appearance.colors.colLayer2Active
                                        useDynamicRadius: true

                                        onClicked: IiLinkService.setNotifBlocked(appRow.pkg, appRow.allowed)

                                        Connections {
                                            target: IiLinkService
                                            function onAppIconReady(readyPkg, path) {
                                                if (readyPkg === appRow.pkg) {
                                                    appRow._reloadingIcon = true;
                                                    Qt.callLater(() => { appRow._reloadingIcon = false; });
                                                }
                                            }
                                        }

                                        contentItem: Item {
                                            anchors.fill: parent

                                            RowLayout {
                                                id: rowLayout
                                                anchors.fill: parent
                                                anchors.leftMargin: 14
                                                anchors.rightMargin: 14
                                                anchors.topMargin: 8
                                                anchors.bottomMargin: 8
                                                spacing: 12

                                                Item {
                                                    Layout.preferredWidth: 32
                                                    Layout.preferredHeight: 32
                                                    Layout.alignment: Qt.AlignVCenter

                                                    Image {
                                                        id: appIconImg
                                                        anchors.fill: parent
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
                                                        mipmap: true
                                                        cache: false
                                                        asynchronous: true
                                                        source: (!appRow._reloadingIcon && appRow.iconPath !== "") ? `file://${appRow.iconPath}` : ""
                                                        visible: status === Image.Ready
                                                    }

                                                    MaterialShapeWrappedMaterialSymbol {
                                                        anchors.fill: parent
                                                        visible: !appIconImg.visible
                                                        shape: MaterialShape.Shape.Circle
                                                        iconSize: 18
                                                        padding: 0
                                                        text: "notifications"
                                                        color: Appearance.colors.colLayer3
                                                        colSymbol: Appearance.colors.colOnLayer2
                                                    }
                                                }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: appRow.appName
                                                    elide: Text.ElideRight
                                                    font.pixelSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colOnLayer2
                                                }

                                                StyledSwitch {
                                                    Layout.alignment: Qt.AlignVCenter
                                                    checked: appRow.allowed
                                                    enabled: false
                                                    down: appRow.isPressed
                                                    isPressed: appRow.isPressed
                                                    opacity: appRow.enabled ? 1 : 0.45
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Phone calendar ──────────────────────────────────────────────
        PhoneCalendarSettings {
            Layout.topMargin: 6
        }

        // ── Control, media & sharing (12 tiles via explicit-height Flow) ─
        AppSettingsSection {
            Layout.topMargin: 6
            symbol: "tune"
            title: Translation.tr("Control, media & sharing")
            description: Translation.tr("Remote input, media transport, shared storage, stream deck, Wake-on-LAN, and access away from home.")

            Item {
                id: controlTilesBox
                Layout.fillWidth: true
                implicitHeight: controlFlow.implicitHeight
                readonly property int gap: 12
                readonly property int columns: width >= 3 * 220 + 2 * gap ? 3 : (width >= 2 * 210 + gap ? 2 : 1)
                readonly property int tileWidth: Math.floor((width - gap * (columns - 1)) / columns)

                Flow {
                    id: controlFlow
                    width: parent.width
                    spacing: controlTilesBox.gap

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "settings_remote"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Remote control")
                        summary: Translation.tr("Lock, workspaces, scratchpad, and presets from phone")
                        checked: Config.options.iiTools.remote.enable
                        onToggled: value => Config.options.iiTools.remote.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "volume_up"
                        shapeOn: MaterialShape.Shape.Sunny
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("PC audio")
                        summary: Translation.tr("Sinks, per-app volume, and EasyEffects presets")
                        checked: Config.options.iiTools.audio.enable
                        onToggled: value => Config.options.iiTools.audio.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "music_note"
                        shapeOn: MaterialShape.Shape.Flower
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone media")
                        summary: Translation.tr("Show phone playback in widgets, island, and lock screen")
                        checked: Config.options.iiTools.media.enable
                        onToggled: value => Config.options.iiTools.media.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "queue_music"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("PC media")
                        summary: Translation.tr("Mirror desktop player controls onto phone lock screen")
                        checked: Config.options.iiTools.pcMedia.enable
                        onToggled: value => Config.options.iiTools.pcMedia.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "folder_open"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone files")
                        summary: Translation.tr("Browse storage over sshfs while connected")
                        checked: Config.options.iiTools.files.enable
                        onToggled: value => Config.options.iiTools.files.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "photo_library"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Gallery")
                        summary: Translation.tr("Browse the phone's photos and videos in the Phone tab")
                        checked: Config.options.iiTools.gallery.enable
                        onToggled: value => Config.options.iiTools.gallery.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "videocam"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone as webcam")
                        summary: Translation.tr("Use the phone's camera as a PC webcam")
                        checked: Config.options.iiTools.camera.enable
                        onToggled: value => Config.options.iiTools.camera.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "mic"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone as microphone")
                        summary: Translation.tr("Use the phone's microphone as a PC microphone")
                        checked: Config.options.iiTools.mic.enable
                        onToggled: value => Config.options.iiTools.mic.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "touch_app"
                        shapeOn: MaterialShape.Shape.Pill
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Touchpad & keyboard")
                        summary: Translation.tr("Phone pointer & text input via /dev/uinput")
                        checked: Config.options.iiTools.touchpad.enable
                        onToggled: value => Config.options.iiTools.touchpad.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "draw"
                        shapeOn: MaterialShape.Shape.Puffy
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Drawing pad")
                        summary: Translation.tr("Draw on the phone, ink appears in live draw on the focused screen")
                        checked: Config.options.iiTools.draw.enable
                        onToggled: value => Config.options.iiTools.draw.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "co_present"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Presenter")
                        summary: Translation.tr("Change slides from the phone and point with an on-screen laser")
                        checked: Config.options.iiTools.present.enable
                        onToggled: value => Config.options.iiTools.present.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "screen_share"
                        shapeOn: MaterialShape.Shape.Sunny
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Phone as a monitor")
                        summary: Translation.tr("Extend or mirror this PC on the phone over USB or Wi-Fi, touch included")
                        checked: Config.options.iiTools.screen.enable
                        onToggled: value => Config.options.iiTools.screen.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "speed"
                        shapeOn: MaterialShape.Shape.Cookie7Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Performance panel")
                        summary: Translation.tr("Stream CPU, GPU, RAM, and FPS while panel is open")
                        checked: Config.options.iiTools.perf.enable
                        onToggled: value => Config.options.iiTools.perf.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "content_paste"
                        shapeOn: MaterialShape.Shape.Sunny
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Clipboard")
                        summary: Translation.tr("Sync copied text and images between PC and phone")
                        checked: Config.options.iiTools.clipboard.enable
                        onToggled: value => Config.options.iiTools.clipboard.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "share"
                        shapeOn: MaterialShape.Shape.Flower
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Send to PC")
                        summary: Translation.tr("Receive links, notes, tasks, and files from share sheet")
                        checked: Config.options.iiTools.share.enable
                        onToggled: value => Config.options.iiTools.share.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "wallpaper"
                        shapeOn: MaterialShape.Shape.Clover4Leaf
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Wallpaper from phone")
                        summary: Translation.tr("Apply images shared via \"Set on PC\"")
                        checked: Config.options.iiTools.wallpaper.enable
                        onToggled: value => Config.options.iiTools.wallpaper.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "imagesmode"
                        shapeOn: MaterialShape.Shape.Cookie9Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Wallpaper on phone")
                        summary: Translation.tr("Show the desktop wallpaper behind the PC card in the app")
                        checked: Config.options.iiTools.look.enable
                        onToggled: value => Config.options.iiTools.look.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "grid_view"
                        shapeOn: MaterialShape.Shape.SoftBurst
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Deck")
                        summary: Translation.tr("Stream deck keys for shell actions, apps, and scripts")
                        checked: Config.options.iiTools.deck.enable
                        onToggled: value => Config.options.iiTools.deck.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "settings_ethernet"
                        shapeOn: MaterialShape.Shape.Pill
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Wake-on-LAN")
                        summary: IiLinkService.wakeTargets.length > 0
                            ? Translation.tr("Advertises %1").arg(IiLinkService.wakeTargets.map(t => `${t.iface}`).join(", "))
                            : Translation.tr("No LAN adapter MAC detected right now")
                        checked: Config.options.iiTools.wol.enable
                        onToggled: value => Config.options.iiTools.wol.enable = value
                    }

                    ColorsFeatureTile {
                        width: controlTilesBox.tileWidth
                        height: 152
                        symbol: "public"
                        shapeOn: MaterialShape.Shape.Cookie9Sided
                        shapeOff: MaterialShape.Shape.Circle
                        title: Translation.tr("Away from home")
                        summary: !Config.options.iiTools.tailscale.enable
                            ? Translation.tr("Reach this PC from the phone on any network, over Tailscale")
                            : !TailscaleService.available
                            ? Translation.tr("Install Tailscale on this PC and log in")
                            : TailscaleService.active
                            ? Translation.tr("Reachable at %1").arg(TailscaleService.dnsName || TailscaleService.tailscaleIp4)
                            : TailscaleService.backendState === "NeedsLogin"
                            ? Translation.tr("Log in to Tailscale on this PC")
                            : Translation.tr("Turn Tailscale on in the dashboard")
                        checked: Config.options.iiTools.tailscale.enable
                        onToggled: value => Config.options.iiTools.tailscale.enable = value
                    }
                }
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.remote.enable
                symbol: "power_settings_new"
                title: Translation.tr("Shut down and restart from phone")
                description: Translation.tr("The Remote page can power off or restart this PC after asking for confirmation")
                checked: Config.options.iiTools.remote.power
                onToggled: value => Config.options.iiTools.remote.power = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.clipboard.enable
                symbol: "history"
                title: Translation.tr("Clipboard history on phone")
                description: Translation.tr("Browse cliphist entries from the phone and pull older text or images (blocked while locked)")
                checked: Config.options.iiTools.clipboard.history
                onToggled: value => Config.options.iiTools.clipboard.history = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.screen.enable
                symbol: "wifi"
                title: Translation.tr("Phone as a monitor over Wi-Fi")
                description: Translation.tr("Without a USB cable, the screen goes over ii link on the local network. USB is still used when plugged in, for the lowest latency")
                checked: Config.options.iiTools.screen.wireless
                onToggled: value => Config.options.iiTools.screen.wireless = value
            }

            // The screen goes over USB when Wi-Fi is off: adb carries it.
            AppSettingRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.screen.enable && !Config.options.iiTools.screen.wireless && !PhoneScreenService.adbPresent
                symbol: "usb"
                title: Translation.tr("Install adb for the phone as a monitor")
                description: Translation.tr("The screen goes over USB through adb (android-tools); turn on USB debugging on the phone.")
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.camera.enable
                symbol: "swap_horiz"
                title: Translation.tr("Use DroidCam instead")
                description: Translation.tr("Fall back to droidcam-cli instead of streaming over ii tools")
                checked: Config.options.iiTools.camera.useDroidcam
                onToggled: value => Config.options.iiTools.camera.useDroidcam = value
            }

            AppToggleRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.mic.enable
                symbol: "swap_horiz"
                title: Translation.tr("Use scrcpy or DroidCam for the microphone")
                description: Translation.tr("Fall back to the old microphone backends instead of streaming over ii tools")
                checked: Config.options.iiTools.mic.useDroidcam
                onToggled: value => Config.options.iiTools.mic.useDroidcam = value
            }

            AppToggleRow {
                visible: Config.options.iiTools.mic.enable && !Config.options.iiTools.mic.useDroidcam
                symbol: "noise_aware"
                title: Translation.tr("Microphone noise suppression")
                description: Translation.tr("The phone reduces background noise before sending the microphone")
                checked: Config.options.phone.microphone.noiseSuppression
                onToggled: value => Config.options.phone.microphone.noiseSuppression = value
            }

            AppToggleRow {
                visible: Config.options.iiTools.mic.enable && !Config.options.iiTools.mic.useDroidcam
                symbol: "record_voice_over"
                title: Translation.tr("Microphone echo cancellation")
                description: Translation.tr("The phone cancels echo, for calls on the speakers")
                checked: Config.options.phone.microphone.echoCancellation
                onToggled: value => Config.options.phone.microphone.echoCancellation = value
            }

            AppToggleRow {
                visible: Config.options.iiTools.mic.enable && !Config.options.iiTools.mic.useDroidcam
                symbol: "trending_up"
                title: Translation.tr("Microphone auto gain")
                description: Translation.tr("The phone evens out the microphone's level")
                checked: Config.options.phone.microphone.autoGainControl
                onToggled: value => Config.options.phone.microphone.autoGainControl = value
            }

            // Where the phone's picture shows up: a loopback device every app lists, or a
            // PipeWire camera that needs no kernel module.
            AppSettingRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.camera.enable && !Config.options.iiTools.camera.useDroidcam
                symbol: "switch_video"
                title: Translation.tr("Webcam output")
                description: IiCameraService.output === "pipewire"
                    ? Translation.tr("PipeWire camera: no kernel module; OBS and apps that read cameras through PipeWire see it")
                    : Translation.tr("Virtual camera device (v4l2loopback): every app sees it; the kernel module must be installed")
            }

            ConfigSelectionArray {
                visible: Config.options.iiTools.camera.enable && !Config.options.iiTools.camera.useDroidcam
                currentValue: Config.options.iiTools.camera.output
                options: [
                    { displayName: Translation.tr("Automatic"), value: "auto", icon: "auto_mode" },
                    { displayName: Translation.tr("Device"), value: "v4l2", icon: "videocam" },
                    { displayName: Translation.tr("PipeWire"), value: "pipewire", icon: "graphic_eq" }
                ]
                onSelected: value => Config.options.iiTools.camera.output = value
            }

            // What each output gives up, so the choice is an informed one.
            NoticeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: Config.options.iiTools.camera.enable && !Config.options.iiTools.camera.useDroidcam
                materialIcon: "info"
                text: Translation.tr("Device: a /dev/video camera that every app lists (browsers, Discord, Zoom, Teams, OBS). Needs the v4l2loopback kernel module, which on some systems must be signed for Secure Boot.\n\n"
                    + "PipeWire: no kernel module and no admin password, but only apps that read cameras through PipeWire see it: GNOME Snapshot, OBS (\"Video Capture Device (PipeWire)\"), and browsers with their PipeWire camera option turned on. Most video call apps do not.\n\n"
                    + "Automatic uses the device when the module is installed, PipeWire otherwise. With either, stopping the stream removes the camera: an app showing it may stay on the last picture until it is reopened.")
            }

            AppSettingRow {
                Layout.topMargin: 4
                visible: Config.options.iiTools.camera.enable
                    && !Config.options.iiTools.camera.useDroidcam
                    && IiCameraService._depsChecked
                    && !IiCameraService.available
                symbol: "download"
                title: Translation.tr("Install %1 for the phone webcam")
                    .arg(IiCameraService.missingPackageSummary || Translation.tr("missing packages"))
                description: IiCameraService.output === "pipewire"
                    ? Translation.tr("PipeWire webcam output needs FFmpeg with H.264 decoding and GStreamer's PipeWire plugins. See the Phone sidebar's Webcam card for copyable commands.")
                    : Translation.tr("Virtual camera output needs FFmpeg with H.264 decoding and the v4l2loopback kernel module. See the Phone sidebar's Webcam card for copyable commands.")
            }
        }

        // ── Other PCs (PC link) ─────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 6
            symbol: "devices"
            title: Translation.tr("Other PCs")
            description: Translation.tr("PCs linked straight to this one, without the phone in between. Link them once from the ii tools app: Your PCs → Link.")

            AppToggleRow {
                symbol: "lan"
                title: Translation.tr("Link with other PCs")
                description: Translation.tr("Accept and keep links with other PCs that run ii tools")
                checked: Config.options.iiTools.pcLink.enable
                onToggled: value => Config.options.iiTools.pcLink.enable = value
            }

            AppToggleRow {
                visible: Config.options.iiTools.pcLink.enable
                symbol: "content_paste_go"
                title: Translation.tr("Universal clipboard")
                description: Translation.tr("Text and images copied here reach the linked PCs, and theirs reach this one")
                checked: Config.options.iiTools.pcLink.clipboard
                onToggled: value => Config.options.iiTools.pcLink.clipboard = value
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: Config.options.iiTools.pcLink.enable && IiLinkService.pcPeers.length === 0
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("No PC linked yet. Pair the phone with both PCs, then tap Link in the app's PC list.")
            }

            // Without the phone: one PC shows a code, the other finds it on the LAN and types it.
            RowLayout {
                Layout.topMargin: 4
                visible: Config.options.iiTools.pcLink.enable && IiLinkService.running
                spacing: 8
                RippleButtonWithIcon {
                    materialIcon: "pin"
                    mainText: Translation.tr("Show a code")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colText: Appearance.colors.colOnSecondaryContainer
                    onClicked: {
                        root.pcCodeMode = "show";
                        IiLinkService.openPcCode();
                    }
                }
                RippleButtonWithIcon {
                    materialIcon: "keyboard"
                    mainText: Translation.tr("Enter a code")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colText: Appearance.colors.colOnSecondaryContainer
                    onClicked: {
                        root.pcCodeMode = "enter";
                        root.pcCodeTarget = null;
                        IiLinkService.discoverPcs();
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.pcCodeMode === "show" && Config.options.iiTools.pcLink.enable
                implicitHeight: showCol.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                ColumnLayout {
                    id: showCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 6
                    StyledText {
                        text: IiLinkService.localPair ? IiLinkService.localPair.code.replace(/(\d{3})(\d{3})/, "$1 $2") : "—"
                        font.pixelSize: Appearance.font.pixelSize.huge * 1.6
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: IiLinkService.localPair
                            ? Translation.tr("On the other PC: Settings → ii tools → Other PCs → Enter a code. Check that it shows this PC with %1. The code lasts 2 minutes and one wrong try cancels it.").arg(IiLinkService.localPair.check)
                            : Translation.tr("The code expired or was used.")
                    }
                    RippleButtonWithIcon {
                        materialIcon: "close"
                        mainText: Translation.tr("Done")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colText: Appearance.colors.colOnLayer2
                        onClicked: {
                            IiLinkService.closePcCode();
                            root.pcCodeMode = "";
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.pcCodeMode === "enter" && Config.options.iiTools.pcLink.enable
                implicitHeight: enterCol.implicitHeight + 32
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                ColumnLayout {
                    id: enterCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: IiLinkService.pcDiscovering ? Translation.tr("Looking for PCs on this network…")
                            : IiLinkService.pcFound.length === 0 ? Translation.tr("No other PC with ii tools answered on this network.")
                            : Translation.tr("Pick the PC that shows the code (its check is under its name):")
                    }
                    Repeater {
                        model: IiLinkService.pcFound
                        delegate: RippleButtonWithIcon {
                            required property var modelData
                            Layout.fillWidth: true
                            materialIcon: root.pcCodeTarget?.fp === modelData.fp ? "radio_button_checked" : "computer"
                            mainText: `${modelData.name || modelData.addr} · ${modelData.check}`
                            buttonRadius: Appearance.rounding.normal
                            colBackground: root.pcCodeTarget?.fp === modelData.fp ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colText: Appearance.colors.colOnLayer2
                            onClicked: root.pcCodeTarget = modelData
                        }
                    }
                    RowLayout {
                        visible: root.pcCodeTarget !== null
                        spacing: 8
                        MaterialTextField {
                            id: codeField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("6-digit code")
                            inputMethodHints: Qt.ImhDigitsOnly
                            onAccepted: IiLinkService.joinPcByCode(root.pcCodeTarget, text)
                        }
                        RippleButtonWithIcon {
                            materialIcon: "link"
                            mainText: Translation.tr("Link PC")
                            enabled: IiLinkService.localJoin !== "working"
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            colText: Appearance.colors.colOnPrimary
                            onClicked: IiLinkService.joinPcByCode(root.pcCodeTarget, codeField.text)
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: IiLinkService.localJoin !== ""
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: IiLinkService.localJoin === "ok" ? Appearance.colors.colPrimary : IiLinkService.localJoin === "working" ? Appearance.colors.colSubtext : Appearance.colors.colError
                        text: IiLinkService.localJoin === "ok" ? Translation.tr("Linked.")
                            : IiLinkService.localJoin === "working" ? Translation.tr("Linking…")
                            : IiLinkService.localJoin === "bad_secret" ? Translation.tr("Wrong code. Show a new one on the other PC.")
                            : Translation.tr("Could not link (%1).").arg(IiLinkService.localJoin)
                    }
                    RippleButtonWithIcon {
                        materialIcon: "refresh"
                        mainText: Translation.tr("Search again")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colText: Appearance.colors.colOnLayer2
                        onClicked: IiLinkService.discoverPcs()
                    }
                }
            }

            Repeater {
                model: Config.options.iiTools.pcLink.enable ? IiLinkService.pcPeers : []

                delegate: PcRow {
                    required property var modelData
                    Layout.fillWidth: true
                    pc: modelData
                }
            }
        }

        // ── Do Not Disturb ──────────────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 6
            symbol: "do_not_disturb_on"
            title: Translation.tr("Do Not Disturb")

            AppToggleRow {
                symbol: "sync"
                title: Translation.tr("Sync Do Not Disturb")
                description: Translation.tr("Keep silence states coordinated between phone and PC")
                checked: Config.options.iiTools.dnd.enable
                onToggled: value => Config.options.iiTools.dnd.enable = value
            }

            AppToggleRow {
                visible: Config.options.iiTools.dnd.enable
                symbol: "phone_android"
                title: Translation.tr("Phone follows PC Do Not Disturb")
                checked: Config.options.iiTools.dnd.phoneFollowsShell
                onToggled: value => Config.options.iiTools.dnd.phoneFollowsShell = value
            }

            AppSettingRow {
                visible: Config.options.iiTools.dnd.enable && Modes.modes.length > 0
                symbol: "tune"
                title: Translation.tr("Modes that silence the phone")
                below: Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: Modes.modes
                        delegate: ColorsChip {
                            required property var modelData
                            symbol: modelData.icon || "tune"
                            label: modelData.name
                            chosen: Array.from(Config.options.iiTools.dnd.modes).includes(modelData.id)
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const wasChosen = parent.chosen;
                                    const list = Array.from(Config.options.iiTools.dnd.modes).filter(id => id !== modelData.id);
                                    if (!wasChosen)
                                        list.push(modelData.id);
                                    Config.options.iiTools.dnd.modes = list;
                                }
                            }
                        }
                    }
                }
            }

            AppToggleRow {
                visible: Config.options.iiTools.dnd.enable
                symbol: "computer"
                title: Translation.tr("PC follows phone Do Not Disturb")
                checked: Config.options.iiTools.dnd.shellFollowsPhone
                onToggled: value => Config.options.iiTools.dnd.shellFollowsPhone = value
            }

            AppChoiceRow {
                visible: Config.options.iiTools.dnd.enable && Config.options.iiTools.dnd.shellFollowsPhone
                symbol: "notifications_paused"
                title: Translation.tr("Phone Do Not Disturb triggers")
                currentValue: Config.options.iiTools.dnd.phoneTurnsOn
                options: [{ label: Translation.tr("Do Not Disturb"), icon: "do_not_disturb_on", value: "" }]
                    .concat(Modes.modes.map(m => ({ label: m.name, icon: m.icon || "tune", value: m.id })))
                onSelected: newValue => Config.options.iiTools.dnd.phoneTurnsOn = newValue
            }
        }

        // ── Connection & diagnostics ────────────────────────────────────
        AppSettingsSection {
            Layout.topMargin: 6
            symbol: "monitor_heart"
            title: Translation.tr("Connection & diagnostics")
            description: Translation.tr("Local TLS verified by pairing fingerprint; works over LAN and Tailscale.")

            AppStepperRow {
                symbol: "settings_ethernet"
                title: Translation.tr("Port (TCP & UDP)")
                description: Translation.tr("Listening port used by the ii tools link helper")
                from: 1025
                to: 65535
                stepSize: 1
                value: Config.options.iiTools.port
                onMoved: value => Config.options.iiTools.port = value
            }

            AppSettingRow {
                symbol: "memory"
                title: Translation.tr("Helper status")
                StyledText {
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: IiLinkService.running ? Translation.tr("running · pid %1").arg(IiLinkService.helperPid)
                        : (IiLinkService.binaryPresent ? Translation.tr("standby") : Translation.tr("not installed"))
                }
            }

            AppSettingRow {
                symbol: "speed"
                title: Translation.tr("Memory · CPU")
                StyledText {
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: stats.text
                }
            }

            AppSettingRow {
                symbol: "lan"
                title: Translation.tr("Addresses")
                StyledText {
                    Layout.maximumWidth: 340
                    elide: Text.ElideMiddle
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: IiLinkService.running ? IiLinkService.addresses.map(a => `${a}:${IiLinkService.port}`).join("  ") : "—"
                }
            }

            AppSettingRow {
                symbol: "verified_user"
                title: Translation.tr("Fingerprint")
                StyledText {
                    Layout.maximumWidth: 340
                    elide: Text.ElideMiddle
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                    text: IiLinkService.fingerprint !== "" ? IiLinkService.fingerprint.match(/.{1,4}/g).slice(0, 8).join(" ") + " …" : "—"
                }
            }
        }
    }

    QtObject {
        id: stats
        property string text: "—"
    }
    Timer {
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: root.visible && IiLinkService.running && IiLinkService.helperPid > 0
        onTriggered: {
            statsProc.running = false;
            statsProc.running = true;
        }
    }
    Process {
        id: statsProc
        command: ["ps", "-o", "rss=,pcpu=", "-p", String(IiLinkService.helperPid)]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split(/\s+/);
                stats.text = parts.length === 2 ? `${(Number(parts[0]) / 1024).toFixed(1)} MB · ${parts[1]}%` : "—";
            }
        }
    }

    // ── Components ──────────────────────────────────────────────────────
    component HeroPill: Rectangle {
        id: pill
        property string symbol: ""
        property string label: ""
        property bool primaryStyle: false
        property bool secondaryStyle: false

        implicitWidth: pillRow.implicitWidth + 20
        implicitHeight: 30
        radius: Appearance.rounding.full
        color: pill.primaryStyle
            ? Appearance.colors.colPrimary
            : (pill.secondaryStyle ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: pill.symbol
                iconSize: 15
                fill: pill.primaryStyle ? 1 : 0
                color: pill.primaryStyle
                    ? Appearance.colors.colOnPrimary
                    : (pill.secondaryStyle ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
            }

            StyledText {
                text: pill.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: pill.primaryStyle
                    ? Appearance.colors.colOnPrimary
                    : (pill.secondaryStyle ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2)
            }
        }
    }

    // Pairing hub: a tonal banner with the phone count, the Pair action and
    // the paired phones inside it.
    component PairBanner: Item {
        id: pairBanner
        readonly property int peerCount: IiLinkService.peers?.length ?? 0
        readonly property bool online: IiLinkService.phoneConnected
        readonly property bool pairingOpen: IiLinkService.pairingRequested || IiLinkService.pairing !== null
        readonly property bool wide: width >= 600
        readonly property color colOn: Appearance.colors.colOnSecondaryContainer

        implicitHeight: pairCol.implicitHeight + 48

        Rectangle {
            id: pairMask
            width: pairSurface.width
            height: pairSurface.height
            radius: Appearance.rounding.verylarge
            visible: false
            layer.enabled: true
        }

        Item {
            id: pairSurface
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: pairMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colSecondaryContainer
            }

            MaterialShape {
                implicitSize: 260
                x: pairBanner.width - implicitSize * 0.55
                y: -implicitSize * 0.4
                shape: pairBanner.online
                    ? MaterialShape.Shape.Sunny
                    : (pairBanner.peerCount > 0 ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Clover4Leaf)
                color: Appearance.colors.colPrimary
                opacity: 0.12
            }
        }

        ColumnLayout {
            id: pairCol
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            GridLayout {
                Layout.fillWidth: true
                columns: pairBanner.wide ? 3 : 2
                columnSpacing: 18
                rowSpacing: 16

                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    shape: pairBanner.online
                        ? MaterialShape.Shape.Cookie7Sided
                        : (pairBanner.peerCount > 0 ? MaterialShape.Shape.Pentagon : MaterialShape.Shape.Gem)
                    implicitSize: 68
                    padding: 12
                    iconSize: 30
                    text: pairBanner.online ? "mobile_friendly" : (pairBanner.peerCount > 0 ? "phonelink" : "qr_code_scanner")
                    fill: 1
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("PAIRED PHONES")
                        font.pixelSize: Appearance.font.pixelSize.smaller - 1
                        font.variableAxes: ({ "wght": 800, "wdth": 115, "ROND": 0 })
                        font.letterSpacing: 1.5
                        color: pairBanner.colOn
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: {
                            if (pairBanner.online && IiLinkService.connectedList.length > 0) {
                                const c = IiLinkService.connectedList[0];
                                return Translation.tr("%1 is here").arg(c.name || c.model || Translation.tr("Your phone"));
                            }
                            if (pairBanner.peerCount === 1)
                                return Translation.tr("1 phone paired");
                            if (pairBanner.peerCount > 1)
                                return Translation.tr("%1 phones paired").arg(pairBanner.peerCount);
                            return Translation.tr("Bring your phone in");
                        }
                        font.pixelSize: 26
                        font.variableAxes: ({ "wght": 800, "wdth": 110, "ROND": 20 })
                        color: pairBanner.colOn
                    }

                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        lineHeight: 1.2
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ColorUtils.applyAlpha(pairBanner.colOn, 0.78)
                        text: {
                            if (pairBanner.pairingOpen)
                                return Translation.tr("Scan the code below with ii tools on the phone.");
                            if (pairBanner.online)
                                return Translation.tr("Connected over the encrypted ii link. Pair another phone any time.");
                            if (pairBanner.peerCount > 0)
                                return Translation.tr("Waiting for a paired phone on your network or Tailscale.");
                            return Translation.tr("Install ii tools on an Android 12+ phone, then pair it with a QR code. Its certificate is pinned on the first connection.");
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.columnSpan: pairBanner.wide ? 1 : 2
                    Layout.fillWidth: !pairBanner.wide
                    Layout.alignment: Qt.AlignVCenter
                    visible: !pairBanner.pairingOpen
                    implicitHeight: 56
                    horizontalPadding: 26
                    centerContent: true
                    enabled: IiLinkService.binaryPresent || !IiLinkService.probed
                    materialIcon: "qr_code_2"
                    iconPixelSize: 22
                    textPixelSize: Appearance.font.pixelSize.normal
                    mainText: pairBanner.peerCount > 0 ? Translation.tr("Pair another phone") : Translation.tr("Pair a phone")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colText: Appearance.colors.colOnPrimary
                    onClicked: {
                        if (KdeConnectService.activePhoneService !== "iiTools")
                            KdeConnectService.selectPhoneService("iiTools");
                        if (!IiLinkService.probed)
                            IiLinkService.checkBinary();
                        IiLinkService.startPairing();
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: pairBanner.peerCount > 0
                spacing: 6

                Repeater {
                    model: IiLinkService.peers

                    delegate: DeviceRow {
                        required property var modelData
                        Layout.fillWidth: true
                        device: modelData
                    }
                }
            }
        }
    }

    component DeviceRow: Rectangle {
        id: devRow
        property var device
        readonly property var conn: IiLinkService.connections[devRow.device?.id ?? ""] ?? null
        readonly property bool online: devRow.conn !== null
        readonly property var statusParts: {
            const st = IiLinkService.phoneStatus;
            if (!devRow.online || !st)
                return [];
            const parts = [];
            const b = st.battery;
            if (b && b.level >= 0)
                parts.push(`${b.level}%${b.charging ? " ⚡" : ""}${b.temp ? ` ${Number(b.temp).toFixed(0)} °C` : ""}`);
            const n = st.net;
            if (n && n.type && n.type !== "none")
                parts.push(n.type === "wifi" ? "Wi-Fi" : n.type === "cellular" ? Translation.tr("Mobile data") : n.type);
            if (Array.isArray(st.peripherals)) {
                for (const p of st.peripherals) {
                    if (p.level >= 0)
                        parts.push(`${p.name} ${p.level}%`);
                }
            }
            return parts;
        }

        implicitHeight: devRowLayout.implicitHeight + 28
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: devRow.online
            color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
        }

        RowLayout {
            id: devRowLayout
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                shape: devRow.online ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                implicitSize: 44
                padding: 7
                iconSize: 20
                text: "smartphone"
                fill: devRow.online ? 1 : 0
                color: devRow.online ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colSymbol: devRow.online ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: devRow.device?.name || devRow.device?.model || Translation.tr("Phone")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: Appearance.font.variableAxes.title
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: devRow.online
                        ? [IiLinkService.isTailnet(devRow.conn.addr)
                            ? Translation.tr("Connected via Tailscale · %1").arg(devRow.conn.addr)
                            : Translation.tr("Connected · %1").arg(devRow.conn.addr)].concat(devRow.statusParts).join(" · ")
                        : Translation.tr("Last seen %1").arg(devRow.device?.lastSeen ? new Date(devRow.device.lastSeen).toLocaleString(Qt.locale(), Locale.ShortFormat) : "—")
                }
            }

            RippleButtonWithIcon {
                materialIcon: "link_off"
                mainText: Translation.tr("Unpair")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colText: Appearance.colors.colOnLayer2
                onClicked: IiLinkService.unpair(devRow.device.id)
            }
        }
    }

    // The link helper, always shown: whether it matches its sources, and the two ways to
    // fix it when it does not (the CI's prebuilt, or a compile here). The shell downloads
    // it by itself when it is missing or stale; this is for when that did not work.
    component HelperCard: Rectangle {
        id: helperCard
        readonly property var hb: IiLinkService.helperBuild
        readonly property bool busy: helperCard.hb.building || helperCard.hb.fetching
        readonly property bool good: IiLinkService.binaryPresent && helperCard.hb.state === "ok"
        readonly property string statusText: {
            if (helperCard.hb.fetching)
                return Translation.tr("Downloading the prebuilt helper…");
            if (helperCard.hb.building)
                return Translation.tr("Compiling · %1 · %2 s").arg(helperCard.hb.progressText).arg(helperCard.hb.elapsedSeconds);
            if (helperCard.hb.fetchResult === "failed" && helperCard.hb.buildResult !== "ok")
                return Translation.tr("Download failed: %1").arg(helperCard.hb.fetchOutput || Translation.tr("no connection"));
            if (helperCard.hb.buildResult === "failed")
                return Translation.tr("Build failed: %1").arg(helperCard.hb.failureSummary(2));
            if (!IiLinkService.binaryPresent)
                return Translation.tr("Not installed");
            switch (helperCard.hb.state) {
            case "ok":
                return Translation.tr("Up to date with its sources");
            case "stale":
                return Translation.tr("Older than its sources: download or rebuild it to get the fixes");
            case "unknown":
                return Translation.tr("Installed, but not recorded from which sources");
            }
            return "";
        }

        implicitHeight: helperLayout.implicitHeight + 28
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: helperLayout
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                MaterialShapeWrappedMaterialSymbol {
                    shape: helperCard.good ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                    implicitSize: 44
                    padding: 7
                    iconSize: 20
                    text: helperCard.good ? "lan" : "build"
                    fill: helperCard.good ? 1 : 0
                    color: helperCard.good ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                    colSymbol: helperCard.good ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Link helper")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: Appearance.font.variableAxes.title
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: (helperCard.hb.fetchResult === "failed" || helperCard.hb.buildResult === "failed") && !helperCard.busy
                            ? Appearance.colors.colError : Appearance.colors.colSubtext
                        text: helperCard.statusText
                    }
                }
            }

            StyledProgressBar {
                Layout.fillWidth: true
                visible: helperCard.hb.building
                value: helperCard.hb.progress
            }

            RowLayout {
                spacing: 8
                RippleButtonWithIcon {
                    visible: helperCard.hb.prebuilt
                    enabled: !helperCard.busy
                    materialIcon: "download"
                    mainText: Translation.tr("Download")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    colText: Appearance.colors.colOnSecondaryContainer
                    onClicked: helperCard.hb.fetch()
                }
                RippleButtonWithIcon {
                    enabled: !helperCard.busy && helperCard.hb.cargoAvailable
                    materialIcon: "construction"
                    mainText: Translation.tr("Rebuild")
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colText: Appearance.colors.colOnLayer2
                    onClicked: helperCard.hb.build()
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !helperCard.hb.cargoAvailable
                    wrapMode: Text.WordWrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Rebuilding needs Rust (cargo)")
                }
            }
        }

        Component.onCompleted: helperCard.hb.refreshState()
    }

    component PcRow: Rectangle {
        id: pcRow
        property var pc
        readonly property bool online: IiLinkService.pcConnections[pcRow.pc?.fp ?? ""] !== undefined

        implicitHeight: pcRowLayout.implicitHeight + 28
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: pcRow.online
            color: ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08)
        }

        RowLayout {
            id: pcRowLayout
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            MaterialShapeWrappedMaterialSymbol {
                shape: pcRow.online ? MaterialShape.Shape.Cookie7Sided : MaterialShape.Shape.Circle
                implicitSize: 44
                padding: 7
                iconSize: 20
                text: "computer"
                fill: pcRow.online ? 1 : 0
                color: pcRow.online ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                colSymbol: pcRow.online ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: pcRow.pc?.name || Translation.tr("PC")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: Appearance.font.variableAxes.title
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: pcRow.online
                        ? Translation.tr("Connected")
                        : Translation.tr("Last seen %1").arg(pcRow.pc?.lastSeen ? new Date(pcRow.pc.lastSeen).toLocaleString(Qt.locale(), Locale.ShortFormat) : "—")
                }
            }

            RippleButtonWithIcon {
                visible: !pcRow.online && (pcRow.pc?.canWake ?? false)
                enabled: IiLinkService.running
                materialIcon: "power_settings_new"
                mainText: Translation.tr("Wake")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colText: Appearance.colors.colOnSecondaryContainer
                onClicked: IiLinkService.wakePc(pcRow.pc.fp)
            }

            RippleButtonWithIcon {
                materialIcon: "link_off"
                mainText: Translation.tr("Unlink")
                enabled: IiLinkService.running
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colText: Appearance.colors.colOnLayer2
                onClicked: IiLinkService.unpairPc(pcRow.pc.fp)
            }
        }
    }

    component PairingPanel: Rectangle {
        id: panel
        readonly property var pairing: IiLinkService.pairing
        readonly property var qr: panel.pairing?.qr ?? []
        property int secondsLeft: 0

        implicitHeight: panelLayout.implicitHeight + 36
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        Timer {
            running: panel.visible && panel.pairing !== null
            interval: 1000
            repeat: true
            triggeredOnStart: true
            onTriggered: panel.secondsLeft = Math.max(0, Math.round(((panel.pairing?.expires ?? 0) - Date.now()) / 1000))
        }

        RowLayout {
            id: panelLayout
            anchors.fill: parent
            anchors.margins: 18
            spacing: 20

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 196
                implicitHeight: 196
                radius: Appearance.rounding.large
                color: "white"

                Canvas {
                    id: qrCanvas
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: panel.qr.length > 0
                    renderStrategy: Canvas.Cooperative
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const n = panel.qr.length;
                        if (n === 0)
                            return;
                        const cell = Math.floor(width / n);
                        const offset = Math.floor((width - cell * n) / 2);
                        ctx.fillStyle = "black";
                        for (let y = 0; y < n; y++) {
                            const rowBits = panel.qr[y];
                            for (let x = 0; x < n; x++) {
                                if (rowBits[x] === "1")
                                    ctx.fillRect(offset + x * cell, offset + y * cell, cell, cell);
                            }
                        }
                    }
                    Connections {
                        target: panel
                        function onQrChanged() {
                            qrCanvas.requestPaint();
                        }
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: panel.qr.length === 0
                    loading: visible
                    implicitSize: 40
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 10

                StyledText {
                    text: Translation.tr("Scan with ii tools")
                    font.pixelSize: 20
                    font.variableAxes: ({ "wght": 750, "wdth": 100, "ROND": 0 })
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("Open ii tools on your phone and press Scan QR code on the home, on the same network or Tailscale. No app yet? Get it from github.com/P3DROVFX/ii-tools.")
                }
                StyledText {
                    visible: panel.pairing !== null
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    text: Translation.tr("Expires in %1:%2").arg(Math.floor(panel.secondsLeft / 60)).arg(String(panel.secondsLeft % 60).padStart(2, "0"))
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButtonWithIcon {
                        enabled: panel.pairing !== null
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy link")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colPrimary
                        colText: Appearance.colors.colOnPrimary
                        onClicked: Quickshell.clipboardText = panel.pairing.url
                    }
                    RippleButtonWithIcon {
                        materialIcon: "close"
                        mainText: Translation.tr("Cancel")
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer2
                        colText: Appearance.colors.colOnLayer2
                        onClicked: IiLinkService.cancelPairing()
                    }
                }
            }
        }
    }
}
