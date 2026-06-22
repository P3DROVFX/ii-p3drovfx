pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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

            // Subtle tactile feedback on the whole chip.
            scale: down ? 0.97 : (hovered ? 1.015 : 1.0)
            Behavior on scale {
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
            Layout.preferredHeight: 30
            Layout.preferredWidth: signalRow.implicitWidth + 22
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            opacity: KdeConnectService.activeReachable ? 1.0 : 0.4

            RowLayout {
                id: signalRow
                anchors.centerIn: parent
                spacing: 5

                // Bar indicator (4 bars, growing in height)
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Repeater {
                        model: 4
                        Rectangle {
                            required property int index
                            width: 3
                            height: 4 + index * 4
                            radius: 1
                            y: (parent.height - height) / 2
                            color: index < root._signalStrength
                                ? Appearance.colors.colPrimary
                                : "transparent"
                            border.width: 1
                            border.color: index < root._signalStrength
                                ? Appearance.colors.colPrimary
                                : (KdeConnectService.activeReachable
                                    ? Appearance.colors.colSubtext
                                    : Appearance.colors.colOnLayer3)
                            opacity: index < root._signalStrength ? 1.0 : 0.4
                            scale: index < root._signalStrength ? 1.0 : 0.85
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast
                                    .colorAnimation.createObject(this)
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Appearance.animation.elementMoveFast.type
                                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 180
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.4
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root._signalStrength > 0
                        ? (root._signalType.length > 0 ? root._signalType : "•")
                        : "—"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer3
                }
            }
        }

        // ─── Battery pill ───
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: batRow.implicitWidth + 22
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer3
            opacity: root._battery >= 0 ? 1.0 : 0.4
            scale: (batMouseArea?.containsPress ? 0.96
                    : (batMouseArea?.containsMouse ? 1.04 : 1.0))
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.5
                }
            }

            RowLayout {
                id: batRow
                anchors.centerIn: parent
                spacing: 5

                CircularProgress {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    implicitSize: 16
                    lineWidth: 3
                    value: root._battery >= 0 ? root._battery / 100 : 0
                    colPrimary: root._battery >= 0
                        ? (root._battery < 20
                            ? (root._charging
                                ? Appearance.colors.colPrimary
                                : Appearance.m3colors.m3error)
                            : (root._battery < 40
                                ? Appearance.colors.colSecondary
                                : Appearance.colors.colPrimary))
                        : Appearance.colors.colSubtext
                    colSecondary: ColorUtils.mix(
                        Appearance.colors.colLayer3,
                        Appearance.colors.colOnLayer3, 0.18)
                    Behavior on value {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root._battery >= 0
                        ? (root._battery + "%")
                        : "—"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer3
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "bolt"
                    iconSize: 12
                    color: Appearance.colors.colPrimary
                    visible: root._charging
                    animateChange: true
                    scale: visible ? 1.0 : 0.5
                    Behavior on scale {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.6
                        }
                    }
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
