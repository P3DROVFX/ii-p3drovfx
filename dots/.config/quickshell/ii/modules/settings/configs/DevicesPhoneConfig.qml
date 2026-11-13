pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.devices

/**
 * Settings → Devices & Phone:
 * Google Material 3 Expressive hub for choosing the single active phone
 * integration service (ii tools OR KDE Connect OR Off), LocalSend, and
 * Bluetooth device artwork.
 */
Item {
    id: root
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    property int loadStage: 0
    onVisibleChanged: {
        if (!visible)
            return;
        if (loadStage < 1)
            loadStage = 1;
    }
    Timer {
        interval: 60
        running: root.visible && root.loadStage < 1
        repeat: false
        onTriggered: {
            if (root.loadStage < 1)
                root.loadStage = 1;
        }
    }

    readonly property string activeService: KdeConnectService.activePhoneService
    readonly property bool iiActive: activeService === "iiTools"
    readonly property bool kdeActive: activeService === "kdeconnect"
    readonly property int iiModuleCount: {
        const o = Config.options.iiTools;
        return [
            o.remote.enable, o.audio.enable, o.liveUpdates.enable, o.pcLive.enable,
            o.media.enable, o.pcMedia.enable, o.files.enable, o.touchpad.enable,
            o.perf.enable, o.phoneData.enable, o.screenshots.enable, o.clipboard.enable,
            o.share.enable, o.notifications.enable, o.calls.enable, o.wallpaper.enable,
            o.deck.enable, o.wol.enable
        ].filter(Boolean).length;
    }
    readonly property int kdePairedCount: KdeConnectService._kdeDevices
        ? KdeConnectService._kdeDevices.filter(d => d.paired).length
        : 0

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        // ── Expressive Hero (MultiEffect-clipped, matching SportsHero) ──
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

                MaterialShape {
                    implicitSize: hero.height * 1.45
                    x: hero.width - implicitSize * 0.44
                    y: hero.height - implicitSize * 0.56
                    shape: root.iiActive
                        ? MaterialShape.Shape.Cookie9Sided
                        : (root.kdeActive ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Circle)
                    color: Appearance.colors.colPrimary
                    opacity: 0.08
                }
            }

            ColumnLayout {
                id: heroCol
                anchors.fill: parent
                anchors.margins: 22
                spacing: 12

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("DEVICES & PHONE")
                    font.pixelSize: Appearance.font.pixelSize.smaller - 1
                    font.variableAxes: ({ "wght": 800, "wdth": 115, "ROND": 0 })
                    font.letterSpacing: 1.8
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Connected devices")
                    font.pixelSize: 28
                    font.variableAxes: ({ "wght": 800, "wdth": 110, "ROND": 0 })
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                    text: Translation.tr("Pick one phone bridge, share files over LAN with LocalSend, or customize Bluetooth artwork.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 8

                    HeroStatusPill {
                        symbol: root.iiActive ? "phonelink" : (root.kdeActive ? "smartphone" : "sync_disabled")
                        primaryStyle: KdeConnectService.serviceEnabled && KdeConnectService.activeReachable
                        secondaryStyle: KdeConnectService.serviceEnabled && !KdeConnectService.activeReachable
                        label: {
                            if (root.iiActive) {
                                return IiLinkService.phoneConnected
                                    ? Translation.tr("ii tools · Connected")
                                    : Translation.tr("ii tools · Standby");
                            }
                            if (root.kdeActive) {
                                return KdeConnectService.activeReachable
                                    ? Translation.tr("KDE Connect · Connected")
                                    : Translation.tr("KDE Connect · Standby");
                            }
                            return Translation.tr("Phone bridge · Off");
                        }
                    }

                    HeroStatusPill {
                        symbol: LocalSend.serverRunning ? "wifi_tethering" : "share"
                        primaryStyle: LocalSend.serverRunning
                        secondaryStyle: false
                        label: !LocalSend.available
                            ? Translation.tr("LocalSend · Missing CLI")
                            : (LocalSend.serverRunning ? Translation.tr("LocalSend · Receiving") : Translation.tr("LocalSend · Ready"))
                    }

                    HeroStatusPill {
                        visible: KdeConnectService.activeDeviceDisplayName !== ""
                        symbol: "devices"
                        primaryStyle: false
                        secondaryStyle: KdeConnectService.activeReachable
                        label: KdeConnectService.activeReachable && (KdeConnectService.activeDevice?.charge ?? -1) >= 0
                            ? `${KdeConnectService.activeDeviceDisplayName} · ${Math.round(KdeConnectService.activeDevice.charge)}%`
                            : KdeConnectService.activeDeviceDisplayName
                    }
                }
            }
        }

        // ── Unified Phone Integration Service (mutually exclusive) ──────
        AppSettingsSection {
            Layout.topMargin: 4
            visible: Config.options.policies.phone !== 0
            symbol: "smartphone"
            title: Translation.tr("Phone integration")
            description: Translation.tr("Choose one phone service for notifications, media, scrcpy, and toggles. ii tools and KDE Connect never run together.")

            PhoneServiceSelector {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                interactive: Config.options.policies.phone !== 0
                currentService: root.activeService
                onSelected: service => KdeConnectService.selectPhoneService(service)
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.width >= 680 ? 2 : 1
                columnSpacing: 14
                rowSpacing: 14

                PhoneServiceCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1

                    overline: Translation.tr("COMPANION APP")
                    title: Translation.tr("ii tools")
                    description: Translation.tr("Encrypted LAN & Tailscale bridge for live updates, remote deck, calls, clipboard, and media.")
                    symbol: "phonelink"
                    shapeActive: MaterialShape.Shape.Cookie7Sided
                    shapeIdle: MaterialShape.Shape.Circle
                    active: root.iiActive
                    connected: root.iiActive && IiLinkService.phoneConnected
                    switchEnabled: Config.options.policies.phone !== 0

                    primaryStatLabel: Translation.tr("Paired phone")
                    primaryStatValue: {
                        if (IiLinkService.phoneConnected && IiLinkService.connectedList.length > 0) {
                            const c = IiLinkService.connectedList[0];
                            const lvl = IiLinkService.phoneStatus?.battery?.level ?? -1;
                            const name = c.name || c.model || Translation.tr("Phone");
                            return lvl >= 0 ? `${name} · ${lvl}%` : name;
                        }
                        if (IiLinkService.hasPeers)
                            return IiLinkService.peers[0].name || IiLinkService.peers[0].model || Translation.tr("1 paired");
                        return Translation.tr("None paired");
                    }
                    secondaryStatLabel: Translation.tr("Modules")
                    secondaryStatValue: Translation.tr("%1 / 18 on").arg(root.iiModuleCount)

                    statusText: !root.iiActive
                        ? Translation.tr("Standby")
                        : (IiLinkService.phoneConnected ? Translation.tr("Connected") : Translation.tr("Active"))
                    actionLabel: Translation.tr("Configure")
                    actionIcon: "tune"
                    onToggled: wantActive => KdeConnectService.selectPhoneService(wantActive ? "iiTools" : "off")
                    onActionRequested: subPageOverlay.open(Qt.resolvedUrl("devices/IiToolsConfig.qml"))
                }

                PhoneServiceCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1

                    overline: Translation.tr("SYSTEM SERVICE")
                    title: Translation.tr("KDE Connect")
                    description: Translation.tr("System daemon for device discovery, clipboard, file share, remote commands, and scrcpy.")
                    symbol: "smartphone"
                    shapeActive: MaterialShape.Shape.Sunny
                    shapeIdle: MaterialShape.Shape.Circle
                    active: root.kdeActive
                    connected: root.kdeActive && KdeConnectService.activeReachable
                    switchEnabled: Config.options.policies.phone !== 0

                    primaryStatLabel: Translation.tr("Paired devices")
                    primaryStatValue: {
                        if (root.kdeActive && KdeConnectService.activeReachable && !KdeConnectService.activeIsIi) {
                            const name = KdeConnectService.activeDeviceDisplayName || Translation.tr("Phone");
                            const ch = KdeConnectService.activeDevice?.charge ?? -1;
                            return ch >= 0 ? `${name} · ${Math.round(ch)}%` : name;
                        }
                        return root.kdePairedCount > 0
                            ? Translation.tr("%1 paired").arg(root.kdePairedCount)
                            : Translation.tr("None paired");
                    }
                    secondaryStatLabel: Translation.tr("Daemon")
                    secondaryStatValue: !root.kdeActive
                        ? Translation.tr("Dormant")
                        : (KdeConnectService.available ? Translation.tr("Running") : Translation.tr("Missing"))

                    statusText: !root.kdeActive
                        ? Translation.tr("Standby")
                        : (KdeConnectService.activeReachable ? Translation.tr("Connected") : Translation.tr("Active"))
                    actionLabel: root.kdeActive
                        ? Translation.tr("Open app")
                        : Translation.tr("Use KDE Connect")
                    actionIcon: root.kdeActive ? "open_in_new" : "check"
                    showAction: !root.kdeActive || KdeConnectService.available
                    onToggled: wantActive => KdeConnectService.selectPhoneService(wantActive ? "kdeconnect" : "off")
                    onActionRequested: {
                        if (!root.kdeActive) {
                            KdeConnectService.selectPhoneService("kdeconnect");
                        } else {
                            Quickshell.execDetached(["kdeconnect-app"]);
                        }
                    }
                }
            }
        }

        // ── Redesigned LocalSend section ────────────────────────────────
        LocalSendSection {
            Layout.fillWidth: true
            Layout.topMargin: 6
        }

        // ── Bluetooth Device Images (kept unchanged) ────────────────────
        ProgressiveSectionLoader {
            Layout.topMargin: 6
            source: Qt.resolvedUrl("sections/PhoneBluetoothImagesSection.qml")
            active: root.loadStage >= 1
            estimatedHeight: 620
            showSkeleton: true
            sectionTitle: Translation.tr("Bluetooth Device Images")
            prioritizeOnViewport: true
            prioritizeOnSearch: true
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }

    component HeroStatusPill: Rectangle {
        id: hPill
        property string symbol: ""
        property string label: ""
        property bool primaryStyle: false
        property bool secondaryStyle: false

        implicitWidth: hPillRow.implicitWidth + 20
        implicitHeight: 30
        radius: Appearance.rounding.full
        color: hPill.primaryStyle
            ? Appearance.colors.colPrimary
            : (hPill.secondaryStyle ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)

        RowLayout {
            id: hPillRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                text: hPill.symbol
                iconSize: 16
                fill: hPill.primaryStyle ? 1 : 0
                color: hPill.primaryStyle
                    ? Appearance.colors.colOnPrimary
                    : (hPill.secondaryStyle ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext)
            }

            StyledText {
                text: hPill.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: hPill.primaryStyle
                    ? Appearance.colors.colOnPrimary
                    : (hPill.secondaryStyle ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2)
            }
        }
    }
}
