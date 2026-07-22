pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * Device switcher + status pills row at the top of the Phone tab.
 *
 * The left side shows a clickable "chip" that opens a small popup with all
 * paired devices (online + offline) and lets the user pick the active one.
 *
 * The popup itself does NOT live inside this Item because ColumnLayout
 * siblings ignore `z`, so any popup declared here would render behind the
 * action buttons below. Instead the popup is declared in `Phone.qml` and
 * positioned via a `requestDeviceMenu(globalX, globalY)` signal — that way
 * it can overlay the entire Phone panel with `z: 99999`.
 *
 * The right side shows two circular pills side-by-side:
 *   - Battery: CircularProgress colored by charge level + numeric %
 *   - Signal: strength meter (4 bars) + cellular-network-type label
 */
Item {
    id: root
    implicitHeight: deviceSelectorRow.implicitHeight
    height: deviceSelectorRow.implicitHeight

    // Pass the deviceChip ref itself (rather than scene coordinates) so the
    // Phone panel can compute the popup position via `mapFromItem` against
    // its own `deviceMenuOverlay`. Passing scene coords (via `mapToItem
    // null`) made the popup appear at the wrong x/y because the overlay
    // is anchored to the Phone panel rectangle, not the screen origin.
    signal requestDeviceMenu(var originItem, real originW)

    readonly property var _device: KdeConnectService.activeDevice
    readonly property int _battery: _device?.charge ?? -1
    readonly property bool _charging: _device?.charging ?? false
    readonly property string _signalType: _device?.signalType ?? ""
    readonly property int _signalStrength: _device?.signalStrength ?? 0

    readonly property string _deviceIconName: _device
        ? (_device.type === "tablet"
            ? (_device.reachable ? "tablet" : "tablet_off")
            : "smartphone")
        : "smartphone"

    // ─── Entrance Animations ───────────────────────────
    property int entranceTrigger: -1

    onEntranceTriggerChanged: {
        if (entranceTrigger >= 0) {
            // Reset values
            deviceChip.opacity = 0
            deviceChipTransform.x = -30
            deviceChip.scale = 0.85

            signalPill.opacity = 0
            signalPillTransform.x = 30
            signalPill.scale = 0.85

            batteryPill.opacity = 0
            batteryPill.scale = 0.85

            Qt.callLater(function() {
                headerEntranceAnim.stop()
                headerEntranceAnim.start()
            })
        }
    }

    ParallelAnimation {
        id: headerEntranceAnim

        // Device chip animation
        SequentialAnimation {
            PauseAnimation { duration: 30 }
            ParallelAnimation {
                NumberAnimation { target: deviceChip; property: "opacity"; to: (deviceChip.enabled ? 1.0 : 0.5); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: deviceChipTransform; property: "x"; to: 0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                NumberAnimation { target: deviceChip; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
            }
        }

        // Signal pill animation
        SequentialAnimation {
            PauseAnimation { duration: 70 }
            ParallelAnimation {
                NumberAnimation { target: signalPill; property: "opacity"; to: (KdeConnectService.activeReachable ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: signalPillTransform; property: "x"; to: 0; duration: 400; easing.type: Easing.OutExpo }
                NumberAnimation { target: signalPill; property: "scale"; to: 1.0; duration: 400; easing.type: Easing.OutExpo }
            }
        }

        // Battery pill animation
        SequentialAnimation {
            PauseAnimation { duration: 110 }
            ParallelAnimation {
                NumberAnimation { target: batteryPill; property: "opacity"; to: (root._battery >= 0 ? 1.0 : 0.4); duration: 320; easing.type: Easing.OutCubic }
                NumberAnimation { target: batteryPill; property: "scale"; to: 1.0; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
            }
        }
    }

    RowLayout {
        id: deviceSelectorRow
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 8

        // ─── Device selector chip ───
        RippleButton {
            id: deviceChip
            property var pairedDevices: KdeConnectService.devices
                                                    .filter(d => d.paired)

            Layout.preferredHeight: 38
            Layout.fillWidth: false
            Layout.minimumWidth: 140
            Layout.maximumWidth: 280
            enabled: KdeConnectService.hasDevices && pairedDevices.length > 0
            opacity: 0
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover

            transform: Translate {
                id: deviceChipTransform
                x: -30
            }
            scale: 0.85

            // Subtle tactile feedback on the whole chip.
            Behavior on scale {
                enabled: !headerEntranceAnim.running
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
            }

            RectangularShadow {
                anchors.fill: parent
                radius: parent.buttonEffectiveRadius
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65)
                opacity: deviceChip.opacity * 0.4
                blur: 14
                spread: 1
                visible: opacity > 0.01
            }

            contentItem: RowLayout {
                spacing: 6
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root._deviceIconName
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: Appearance.colors.colOnLayer3
                    animateChange: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: KdeConnectService.activeDevice
                          ? KdeConnectService.activeDevice.name
                          : Translation.tr("No device")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer3
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "expand_more"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: Appearance.colors.colSubtext
                    animateChange: true
                }
            }
            onClicked: {
                // Hand the chip itself to the Phone panel; it will use
                // mapFromItem to translate into overlay-space coords.
                root.requestDeviceMenu(deviceChip, deviceChip.width)
            }
        }

        Item { Layout.fillWidth: true }

        // ─── Signal pill ───
        Rectangle {
            id: signalPill
            Layout.preferredHeight: 38
            Layout.preferredWidth: signalRow.implicitWidth + 24
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            opacity: 0

            transform: Translate {
                id: signalPillTransform
                x: 30
            }
            scale: 0.85

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                color: KdeConnectService.activeReachable
                    ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                    : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.8)
                opacity: signalPill.opacity * 0.45
                blur: 12
                spread: 1
                visible: opacity > 0.01
            }

            RowLayout {
                id: signalRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: KdeConnectService.activeReachable ? "wifi" : "wifi_off"
                    iconSize: Appearance.font.pixelSize.normal
                    fill: 1
                    color: KdeConnectService.activeReachable
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                    animateChange: true
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: KdeConnectService.activeReachable
                        ? (PhoneCameraService.activeIp.length > 0
                            ? PhoneCameraService.activeIp
                            : (root._signalType && root._signalType !== "Unknown" && root._signalType !== "0"
                                ? root._signalType
                                : Translation.tr("KDE Connect")))
                        : Translation.tr("Offline")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer3
                }
            }
        }

        // ─── Battery pill ───
        Rectangle {
            id: batteryPill
            Layout.preferredHeight: 38
            Layout.preferredWidth: batRow.implicitWidth + 28
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            opacity: 0
            scale: 0.85
            Behavior on scale {
                enabled: !headerEntranceAnim.running
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.5
                }
            }

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.65)
                opacity: batteryPill.opacity * 0.45
                blur: 12
                spread: 1
                visible: opacity > 0.01
            }

            RowLayout {
                id: batRow
                anchors.centerIn: parent
                spacing: 6

                Android16Battery {
                    Layout.alignment: Qt.AlignVCenter
                    height: 18
                    batteryLevel: root._battery >= 0 ? root._battery : 0
                    isCharging: root._charging
                    colorFillNormal: Appearance.colors.colOnLayer3
                    colorTextEmpty: Appearance.colors.colOnLayer3
                    colorTextFilled: Appearance.colors.colLayer3
                }
            }

            MouseArea {
                id: batMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: KdeConnectService._probeAdb()
            }
        }
    }
}
