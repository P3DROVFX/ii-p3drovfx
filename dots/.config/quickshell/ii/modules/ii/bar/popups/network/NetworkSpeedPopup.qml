import qs.modules.ii.bar.shared
import "../../shared/cards"
import qs.services
import qs.services as Services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    popupRadius: Appearance.rounding.large

    readonly property var network: Services.NetworkSpeed

    function formatRate(bytesPerSecond) {
        const units = root.binaryUnits ? ["B/s", "KiB/s", "MiB/s", "GiB/s"] : ["B/s", "KB/s", "MB/s", "GB/s"];
        const step = root.binaryUnits ? 1024 : 1000;
        let value = Math.max(0, Number(bytesPerSecond) || 0);
        let unitIndex = 0;
        while (value >= step && unitIndex < units.length - 1) {
            value /= step;
            unitIndex++;
        }
        return `${value.toFixed(unitIndex > 0 && value < 10 ? 1 : 0)} ${units[unitIndex]}`;
    }

    function formatBytes(bytes) {
        const units = root.binaryUnits ? ["B", "KiB", "MiB", "GiB", "TiB"] : ["B", "KB", "MB", "GB", "TB"];
        const step = root.binaryUnits ? 1024 : 1000;
        let value = Math.max(0, Number(bytes) || 0);
        let unitIndex = 0;
        while (value >= step && unitIndex < units.length - 1) {
            value /= step;
            unitIndex++;
        }
        return `${value.toFixed(unitIndex > 0 && value < 10 ? 1 : 0)} ${units[unitIndex]}`;
    }

    readonly property bool binaryUnits: (Config.options.bar.networkSpeed?.unit ?? "decimal") === "binary"

    contentItem: ColumnLayout {
        id: columnLayout
        spacing: 10

        function getDelay(index) {
            const delays = [40, 100, 160];
            return delays[Math.min(index, delays.length - 1)];
        }

        property int _entranceGeneration: 0
        readonly property bool startAnim: root.opened && root.popupOpenProgress > 0.6

        function resetContentEntrance() {
            _entranceGeneration++;

            heroAnim.stop();
            pillsAnim.stop();

            networkHero.opacity = 0.0;
            networkHero.scale = 0.85;
            heroTransform.y = 25;

            infoColumn.opacity = 0.0;
            infoColumn.scale = 0.85;
            infoColumnTransform.y = 25;
        }

        function startContentEntrance() {
            const generation = _entranceGeneration;
            Qt.callLater(function () {
                if (!root.opened || !columnLayout.startAnim || generation !== _entranceGeneration)
                    return;

                heroAnim.start();
                pillsAnim.start();

                // Chain the pills' internal animations after the outer bounce,
                // like the clock popup does for its InfoPills
                downloadPill.startAnim = false;
                uploadPill.startAnim = false;
                if (!root.compactMode)
                    usagePill.startAnim = false;
                Qt.callLater(function () {
                    downloadPill.startAnim = true;
                    uploadPill.startAnim = true;
                    if (!root.compactMode)
                        usagePill.startAnim = true;
                });
            });
        }

        onStartAnimChanged: {
            if (startAnim) {
                resetContentEntrance();
                startContentEntrance();
            }
        }

        Connections {
            target: root
            function onPopupOpenProgressChanged() {
                if (root.popupOpenProgress === 0.0) {
                    columnLayout.resetContentEntrance();
                }
            }
        }

        // ── Connection hero ──────────────────────────────────────────────────
        HeroCard {
            id: networkHero
            compactMode: true
            adaptiveWidth: true
            margins: 14
            iconSize: 64
            iconFontSize: 30
            icon: Network.materialSymbol ?? "lan"
            title: Network.ethernet ? Translation.tr("Ethernet") : Translation.tr("Wi-Fi")
            subtitle: Network.networkName || Translation.tr("Connected")

            pillIcon: !Network.ethernet ? "signal_wifi_4_bar" : ""
            pillText: !Network.ethernet ? `${Network.active?.strength ?? 0}%` : ""
            startAnim: columnLayout.startAnim

            Layout.alignment: Qt.AlignHCenter

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: heroTransform
                y: 25
            }

            SequentialAnimation {
                id: heroAnim
                PauseAnimation {
                    duration: columnLayout.getDelay(0)
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: networkHero
                        property: "opacity"
                        to: 1.0
                        duration: 300
                    }
                    NumberAnimation {
                        target: networkHero
                        property: "scale"
                        to: 1.0
                        duration: 380
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: heroTransform
                        property: "y"
                        to: 0
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ── Throughput and usage pills ───────────────────────────────────────
        ColumnLayout {
            id: infoColumn
            visible: true
            spacing: 8
            Layout.fillWidth: true

            implicitWidth: 300

            opacity: 0.0
            scale: 0.85
            transform: Translate {
                id: infoColumnTransform
                y: 25
            }

            SequentialAnimation {
                id: pillsAnim
                PauseAnimation {
                    duration: columnLayout.getDelay(1)
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: infoColumn
                        property: "opacity"
                        to: 1.0
                        duration: 300
                    }
                    NumberAnimation {
                        target: infoColumn
                        property: "scale"
                        to: 1.0
                        duration: 380
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        target: infoColumnTransform
                        property: "y"
                        to: 0
                        duration: 380
                        easing.type: Easing.OutCubic
                    }
                }
            }

            component SpeedPill: InfoPill {
                id: speedPill

                property string label
                property real rate

                implicitWidth: 300
                shapeString: "Circle"

                textContent: StyledText {
                    anchors.centerIn: parent
                    text: `${speedPill.label}: ${root.formatRate(speedPill.rate)}`
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                    color: speedPill.textColor
                }
            }

            SpeedPill {
                id: downloadPill
                Layout.fillWidth: true
                label: Translation.tr("Download")
                rate: root.network.downloadBytesPerSecond
                icon: "download"
                containerColor: Appearance.colors.colPrimaryContainer
                shapeColor: Appearance.colors.colPrimary
                symbolColor: Appearance.colors.colOnPrimary
                textColor: Appearance.colors.colOnPrimaryContainer
            }

            SpeedPill {
                id: uploadPill
                Layout.fillWidth: true
                label: Translation.tr("Upload")
                rate: root.network.uploadBytesPerSecond
                icon: "upload"
                containerColor: Appearance.colors.colSecondaryContainer
                shapeColor: Appearance.colors.colSecondary
                symbolColor: Appearance.colors.colOnSecondary
                textColor: Appearance.colors.colOnSecondaryContainer
            }

            InfoPill {
                id: usagePill
                visible: !root.compactMode
                Layout.fillWidth: true
                implicitWidth: 300
                icon: "data_usage"
                containerColor: Appearance.colors.colTertiaryContainer
                shapeColor: Appearance.colors.colTertiary
                symbolColor: Appearance.colors.colOnTertiary
                textColor: Appearance.colors.colOnTertiaryContainer

                textContent: StyledText {
                    anchors.centerIn: parent
                    text: `${Translation.tr("Usage")}: ${root.formatBytes(root.network.downloadedBytes + root.network.uploadedBytes)}`
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                    color: usagePill.textColor
                }
            }
        }
    }
}
