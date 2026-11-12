pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.tablet.setup

/**
 * Settings → ii tools: the one place where the PC side of the ii tools Android app is
 * controlled — installing the app, pairing, the link and every integration's switch.
 *
 * Opening the page costs nothing either: it starts the link helper only when the user
 * presses "Pair a phone", and polls the helper's memory only while it is on screen.
 */
Item {
    id: root
    anchors.fill: parent

    property alias contentY: page.contentY

    // The helper's binary is probed lazily; the page needs to know whether it exists.
    Component.onCompleted: {
        if (!IiLinkService.probed)
            IiLinkService.checkBinary();
    }

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        // ── Hero ────────────────────────────────────────────────────────
        Rectangle {
            id: hero
            Layout.fillWidth: true
            implicitHeight: heroRow.implicitHeight + 32
            radius: Appearance.rounding.large
            readonly property bool live: IiLinkService.phoneConnected
            color: hero.live ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            RowLayout {
                id: heroRow
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                MaterialShapeWrappedMaterialSymbol {
                    text: hero.live ? "phonelink" : "phonelink_off"
                    iconSize: 30
                    padding: 14
                    shape: hero.live ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Cookie7Sided
                    color: hero.live ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    colSymbol: hero.live ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("ii tools")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: hero.live ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: hero.live ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        text: {
                            if (hero.live)
                                return Translation.tr("Connected to %1").arg(IiLinkService.connectedList.map(c => c.name || c.model).join(", "));
                            if (IiLinkService.hasPeers)
                                return IiLinkService.enabled ? Translation.tr("Paired · waiting for the phone") : Translation.tr("Paired · link switched off");
                            return Translation.tr("The Android companion of the shell: live updates, remote control and more, over your own network.");
                        }
                    }
                }
            }
        }

        // ── Install ─────────────────────────────────────────────────────
        ContentSection {
            icon: "install_mobile"
            title: Translation.tr("Get the app")

            NoticeBox {
                Layout.fillWidth: true
                isFirst: true
                isLast: true
                materialIcon: "schedule"
                text: Translation.tr("ii tools has not been released yet. A download link and its QR code will appear here.")

                RippleButtonWithIcon {
                    enabled: false
                    opacity: 0.5
                    materialIcon: "download"
                    mainText: Translation.tr("Coming soon")
                }
            }
        }

        // ── Phone ───────────────────────────────────────────────────────
        ContentSection {
            icon: "smartphone"
            title: Translation.tr("Phone")

            TabletHelperSetupRow {
                Layout.fillWidth: true
                visible: IiLinkService.probed && !IiLinkService.binaryPresent
                symbol: "lan"
                title: Translation.tr("Link helper")
                description: IiLinkService.helperBuild.cargoAvailable
                    ? Translation.tr("A small native program that keeps the connection to the phone. Build it once.")
                    : Translation.tr("Needs the Rust toolchain (cargo) to build.")
                built: IiLinkService.binaryPresent
                building: IiLinkService.helperBuild.building
                failed: IiLinkService.helperBuild.buildResult === "failed"
                failureText: IiLinkService.helperBuild.buildOutput
                progressText: IiLinkService.helperBuild.currentUnit
                unitsCompiled: IiLinkService.helperBuild.unitsCompiled
                elapsedSeconds: IiLinkService.helperBuild.elapsedSeconds
                progress: IiLinkService.helperBuild.progress
                onBuildRequested: IiLinkService.helperBuild.build()
            }

            Repeater {
                model: IiLinkService.peers

                delegate: DeviceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    device: modelData
                }
            }

            PairingPanel {
                Layout.fillWidth: true
                visible: IiLinkService.pairingRequested || IiLinkService.pairing !== null
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: IiLinkService.lastPaired !== null && !IiLinkService.pairingRequested
                materialIcon: "check_circle"
                text: Translation.tr("Paired with %1.").arg(IiLinkService.lastPaired?.name ?? "")
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: IiLinkService.lastError !== ""
                materialIcon: "error"
                text: IiLinkService.lastError
            }

            RippleButtonWithIcon {
                visible: !IiLinkService.pairingRequested && IiLinkService.pairing === null
                enabled: IiLinkService.enabled && (IiLinkService.binaryPresent || !IiLinkService.probed)
                materialIcon: "qr_code_2"
                mainText: IiLinkService.hasPeers ? Translation.tr("Pair another phone") : Translation.tr("Pair a phone")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colText: Appearance.colors.colOnPrimary
                onClicked: {
                    if (!IiLinkService.probed)
                        IiLinkService.checkBinary();
                    IiLinkService.startPairing();
                }
            }
        }

        // ── The phone in the shell ──────────────────────────────────────
        ContentSection {
            icon: "smartphone"
            title: Translation.tr("The phone in the shell")

            ConfigSwitch {
                buttonIcon: "swap_horiz"
                text: Translation.tr("Use ii tools for this phone")
                description: Translation.tr("The Phone tab, dock, widgets and quick toggles use the ii tools app instead of KDE Connect's entry for the same phone")
                checked: Config.options.iiTools.primary
                onCheckedChanged: {
                    Config.options.iiTools.primary = checked;
                    if (!checked && KdeConnectService._isIi(KdeConnectService.activeDeviceId)) {
                        const other = KdeConnectService._kdeDevices.find(d => d.paired);
                        if (other)
                            KdeConnectService.selectDevice(other.id);
                    }
                }
            }
        }

        // ── Connection ──────────────────────────────────────────────────
        ContentSection {
            icon: "lan"
            title: Translation.tr("Connection")

            ConfigSwitch {
                buttonIcon: "power_settings_new"
                text: Translation.tr("Enable the link")
                description: Translation.tr("Runs only while a phone is paired")
                checked: Config.options.iiTools.enable
                onCheckedChanged: Config.options.iiTools.enable = checked
            }

            ConfigSpinBox {
                icon: "settings_ethernet"
                text: Translation.tr("Port (TCP and UDP)")
                from: 1025
                to: 65535
                stepSize: 1
                value: Config.options.iiTools.port
                onValueChanged: Config.options.iiTools.port = value
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "info"
                text: Translation.tr("The phone connects over TLS and checks this computer's certificate fingerprint, learned when pairing. Nothing leaves your network; with Tailscale on, the phone can reach the computer from anywhere.")
            }
        }

        // ── Integrations ────────────────────────────────────────────────
        ContentSection {
            icon: "widgets"
            title: Translation.tr("Integrations")

            ConfigSwitch {
                buttonIcon: "settings_remote"
                text: Translation.tr("Remote control")
                description: Translation.tr("Lock, media mode, workspaces, scratchpad, modes and presets from the phone")
                checked: Config.options.iiTools.remote.enable
                onCheckedChanged: Config.options.iiTools.remote.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "volume_up"
                text: Translation.tr("PC audio")
                description: Translation.tr("Output and input devices, volume per app and EasyEffects presets from the phone")
                checked: Config.options.iiTools.audio.enable
                onCheckedChanged: Config.options.iiTools.audio.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "notifications_active"
                text: Translation.tr("Live updates")
                description: Translation.tr("Ongoing phone notifications (deliveries, rides, timers) on the island and in the Phone tab")
                checked: Config.options.iiTools.liveUpdates.enable
                onCheckedChanged: Config.options.iiTools.liveUpdates.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("PC live updates on the phone")
                description: Translation.tr("Recording, timers, a ringing alarm and progress on the phone's lock screen, with their buttons")
                checked: Config.options.iiTools.pcLive.enable
                onCheckedChanged: Config.options.iiTools.pcLive.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "music_note"
                text: Translation.tr("Phone media")
                description: Translation.tr("What plays on the phone shows in the media widgets, the island and the lock screen, and the media keys control it")
                checked: Config.options.iiTools.media.enable
                onCheckedChanged: Config.options.iiTools.media.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "queue_music"
                text: Translation.tr("PC media on the phone")
                description: Translation.tr("What plays here shows as a media player on the phone's lock screen and Quick Settings, with play, skip and seek")
                checked: Config.options.iiTools.pcMedia.enable
                onCheckedChanged: Config.options.iiTools.pcMedia.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "folder_open"
                text: Translation.tr("Phone files")
                description: Translation.tr("Browse the phone's storage in the file manager (needs sshfs); mounted while you use it, gone when the phone leaves")
                checked: Config.options.iiTools.files.enable
                onCheckedChanged: Config.options.iiTools.files.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "speed"
                text: Translation.tr("Performance panel")
                description: Translation.tr("CPU, GPU, RAM and the frame rate on the phone, sampled only while its panel is open")
                checked: Config.options.iiTools.perf.enable
                onCheckedChanged: Config.options.iiTools.perf.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "contacts"
                text: Translation.tr("Phone data")
                description: Translation.tr("The phone's next alarm, contacts with photos, battery and network, without ADB or KDE Connect")
                checked: Config.options.iiTools.phoneData.enable
                onCheckedChanged: Config.options.iiTools.phoneData.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "screenshot_region"
                text: Translation.tr("Screenshots")
                description: Translation.tr("Screenshots taken here reach the phone's gallery; the phone's land in Pictures/Screenshots/Phone with the preview")
                checked: Config.options.iiTools.screenshots.enable
                onCheckedChanged: Config.options.iiTools.screenshots.enable = checked
            }

            ConfigSwitch {
                visible: Config.options.iiTools.screenshots.enable
                buttonIcon: "send_to_mobile"
                text: Translation.tr("Send PC screenshots automatically")
                description: Translation.tr("Off: the screenshot preview offers \"Save to phone\" instead")
                checked: Config.options.iiTools.screenshots.autoToPhone
                onCheckedChanged: Config.options.iiTools.screenshots.autoToPhone = checked
            }

            ConfigSwitch {
                buttonIcon: "content_paste"
                text: Translation.tr("Clipboard")
                description: Translation.tr("What you copy here reaches the phone, images included; the phone sends its own from a tile, the share sheet or the app")
                checked: Config.options.iiTools.clipboard.enable
                onCheckedChanged: Config.options.iiTools.clipboard.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "share"
                text: Translation.tr("Send to PC")
                description: Translation.tr("From the phone's share sheet: links, notes, reminders, tasks, the AI chat, Downloads and the file shelf")
                checked: Config.options.iiTools.share.enable
                onCheckedChanged: Config.options.iiTools.share.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notifications")
                description: Translation.tr("Phone notifications with icons, images, actions and replies; KDE Connect's copies are left out")
                checked: Config.options.iiTools.notifications.enable
                onCheckedChanged: Config.options.iiTools.notifications.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "call"
                text: Translation.tr("Calls")
                description: Translation.tr("The call card follows the phone and answers, declines and dials without ADB")
                checked: Config.options.iiTools.calls.enable
                onCheckedChanged: Config.options.iiTools.calls.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "wallpaper"
                text: Translation.tr("Wallpaper from the phone")
                description: Translation.tr("Images shared to \"Set on PC\" are saved to the wallpapers folder and applied")
                checked: Config.options.iiTools.wallpaper.enable
                onCheckedChanged: Config.options.iiTools.wallpaper.enable = checked
            }

            ConfigSwitch {
                buttonIcon: "grid_view"
                text: Translation.tr("Deck")
                description: Translation.tr("The phone as a stream deck: shell actions, apps and your own commands, with live state")
                checked: Config.options.iiTools.deck.enable
                onCheckedChanged: Config.options.iiTools.deck.enable = checked
            }
        }

        // ── Wake-on-LAN ─────────────────────────────────────────────────
        ContentSection {
            icon: "power_settings_new"
            title: Translation.tr("Wake from the phone")

            ConfigSwitch {
                buttonIcon: "settings_ethernet"
                text: Translation.tr("Let the phone wake this PC")
                description: IiLinkService.wakeTargets.length > 0
                    ? Translation.tr("Sends the phone %1. Wake-on-LAN must be on in the firmware and for the adapter (usually wired only).")
                        .arg(IiLinkService.wakeTargets.map(t => `${t.iface} ${t.mac}`).join(", "))
                    : Translation.tr("No wired or Wi-Fi adapter with a LAN address right now.")
                checked: Config.options.iiTools.wol.enable
                onCheckedChanged: Config.options.iiTools.wol.enable = checked
            }
        }

        // ── Do Not Disturb ──────────────────────────────────────────────
        ContentSection {
            icon: "do_not_disturb_on"
            title: Translation.tr("Do Not Disturb")

            ConfigSwitch {
                buttonIcon: "sync"
                text: Translation.tr("Sync Do Not Disturb with the phone")
                checked: Config.options.iiTools.dnd.enable
                onCheckedChanged: Config.options.iiTools.dnd.enable = checked
            }

            ConfigSwitch {
                visible: Config.options.iiTools.dnd.enable
                buttonIcon: "phone_android"
                text: Translation.tr("The phone follows this PC's Do Not Disturb")
                checked: Config.options.iiTools.dnd.phoneFollowsShell
                onCheckedChanged: Config.options.iiTools.dnd.phoneFollowsShell = checked
            }

            ContentSubsection {
                visible: Config.options.iiTools.dnd.enable && Modes.modes.length > 0
                title: Translation.tr("Modes that also silence the phone")

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: Modes.modes
                        delegate: SelectionGroupButton {
                            required property var modelData
                            buttonIcon: modelData.icon || "tune"
                            buttonText: modelData.name
                            toggled: Array.from(Config.options.iiTools.dnd.modes).includes(modelData.id)
                            leftmost: true
                            rightmost: true
                            onClicked: {
                                const list = Array.from(Config.options.iiTools.dnd.modes).filter(id => id !== modelData.id);
                                if (!toggled)
                                    list.push(modelData.id);
                                Config.options.iiTools.dnd.modes = list;
                            }
                        }
                    }
                }
            }

            ConfigSwitch {
                visible: Config.options.iiTools.dnd.enable
                buttonIcon: "computer"
                text: Translation.tr("This PC follows the phone's Do Not Disturb")
                checked: Config.options.iiTools.dnd.shellFollowsPhone
                onCheckedChanged: Config.options.iiTools.dnd.shellFollowsPhone = checked
            }

            ContentSubsection {
                visible: Config.options.iiTools.dnd.enable && Config.options.iiTools.dnd.shellFollowsPhone
                title: Translation.tr("The phone's Do Not Disturb turns on")

                ConfigSelectionArray {
                    currentValue: Config.options.iiTools.dnd.phoneTurnsOn
                    onSelected: newValue => Config.options.iiTools.dnd.phoneTurnsOn = newValue
                    options: [{ displayName: Translation.tr("Do Not Disturb"), icon: "do_not_disturb_on", value: "" }]
                        .concat(Modes.modes.map(m => ({ displayName: m.name, icon: m.icon || "tune", value: m.id })))
                }
            }
        }

        // ── Deck commands ───────────────────────────────────────────────
        ContentSection {
            visible: Config.options.iiTools.deck.enable
            icon: "terminal"
            title: Translation.tr("Deck commands")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Keys the phone can add to its deck. Each runs with bash on this PC when tapped; the icon is a Material Symbol name.")
            }

            Repeater {
                model: Config.options.iiTools.deck.commands
                delegate: DeckCommandRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    command: modelData
                    commandIndex: index
                }
            }

            RippleButtonWithIcon {
                materialIcon: "add"
                mainText: Translation.tr("Add command")
                onClicked: {
                    const list = Array.from(Config.options.iiTools.deck.commands);
                    list.push({ id: Date.now().toString(36), name: Translation.tr("New command"), icon: "terminal", command: "" });
                    Config.options.iiTools.deck.commands = list;
                }
            }
        }

        // ── Diagnostics ─────────────────────────────────────────────────
        ContentSection {
            icon: "monitor_heart"
            title: Translation.tr("Diagnostics")

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 16
                rowSpacing: 6

                Key { text: Translation.tr("Helper") }
                Value {
                    text: IiLinkService.running ? Translation.tr("running · pid %1").arg(IiLinkService.helperPid)
                        : (IiLinkService.binaryPresent ? Translation.tr("stopped (no phone paired)") : Translation.tr("not built"))
                }
                Key { text: Translation.tr("Memory · CPU") }
                Value { text: stats.text }
                Key { text: Translation.tr("Addresses") }
                Value { text: IiLinkService.running ? IiLinkService.addresses.map(a => `${a}:${IiLinkService.port}`).join("  ") : "—" }
                Key { text: Translation.tr("Fingerprint") }
                Value { text: IiLinkService.fingerprint !== "" ? IiLinkService.fingerprint.match(/.{1,4}/g).slice(0, 8).join(" ") + " …" : "—" }
            }
        }
    }

    // Read off ps only while the page is visible and the helper runs.
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
    component Key: StyledText {
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }
    component Value: StyledText {
        Layout.fillWidth: true
        elide: Text.ElideMiddle
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.small
    }

    component DeckCommandRow: Rectangle {
        id: cmdRow
        property var command
        property int commandIndex

        function update(field, value): void {
            const list = Array.from(Config.options.iiTools.deck.commands);
            const next = Object.assign({}, list[cmdRow.commandIndex]);
            next[field] = value;
            list[cmdRow.commandIndex] = next;
            Config.options.iiTools.deck.commands = list;
        }

        implicitHeight: cmdLayout.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: cmdLayout
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol {
                    text: cmdRow.command?.icon || "terminal"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer2
                }
                MaterialTextField {
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("Name")
                    text: cmdRow.command?.name ?? ""
                    onEditingFinished: cmdRow.update("name", text.trim())
                }
                MaterialTextField {
                    Layout.preferredWidth: 160
                    placeholderText: Translation.tr("Icon")
                    text: cmdRow.command?.icon ?? ""
                    onEditingFinished: cmdRow.update("icon", text.trim())
                }
                RippleButtonWithIcon {
                    materialIcon: "delete"
                    mainText: ""
                    onClicked: {
                        const list = Array.from(Config.options.iiTools.deck.commands);
                        list.splice(cmdRow.commandIndex, 1);
                        Config.options.iiTools.deck.commands = list;
                    }
                }
            }
            MaterialTextField {
                Layout.fillWidth: true
                placeholderText: Translation.tr("Command, e.g. notify-send hi")
                font.family: Appearance.font.family.monospace
                text: cmdRow.command?.command ?? ""
                onEditingFinished: cmdRow.update("command", text)
            }
        }
    }

    component DeviceRow: Rectangle {
        id: row
        property var device
        readonly property var conn: IiLinkService.connections[row.device?.id ?? ""] ?? null
        readonly property bool online: row.conn !== null
        // Battery and network, when the app reports them (Phone data).
        readonly property var statusParts: {
            const st = IiLinkService.phoneStatus;
            if (!row.online || !st)
                return [];
            const parts = [];
            const b = st.battery;
            if (b && b.level >= 0)
                parts.push(`${b.level}%${b.charging ? " ⚡" : ""}${b.temp ? ` ${Number(b.temp).toFixed(0)} °C` : ""}`);
            const n = st.net;
            if (n && n.type && n.type !== "none")
                parts.push(n.type === "wifi" ? "Wi-Fi" : n.type === "cellular" ? Translation.tr("Mobile data") : n.type);
            return parts;
        }

        implicitHeight: rowLayout.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: row.online ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 10
            spacing: 12

            MaterialSymbol {
                text: "smartphone"
                iconSize: Appearance.font.pixelSize.huge
                fill: row.online ? 1 : 0
                color: row.online ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.device?.name || row.device?.model || Translation.tr("Phone")
                    color: row.online ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: row.online ? [Translation.tr("Connected · %1").arg(row.conn.addr)].concat(row.statusParts).join(" · ")
                        : Translation.tr("Last seen %1").arg(row.device?.lastSeen ? new Date(row.device.lastSeen).toLocaleString(Qt.locale(), Locale.ShortFormat) : "—")
                }
            }

            RippleButtonWithIcon {
                materialIcon: "link_off"
                mainText: Translation.tr("Unpair")
                onClicked: IiLinkService.unpair(row.device.id)
            }
        }
    }

    component PairingPanel: Rectangle {
        id: panel
        readonly property var pairing: IiLinkService.pairing
        readonly property var qr: panel.pairing?.qr ?? []
        property int secondsLeft: 0

        implicitHeight: panelLayout.implicitHeight + 32
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2

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
            anchors.margins: 16
            spacing: 20

            // Black on white whatever the theme: phone scanners read dark-on-light codes
            // best, and an inverted code fails on some of them.
            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 196
                implicitHeight: 196
                radius: Appearance.rounding.normal
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
                spacing: 8

                StyledText {
                    text: Translation.tr("Scan with ii tools")
                    font.family: Appearance.font.family.title
                    font.variableAxes: Appearance.font.variableAxes.titleRounded
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: Translation.tr("On the phone, open ii tools → Connect to PC → Scan QR code. The phone must be on the same network as this computer.")
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

                    // Camera-free pairing: KDE Connect opens the link on the phone,
                    // and ii tools handles iilink:// links.
                    RippleButtonWithIcon {
                        visible: KdeConnectService.activeReachable
                        enabled: panel.pairing !== null
                        materialIcon: "send_to_mobile"
                        mainText: Translation.tr("Send via KDE Connect")
                        onClicked: KdeConnectService.shareUrl(KdeConnectService.activeDeviceId, panel.pairing.url)
                    }
                    RippleButtonWithIcon {
                        enabled: panel.pairing !== null
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy link")
                        onClicked: Quickshell.clipboardText = panel.pairing.url
                    }
                    RippleButtonWithIcon {
                        materialIcon: "close"
                        mainText: Translation.tr("Cancel")
                        onClicked: IiLinkService.cancelPairing()
                    }
                }
            }
        }
    }
}
