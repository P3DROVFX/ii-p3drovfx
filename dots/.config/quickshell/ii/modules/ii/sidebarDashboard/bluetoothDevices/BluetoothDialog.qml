import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../bar/shared/cards"

WindowDialog {
    id: root
    backgroundHeight: 600

    readonly property var connectedDevices: BluetoothStatus.friendlyDeviceList.filter(d => d.connected)
    readonly property var savedDevices: BluetoothStatus.friendlyDeviceList.filter(d => d.paired && !d.connected)
    readonly property var availableDevices: BluetoothStatus.friendlyDeviceList.filter(d => !d.paired && !d.connected)

    // Header (margins, fonts, and spacing matching WifiDialog/VolumeDialog)
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 0
        
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Bluetooth")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: Bluetooth.defaultAdapter?.enabled ?? false
            onToggled: {
                if (Bluetooth.defaultAdapter) {
                    Bluetooth.defaultAdapter.enabled = checked;
                }
            }
        }
    }

    // Scrollable content area
    StyledFlickable {
        id: scrollArea
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.topMargin: -4
        contentHeight: scrollContent.implicitHeight
        clip: true

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Item {
                id: maskRoot
                width: scrollArea.width
                height: scrollArea.height

                property color topFadeColor: scrollArea.atYBeginning ? "white" : "transparent"
                property color bottomFadeColor: scrollArea.atYEnd ? "white" : "transparent"

                Behavior on topFadeColor {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }
                Behavior on bottomFadeColor {
                    ColorAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: Math.min(46, parent.height / 2)
                        color: "transparent"
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: maskRoot.topFadeColor
                            }
                            GradientStop {
                                position: 1.0
                                color: "white"
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.max(0, parent.height - Math.min(46, parent.height / 2) - Math.min(56, parent.height / 2))
                        color: "white"
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.min(56, parent.height / 2)
                        color: "transparent"
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: "white"
                            }
                            GradientStop {
                                position: 1.0
                                color: maskRoot.bottomFadeColor
                            }
                        }
                    }
                }
            }
        }

        ColumnLayout {
            id: scrollContent
            width: parent.width
            spacing: 16

            // Connected devices section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Bluetooth.defaultAdapter?.enabled ?? false

                StyledText {
                    text: Translation.tr("Connected devices")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colSubtext
                    Layout.fillWidth: true
                }

                // Empty state for connected devices
                StyledText {
                    visible: root.connectedDevices.length === 0
                    text: Translation.tr("No connected devices")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                }

                // Connected devices list
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.connectedDevices.length > 0

                    Repeater {
                        model: ScriptModel {
                            values: root.connectedDevices
                        }
                        delegate: BluetoothDeviceItem {
                            required property BluetoothDevice modelData
                            required property int index
                            device: modelData
                            isFirst: index === 0
                            isLast: index === root.connectedDevices.length - 1
                            index: index
                            totalCount: root.connectedDevices.length
                            isPairedSection: true
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Saved devices section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Bluetooth.defaultAdapter?.enabled ?? false

                StyledText {
                    text: Translation.tr("Saved devices")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colSubtext
                    Layout.fillWidth: true
                }

                // Empty state for saved devices
                StyledText {
                    visible: root.savedDevices.length === 0
                    text: Translation.tr("No saved devices")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                }

                // Saved devices list
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.savedDevices.length > 0

                    Repeater {
                        model: ScriptModel {
                            values: root.savedDevices
                        }
                        delegate: BluetoothDeviceItem {
                            required property BluetoothDevice modelData
                            required property int index
                            device: modelData
                            isFirst: index === 0
                            isLast: index === root.savedDevices.length - 1
                            index: index
                            totalCount: root.savedDevices.length
                            isPairedSection: true
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // Available devices section
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: Bluetooth.defaultAdapter?.enabled ?? false

                StyledText {
                    text: Translation.tr("Available devices")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.bold: true
                    color: Appearance.colors.colSubtext
                    Layout.fillWidth: true
                }

                // Available devices list
                ColumnLayout {
                    id: availableDevicesList
                    Layout.fillWidth: true
                    spacing: 4
                    visible: root.availableDevices.length > 0

                    Repeater {
                        model: ScriptModel {
                            values: root.availableDevices
                        }
                        delegate: BluetoothDeviceItem {
                            required property BluetoothDevice modelData
                            required property int index
                            device: modelData
                            isFirst: index === 0
                            isLast: index === root.availableDevices.length - 1
                            index: index
                            totalCount: root.availableDevices.length
                            isPairedSection: false
                            Layout.fillWidth: true
                        }
                    }
                }

                // Searching / Empty placeholder for available devices
                LoadingPlaceholder {
                    id: availableDevicesPlaceholder
                    Layout.fillWidth: true
                    Layout.preferredHeight: 100
                    visible: root.availableDevices.length === 0
                    loading: Bluetooth.defaultAdapter?.discovering ?? false
                    loadingText: Translation.tr("Searching...")
                    emptyText: Translation.tr("No devices found")
                    indicatorSize: 36
                }

                // Scan for devices button
                RippleButton {
                    id: scanForDevicesBtn
                    Layout.fillWidth: true
                    implicitHeight: 56
                    buttonRadius: Appearance.rounding.large
                    
                    // Disabled when discovering is active
                    enabled: !(Bluetooth.defaultAdapter?.discovering ?? false)
                    opacity: enabled ? 1.0 : 0.5
                    
                    colBackground: scanMouseArea.containsPress ? Appearance.colors.colSurfaceContainerHighestActive
                                   : scanMouseArea.containsMouse ? Appearance.colors.colSurfaceContainerHighestHover
                                   : Appearance.colors.colSurfaceContainerHighest
                    
                    Behavior on colBackground {
                        ColorAnimation { duration: 150 }
                    }
                    
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    MouseArea {
                        id: scanMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!Bluetooth.defaultAdapter?.discovering) {
                                Bluetooth.defaultAdapter?.startDiscovery();
                            }
                        }
                    }

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 12

                        MaterialSymbol {
                            text: "search"
                            iconSize: 24
                            color: Appearance.colors.colOnSurface
                        }

                        StyledText {
                            text: Translation.tr("Scan for devices")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.bold: true
                            color: Appearance.colors.colOnSurface
                        }
                    }
                }
            }

            // Bluetooth disabled placeholder
            PagePlaceholder {
                id: offPlaceholder
                Layout.fillHeight: true
                Layout.fillWidth: true
                Layout.preferredHeight: 300
                icon: "bluetooth_disabled"
                title: Translation.tr("Bluetooth is off")
                description: Translation.tr("Turn on Bluetooth to see devices")
                shape: MaterialShape.Shape.Cookie7Sided
                shown: !(Bluetooth.defaultAdapter?.enabled ?? false)
                visible: shown
            }
        }
    }

    // Bottom Buttons Row (Details and Done)
    WindowDialogButtonRow {
        Layout.leftMargin: 0
        Layout.rightMargin: 0
        Layout.bottomMargin: -8
        
        // Details button with only a border and no fill
        RippleButton {
            id: detailsBtn
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: "transparent"
            colRipple: "transparent"
            implicitHeight: 36
            implicitWidth: detailsText.implicitWidth + 48

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                radius: parent.buttonEffectiveRadius

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }
            }

            contentItem: StyledText {
                id: detailsText
                text: Translation.tr("Details")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 500
                    })
                color: detailsBtn.hovered ? Appearance.colors.colOnSurface : Appearance.colors.colOutline
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.sidebarRightOpen = false;
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Done button with fill
        RippleButton {
            id: doneBtn
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            implicitHeight: 36
            implicitWidth: doneText.implicitWidth + 48

            contentItem: StyledText {
                id: doneText
                text: Translation.tr("Done")
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
                font.variableAxes: ({
                        "wght": 700
                    })
                color: Appearance.colors.colOnPrimary
            }
            onClicked: root.dismiss()
        }
    }
}
