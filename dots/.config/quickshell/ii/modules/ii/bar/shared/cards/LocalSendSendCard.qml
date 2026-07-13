import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

SectionCard {
    id: rootCard
    title: Translation.tr("Dropped Files")
    icon: "attach_file"
    shapeColor: Appearance.colors.colPrimaryContainer
    symbolColor: Appearance.colors.colOnPrimaryContainer
    showDivider: false

    ColumnLayout {
        spacing: 16 // Generous vertical breathing room
        Layout.fillWidth: true
        Layout.topMargin: 4
        Layout.bottomMargin: 4

        // Dropped files list
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: LocalSend.droppedFiles.length > 0

            Repeater {
                model: LocalSend.droppedFiles

                delegate: Rectangle {
                    id: fileRect
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10

                        MaterialSymbol {
                            text: "description"
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.size > 0 ? modelData.name + " (" + LocalSend.formatFileSize(modelData.size) + ")" : modelData.name
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            elide: Text.ElideMiddle
                        }

                        RippleButton {
                            id: removeBtn
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colErrorContainerHover
                            onClicked: LocalSend.removeDroppedFile(index)
                            
                            background: Rectangle {
                                radius: removeBtn.buttonRadius
                                color: removeBtn.buttonColor
                            }

                            contentItem: Item {
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 16
                                    color: removeBtn.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colSubtext
                                }
                            }
                        }
                    }
                }
            }
        }

        // Empty state placeholder
        StyledText {
            visible: LocalSend.droppedFiles.length === 0
            text: Translation.tr("No files selected to send.")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
        }

        // Action Buttons Row (Add Files and Scan)
        RowLayout {
            spacing: 10
            Layout.fillWidth: true

            RippleButton {
                id: addBtn
                Layout.fillWidth: true
                implicitHeight: 38
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                onClicked: LocalSend.openFilePicker()
                
                contentItem: Item {
                    RowLayout {
                        spacing: 6
                        anchors.centerIn: parent
                        MaterialSymbol {
                            text: "add"
                            iconSize: 16
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            text: Translation.tr("Add Files...")
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            RippleButton {
                id: scanBtn
                implicitHeight: 38
                implicitWidth: 100
                buttonRadius: Appearance.rounding.normal
                colBackground: "transparent"
                colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.1)
                enabled: !LocalSend.scanning
                onClicked: LocalSend.startScanning()
                
                // Outline border instead of solid background
                background: Rectangle {
                    radius: scanBtn.buttonRadius
                    color: scanBtn.buttonColor
                    border.width: 1
                    border.color: Appearance.colors.colPrimary
                }

                contentItem: Item {
                    RowLayout {
                        spacing: 6
                        anchors.centerIn: parent
                        MaterialSymbol {
                            text: "sync"
                            iconSize: 16
                            color: LocalSend.scanning ? Appearance.colors.colPrimary : Appearance.colors.colPrimary

                            RotationAnimation on rotation {
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1000
                                running: LocalSend.scanning
                            }
                        }
                        StyledText {
                            text: LocalSend.scanning ? Translation.tr("Scanning...") : Translation.tr("Scan")
                            color: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // Section Title: Devices
        StyledText {
            visible: LocalSend.discoveredDevices.length > 0
            text: Translation.tr("Devices")
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: Appearance.colors.colPrimary
            Layout.topMargin: 4
        }

        // Discovered Devices list
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: LocalSend.discoveredDevices.length > 0

            Repeater {
                model: LocalSend.discoveredDevices

                delegate: Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        MaterialSymbol {
                            text: "smartphone"
                            iconSize: 22
                            color: Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                text: modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                                elide: Text.ElideRight
                            }

                            StyledText {
                                text: modelData.ip
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }

                        RippleButton {
                            id: sendBtn
                            implicitWidth: 76
                            implicitHeight: 32
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            buttonRadius: Appearance.rounding.normal
                            colBackground: Appearance.colors.colPrimary
                            colBackgroundHover: Appearance.colors.colPrimaryHover
                            enabled: !LocalSend.sending && LocalSend.droppedFiles.length > 0
                            onClicked: LocalSend.sendToDevice(modelData.ip)
                            
                            contentItem: Item {
                                RowLayout {
                                    spacing: 4
                                    anchors.centerIn: parent
                                    MaterialSymbol {
                                        text: "send"
                                        iconSize: 14
                                        color: Appearance.colors.colOnPrimary
                                    }
                                    StyledText {
                                        text: Translation.tr("Send")
                                        color: Appearance.colors.colOnPrimary
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Active Sending Status Card
        Rectangle {
            visible: LocalSend.sending
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Appearance.rounding.normal
            color: Appearance.colors.colPrimaryContainer
            border.width: 1
            border.color: Appearance.colors.colPrimary

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 8

                MaterialLoadingIndicator {
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Sending files... Check receiver device.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
        }

        // Waiting/Offline placeholders
        StyledText {
            visible: LocalSend.discoveredDevices.length === 0 && LocalSend.serverRunning && !LocalSend.scanning
            text: Translation.tr("No devices found yet. Click Scan above.")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
        }

        StyledText {
            visible: !LocalSend.serverRunning
            text: Translation.tr("LocalSend server is offline. Toggle on from sidebar dashboard.")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
        }
    }

    Component.onCompleted: {
        LocalSend.startScanning()
    }

    Component.onDestruction: {
        LocalSend.stopScanning()
    }
}
