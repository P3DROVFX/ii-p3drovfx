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
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 650

    // Lifecycle: scan on open, stop on close
    Component.onCompleted: {
        LocalSend.startScanning()
    }
    Component.onDestruction: {
        LocalSend.stopScanning()
    }

    // Header Row (Compact but clean)
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Layout.bottomMargin: 8
        
        Rectangle {
            width: 32
            height: 32
            radius: 16
            color: Appearance.colors.colPrimaryContainer
            
            MaterialSymbol {
                anchors.centerIn: parent
                iconSize: 20
                text: "share"
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
        
        StyledText {
            id: headerTitle
            Layout.fillWidth: true
            text: Translation.tr("LocalSend Files")
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer1
        }

        StyledSwitch {
            checked: LocalSend.serverRunning
            onToggled: {
                if (checked) {
                    LocalSend.startServer()
                } else {
                    LocalSend.stopServer()
                }
            }
        }
    }

    // Scrollable content area
    StyledFlickable {
        id: scrollArea
        Layout.fillHeight: true
        Layout.fillWidth: true
        contentHeight: scrollContent.implicitHeight
        clip: true

        ColumnLayout {
            id: scrollContent
            width: parent.width
            spacing: 24 // Highly spacious vertical layout

            // Progress bar when scanning
            StyledProgressBar {
                indeterminate: true
                visible: LocalSend.scanning
                Layout.fillWidth: true
                Layout.topMargin: -8
                Layout.bottomMargin: -8
            }

            // SECTION: INCOMING TRANSFER
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12
                visible: LocalSend.currentTransfer !== null

                // Section Title Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    MaterialSymbol {
                        iconSize: 18
                        text: "downloading"
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Incoming Transfer") + " (" + (LocalSend.currentTransfer ? LocalSend.currentTransfer.files.length : 0) + ")"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Transfer Details Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: detailsColumn.implicitHeight + 28
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerHigh
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    ColumnLayout {
                        id: detailsColumn
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        StyledText {
                            text: Translation.tr("From: %1").arg(LocalSend.currentTransfer ? LocalSend.currentTransfer.sender : "")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurface
                        }

                        // Files list
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: LocalSend.currentTransfer ? LocalSend.currentTransfer.files : []
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    MaterialSymbol {
                                        text: "file_present"
                                        iconSize: 16
                                        color: Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnSurface
                                        elide: Text.ElideMiddle
                                    }

                                    StyledText {
                                        text: LocalSend.formatFileSize(modelData.size || 0)
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        // Accept / Deny Buttons
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Layout.topMargin: 4

                            RippleButton {
                                id: denyBtn
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colSurfaceContainerHighest
                                colBackgroundHover: Appearance.colors.colErrorContainerHover
                                onClicked: LocalSend.denyTransfer()

                                contentItem: Item {
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: Translation.tr("Decline")
                                        color: denyBtn.containsMouse ? Appearance.colors.colOnErrorContainer : Appearance.colors.colError
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.Bold
                                    }
                                }
                            }

                            RippleButton {
                                id: acceptBtn
                                Layout.fillWidth: true
                                implicitHeight: 38
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimary
                                onClicked: LocalSend.acceptTransfer()

                                contentItem: Item {
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: Translation.tr("Accept")
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

            // SECTION 1: FILES TO SEND
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                // Section Title Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    
                    MaterialSymbol {
                        iconSize: 18
                        text: "description"
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Files to Send") + " (" + LocalSend.droppedFiles.length + ")"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Selected files list (Taller, highly styled entries)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: LocalSend.droppedFiles.length > 0

                    Repeater {
                        model: LocalSend.droppedFiles
                        delegate: Rectangle {
                            id: dialogFileRect
                            Layout.fillWidth: true
                            implicitHeight: 52 // Taller entries for luxurious touch target
                            radius: Appearance.rounding.normal
                            color: Appearance.colors.colSurfaceContainerHigh
                            border.width: 1
                            border.color: Appearance.colors.colLayer0Border

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: 12

                                MaterialSymbol {
                                    text: "attach_file"
                                    iconSize: 20
                                    color: Appearance.colors.colPrimary
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnSurface
                                    elide: Text.ElideMiddle
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                RippleButton {
                                    id: dialogRemoveBtn
                                    implicitWidth: 32
                                    implicitHeight: 32
                                    buttonRadius: Appearance.rounding.full
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                                    onClicked: LocalSend.removeDroppedFile(index)
                                    
                                    background: Rectangle {
                                        radius: dialogRemoveBtn.buttonRadius
                                        color: dialogRemoveBtn.buttonColor
                                    }

                                    contentItem: Item {
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"
                                            iconSize: 18
                                            color: dialogRemoveBtn.hovered ? Appearance.colors.colOnErrorContainer : Appearance.colors.colError
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state text
                StyledText {
                    visible: LocalSend.droppedFiles.length === 0
                    text: Translation.tr("No files selected to send yet.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    Layout.bottomMargin: 12
                }

                // Add Files Button (Big and perfectly centered)
                RippleButton {
                    id: dialogAddBtn
                    Layout.fillWidth: true
                    implicitHeight: 48 // Spacious button height
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colSecondaryContainer
                    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                    onClicked: LocalSend.openFilePicker()
                    
                    contentItem: Item {
                        RowLayout {
                            spacing: 8
                            anchors.centerIn: parent
                            MaterialSymbol {
                                text: "add_circle"
                                iconSize: 20
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: Translation.tr("Add Files to Send")
                                color: Appearance.colors.colOnSecondaryContainer
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                            }
                        }
                    }
                }
            }

            // SECTION 2: DISCOVERED DEVICES
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 14

                // Section Title Row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        iconSize: 18
                        text: "devices"
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Select Device to Send")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnLayer1
                    }
                }

                // Discovered devices list (Big, spacious 72px luxury clickable vertical cards)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    visible: LocalSend.discoveredDevices.length > 0

                    Repeater {
                        model: LocalSend.discoveredDevices
                        delegate: RippleButton {
                            id: deviceCard
                            Layout.fillWidth: true
                            implicitHeight: 72 // Taller and highly spacious
                            buttonRadius: Appearance.rounding.normal
                            colBackground: Appearance.colors.colSurfaceContainerHigh
                            colBackgroundHover: Appearance.colors.colSurfaceContainerHighest
                            enabled: !LocalSend.sending && LocalSend.droppedFiles.length > 0
                            onClicked: LocalSend.sendToDevice(modelData.ip)

                            // Premium overlay highlight border when files are ready to send
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.normal
                                color: "transparent"
                                border.width: 1.5
                                border.color: LocalSend.droppedFiles.length > 0 ? Appearance.colors.colPrimary : "transparent"
                                opacity: deviceCard.containsMouse ? 0.8 : 0.4
                                z: 1
                            }

                            contentItem: RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 16

                                Rectangle {
                                    width: 40
                                    height: 40
                                    radius: 20
                                    color: LocalSend.droppedFiles.length > 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSurfaceContainerHighest
                                    Layout.alignment: Qt.AlignVCenter
                                    
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "smartphone"
                                        iconSize: 22
                                        color: LocalSend.droppedFiles.length > 0 ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 3
                                    Layout.alignment: Qt.AlignVCenter

                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                        elide: Text.ElideMiddle
                                    }

                                    StyledText {
                                        text: modelData.ip
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                // High fidelity Send badge indicator
                                Rectangle {
                                    width: 36
                                    height: 36
                                    radius: 18
                                    color: LocalSend.droppedFiles.length > 0 ? Appearance.colors.colPrimary : Appearance.colors.colSurfaceContainerHighest
                                    Layout.alignment: Qt.AlignVCenter
                                    
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "send"
                                        iconSize: 18
                                        color: LocalSend.droppedFiles.length > 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }
                    }
                }

                // Empty state text (when no devices found)
                StyledText {
                    visible: LocalSend.discoveredDevices.length === 0
                    text: Translation.tr("No LocalSend devices found yet.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    Layout.bottomMargin: 12
                }

                // Scan Button (Big, full-width and perfectly centered)
                RippleButton {
                    id: dialogScanBtn
                    Layout.fillWidth: true
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colSurfaceContainerHighest
                    colBackgroundHover: Appearance.colors.colSurfaceContainerLowest
                    enabled: !LocalSend.scanning
                    onClicked: LocalSend.startScanning()

                    contentItem: Item {
                        RowLayout {
                            spacing: 8
                            anchors.centerIn: parent
                            
                            MaterialSymbol {
                                text: "sync"
                                iconSize: 20
                                color: LocalSend.scanning ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                Layout.alignment: Qt.AlignVCenter

                                RotationAnimation on rotation {
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 1000
                                    running: LocalSend.scanning
                                }
                            }

                            StyledText {
                                text: LocalSend.scanning ? Translation.tr("Scanning Network...") : Translation.tr("Scan for Devices")
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.normal
                                font.weight: Font.Bold
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }
                }
            }

            // ACTIVE SENDING STATUS CARD (Spacious and high contrast)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: LocalSend.sending

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colPrimaryContainer
                    border.width: 1
                    border.color: Appearance.colors.colPrimary

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12

                        MaterialLoadingIndicator {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            Layout.alignment: Qt.AlignVCenter
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Sending files... Accept transfer on the receiver.")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    WindowDialogSeparator {}

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
