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
 * The right side holds the battery pill and the gear that opens the
 * Phone's own settings page.
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
    signal requestSettings()

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
            headerEntranceAnim.stop()
            headerEntranceAnim.start()
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
            opacity: enabled ? 1.0 : 0.5
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover

            transform: Translate {
                id: deviceChipTransform
                x: 0
            }
            scale: 1.0

            // Subtle tactile feedback on the whole chip.
            Behavior on scale {
                enabled: !headerEntranceAnim.running
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutQuad
                }
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
                          ? KdeConnectService.activeDeviceDisplayName
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

        // ─── Battery pill ───
        Rectangle {
            id: batteryPill
            Layout.preferredHeight: 38
            Layout.preferredWidth: batRow.implicitWidth + 28
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            opacity: root._battery >= 0 ? 1.0 : 0.4
            scale: 1.0
            Behavior on scale {
                enabled: !headerEntranceAnim.running
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.5
                }
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

        // ─── Phone settings ───
        RippleButton {
            id: settingsButton
            implicitWidth: 38
            implicitHeight: 38
            buttonRadius: settingsButton.hovered ? Appearance.rounding.small : Appearance.rounding.full
            colBackground: Appearance.colors.colLayer3
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "settings"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
                rotation: settingsButton.hovered ? 60 : 0
                Behavior on rotation {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
            onClicked: root.requestSettings()

            StyledToolTip {
                text: Translation.tr("Phone settings")
            }
        }
    }
}
