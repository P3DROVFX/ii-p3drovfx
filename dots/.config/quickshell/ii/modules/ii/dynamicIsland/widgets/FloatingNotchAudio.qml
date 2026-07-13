import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import Quickshell.Services.Pipewire

Item {
    id: root
    anchors.fill: parent
    property bool isExpanded: false

    // Fetch output devices from Audio service
    readonly property var outputDevices: Audio.outputDevices
    readonly property var activeSink: Pipewire.defaultAudioSink

    function getDeviceIcon(desc) {
        if (!desc)
            return "volume_up";
        let d = desc.toLowerCase();
        if (d.includes("headphone") || d.includes("headset") || d.includes("wired"))
            return "headphones";
        if (d.includes("bluetooth") || d.includes("bt"))
            return "bluetooth";
        if (d.includes("speaker") || d.includes("line"))
            return "volume_up";
        if (d.includes("hdmi") || d.includes("display") || d.includes("monitor"))
            return "tv";
        return "volume_up";
    }

    // Contracted state layout: simple output status display
    RowLayout {
        id: contractedLayout
        anchors.centerIn: parent
        spacing: 8
        opacity: !root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        MaterialShape {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            shapeString: "Cookie12Sided"
            color: Appearance.colors.colPrimaryContainer

            MaterialSymbol {
                anchors.centerIn: parent
                text: {
                    let desc = Audio.sink ? Audio.sink.description : "";
                    return root.getDeviceIcon(desc);
                }
                iconSize: 14
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        StyledText {
            text: (Audio.sink && Audio.sink.audio) ? Math.round(Audio.sink.audio.volume * 100) + "%" : "Muted"
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.bold: true
            color: Appearance.colors.colOnSurface
        }
    }

    // Expanded state layout: Android 16-inspired Output switcher list
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 8
        anchors.bottomMargin: 4
        spacing: 6
        opacity: root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        // Section Title: Output
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                text: "Output"
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.bold: true
                color: Appearance.colors.colOnSurface
            }

            Item {
                Layout.fillWidth: true
            }
        }

        // List of output devices
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ListView {
                id: devicesList
                anchors.fill: parent
                model: root.outputDevices
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds

                delegate: RowLayout {
                    width: devicesList.width
                    spacing: 8

                    readonly property var deviceNode: modelData
                    readonly property bool isActive: root.activeSink && (deviceNode.id === root.activeSink.id)
                    readonly property string deviceName: Audio.friendlyDeviceName(deviceNode)

                    // 1. Material Shape Icon on the Left
                    MaterialShape {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        shapeString: "Circle"
                        color: isActive ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: root.getDeviceIcon(deviceNode.description)
                            iconSize: 15
                            color: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    // 2. Main Pill Rectangle with volume slider (if active) or plain click selector (if inactive)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 14
                        color: isActive ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest
                        border.width: 0
                        clip: true

                        // Highlighted filled volume progress (only when active)
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * (isActive && deviceNode.audio ? deviceNode.audio.volume : 0)
                            color: Appearance.colors.colPrimaryContainer
                            radius: parent.radius
                            visible: isActive
                        }

                        // Display name text
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            text: deviceName
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: isActive
                            color: isActive ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        // Active Volume Drag Controller / Inactive Switch Clicker
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor

                            onClicked: {
                                if (!isActive) {
                                    Audio.setDefaultSink(deviceNode);
                                }
                            }

                            // Horizontal drag to change active device volume
                            onPositionChanged: {
                                if (isActive && pressed && deviceNode.audio) {
                                    let newVol = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                    deviceNode.audio.volume = newVol;
                                }
                            }
                            onPressed: {
                                if (isActive && deviceNode.audio) {
                                    let newVol = Math.max(0.0, Math.min(1.0, mouse.x / width));
                                    deviceNode.audio.volume = newVol;
                                }
                            }
                        }
                    }

                    // 3. Right Checkmark Button (only when active)
                    Item {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        visible: isActive

                        MaterialShape {
                            anchors.fill: parent
                            shapeString: "Circle"
                            color: Appearance.colors.colPrimaryContainer

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "check"
                                iconSize: 15
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                        }
                    }

                    // Placeholder to maintain spacing alignment for inactive rows
                    Item {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        visible: !isActive
                    }
                }
            }
        }

        // "Connect a device" Row at bottom
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Plus icon inside circle
            MaterialShape {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                shapeString: "Circle"
                color: Appearance.colors.colSurfaceContainerLow

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: 15
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            // Connect button pill
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                radius: 14
                color: Appearance.colors.colSurfaceContainerLow
                border.width: 0

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    text: "Connect a device"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurface
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Open bluetooth settings tool or launch blueman-manager
                        Quickshell.execDetached(["blueman-manager"]);
                    }
                }
            }

            // Align space on right to match rows above
            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
            }
        }
    }
}
