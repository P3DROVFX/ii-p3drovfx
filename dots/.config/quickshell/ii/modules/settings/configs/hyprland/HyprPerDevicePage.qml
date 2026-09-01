pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings -> Hyprland -> Input -> Per device.
 *
 * A list of what is plugged in, and nothing else.
 *
 * This used to be every device's whole settings card, one under the next, on one page. On this
 * laptop that is nine devices, so it was nine identical "Settings just for this device" switches
 * with the device name above each - a page whose entire content was the same row repeated, where
 * finding the mouse meant reading nine names. The settings for one device are a page of their
 * own now, and this is the list you pick from, which is the shape every other list in Settings
 * already has.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    signal goBack
    property bool showBackButton: false
    property alias activeSubPage: subPageOverlay.activeSubPage

    readonly property url devicePage: Qt.resolvedUrl("HyprDevicePage.qml")

    function edit(name: string, kind: string) {
        HyprlandDevices.beginEdit(name, kind);
        subPageOverlay.activeSubPage = subPageRoot.devicePage;
    }

    /// One device: what it is, whether it has settings of its own, and a way in.
    component DeviceRow: HyprNavRow {
        id: deviceRow

        required property var device
        required property string deviceKind

        readonly property string deviceName: String(deviceRow.device?.name ?? "")
        readonly property bool overridden: HyprlandGui.deviceSpec(deviceRow.deviceName) !== null

        buttonIcon: {
            if (deviceRow.deviceKind === "keyboard") return "keyboard";
            if (deviceRow.deviceKind === "tablet") return "stylus";
            if (deviceRow.deviceKind === "touch") return "touch_app";
            return HyprlandDevices.isTouchpad(deviceRow.device) ? "touchpad_mouse" : "mouse";
        }
        text: deviceRow.deviceName
        value: deviceRow.overridden ? "" : Translation.tr("Follows Input")
        badgeText: deviceRow.overridden ? Translation.tr("Custom") : ""
        onOpenSubPage: subPageRoot.edit(deviceRow.deviceName, deviceRow.deviceKind)
    }

    ContentPage {
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        RowLayout {
            visible: subPageRoot.showBackButton
            Layout.fillWidth: true
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Per device")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.family: Appearance.font.family.title
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Settings for one device instead of all of them")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                }
            }
        }

        ContentSection {
            title: Translation.tr("Keyboards")
            icon: "keyboard"
            visible: HyprlandDevices.realKeyboards.length > 0

            Repeater {
                model: HyprlandDevices.realKeyboards

                delegate: DeviceRow {
                    required property var modelData

                    device: modelData
                    deviceKind: "keyboard"
                }
            }
        }

        ContentSection {
            title: Translation.tr("Pointers")
            icon: "mouse"
            visible: HyprlandDevices.realMice.length > 0

            Repeater {
                model: HyprlandDevices.realMice

                delegate: DeviceRow {
                    required property var modelData

                    device: modelData
                    deviceKind: "pointer"
                }
            }
        }

        ContentSection {
            title: Translation.tr("Tablets and touch")
            icon: "stylus"
            visible: HyprlandDevices.realTablets.length > 0 || HyprlandDevices.realTouch.length > 0

            Repeater {
                model: HyprlandDevices.realTablets

                delegate: DeviceRow {
                    required property var modelData

                    device: modelData
                    deviceKind: "tablet"
                }
            }

            Repeater {
                model: HyprlandDevices.realTouch

                delegate: DeviceRow {
                    required property var modelData

                    device: modelData
                    deviceKind: "touch"
                }
            }
        }

        ContentSection {
            title: Translation.tr("Devices")
            icon: "devices"
            visible: !HyprlandDevices.ready || HyprlandDevices.hiddenCount > 0

            StyledText {
                Layout.fillWidth: true
                visible: !HyprlandDevices.ready
                text: Translation.tr("Asking Hyprland what is plugged in…")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            HyprOptionNote {
                notes: HyprlandDevices.hiddenCount > 0
                    ? [{ "icon": "visibility_off", "text": Translation.tr("%1 device(s) Hyprland reports are not hardware — keyd, ydotool, logiops and the lid switch each register one — so they are left out.")
                        .arg(HyprlandDevices.hiddenCount) }]
                    : []
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}
