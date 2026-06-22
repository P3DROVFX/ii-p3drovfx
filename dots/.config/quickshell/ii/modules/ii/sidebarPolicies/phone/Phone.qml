pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * "Phone" tab of the Sidebar Policies.
 *
 * Backed by `KdeConnectService` which mirrors the KDE Connect daemon into a
 * reactive JS state. The page is split into three zones:
 *
 *   ┌─ Header ────────────────────────┐
 *   │ Device switcher   •  •  •  •  │ + battery pill + signal pill
 *   ├─ Actions row (icons only) ──── │ styled M3 circular buttons
 *   ├─ Notifications ─────────────── │ RemoteNotificationListView (mirror of
 *   │                                │   the dashboard design) + bottom
 *   │                                │   toolbar (count + clear all)
 *   ├─ Footer ─────────────────────── │ scrcpy hero card (placeholder for the
 *   │                                │   coming-soon screen mirror shortcut)
 *   └─────────────────────────────────┘
 *
 * A floating toast at the top of the panel surfaces feedback (success/fail)
 * from action buttons. It auto-dismisses after 2.5s.
 *
 * If no devices are paired/reachable, the whole panel collapses into an
 * empty state with a "Link via KDE Connect" message.
 */
Item {
    id: root

    // ─── Sub-page navigation (Hub-and-spoke pattern) ─────
    // Mirrors CoreServicesConfig.qml: activeSubPage holds the URL of the
    // currently-open sub-page (PhoneWebcamPage or PhoneMicPage). When empty,
    // the main content is shown.
    property url activeSubPage: ""

    function openSubPage(url: url): void {
        root.activeSubPage = Qt.resolvedUrl(url)
    }

    function closeSubPage(): void {
        root.activeSubPage = ""
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        anchors.topMargin: -1
        anchors.bottomMargin: 4
        color: Appearance.colors.colLayer2
        radius: Appearance.rounding.normal

        // ─── Floating Toast ─────────────────────────────────────────
        // Surfaces feedback from action clicks (send clipboard, ping, etc.).
        // Stays overlaid at the top of the panel, doesn't push content.
        Item {
            id: toastLayer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 10
            z: 9999
            height: toastBg.height + anchors.topMargin
            visible: opacity > 0
            opacity: 0
            scale: 0.96
            y: -8

            Behavior on opacity {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            property string message: ""
            property bool ok: true

            function show(msg, success) {
                toastLayer.message = msg
                toastLayer.ok = success
                toastHideTimer.restart()
                toastLayer.opacity = 1
                toastLayer.scale = 1
                toastLayer.y = 0
            }

            function hide() {
                toastLayer.opacity = 0
                toastLayer.scale = 0.96
                toastLayer.y = -8
            }

            Timer {
                id: toastHideTimer
                interval: 2800
                repeat: false
                onTriggered: toastLayer.hide()
            }

            Rectangle {
                id: toastBg
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 16, toastRow.implicitWidth + 28)
                height: Math.max(40, toastCol.implicitHeight + 18)
                radius: Appearance.rounding.full
                color: toastLayer.ok
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colErrorContainer

                RectangularShadow {
                    anchors.fill: parent
                    radius: parent.radius
                    color: ColorUtils.transparentize(
                        toastLayer.ok ? Appearance.colors.colPrimary : Appearance.colors.colError, 0.78)
                    opacity: 0.45
                    blur: 0.9 * Appearance.sizes.elevationMargin
                    offset: Qt.vector2d(0.0, 1.0)
                    spread: 1
                    cached: true
                    visible: toastLayer.opacity > 0.01
                }

                ColumnLayout {
                    id: toastCol
                    anchors.centerIn: parent
                    spacing: 0

                    RowLayout {
                        id: toastRow
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: toastBg.width - 28
                        spacing: 8

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: toastLayer.ok ? "check_circle" : "error"
                            iconSize: 18
                            fill: 1.0
                            color: toastLayer.ok
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnErrorContainer
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            text: toastLayer.message
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: toastLayer.ok
                                ? Appearance.colors.colOnPrimaryContainer
                                : Appearance.colors.colOnErrorContainer
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            horizontalAlignment: Text.AlignLeft
                        }
                    }
                }
            }
        }

        Connections {
            target: KdeConnectService
            ignoreUnknownSignals: true
            function onActionFeedback(message, ok) {
                toastLayer.show(message, ok)
            }
            function onActiveDeviceBatteryLow(devId, charge) {
                const name = KdeConnectService.activeDevice
                    ? KdeConnectService.activeDevice.name
                    : Translation.tr("Phone")
                Quickshell.execDetached([
                    "notify-send",
                    "-i", "phone",
                    "-u", "normal",
                    Translation.tr("Low battery: %1").arg(name),
                    Translation.tr("Charge is at %1%.").arg(String(charge))
                ])
            }
            function onActiveDeviceBatteryRecovered(devId, charge) {
                const name = KdeConnectService.activeDevice
                    ? KdeConnectService.activeDevice.name
                    : Translation.tr("Phone")
                Quickshell.execDetached([
                    "notify-send",
                    "-i", "phone",
                    "-u", "low",
                    Translation.tr("Battery recovered: %1").arg(name),
                    Translation.tr("Charge is back to %1%.").arg(String(charge))
                ])
            }
            function onCriticalDepMissing(depName, message) {
                // Show a toast AND a desktop notification — missing deps
                // are important enough to be hard to miss.
                toastLayer.show(message, false)
                Quickshell.execDetached([
                    "notify-send",
                    "-i", "error",
                    "-u", "critical",
                    Translation.tr("Missing dependency: %1").arg(depName),
                    message
                ])
            }
        }

        // ─── Phone service feedback (camera/mic errors only) ───
        // We only show error toasts — success/stopped toasts are redundant
        // because the card's visual state already reflects the running/
        // stopped transition. Showing a toast on every stateChanged()
        // caused spam because stateChanged fires from periodic availability
        // checks (every 10s) and internal property updates, not just from
        // user-driven start/stop.
        Connections {
            target: PhoneCameraService
            ignoreUnknownSignals: true
            function onErrorOccurred(message) {
                toastLayer.show(message.split("\n")[0], false)
            }
            function onCriticalDepMissing(depName, message) {
                toastLayer.show(message, false)
            }
        }

        Connections {
            target: PhoneMicService
            ignoreUnknownSignals: true
            function onErrorOccurred(message) {
                toastLayer.show(message.split("\n")[0], false)
            }
            function onCriticalDepMissing(depName, message) {
                toastLayer.show(message, false)
            }
        }

        // ───────── Device selector popup (overlay, z=9999) ───────
        // Lives here (not in PhoneHeader) because ColumnLayout
        // siblings ignore `z` — any popup declared inside the header
        // would render behind the actions row below.
        Item {
            id: deviceMenuOverlay
            anchors.fill: parent
            visible: false
            enabled: visible
            z: 99999

            // Click-outside catcher — must toggle the OVERLAY's
            // visibility (not just deviceMenu's) so the MouseArea
            // itself gets disabled. If only deviceMenu.visible is
            // set to false, the overlay stays visible+enabled and
            // swallows every click beneath it, freezing the panel.
            MouseArea {
                anchors.fill: parent
                onClicked: deviceMenuOverlay.visible = false
                z: 0
            }

            Rectangle {
                id: deviceMenu
                parent: deviceMenuOverlay
                // Use the *Base variant (fully opaque) — colLayer4 has alpha < 1
                // when contentTransparency > 0, which makes the popup see-through
                // and the sidebar content bleeds through. Other opaque widgets
                // (ConfigSlider, ContentSubsection, etc.) follow the same pattern.
                color: Appearance.colors.colLayer4Base
                radius: Appearance.rounding.normal
                width: Math.min(280, parent.width - 8)
                height: deviceMenuColumn.implicitHeight + 16
                x: deviceMenuOriginX
                z: 1
                transformOrigin: Item.Top

                // absolute x / y inside the overlay (set when the chip is
                // clicked). X is clamped so the popup never escapes the
                // panel, and Y is offset 4px below the chip bottom like a
                // native dropdown menu.
                property real deviceMenuOriginX: 4
                property real deviceMenuOriginY: 0

                // Keep the menu's visibility in sync with the overlay so
                // there's never a stale Rectangle lingering invisible on
                // top of the panel content.
                visible: deviceMenuOverlay.visible

                opacity: visible ? 1.0 : 0.0
                scale: visible ? 1.0 : 0.96
                y: visible ? deviceMenuOriginY : deviceMenuOriginY - 6

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                    }
                }

                RectangularShadow {
                    anchors.fill: parent
                    radius: parent.radius
                    color: ColorUtils.transparentize(Appearance.colors.colShadow, 0.7)
                    opacity: 0.5
                    blur: 18
                    offset: Qt.vector2d(0.0, 6.0)
                    spread: 1
                    cached: true
                    visible: deviceMenu.opacity > 0.01
                }

                ColumnLayout {
                    id: deviceMenuColumn
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    // ─── Recent devices (MRU) ────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        visible: recentRepeater.count > 0

                        StyledText {
                            Layout.leftMargin: 8
                            Layout.bottomMargin: 2
                            text: Translation.tr("Recent")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                            opacity: 0.8
                        }

                        Repeater {
                            id: recentRepeater
                            model: KdeConnectService.recentDevices
                            delegate: RippleButton {
                                id: recentMenuItem
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40
                                buttonRadius: Appearance.rounding.small
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2Hover
                                contentItem: RowLayout {
                                    spacing: 8
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: "history"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: modelData?.reachable
                                            ? Appearance.colors.colOnLayer2
                                            : Appearance.colors.colSubtext
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData?.name || Translation.tr("Unknown")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            color: modelData?.reachable
                                                ? Appearance.colors.colOnLayer2
                                                : Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData?.reachable
                                                ? Translation.tr("Tap to use")
                                                : Translation.tr("Offline · paired")
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                            opacity: 0.8
                                        }
                                    }
                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: modelData?.reachable
                                            ? "radio_button_unchecked"
                                            : "do_not_disturb_on"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colSubtext
                                        animateChange: true
                                    }
                                }
                                onClicked: () => {
                                    KdeConnectService.selectDevice(modelData?.id)
                                    deviceMenuOverlay.visible = false
                                }
                            }
                        }
                    }

                    // ─── Divider between recent and all devices ─────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Appearance.colors.colOutlineVariant
                        opacity: 0.4
                        visible: recentRepeater.count > 0
                    }

                    StyledText {
                        Layout.leftMargin: 8
                        Layout.bottomMargin: 2
                        visible: recentRepeater.count > 0
                        text: Translation.tr("All paired devices")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                        opacity: 0.8
                    }

                    Repeater {
                        model: KdeConnectService.devices.filter(d => d.paired)
                        delegate: RippleButton {
                            id: deviceMenuItem
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 40
                            buttonRadius: Appearance.rounding.small
                            colBackground: modelData?.id === KdeConnectService.activeDeviceId
                                ? Appearance.colors.colPrimaryContainer
                                : "transparent"
                            colBackgroundHover: modelData?.id === KdeConnectService.activeDeviceId
                                ? Appearance.colors.colPrimaryContainerHover
                                : Appearance.colors.colLayer2Hover
                            contentItem: RowLayout {
                                spacing: 8
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "smartphone"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: modelData?.id === KdeConnectService.activeDeviceId
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : (modelData?.reachable
                                            ? Appearance.colors.colOnLayer2
                                            : Appearance.colors.colSubtext)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData?.name || "Unknown"
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        color: modelData?.id === KdeConnectService.activeDeviceId
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : (modelData?.reachable
                                                ? Appearance.colors.colOnLayer2
                                                : Appearance.colors.colSubtext)
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData?.reachable
                                            ? Translation.tr("Tap to use")
                                            : Translation.tr("Offline · paired")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: modelData?.id === KdeConnectService.activeDeviceId
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                        opacity: 0.8
                                    }
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData?.id === KdeConnectService.activeDeviceId
                                        ? "check_circle"
                                        : (modelData?.reachable
                                            ? "radio_button_unchecked"
                                            : "do_not_disturb_on")
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: modelData?.id === KdeConnectService.activeDeviceId
                                        ? Appearance.colors.colOnPrimaryContainer
                                        : Appearance.colors.colSubtext
                                    animateChange: true
                                }
                            }
                            onClicked: () => {
                                KdeConnectService.selectDevice(modelData?.id)
                                deviceMenuOverlay.visible = false
                            }
                        }
                    }

                    // ─── Refresh device list ────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Appearance.colors.colOutlineVariant
                        opacity: 0.4
                    }

                    RippleButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "refresh"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Refresh devices")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer2
                            }
                        }
                        onClicked: {
                            KdeConnectService.refreshDevices()
                            deviceMenuOverlay.visible = false
                        }
                    }
                }
            }
        }

        Connections {
            target: phoneHeader
            ignoreUnknownSignals: true
            function onRequestDeviceMenu(originItem, originW) {
                // Translate the chip's bottom-left corner into overlay-space
                // coords so the popup appears anchored underneath the chip
                // like a native dropdown — instead of at the panel's edge.
                const p = deviceMenuOverlay.mapFromItem(
                    originItem, 0, originItem.height + 4)
                const popupWidth = deviceMenu.width
                // Centre horizontally on the chip, clamped inside the overlay.
                const centeredX = p.x + originW / 2 - popupWidth / 2
                const maxX = deviceMenuOverlay.width - popupWidth - 4
                deviceMenu.deviceMenuOriginX = Math.max(4, Math.min(maxX, centeredX))
                deviceMenu.deviceMenuOriginY = p.y
                deviceMenuOverlay.visible = true
            }
        }

        ColumnLayout {
            id: contentRoot
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            // ───────── HEADER (device + battery/signal pills) ─────────
            PhoneHeader {
                id: phoneHeader
                Layout.fillWidth: true
            }

            // ───────── PAIRING REQUEST BANNERS ─────────
            Repeater {
                model: KdeConnectService.pendingPairRequests
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: pairBannerLayout.implicitHeight + 16
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer
                    opacity: 0
                    scale: 0.98
                    Component.onCompleted: {
                        opacity = 1
                        scale = 1
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Appearance.animation.elementMoveEnter.type
                            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                        }
                    }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveEnter.duration
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
                        }
                    }

                    RowLayout {
                        id: pairBannerLayout
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "phonelink_setup"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimaryContainer
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Pairing request")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData?.name || Translation.tr("Unknown device")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.85
                                elide: Text.ElideRight
                            }
                        }

                        RippleButton {
                            Layout.preferredHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: ColorUtils.transparentize(
                                Appearance.colors.colOnPrimaryContainer, 0.85)
                            colBackgroundHover: ColorUtils.transparentize(
                                Appearance.colors.colOnPrimaryContainer, 0.75)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            onClicked: KdeConnectService.declinePairing(modelData?.id)
                            StyledToolTip {
                                text: Translation.tr("Decline")
                            }
                        }

                        RippleButton {
                            Layout.preferredHeight: 32
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            contentItem: StyledText {
                                anchors.centerIn: parent
                                leftPadding: 12
                                rightPadding: 12
                                text: Translation.tr("Accept")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                            onClicked: KdeConnectService.acceptPairing(modelData?.id)
                        }
                    }
                }
            }

            // ───────── ACTIONS ROW (icon-only M3 buttons) ─────────
            PhoneActionsRow {
                id: actionsRow
                Layout.fillWidth: true
            }

            // ───────── NOTIFICATIONS ─────────
            // The empty state ("No notifications" + the Android permission
            // hint) is owned by `RemoteNotificationListView` itself — see
            // `modules/common/widgets/RemoteNotificationListView.qml`. The
            // PagePlaceholder there is the single source of truth and its
            // description is dynamic to surface the Notification Access tip
            // exactly when the active device supports the notifications
            // plugin. Do NOT duplicate the empty state here or both overlays
            // render on top of each other.
            Item {
                id: notifArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                RemoteNotificationListView {
                    id: notifList
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: listBottomRow.top
                    anchors.bottomMargin: 8
                    clip: true
                }

                RowLayout {
                    id: listBottomRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    spacing: 5

                    RippleButtonWithIcon {
                        Layout.preferredHeight: 36
                        horizontalPadding: 10
                        rippleEnabled: false
                        scale: 1.0
                        buttonRadius: 18
                        buttonRadiusPressed: 18
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colText: Appearance.colors.colOnLayer2
                        enabled: KdeConnectService.activeReachable
                        opacity: enabled ? 1.0 : 0.5
                        materialIcon: "sync"
                        mainText: ""
                        background: Rectangle {
                            anchors.fill: parent
                            radius: parent.buttonEffectiveRadius
                            color: parent.buttonColor
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        onClicked: () => KdeConnectService.requestNotificationsRefresh()
                        StyledToolTip {
                            text: Translation.tr("Sync notifications")
                        }
                    }
                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        horizontalPadding: 10
                        rippleEnabled: false
                        scale: 1.0
                        buttonRadius: 18
                        buttonRadiusPressed: 18
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colText: Appearance.colors.colOnLayer2
                        enabled: false
                        hoverEnabled: false
                        opacity: 1.0
                        materialIcon: ""
                        mainText: KdeConnectService.activeReachable
                                    ? Translation.tr("%1 notif.").arg(
                                        String(KdeConnectService.notificationCount))
                                    : Translation.tr("Device offline")
                        contentItem: StyledText {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.mainText
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: parent.colText
                        }
                        background: Rectangle {
                            anchors.fill: parent
                            radius: parent.buttonEffectiveRadius
                            color: parent.buttonColor
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                    RippleButtonWithIcon {
                        Layout.preferredHeight: 36
                        horizontalPadding: 10
                        rippleEnabled: false
                        scale: 1.0
                        buttonRadius: 18
                        buttonRadiusPressed: 18
                        colBackground: Appearance.colors.colLayer2
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colText: Appearance.colors.colOnLayer2
                        enabled: KdeConnectService.available
                                   && KdeConnectService.activeReachable
                                   && KdeConnectService.hasDevices
                                   && KdeConnectService.notificationCount > 0
                        opacity: enabled ? 1.0 : 0.5
                        materialIcon: KdeConnectService.notificationCount > 0
                                    ? "delete_sweep"
                                    : "do_not_disturb_on"
                        mainText: ""
                        background: Rectangle {
                            anchors.fill: parent
                            radius: parent.buttonEffectiveRadius
                            color: parent.buttonColor
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                        onClicked: () => KdeConnectService.discardAllNotifications()
                        StyledToolTip {
                            text: Translation.tr("Dismiss all phone notifications")
                        }
                    }
                }
            }

            // ───────── FOOTER (3 hero cards: scrcpy / webcam / microphone) ─────────
            PhoneFooter {
                id: phoneFooter
                Layout.fillWidth: true
                onRequestOpenSubPage: (url) => root.openSubPage(url)
            }
        }

        // ─── Sub-page overlay (slides in from right when activeSubPage != "") ───
        // Mirrors the pattern from CoreServicesConfig.qml — slides in over the
        // main content with a fade parallax effect.
        Item {
            id: subPageOverlay
            anchors.fill: parent
            z: 10

            property bool isOpen: root.activeSubPage.toString() !== ""
            property bool overlayActive: isOpen

            x: isOpen ? 0 : subPageOverlay.width

            Behavior on x {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveSmall.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.standardDecel
                }
            }

            onXChanged: {
                if (!isOpen && x >= subPageOverlay.width - 1)
                    overlayActive = false
            }
            onIsOpenChanged: {
                if (isOpen) overlayActive = true
            }

            enabled: isOpen
            visible: x < subPageOverlay.width

            Loader {
                id: subPageLoader
                anchors.fill: parent
                source: root.activeSubPage
                active: subPageOverlay.overlayActive

                onLoaded: {
                    if (item.hasOwnProperty("showBackButton"))
                        item.showBackButton = true
                    if (item.hasOwnProperty("goBack")) {
                        item.goBack.connect(root.closeSubPage)
                    }
                }
            }
        }

        // Empty state — KDE Connect unavailable / no paired device.
        ColumnLayout {
            id: emptyState
            anchors.fill: parent
            anchors.margins: 24
            visible: !KdeConnectService.available
                       || (KdeConnectService.hasDevices
                           && KdeConnectService.devices
                                  .filter(d => d.reachable && d.paired)
                                  .length === 0)
                       || !KdeConnectService.hasDevices
            // When invisible, this ColumnLayout's children include a
            // RippleButton ("Install KDE Connect") whose MouseArea could
            // still be enabled if the parent reports visibility async.
            // Bind `enabled` to `visible` so the whole subtree becomes
            // completely inert whenever the empty state isn't shown —
            // this guarantees the underlying action buttons remain
            // clickable while a paired+reachable device is connected.
            enabled: visible
            z: 100

            Item { Layout.fillHeight: true }

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: KdeConnectService.available
                      ? "phonelink_off" : "phonelink_erase"
                iconSize: 64
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width * 0.85
                text: KdeConnectService.available
                      ? Translation.tr("No device connected")
                      : Translation.tr("KDE Connect not installed")
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer2
                horizontalAlignment: Text.AlignHCenter
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: parent.width * 0.85
                text: KdeConnectService.available
                      ? Translation.tr("Pair a device through KDE Connect on your phone — once it shows up here, sync notifications, share clipboard, dump files and launch scrcpy mirror.")
                      : Translation.tr("Install `kdeconnect-cli` and the KDE Connect Android app, then pair a device. After pairing it will mirror here automatically.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                opacity: 0.7
            }

            RippleButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 36
                Layout.preferredWidth: 220
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                visible: !KdeConnectService.available
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "download"
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Install KDE Connect")
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                    }
                }
                onClicked: () => {
                    Quickshell.execDetached(["xdg-open",
                        "https://kdeconnect.kde.org/download.html"])
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
