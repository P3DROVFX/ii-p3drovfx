import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "./cards"

StyledPopup {
    id: root
    popupRadius: Appearance.rounding.large
    
    // String cleanup functions
    function cleanDistro(name) {
        return name.replace(/ Linux/g, "")
                   .replace(/\s*\(.*?\)/g, "")
                   .trim();
    }
    
    function cleanCpu(model) {
        return model.replace(/Intel\(R\)|Core\(TM\)|CPU|Processor|(\d+th Gen)/g, "")
                    .replace(/\s+/g, " ")
                    .trim();
    }
    
    function cleanGpu(model) {
        return model.replace(/NVIDIA|GeForce|AMD|Radeon|Laptop GPU|Graphics/gi, "")
                    .replace(/\s+/g, " ")
                    .trim();
    }

    contentItem: ColumnLayout {
        spacing: 12
        implicitWidth: 380

        // Hero Card
        Rectangle {
            id: heroCard
            implicitWidth: 380
            implicitHeight: 140
            radius: Appearance.rounding.large
            color: Appearance.colors.colPrimaryContainer
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                
                MaterialShape {
                    shapeString: "Cookie9Sided"
                    implicitSize: 74
                    color: Appearance.m3colors.m3primary
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "laptop_chromebook"
                        iconSize: 36
                        color: Appearance.m3colors.m3onPrimary
                    }
                }
                
                Item { Layout.fillWidth: true }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 4
                    
                    Rectangle {
                        Layout.alignment: Qt.AlignRight
                        color: Appearance.colors.colPrimary
                        radius: Appearance.rounding.full
                        implicitWidth: distroRow.implicitWidth + 24
                        implicitHeight: 28
                        
                        RowLayout {
                            id: distroRow
                            anchors.centerIn: parent
                            spacing: 8
                            CustomIcon {
                                source: SystemInfo.distroIcon
                                implicitWidth: 14
                                implicitHeight: 14
                                colorize: true
                                color: Appearance.m3colors.m3onPrimary
                            }
                            StyledText {
                                text: root.cleanDistro(SystemInfo.distroName)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Bold
                                color: Appearance.m3colors.m3onPrimary
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignRight
                        spacing: -2
                        
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.cleanCpu(ResourceUsage.cpuModel)
                            font.pixelSize: 24
                            font.weight: Font.Black
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.cleanGpu(ResourceUsage.gpuModel)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }
            }
        }
        
        RowLayout {
            implicitWidth: 380
            spacing: 12
            
            // CPU Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 165
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 0
                    
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialSymbol {
                            text: "memory"
                            iconSize: 32
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.8
                        }
                        Item { Layout.fillWidth: true }
                        RowLayout {
                            spacing: 4
                            MaterialSymbol {
                                text: "thermostat"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Math.round(ResourceUsage.cpuTemp) + "°C"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                    
                    Item { Layout.fillHeight: true }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        
                        StyledText {
                            text: "CPU Usage"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.6
                        }
                        
                        StyledText {
                            text: Math.round(ResourceUsage.cpuUsage * 100) + "%"
                            font.pixelSize: 36
                            font.weight: Font.Black
                            color: Appearance.colors.colOnLayer1
                        }
                        
                        StyledProgressBar {
                            Layout.fillWidth: true
                            value: ResourceUsage.cpuUsage
                            wavy: true
                            highlightColor: Appearance.colors.colPrimary
                            trackColor: Appearance.colors.colLayer0Border
                        }
                    }
                }
            }
            
            // GPU Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 165
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh
                
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 0
                    
                    RowLayout {
                        Layout.fillWidth: true
                        MaterialSymbol {
                            text: "videogame_asset"
                            iconSize: 32
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.8
                        }
                        Item { Layout.fillWidth: true }
                        RowLayout {
                            spacing: 4
                            MaterialSymbol {
                                text: "thermostat"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Math.round(ResourceUsage.gpuTemp) + "°C"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                    
                    Item { Layout.fillHeight: true }
                    
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        
                        StyledText {
                            text: "GPU Usage"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.6
                        }
                        
                        StyledText {
                            text: Math.round(ResourceUsage.gpuUsage * 100) + "%"
                            font.pixelSize: 36
                            font.weight: Font.Black
                            color: Appearance.colors.colOnLayer1
                        }
                        
                        StyledProgressBar {
                            Layout.fillWidth: true
                            value: ResourceUsage.gpuUsage
                            wavy: true
                            highlightColor: Appearance.colors.colPrimary
                            trackColor: Appearance.colors.colLayer0Border
                        }
                    }
                }
            }
        }
        
        // RAM Pill
        Rectangle {
            implicitWidth: 380
            implicitHeight: 64
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                
                MaterialShape {
                    shapeString: "Circle"
                    implicitSize: 40
                    color: Appearance.colors.colLayer0
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "memory"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer0
                    }
                }
                
                ColumnLayout {
                    spacing: -2
                    StyledText {
                        text: "RAM"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: (ResourceUsage.memoryUsed / (1024*1024)).toFixed(1) + " GB / " + (ResourceUsage.memoryTotal / (1024*1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                StyledText {
                    text: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                }
            }
        }
        
        // Disk Pill
        Rectangle {
            implicitWidth: 380
            implicitHeight: 64
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer
            
            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                
                MaterialShape {
                    shapeString: "Circle"
                    implicitSize: 40
                    color: Appearance.colors.colLayer4
                    
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "hard_drive"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer4
                    }
                }
                
                ColumnLayout {
                    spacing: -2
                    StyledText {
                        text: "DISK"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: (ResourceUsage.diskUsed / (1024*1024*1024)).toFixed(1) + " GB / " + (ResourceUsage.diskTotal / (1024*1024*1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                
                Item { Layout.fillWidth: true }
                
                StyledText {
                    text: Math.round(ResourceUsage.diskUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                }
            }
        }
    }
}
