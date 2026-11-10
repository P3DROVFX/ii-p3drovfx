import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.widgets.dashboard.icons

/**
 * Sculpt dashboard panel button — three Material 3 Expressive treatments,
 * chosen in the widget's page (`bar.dashboardButton.sculptVariant`):
 *
 *   tile      an alarm tile: the unread count in tall condensed digits beside a
 *             small switch. The switch is the panel — on while it is open, and
 *             the tile goes vivid and its digits bold with it. The indicators
 *             ride in a neutral pill in front of the tile.
 *   chip      one chip: the indicators, then a count badge with the bell. Open
 *             swaps the chip and its badge between the two tones of the pair.
 *   cluster   every indicator in a bubble of its own size, height and tone, a
 *             loose cluster that ends in the bell's bubble. Opening the panel
 *             settles them into one line, one size and the vivid tone.
 *
 * The indicators are the same lazy revealers as every other dashboard button;
 * only `SculptIconSlot` changes with the variant.
 */
Item {
    id: root

    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    property bool vertical: BarPlacement.vertical

    readonly property string variant: Config.options.bar.dashboardButton.sculptVariant ?? "tile"
    readonly property bool open: GlobalStates.sidebarRightOpen
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool silent: Notifications.silent
    readonly property int unread: Notifications.unread
    readonly property bool sharp: Appearance.rounding.scale === 0

    BarWidgetPalette {
        id: dashTones
        colorMode: Config.options.bar.dashboardButton.colorMode
    }
    BarWidgetPalette {
        id: neutralTones
        colorMode: "neutral"
    }
    readonly property BarWidgetPalette slotTones: root.variant === "tile" ? neutralTones : dashTones

    readonly property real thickness: (root.vertical
        ? Appearance.sizes.verticalBarWidth
        : Appearance.sizes.baseBarHeight) - 8

    // ── Geometry, along the bar ──────────────────────────────────────────────
    readonly property real rowLength: root.vertical ? flow.implicitHeight : flow.implicitWidth
    readonly property bool hasRow: root.rowLength > 0.5
    readonly property real leadPadding: root.variant === "tile" ? 4 : root.variant === "chip" ? 6 : 0
    readonly property real pillLength: root.variant === "tile" && root.hasRow ? root.rowLength + 6 : 0
    readonly property real pillGap: root.variant === "tile" ? Math.min(3, root.rowLength) : 0
    readonly property real anchorLength: anchorLoader.item ? (root.vertical ? anchorLoader.item.implicitHeight : anchorLoader.item.implicitWidth) : 0
    readonly property real totalLength: {
        if (root.variant === "tile")
            return root.pillLength + root.pillGap + root.anchorLength;
        if (root.variant === "chip")
            return root.leadPadding + root.rowLength + root.anchorLength + 4;
        return root.rowLength + root.anchorLength;
    }
    readonly property real anchorOffset: root.variant === "chip"
        ? root.totalLength - root.anchorLength - 4
        : root.totalLength - root.anchorLength

    readonly property real slotPitch: (root.variant === "cluster" ? root.thickness - 2 : root.thickness - 10) + flow.itemSpacing
    function slotOrder(item: Item): int {
        if (!item)
            return 0;
        return Math.max(0, Math.round((root.vertical ? item.y : item.x) / root.slotPitch));
    }

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : root.totalLength
    implicitHeight: root.vertical ? root.totalLength : Appearance.sizes.baseBarHeight

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: GlobalStates.toggleRightSidebar(root.screenName)
    }

    Item {
        id: band
        anchors.centerIn: parent
        width: root.vertical ? root.thickness : root.totalLength
        height: root.vertical ? root.totalLength : root.thickness

        // cluster: a state layer, there is no surface to carry the hover.
        Rectangle {
            visible: root.variant === "cluster"
            anchors.fill: parent
            anchors.margins: -2
            radius: root.sharp ? 0 : root.thickness / 2
            color: ColorUtils.transparentize(dashTones.colBare, 0.92)
            opacity: root.hovered ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(parent)
            }
        }

        // tile: the neutral pill the indicators ride in.
        Rectangle {
            visible: root.variant === "tile" && root.hasRow
            width: root.vertical ? band.width : root.pillLength
            height: root.vertical ? root.pillLength : band.height
            radius: root.sharp ? 0 : root.thickness / 2
            color: root.hovered ? neutralTones.colBackgroundHover : neutralTones.colBackground
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
            }
        }

        // chip: the chip itself.
        Rectangle {
            visible: root.variant === "chip"
            anchors.fill: parent
            radius: root.sharp ? 0 : root.thickness / 2
            color: root.open
                ? (root.hovered ? dashTones.colBackgroundHover : dashTones.colBackground)
                : (root.hovered ? dashTones.colBackgroundVariantHover : dashTones.colBackgroundVariant)
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
            }
        }

        Loader {
            id: anchorLoader
            x: root.vertical ? Math.round((band.width - width) / 2) : root.anchorOffset
            y: root.vertical ? root.anchorOffset : Math.round((band.height - height) / 2)
            sourceComponent: root.variant === "chip" ? chipBadge : root.variant === "cluster" ? clusterBell : alarmTile
        }
    }

    // ── tile: the alarm tile ────────────────────────────────────────────────
    Component {
        id: alarmTile

        Rectangle {
            id: tile

            property real boldness: root.open ? 1 : 0
            Behavior on boldness {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMove.numberAnimation.createObject(tile)
            }
            readonly property color colInk: root.open ? dashTones.colOnBackground : dashTones.colOnBackgroundVariant

            implicitWidth: root.vertical ? root.thickness : tileContent.implicitWidth + 16
            implicitHeight: root.vertical ? tileContent.implicitHeight + 12 : root.thickness
            radius: root.sharp ? 0 : Math.round(root.thickness * 0.3)
            color: root.open
                ? (root.hovered ? dashTones.colBackgroundHover : dashTones.colBackground)
                : (root.hovered ? dashTones.colBackgroundVariantHover : dashTones.colBackgroundVariant)
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(tile)
            }

            Grid {
                id: tileContent
                anchors.centerIn: parent
                columns: root.vertical ? 1 : 2
                columnSpacing: 6
                rowSpacing: 4
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                Item {
                    implicitWidth: root.silent ? pausedGlyph.implicitWidth : digits.implicitWidth
                    implicitHeight: root.silent ? pausedGlyph.implicitHeight : digits.implicitHeight

                    StyledText {
                        id: digits
                        visible: !root.silent
                        text: String(Math.min(99, root.unread)).padStart(2, "0")
                        color: tile.colInk
                        font.family: Appearance.font.family.main
                        font.pixelSize: Math.round(root.thickness * (root.vertical ? 0.6 : 0.82))
                        font.variableAxes: ({
                            "wght": Appearance.font.variableAxes.blend(260, 820, tile.boldness),
                            "wdth": 25,
                            "ROND": 100
                        })
                        font.features: ({
                            "tnum": 1
                        })
                    }

                    MaterialSymbol {
                        id: pausedGlyph
                        visible: root.silent
                        text: "notifications_paused"
                        iconSize: Math.round(root.thickness * 0.56)
                        color: tile.colInk
                    }
                }

                // The switch: the panel's own state.
                Rectangle {
                    id: track
                    readonly property real longSide: Math.round(root.thickness * 0.56)
                    readonly property real shortSide: Math.round(root.thickness * 0.32)
                    width: root.vertical ? track.longSide : track.shortSide
                    height: root.vertical ? track.shortSide : track.longSide
                    radius: root.sharp ? 0 : track.shortSide / 2
                    color: root.open ? dashTones.colOnBackground : ColorUtils.transparentize(dashTones.colOnBackgroundVariant, 0.7)
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(track)
                    }

                    Rectangle {
                        id: thumb
                        readonly property real size: root.open ? track.shortSide - 4 : track.shortSide - 6
                        readonly property real travel: track.longSide - track.shortSide
                        property real along: root.open ? 1 : 0
                        Behavior on along {
                            enabled: !Appearance.reducedMotion
                            animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(thumb)
                        }
                        width: thumb.size
                        height: thumb.size
                        radius: root.sharp ? 0 : thumb.size / 2
                        // Horizontal bar: the switch stands up, on = top.
                        x: root.vertical
                            ? (track.shortSide - thumb.size) / 2 + thumb.travel * thumb.along
                            : (track.shortSide - thumb.size) / 2
                        y: root.vertical
                            ? (track.shortSide - thumb.size) / 2
                            : (track.shortSide - thumb.size) / 2 + thumb.travel * (1 - thumb.along)
                        color: root.open ? dashTones.colBackground : dashTones.colOnBackgroundVariant
                    }
                }
            }
        }
    }

    // ── chip: the count badge ───────────────────────────────────────────────
    Component {
        id: chipBadge

        Rectangle {
            id: badge
            property alias bellIcon: chipBell
            readonly property color colInk: root.open ? dashTones.colOnBackgroundVariant : dashTones.colOnBackground

            implicitWidth: root.vertical ? root.thickness - 8 : badgeRow.implicitWidth + 14
            implicitHeight: root.vertical ? badgeRow.implicitHeight + 12 : root.thickness - 8
            radius: root.sharp ? 0 : Math.min(implicitWidth, implicitHeight) / 2
            color: root.open ? dashTones.colBackgroundVariant : dashTones.colBackground
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(badge)
            }

            Grid {
                id: badgeRow
                anchors.centerIn: parent
                columns: root.vertical ? 1 : 2
                spacing: 4
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                BellIcon {
                    id: chipBell
                    iconSize: Math.round(root.thickness * 0.46)
                    color: badge.colInk
                    silent: root.silent
                }

                StyledText {
                    visible: root.unread > 0 && !root.silent
                    text: Math.min(99, root.unread)
                    color: badge.colInk
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.variableAxes: ({
                        "wght": 800,
                        "wdth": 100,
                        "ROND": 100
                    })
                }
            }
        }
    }

    // ── cluster: the bell's bubble ──────────────────────────────────────────
    Component {
        id: clusterBell

        Item {
            id: bellBubble
            property alias bellIcon: clusterBellIcon
            implicitWidth: root.thickness
            implicitHeight: root.thickness

            Rectangle {
                anchors.fill: parent
                radius: root.sharp ? 0 : width / 2
                color: root.open
                    ? dashTones.colBackgroundVariant
                    : (root.hovered ? dashTones.colBackgroundHover : dashTones.colBackground)
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(parent)
                }
            }

            BellWithBadge {
                id: clusterBellIcon
                anchors.centerIn: parent
                iconSize: Math.round(root.thickness * 0.56)
                color: root.open ? dashTones.colOnBackgroundVariant : dashTones.colOnBackground
                silent: root.silent
            }
        }
    }

    // All the dashboard buttons share one state → cue mapping.
    DashboardIconDriver {
        id: iconDriver
        wifiIcon: wifiRev.registeredIcon
        ethernetIcon: wifiRev.loadedContent?.ethernetRef ?? null
        hotspotIcon: wifiRev.loadedContent?.hotspotRef ?? null
        bluetoothIcon: bluetoothRev.registeredIcon
        volumeIcon: volumeRev.registeredIcon
        micIcon: micRev.registeredIcon
        notificationIcon: anchorLoader.item?.bellIcon ?? null
        caffeineIcon: caffeineRev.registeredIcon
        vpnIcon: vpnRev.registeredIcon
        tailscaleIcon: tailscaleRev.registeredIcon
        pomodoroIcon: pomodoroRev.registeredIcon
        stopwatchIcon: stopwatchRev.registeredIcon
        easyEffectsIcon: easyEffectsRev.registeredIcon
        dnsIcon: dnsRev.registeredIcon
        gameModeIcon: gameModeRev.registeredIcon
        powerProfileIcon: powerProfileRev.registeredIcon
        songRecIcon: songRecRev.registeredIcon
        alarmIcon: alarmRev.registeredIcon
        countdownIcon: countdownRev.registeredIcon
    }

    Grid {
        id: flow
        x: root.vertical ? Math.round((root.width - width) / 2) : band.x + root.leadPadding
        y: root.vertical ? band.y + root.leadPadding : Math.round((root.height - height) / 2)
        flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
        columns: root.vertical ? 1 : Math.max(1, flow.visibleChildren.length)
        property real itemSpacing: root.variant === "cluster" ? (root.open ? 3 : 0) : 2
        Behavior on itemSpacing {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMove.numberAnimation.createObject(flow)
        }
        spacing: 0

        DashboardIconRevealer {
            id: caffeineRev
            reveal: Config.options.bar.dashboardButton.showCaffeine && (Idle.inhibit ?? false)
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(caffeineRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: caffeineWrapper
                    property alias iconRef: caffeineIcon
                    vertical: root.vertical
                    CoffeeIcon {
                        id: caffeineIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: caffeineWrapper.glyphLift
                        anchors.horizontalCenterOffset: caffeineWrapper.glyphShift
                        iconSize: caffeineWrapper.glyphSize
                        color: caffeineWrapper.ink
                        active: Idle.inhibit ?? false
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: volumeRev
            reveal: Config.options.bar.dashboardButton.showVolume
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(volumeRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: volumeWrapper
                    property alias iconRef: volumeIcon
                    vertical: root.vertical
                    VolumeIcon {
                        id: volumeIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: volumeWrapper.glyphLift
                        anchors.horizontalCenterOffset: volumeWrapper.glyphShift
                        iconSize: volumeWrapper.glyphSize
                        color: volumeWrapper.ink
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: micRev
            reveal: Config.options.bar.dashboardButton.showMic && (Audio.source?.audio?.muted ?? false)
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(micRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: micWrapper
                    property alias iconRef: micIcon
                    vertical: root.vertical
                    MicIcon {
                        id: micIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: micWrapper.glyphLift
                        anchors.horizontalCenterOffset: micWrapper.glyphShift
                        iconSize: micWrapper.glyphSize
                        color: micWrapper.ink
                        muted: iconDriver.sourceMuted
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: wifiRev
            reveal: Config.options.bar.dashboardButton.showNetwork
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(wifiRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: netWrapper
                    property alias iconRef: wifiIcon
                    property alias ethernetRef: ethernetIcon
                    property alias hotspotRef: hotspotIcon
                    vertical: root.vertical
    
                    EthernetIcon {
                        id: ethernetIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: netWrapper.glyphLift
                        anchors.horizontalCenterOffset: netWrapper.glyphShift
                        visible: iconDriver.shownNetworkKind === "ethernet"
                        iconSize: netWrapper.glyphSize
                        color: netWrapper.ink
                        linked: Network.ethernet
                    }

                    HotspotIcon {
                        id: hotspotIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: netWrapper.glyphLift
                        anchors.horizontalCenterOffset: netWrapper.glyphShift
                        visible: iconDriver.shownNetworkKind === "hotspot"
                        iconSize: netWrapper.glyphSize
                        color: netWrapper.ink
                        active: NetworkState.accessPointMode
                    }
    
                    WifiIcon {
                        id: wifiIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: netWrapper.glyphLift
                        anchors.horizontalCenterOffset: netWrapper.glyphShift
                        visible: iconDriver.shownNetworkKind === "wifi"
                        iconSize: netWrapper.glyphSize
                        color: netWrapper.ink
                        bars: {
                            if (!Network.ready || Network.wifiStatus !== "connected")
                                return 0;
                            const strength = Number(Network.networkStrength);
                            if (isNaN(strength))
                                return 1;
                            return strength > 67 ? 3 : strength > 33 ? 2 : 1;
                        }
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: bluetoothRev
            reveal: Config.options.bar.dashboardButton.showBluetooth && BluetoothStatus.available
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(bluetoothRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: btWrapper
                    property alias iconRef: bluetoothIcon
                    vertical: root.vertical
                    BluetoothIcon {
                        id: bluetoothIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: btWrapper.glyphLift
                        anchors.horizontalCenterOffset: btWrapper.glyphShift
                        iconSize: btWrapper.glyphSize
                        color: btWrapper.ink
                        connected: BluetoothStatus.connected
                        poweredOff: !BluetoothStatus.enabled
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: vpnRev
            reveal: Config.options.bar.dashboardButton.showVpn && VpnService.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(vpnRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: vpnWrapper
                    property alias iconRef: vpnIcon
                    vertical: root.vertical
                    VpnKeyIcon {
                        id: vpnIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: vpnWrapper.glyphLift
                        anchors.horizontalCenterOffset: vpnWrapper.glyphShift
                        iconSize: vpnWrapper.glyphSize
                        color: vpnWrapper.ink
                        connected: VpnService.active
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: tailscaleRev
            reveal: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(tailscaleRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: tailscaleWrapper
                    property alias iconRef: tailscaleIcon
                    vertical: root.vertical
                    TailscaleIcon {
                        id: tailscaleIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: tailscaleWrapper.glyphLift
                        anchors.horizontalCenterOffset: tailscaleWrapper.glyphShift
                        iconSize: tailscaleWrapper.glyphSize
                        color: tailscaleWrapper.ink
                        connected: TailscaleService.active
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: pomodoroRev
            reveal: Config.options.bar.dashboardButton.showPomodoro && TimerService.pomodoroRunning
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(pomodoroRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: pomodoroWrapper
                    property alias iconRef: pomodoroIcon
                    vertical: root.vertical
                    TimerIcon {
                        id: pomodoroIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: pomodoroWrapper.glyphLift
                        anchors.horizontalCenterOffset: pomodoroWrapper.glyphShift
                        iconSize: pomodoroWrapper.glyphSize
                        color: pomodoroWrapper.ink
                        running: TimerService.pomodoroRunning
                        onBreak: TimerService.pomodoroBreak
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: stopwatchRev
            reveal: Config.options.bar.dashboardButton.showStopwatch && TimerService.stopwatchRunning
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(stopwatchRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: stopwatchWrapper
                    property alias iconRef: stopwatchIcon
                    vertical: root.vertical
                    StopwatchIcon {
                        id: stopwatchIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: stopwatchWrapper.glyphLift
                        anchors.horizontalCenterOffset: stopwatchWrapper.glyphShift
                        iconSize: stopwatchWrapper.glyphSize
                        color: stopwatchWrapper.ink
                        running: TimerService.stopwatchRunning
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: countdownRev
            reveal: Config.options.bar.dashboardButton.showCountdowns && iconDriver.countdownVisible
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(countdownRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: countdownWrapper
                    property alias iconRef: countdownIcon
                    vertical: root.vertical
                    HourglassIcon {
                        id: countdownIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: countdownWrapper.glyphLift
                        anchors.horizontalCenterOffset: countdownWrapper.glyphShift
                        iconSize: countdownWrapper.glyphSize
                        color: countdownWrapper.ink
                        running: iconDriver.countdownRunning
                        paused: iconDriver.countdownPaused
                        finished: iconDriver.countdownFinished
                        progress: iconDriver.countdownProgress
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: easyEffectsRev
            reveal: Config.options.bar.dashboardButton.showEasyEffects && EasyEffects.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(easyEffectsRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: easyEffectsWrapper
                    property alias iconRef: easyEffectsIcon
                    vertical: root.vertical
                    EqualizerIcon {
                        id: easyEffectsIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: easyEffectsWrapper.glyphLift
                        anchors.horizontalCenterOffset: easyEffectsWrapper.glyphShift
                        iconSize: easyEffectsWrapper.glyphSize
                        color: easyEffectsWrapper.ink
                        active: EasyEffects.active
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: dnsRev
            reveal: Config.options.bar.dashboardButton.showDns && DnsOverTls.active
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(dnsRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: dnsWrapper
                    property alias iconRef: dnsIcon
                    vertical: root.vertical
                    EncryptedDnsIcon {
                        id: dnsIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: dnsWrapper.glyphLift
                        anchors.horizontalCenterOffset: dnsWrapper.glyphShift
                        iconSize: dnsWrapper.glyphSize
                        color: dnsWrapper.ink
                        active: DnsOverTls.active
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: powerProfileRev
            reveal: Config.options.bar.dashboardButton.showPowerProfile && iconDriver.powerProfileActive
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(powerProfileRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: powerProfileWrapper
                    property alias iconRef: powerProfileIcon
                    vertical: root.vertical
                    PowerProfileIcon {
                        id: powerProfileIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: powerProfileWrapper.glyphLift
                        anchors.horizontalCenterOffset: powerProfileWrapper.glyphShift
                        iconSize: powerProfileWrapper.glyphSize
                        color: powerProfileWrapper.ink
                        profile: iconDriver.powerProfileName
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: gameModeRev
            reveal: Config.options.bar.dashboardButton.showGameMode && iconDriver.gameModeOn
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(gameModeRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: gameModeWrapper
                    property alias iconRef: gameModeIcon
                    vertical: root.vertical
                    GamepadIcon {
                        id: gameModeIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: gameModeWrapper.glyphLift
                        anchors.horizontalCenterOffset: gameModeWrapper.glyphShift
                        iconSize: gameModeWrapper.glyphSize
                        color: gameModeWrapper.ink
                        active: iconDriver.gameModeOn
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: songRecRev
            reveal: Config.options.bar.dashboardButton.showMusicRecognition && SongRec.running
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(songRecRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: songRecWrapper
                    property alias iconRef: songRecIcon
                    vertical: root.vertical
                    MusicRecognitionIcon {
                        id: songRecIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: songRecWrapper.glyphLift
                        anchors.horizontalCenterOffset: songRecWrapper.glyphShift
                        iconSize: songRecWrapper.glyphSize
                        color: songRecWrapper.ink
                        listening: SongRec.running
                    }
                }
            }
        }
        DashboardIconRevealer {
            id: alarmRev
            reveal: Config.options.bar.dashboardButton.showAlarms && iconDriver.alarmVisible
            vertical: root.vertical
            layoutSpacing: flow.itemSpacing
            deferredContent: Component {
                SculptIconSlot {
                    treatment: root.variant
                    seed: root.slotOrder(alarmRev)
                    open: root.open
                    thickness: root.thickness
                    tones: root.slotTones
                    id: alarmWrapper
                    property alias iconRef: alarmIcon
                    vertical: root.vertical
                    AlarmIcon {
                        id: alarmIcon
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: alarmWrapper.glyphLift
                        anchors.horizontalCenterOffset: alarmWrapper.glyphShift
                        iconSize: alarmWrapper.glyphSize
                        color: alarmWrapper.ink
                        scheduled: iconDriver.alarmCount > 0
                        ringing: iconDriver.alarmRinging
                    }
                }
            }
        }
    }
}
