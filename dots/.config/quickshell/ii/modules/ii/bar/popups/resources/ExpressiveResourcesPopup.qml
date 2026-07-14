import qs.modules.ii.bar.shared
import qs.modules.ii.bar
import qs.modules.ii.bar.widgets.resources
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.services
import qs.modules.common
import qs.modules.common.widgets
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
                
                Qt.callLater(function() {
                    heroCardAnim.start();
                    cpuGpuCardsRowAnim.start();
                    ramCardAnim.start();
                    swapCardAnim.start();
                    diskCardAnim.start();
                    dockerLayoutAnim.start();
                });
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

                Item {
                    Layout.fillWidth: true
                }

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
                        Item {
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            spacing: 4
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
                        Item {
                            Layout.fillWidth: true
                        }
                        RowLayout {
                            spacing: 4
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
            id: ramCard
            implicitWidth: 380
            implicitHeight: 64
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer

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
                        text: "memory_alt"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer4
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
                        text: (ResourceUsage.memoryUsed / (1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.memoryTotal / (1024 * 1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: Math.round(ResourceUsage.memoryUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                }
            }
        }

        // SWAP Pill
        Rectangle {
            id: swapCard
            visible: Config.options.bar.resources.alwaysShowSwap
            implicitWidth: 380
            implicitHeight: 64
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer

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
                        text: "swap_horiz"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer4
                    }
                }

                ColumnLayout {
                    spacing: -2
                    StyledText {
                        text: "SWAP"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        text: (ResourceUsage.swapUsed / (1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.swapTotal / (1024 * 1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: Math.round(ResourceUsage.swapUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
                }
            }
        }

        // Disk Pill
        Rectangle {
            id: diskCard
            implicitWidth: 380
            implicitHeight: 64
            radius: Appearance.rounding.full
            color: Appearance.colors.colSecondaryContainer

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
                        text: (ResourceUsage.diskUsed / (1024 * 1024 * 1024)).toFixed(1) + " GB / " + (ResourceUsage.diskTotal / (1024 * 1024 * 1024)).toFixed(0) + " GB"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                StyledText {
                    text: Math.round(ResourceUsage.diskUsedPercentage * 100) + "%"
                    font.pixelSize: 24
                    font.weight: Font.Black
                    color: Appearance.colors.colOnSecondaryContainer
                    Layout.rightMargin: 12
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
