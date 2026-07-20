import qs.modules.ii.bar.shared
import qs.modules.ii.bar
import qs.modules.ii.bar.widgets.resources
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import "../../shared/cards"

StyledPopup {
    id: root
    popupRadius: Appearance.rounding.large
    stickyHover: true
    animateHeight: false

    onActiveChanged: {
        ResourceUsage.gpuMonitoringEnabled = active;
    }

    // String cleanup functions
    function cleanDistro(name) {
        return name.replace(/ Linux/g, "").replace(/\s*\(.*?\)/g, "").trim();
    }

    function cleanCpu(model) {
        return model.replace(/Intel\(R\)|Core\(TM\)|CPU|Processor|(\d+th Gen)/g, "").replace(/\s+/g, " ").trim();
    }

    function cleanGpu(model) {
        if (!model || model === "--")
            return "--";

        // Remove revision info like (rev xx)
        var cleaned = model.replace(/\(rev\s+[a-f0-9]+\)/gi, "").trim();
        var baseModel = "";

        // If it is an AMD GPU (contains Advanced Micro Devices, AMD, or ATI)
        if (/Advanced Micro Devices|AMD|ATI/i.test(cleaned)) {
            // Find all bracket matches using ES5 compatible regex iteration
            var rx = /\[([^\]]+)\]/g;
            var match;
            var modelBracket = "";
            while ((match = rx.exec(cleaned)) !== null) {
                var content = match[1].trim();
                if (content.toLowerCase() !== "amd/ati") {
                    modelBracket = content;
                }
            }

            if (modelBracket) {
                // If it is something like [Radeon RX Vega M GL Graphics] or [Radeon 680M]
                if (modelBracket.indexOf("/") !== -1) {
                    modelBracket = modelBracket.split("/")[0].trim();
                }
                baseModel = modelBracket;
            } else {
                // Fallback: If no model brackets, remove the vendor prefix
                var modelOnly = cleaned.replace(/Advanced Micro Devices, Inc\.\s*\[AMD\/ATI\]/gi, "").trim();
                if (modelOnly.toLowerCase() === "amd/ati" || modelOnly.length === 0) {
                    baseModel = "Radeon Graphics";
                } else {
                    baseModel = modelOnly;
                }
            }
        } else if (/Intel/i.test(cleaned)) {
            baseModel = cleaned.replace(/Intel Corporation/gi, "Intel").trim();
        } else if (/NVIDIA/i.test(cleaned)) {
            var rxNvidia = /\[([^\]]+)\]/g;
            var matchNvidia;
            var lastBracket = "";
            while ((matchNvidia = rxNvidia.exec(cleaned)) !== null) {
                lastBracket = matchNvidia[1].trim();
            }
            if (lastBracket) {
                baseModel = lastBracket;
            } else {
                baseModel = cleaned.replace(/NVIDIA Corporation/gi, "").trim();
            }
        } else {
            baseModel = cleaned;
        }

        // Apply formatting/stripping system to make the text beautifully short in the UI
        var stripped = baseModel.replace(/NVIDIA|GeForce|AMD|Radeon|Laptop GPU|Graphics|Corporation/gi, "").replace(/\s+/g, " ").trim();
        if (stripped.length > 0) {
            stripped = stripped.replace(/^[\/\-\s]+/, "").trim();
            if (stripped.length > 0) {
                return stripped;
            }
        }
        return baseModel;
    }

    contentItem: ColumnLayout {
        id: contentLayout
        spacing: 12
        implicitWidth: 380

        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6
        
        onStartAnimChanged: {
            if (startAnim) {
                heroCard.opacity = 0.0;
                heroCard.scale = 0.85;
                heroCardTransform.y = 25;
                
                cpuGpuCardsRow.opacity = 0.0;
                cpuGpuCardsRow.scale = 0.85;
                cpuGpuCardsRowTransform.y = 25;
                
                ramCard.opacity = 0.0;
                ramCard.scale = 0.85;
                ramCardTransform.y = 25;
                
                swapCard.opacity = 0.0;
                swapCard.scale = 0.85;
                swapCardTransform.y = 25;
                
                diskCard.opacity = 0.0;
                diskCard.scale = 0.85;
                diskCardTransform.y = 25;
                
                dockerLayout.opacity = 0.0;
                dockerLayout.scale = 0.85;
                dockerLayoutTransform.y = 25;
                
                // Reset inner animation triggers so they re-fire
                heroCard.innerStartAnim = false;
                cpuCard.innerStartAnim = false;
                gpuCard.innerStartAnim = false;
                ramCard.innerStartAnim = false;
                swapCard.innerStartAnim = false;
                diskCard.innerStartAnim = false;
                
                Qt.callLater(function() {
                    heroCardAnim.start();
                    cpuGpuCardsRowAnim.start();
                    ramCardAnim.start();
                    swapCardAnim.start();
                    diskCardAnim.start();
                    dockerLayoutAnim.start();
                    
                    heroCard.innerStartAnim = true;
                    cpuCard.innerStartAnim = true;
                    gpuCard.innerStartAnim = true;
                    ramCard.innerStartAnim = true;
                    swapCard.innerStartAnim = true;
                    diskCard.innerStartAnim = true;
                });
            }
        }

        Connections {
            target: root
            function onPopupOpenProgressChanged() {
                if (root && root.popupOpenProgress === 0.0) {
                    heroCardAnim.stop();
                    cpuGpuCardsRowAnim.stop();
                    ramCardAnim.stop();
                    swapCardAnim.stop();
                    diskCardAnim.stop();
                    dockerLayoutAnim.stop();

                    heroCard.opacity = 0.0;
                    heroCard.scale = 0.85;
                    heroCardTransform.y = 25;
                    
                    cpuGpuCardsRow.opacity = 0.0;
                    cpuGpuCardsRow.scale = 0.85;
                    cpuGpuCardsRowTransform.y = 25;
                    
                    ramCard.opacity = 0.0;
                    ramCard.scale = 0.85;
                    ramCardTransform.y = 25;
                    
                    swapCard.opacity = 0.0;
                    swapCard.scale = 0.85;
                    swapCardTransform.y = 25;
                    
                    diskCard.opacity = 0.0;
                    diskCard.scale = 0.85;
                    diskCardTransform.y = 25;
                    
                    dockerLayout.opacity = 0.0;
                    dockerLayout.scale = 0.85;
                    dockerLayoutTransform.y = 25;
                    
                    heroCard.innerStartAnim = false;
                    cpuCard.innerStartAnim = false;
                    gpuCard.innerStartAnim = false;
                    ramCard.innerStartAnim = false;
                    swapCard.innerStartAnim = false;
                    diskCard.innerStartAnim = false;
                }
            }
        }

        readonly property var _visList: [
            true, // Hero Card
            true, // CPU/GPU Cards
            true, // RAM Pill
            Config.options.bar.resources.alwaysShowSwap, // SWAP Pill
            true, // Disk Pill
            Config.options.bar.resources.showDocker // Docker
        ]

        function getDelay(index) {
            let visIndex = 0;
            for (let i = 0; i < index; i++) {
                if (_visList[i]) visIndex++;
            }
            const delays = [40, 100, 160, 220, 280, 340];
            return delays[Math.min(visIndex, delays.length - 1)];
        }

        // Hero Card
        Rectangle {
            id: heroCard
            implicitWidth: 380
            implicitHeight: 140
            radius: Appearance.rounding.large
            color: Appearance.colors.colPrimaryContainer

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: heroCardTransform
                y: 25
            }
            
            SequentialAnimation {
                id: heroCardAnim
                PauseAnimation { duration: contentLayout.getDelay(0) }
                ParallelAnimation {
                    NumberAnimation { target: heroCard; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: heroCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: heroCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            property bool innerStartAnim: false
            onInnerStartAnimChanged: {
                if (innerStartAnim) {
                    heroShapeWrapper.opacity = 0.0;
                    heroShapeWrapperScale.xScale = 0.8;
                    heroShapeWrapperScale.yScale = 0.8;
                    heroShapeWrapperRotation.angle = -15;
                    heroShapeWrapperTranslate.x = -30;
                    distroPill.opacity = 0.0;
                    distroPillTranslate.x = 30;
                    cpuText.opacity = 0.0;
                    cpuText.scale = 0.9;
                    gpuText.opacity = 0.0;
                    
                    Qt.callLater(function() {
                        heroShapeAnim.start();
                        distroPillAnim.start();
                        cpuTextAnim.start();
                        gpuTextAnim.start();
                    });
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Item {
                    id: heroShapeWrapper
                    width: 74
                    height: 74
                    opacity: 1.0
                    
                    transform: [
                        Scale {
                            id: heroShapeWrapperScale
                            origin.x: 37; origin.y: 37
                            xScale: 1.0; yScale: 1.0
                        },
                        Rotation {
                            id: heroShapeWrapperRotation
                            origin.x: 37; origin.y: 37
                            angle: 0
                        },
                        Translate {
                            id: heroShapeWrapperTranslate
                            x: 0
                        }
                    ]
                    
                    SequentialAnimation {
                        id: heroShapeAnim
                        PauseAnimation { duration: 80 }
                        ParallelAnimation {
                            NumberAnimation { target: heroShapeWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: heroShapeWrapperScale; property: "xScale"; from: 0.8; to: 1.0; duration: 420; easing.type: Easing.OutBack }
                            NumberAnimation { target: heroShapeWrapperScale; property: "yScale"; from: 0.8; to: 1.0; duration: 420; easing.type: Easing.OutBack }
                            NumberAnimation { target: heroShapeWrapperRotation; property: "angle"; from: -15; to: 0; duration: 420; easing.type: Easing.OutCubic }
                            NumberAnimation { target: heroShapeWrapperTranslate; property: "x"; from: -30; to: 0; duration: 420; easing.type: Easing.OutCubic }
                        }
                    }

                    MaterialShape {
                        shapeString: "Cookie9Sided"
                        implicitSize: 74
                        color: Appearance.m3colors.m3primary
                        anchors.centerIn: parent

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "laptop_chromebook"
                            iconSize: 36
                            color: Appearance.m3colors.m3onPrimary
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight
                    spacing: 4

                    Rectangle {
                        id: distroPill
                        Layout.alignment: Qt.AlignRight
                        color: Appearance.colors.colPrimary
                        radius: Appearance.rounding.full
                        implicitWidth: distroRow.implicitWidth + 24
                        implicitHeight: 28
                        opacity: 1.0
                        
                        transform: Translate {
                            id: distroPillTranslate
                            x: 0
                        }
                        
                        SequentialAnimation {
                            id: distroPillAnim
                            PauseAnimation { duration: 120 }
                            ParallelAnimation {
                                NumberAnimation { target: distroPill; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                NumberAnimation { target: distroPillTranslate; property: "x"; from: 30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            }
                        }

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
                            id: cpuText
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.cleanCpu(ResourceUsage.cpuModel)
                            font.pixelSize: 24
                            font.weight: Font.Black
                            color: Appearance.colors.colOnPrimaryContainer
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            opacity: 1.0
                            scale: 1.0
                            
                            SequentialAnimation {
                                id: cpuTextAnim
                                PauseAnimation { duration: 160 }
                                ParallelAnimation {
                                    NumberAnimation { target: cpuText; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                    NumberAnimation { target: cpuText; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        StyledText {
                            id: gpuText
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: root.cleanGpu(ResourceUsage.gpuModel)
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimaryContainer
                            opacity: 0.7
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            
                            SequentialAnimation {
                                id: gpuTextAnim
                                PauseAnimation { duration: 200 }
                                NumberAnimation { target: gpuText; property: "opacity"; from: 0.0; to: 0.7; duration: 320 }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            id: cpuGpuCardsRow
            implicitWidth: 380
            spacing: 12

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: cpuGpuCardsRowTransform
                y: 25
            }
            
            SequentialAnimation {
                id: cpuGpuCardsRowAnim
                PauseAnimation { duration: contentLayout.getDelay(1) }
                ParallelAnimation {
                    NumberAnimation { target: cpuGpuCardsRow; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: cpuGpuCardsRow; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: cpuGpuCardsRowTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            // CPU Card
            Rectangle {
                id: cpuCard
                Layout.fillWidth: true
                implicitHeight: 165
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                property bool innerStartAnim: false
                onInnerStartAnimChanged: {
                    if (innerStartAnim) {
                        cpuIconWrapper.opacity = 0.0;
                        cpuIconWrapperScale.xScale = 0.8;
                        cpuIconWrapperScale.yScale = 0.8;
                        cpuIconWrapperRotation.angle = -10;
                        cpuTempRow.opacity = 0.0;
                        cpuTempRowTranslate.x = 20;
                        cpuLabel.opacity = 0.0;
                        cpuValue.opacity = 0.0;
                        cpuValue.scale = 0.9;
                        cpuProgress.width = 0;
                        
                        Qt.callLater(function() {
                            cpuIconAnim.start();
                            cpuTempAnim.start();
                            cpuLabelAnim.start();
                            cpuValueAnim.start();
                            cpuProgressAnim.start();
                        });
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Item {
                            id: cpuIconWrapper
                            width: 32
                            height: 32
                            opacity: 1.0
                            
                            transform: [
                                Scale {
                                    id: cpuIconWrapperScale
                                    origin.x: 16; origin.y: 16
                                    xScale: 1.0; yScale: 1.0
                                },
                                Rotation {
                                    id: cpuIconWrapperRotation
                                    origin.x: 16; origin.y: 16
                                    angle: 0
                                }
                            ]
                            
                            SequentialAnimation {
                                id: cpuIconAnim
                                PauseAnimation { duration: 60 }
                                ParallelAnimation {
                                    NumberAnimation { target: cpuIconWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                                    NumberAnimation { target: cpuIconWrapperScale; property: "xScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: cpuIconWrapperScale; property: "yScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: cpuIconWrapperRotation; property: "angle"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                }
                            }
                            
                            MaterialSymbol {
                                text: "memory"
                                iconSize: 32
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.8
                                anchors.centerIn: parent
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            id: cpuTempRow
                            spacing: 4
                            opacity: 1.0
                            
                            transform: Translate {
                                id: cpuTempRowTranslate
                                x: 0
                            }
                            
                            SequentialAnimation {
                                id: cpuTempAnim
                                PauseAnimation { duration: 100 }
                                ParallelAnimation {
                                    NumberAnimation { target: cpuTempRow; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                                    NumberAnimation { target: cpuTempRowTranslate; property: "x"; from: 20; to: 0; duration: 320; easing.type: Easing.OutCubic }
                                }
                            }
                            
                            MaterialSymbol {
                                text: "thermostat"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Config.options.bar.weather.useUSCS
                                      ? Math.round(ResourceUsage.cpuTemp * 1.8 + 32) + "°F"
                                      : Math.round(ResourceUsage.cpuTemp) + "°C"
                                  font.pixelSize: Appearance.font.pixelSize.small
                                  font.weight: Font.Bold
                                  color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            id: cpuLabel
                            text: "CPU Usage"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.6
                            
                            SequentialAnimation {
                                id: cpuLabelAnim
                                PauseAnimation { duration: 140 }
                                NumberAnimation { target: cpuLabel; property: "opacity"; from: 0.0; to: 0.6; duration: 250 }
                            }
                        }

                        StyledText {
                            id: cpuValue
                            text: Math.round(ResourceUsage.cpuUsage * 100) + "%"
                            font.pixelSize: 36
                            font.weight: Font.Black
                            color: Appearance.colors.colOnLayer1
                            opacity: 1.0
                            scale: 1.0
                            
                            SequentialAnimation {
                                id: cpuValueAnim
                                PauseAnimation { duration: 180 }
                                ParallelAnimation {
                                    NumberAnimation { target: cpuValue; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                    NumberAnimation { target: cpuValue; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 4
                            
                            StyledProgressBar {
                                id: cpuProgress
                                width: parent.width
                                height: 4
                                value: ResourceUsage.cpuUsage
                                wavy: true
                                highlightColor: Appearance.colors.colPrimary
                                trackColor: Appearance.colors.colLayer0Border
                                
                                SequentialAnimation {
                                    id: cpuProgressAnim
                                    PauseAnimation { duration: 220 }
                                    NumberAnimation { target: cpuProgress; property: "width"; from: 0; to: cpuProgress.parent.width; duration: 450; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }

            // GPU Card
            Rectangle {
                id: gpuCard
                Layout.fillWidth: true
                implicitHeight: 165
                radius: Appearance.rounding.large
                color: Appearance.colors.colSurfaceContainerHigh

                property bool innerStartAnim: false
                onInnerStartAnimChanged: {
                    if (innerStartAnim) {
                        gpuIconWrapper.opacity = 0.0;
                        gpuIconWrapperScale.xScale = 0.8;
                        gpuIconWrapperScale.yScale = 0.8;
                        gpuIconWrapperRotation.angle = -10;
                        gpuTempRow.opacity = 0.0;
                        gpuTempRowTranslate.x = 20;
                        gpuLabel.opacity = 0.0;
                        gpuValue.opacity = 0.0;
                        gpuValue.scale = 0.9;
                        gpuProgress.width = 0;
                        
                        Qt.callLater(function() {
                            gpuIconAnim.start();
                            gpuTempAnim.start();
                            gpuLabelAnim.start();
                            gpuValueAnim.start();
                            gpuProgressAnim.start();
                        });
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Item {
                            id: gpuIconWrapper
                            width: 32
                            height: 32
                            opacity: 1.0
                            
                            transform: [
                                Scale {
                                    id: gpuIconWrapperScale
                                    origin.x: 16; origin.y: 16
                                    xScale: 1.0; yScale: 1.0
                                },
                                Rotation {
                                    id: gpuIconWrapperRotation
                                    origin.x: 16; origin.y: 16
                                    angle: 0
                                }
                            ]
                            
                            SequentialAnimation {
                                id: gpuIconAnim
                                PauseAnimation { duration: 60 }
                                ParallelAnimation {
                                    NumberAnimation { target: gpuIconWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                                    NumberAnimation { target: gpuIconWrapperScale; property: "xScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: gpuIconWrapperScale; property: "yScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                                    NumberAnimation { target: gpuIconWrapperRotation; property: "angle"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                                }
                            }
                            
                            MaterialSymbol {
                                text: "videogame_asset"
                                iconSize: 32
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.8
                                anchors.centerIn: parent
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            id: gpuTempRow
                            spacing: 4
                            opacity: 1.0
                            
                            transform: Translate {
                                id: gpuTempRowTranslate
                                x: 0
                            }
                            
                            SequentialAnimation {
                                id: gpuTempAnim
                                PauseAnimation { duration: 100 }
                                ParallelAnimation {
                                    NumberAnimation { target: gpuTempRow; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                                    NumberAnimation { target: gpuTempRowTranslate; property: "x"; from: 20; to: 0; duration: 320; easing.type: Easing.OutCubic }
                                }
                            }
                            
                            MaterialSymbol {
                                text: "thermostat"
                                iconSize: 16
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                text: Config.options.bar.weather.useUSCS
                                      ? Math.round(ResourceUsage.gpuTemp * 1.8 + 32) + "°F"
                                      : Math.round(ResourceUsage.gpuTemp) + "°C"
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        StyledText {
                            id: gpuLabel
                            text: "GPU Usage"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                            opacity: 0.6
                            
                            SequentialAnimation {
                                id: gpuLabelAnim
                                PauseAnimation { duration: 140 }
                                NumberAnimation { target: gpuLabel; property: "opacity"; from: 0.0; to: 0.6; duration: 250 }
                            }
                        }

                        StyledText {
                            id: gpuValue
                            text: Math.round(ResourceUsage.gpuUsage * 100) + "%"
                            font.pixelSize: 36
                            font.weight: Font.Black
                            color: Appearance.colors.colOnLayer1
                            opacity: 1.0
                            scale: 1.0
                            
                            SequentialAnimation {
                                id: gpuValueAnim
                                PauseAnimation { duration: 180 }
                                ParallelAnimation {
                                    NumberAnimation { target: gpuValue; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                                    NumberAnimation { target: gpuValue; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: 4
                            
                            StyledProgressBar {
                                id: gpuProgress
                                width: parent.width
                                height: 4
                                value: ResourceUsage.gpuUsage
                                wavy: true
                                highlightColor: Appearance.colors.colPrimary
                                trackColor: Appearance.colors.colLayer0Border
                                
                                SequentialAnimation {
                                    id: gpuProgressAnim
                                    PauseAnimation { duration: 220 }
                                    NumberAnimation { target: gpuProgress; property: "width"; from: 0; to: gpuProgress.parent.width; duration: 450; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }
        }

        // RAM Pill
        Rectangle {
            id: ramCard
            Layout.fillWidth: true
            implicitHeight: 64
            radius: Appearance.rounding.full

            readonly property real _percent: ResourceUsage.memoryUsedPercentage
            readonly property color _fillColor: Appearance.colors.colSecondaryContainer

            color: ColorUtils.applyAlpha(_fillColor, 0.25)

            layer.enabled: true
            layer.samples: 4
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: ramCard.width
                    height: ramCard.height
                    radius: ramCard.radius
                }
            }

            Rectangle {
                id: ramFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: parent.width * parent._percent
                color: parent._fillColor

                Behavior on width {
                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                }
            }

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: ramCardTransform
                y: 25
            }
            
            SequentialAnimation {
                id: ramCardAnim
                PauseAnimation { duration: contentLayout.getDelay(2) }
                ParallelAnimation {
                    NumberAnimation { target: ramCard; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: ramCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: ramCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            property bool innerStartAnim: false
            onInnerStartAnimChanged: {
                if (innerStartAnim) {
                    ramShapeWrapper.opacity = 0.0;
                    ramShapeWrapperScale.xScale = 0.8;
                    ramShapeWrapperScale.yScale = 0.8;
                    ramShapeWrapperRotation.angle = -10;
                    ramShapeWrapperTranslate.x = -30;
                    ramLabel.opacity = 0.0;
                    ramUsage.opacity = 0.0;
                    ramPercent.opacity = 0.0;
                    ramPercent.scale = 0.9;
                    
                    Qt.callLater(function() {
                        ramShapeAnim.start();
                        ramLabelAnim.start();
                        ramUsageAnim.start();
                        ramPercentAnim.start();
                    });
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Item {
                    id: ramShapeWrapper
                    width: 40
                    height: 40
                    opacity: 1.0
                    
                    transform: [
                        Scale {
                            id: ramShapeWrapperScale
                            origin.x: 20; origin.y: 20
                            xScale: 1.0; yScale: 1.0
                        },
                        Rotation {
                            id: ramShapeWrapperRotation
                            origin.x: 20; origin.y: 20
                            angle: 0
                        },
                        Translate {
                            id: ramShapeWrapperTranslate
                            x: 0
                        }
                    ]
                    
                    SequentialAnimation {
                        id: ramShapeAnim
                        PauseAnimation { duration: 60 }
                        ParallelAnimation {
                            NumberAnimation { target: ramShapeWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                            NumberAnimation { target: ramShapeWrapperScale; property: "xScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: ramShapeWrapperScale; property: "yScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: ramShapeWrapperRotation; property: "angle"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ramShapeWrapperTranslate; property: "x"; from: -30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                        }
                    }

                    MaterialShape {
                        shapeString: "Circle"
                        implicitSize: 40
                        color: Appearance.colors.colLayer4
                        anchors.centerIn: parent

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "memory_alt"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer4
                        }
                    }
                }

                ColumnLayout {
                    spacing: -2
                    StyledText {
                        id: ramLabel
                        text: "RAM"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: ramLabelAnim
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: ramLabel; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                        }
                    }
                    StyledText {
                        id: ramUsage
                        text: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: ramUsageAnim
                            PauseAnimation { duration: 160 }
                            NumberAnimation { target: ramUsage; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    id: ramPercent
                    text: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                    opacity: 1.0
                    scale: 1.0
                    
                    SequentialAnimation {
                        id: ramPercentAnim
                        PauseAnimation { duration: 200 }
                        ParallelAnimation {
                            NumberAnimation { target: ramPercent; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: ramPercent; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        }
                    }
                }
            }
        }

        // SWAP Pill
        Rectangle {
            id: swapCard
            visible: Config.options.bar.resources.alwaysShowSwap
            Layout.fillWidth: true
            implicitHeight: 64
            radius: Appearance.rounding.full

            readonly property real _percent: ResourceUsage.swapUsedPercentage
            readonly property color _fillColor: Appearance.colors.colSecondaryContainer

            color: ColorUtils.applyAlpha(_fillColor, 0.25)

            layer.enabled: true
            layer.samples: 4
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swapCard.width
                    height: swapCard.height
                    radius: swapCard.radius
                }
            }

            Rectangle {
                id: swapFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: parent.width * parent._percent
                color: parent._fillColor

                Behavior on width {
                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                }
            }

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: swapCardTransform
                y: 25
            }
            
            SequentialAnimation {
                id: swapCardAnim
                PauseAnimation { duration: contentLayout.getDelay(3) }
                ParallelAnimation {
                    NumberAnimation { target: swapCard; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: swapCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: swapCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            property bool innerStartAnim: false
            onInnerStartAnimChanged: {
                if (innerStartAnim) {
                    swapShapeWrapper.opacity = 0.0;
                    swapShapeWrapperScale.xScale = 0.8;
                    swapShapeWrapperScale.yScale = 0.8;
                    swapShapeWrapperRotation.angle = -10;
                    swapShapeWrapperTranslate.x = -30;
                    swapLabel.opacity = 0.0;
                    swapUsage.opacity = 0.0;
                    swapPercent.opacity = 0.0;
                    swapPercent.scale = 0.9;
                    
                    Qt.callLater(function() {
                        swapShapeAnim.start();
                        swapLabelAnim.start();
                        swapUsageAnim.start();
                        swapPercentAnim.start();
                    });
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Item {
                    id: swapShapeWrapper
                    width: 40
                    height: 40
                    opacity: 1.0
                    
                    transform: [
                        Scale {
                            id: swapShapeWrapperScale
                            origin.x: 20; origin.y: 20
                            xScale: 1.0; yScale: 1.0
                        },
                        Rotation {
                            id: swapShapeWrapperRotation
                            origin.x: 20; origin.y: 20
                            angle: 0
                        },
                        Translate {
                            id: swapShapeWrapperTranslate
                            x: 0
                        }
                    ]
                    
                    SequentialAnimation {
                        id: swapShapeAnim
                        PauseAnimation { duration: 60 }
                        ParallelAnimation {
                            NumberAnimation { target: swapShapeWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                            NumberAnimation { target: swapShapeWrapperScale; property: "xScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: swapShapeWrapperScale; property: "yScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: swapShapeWrapperRotation; property: "angle"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            NumberAnimation { target: swapShapeWrapperTranslate; property: "x"; from: -30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                        }
                    }

                    MaterialShape {
                        shapeString: "Circle"
                        implicitSize: 40
                        color: Appearance.colors.colLayer4
                        anchors.centerIn: parent

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "swap_horiz"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer4
                        }
                    }
                }

                ColumnLayout {
                    spacing: -2
                    StyledText {
                        id: swapLabel
                        text: "SWAP"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: swapLabelAnim
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: swapLabel; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                        }
                    }
                    StyledText {
                        id: swapUsage
                        text: (ResourceUsage.swapUsed / (1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.swapTotal / (1024 * 1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: swapUsageAnim
                            PauseAnimation { duration: 160 }
                            NumberAnimation { target: swapUsage; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    id: swapPercent
                    text: Math.round(ResourceUsage.swapUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                    opacity: 1.0
                    scale: 1.0
                    
                    SequentialAnimation {
                        id: swapPercentAnim
                        PauseAnimation { duration: 200 }
                        ParallelAnimation {
                            NumberAnimation { target: swapPercent; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: swapPercent; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        }
                    }
                }
            }
        }

        // Disk Pill
        Rectangle {
            id: diskCard
            Layout.fillWidth: true
            implicitHeight: 64
            radius: Appearance.rounding.full

            readonly property real _percent: ResourceUsage.diskUsedPercentage
            readonly property color _fillColor: Appearance.colors.colSecondaryContainer

            color: ColorUtils.applyAlpha(_fillColor, 0.25)

            layer.enabled: true
            layer.samples: 4
            layer.smooth: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: diskCard.width
                    height: diskCard.height
                    radius: diskCard.radius
                }
            }

            Rectangle {
                id: diskFill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                radius: parent.radius
                width: parent.width * parent._percent
                color: parent._fillColor

                Behavior on width {
                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                }
            }

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: diskCardTransform
                y: 25
            }
            
            SequentialAnimation {
                id: diskCardAnim
                PauseAnimation { duration: contentLayout.getDelay(4) }
                ParallelAnimation {
                    NumberAnimation { target: diskCard; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: diskCard; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: diskCardTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            property bool innerStartAnim: false
            onInnerStartAnimChanged: {
                if (innerStartAnim) {
                    diskShapeWrapper.opacity = 0.0;
                    diskShapeWrapperScale.xScale = 0.8;
                    diskShapeWrapperScale.yScale = 0.8;
                    diskShapeWrapperRotation.angle = -10;
                    diskShapeWrapperTranslate.x = -30;
                    diskLabel.opacity = 0.0;
                    diskUsage.opacity = 0.0;
                    diskPercent.opacity = 0.0;
                    diskPercent.scale = 0.9;
                    
                    Qt.callLater(function() {
                        diskShapeAnim.start();
                        diskLabelAnim.start();
                        diskUsageAnim.start();
                        diskPercentAnim.start();
                    });
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Item {
                    id: diskShapeWrapper
                    width: 40
                    height: 40
                    opacity: 1.0
                    
                    transform: [
                        Scale {
                            id: diskShapeWrapperScale
                            origin.x: 20; origin.y: 20
                            xScale: 1.0; yScale: 1.0
                        },
                        Rotation {
                            id: diskShapeWrapperRotation
                            origin.x: 20; origin.y: 20
                            angle: 0
                        },
                        Translate {
                            id: diskShapeWrapperTranslate
                            x: 0
                        }
                    ]
                    
                    SequentialAnimation {
                        id: diskShapeAnim
                        PauseAnimation { duration: 60 }
                        ParallelAnimation {
                            NumberAnimation { target: diskShapeWrapper; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                            NumberAnimation { target: diskShapeWrapperScale; property: "xScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: diskShapeWrapperScale; property: "yScale"; from: 0.8; to: 1.0; duration: 350; easing.type: Easing.OutBack }
                            NumberAnimation { target: diskShapeWrapperRotation; property: "angle"; from: -10; to: 0; duration: 350; easing.type: Easing.OutCubic }
                            NumberAnimation { target: diskShapeWrapperTranslate; property: "x"; from: -30; to: 0; duration: 350; easing.type: Easing.OutCubic }
                        }
                    }

                    MaterialShape {
                        shapeString: "Circle"
                        implicitSize: 40
                        color: Appearance.colors.colLayer4
                        anchors.centerIn: parent

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "hard_drive"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer4
                        }
                    }
                }

                ColumnLayout {
                    spacing: -2
                    StyledText {
                        id: diskLabel
                        text: "DISK"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: diskLabelAnim
                            PauseAnimation { duration: 120 }
                            NumberAnimation { target: diskLabel; property: "opacity"; from: 0.0; to: 1.0; duration: 250 }
                        }
                    }
                    StyledText {
                        id: diskUsage
                        text: (ResourceUsage.diskUsed / (1024 * 1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.diskTotal / (1024 * 1024 * 1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 1.0
                        
                        SequentialAnimation {
                            id: diskUsageAnim
                            PauseAnimation { duration: 160 }
                            NumberAnimation { target: diskUsage; property: "opacity"; from: 0.0; to: 1.0; duration: 280 }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    id: diskPercent
                    text: Math.round(ResourceUsage.diskUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                    opacity: 1.0
                    scale: 1.0
                    
                    SequentialAnimation {
                        id: diskPercentAnim
                        PauseAnimation { duration: 200 }
                        ParallelAnimation {
                            NumberAnimation { target: diskPercent; property: "opacity"; from: 0.0; to: 1.0; duration: 300 }
                            NumberAnimation { target: diskPercent; property: "scale"; from: 0.9; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                        }
                    }
                }
            }
        }

        // ── Docker Integration ────────────────────────────────────────────
        ColumnLayout {
            id: dockerLayout
            Layout.fillWidth: true
            visible: Config.options.bar.resources.showDocker
            spacing: 12

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: dockerLayoutTransform
                y: 25
            }
            
            SequentialAnimation {
                id: dockerLayoutAnim
                PauseAnimation { duration: contentLayout.getDelay(5) }
                ParallelAnimation {
                    NumberAnimation { target: dockerLayout; property: "opacity"; to: 1.0; duration: 300 }
                    NumberAnimation { target: dockerLayout; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack }
                    NumberAnimation { target: dockerLayoutTransform; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                }
            }

            // ── Docker divider ────────────────────────────────────────────────
            RowLayout {
                implicitWidth: 380
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.08)
                }

                RowLayout {
                    spacing: 4
                    CustomIcon {
                        source: "docker.svg"
                        width: 12
                        height: 12
                        colorize: true
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.35
                    }
                    StyledText {
                        text: "Containers"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.35
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 1
                    color: Qt.rgba(Appearance.colors.colOnLayer1.r, Appearance.colors.colOnLayer1.g, Appearance.colors.colOnLayer1.b, 0.08)
                }
            }

            // ── Docker section ────────────────────────────────────────────────
            DockerSection {
                implicitWidth: 380
            }
        }
    }
}
