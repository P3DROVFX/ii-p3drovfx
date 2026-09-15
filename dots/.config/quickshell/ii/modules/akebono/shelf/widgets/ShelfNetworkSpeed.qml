pragma ComponentBehavior: Bound
import qs.services as Services
import qs.modules.akebono
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import "../../../ii/bar/shared/cards"

Item {
    id: root
    property real barHeight: 54
    property var shelf

    readonly property string displayMode: Config.options.bar.networkSpeed?.displayMode ?? "both"
    readonly property bool showIcon: Config.options.bar.networkSpeed?.showIcon ?? true
    readonly property bool iconOnRight: (Config.options.bar.networkSpeed?.iconPosition ?? "left") === "right"

    readonly property bool idle: Services.NetworkSpeed.downloadBytesPerSecond < 1000 && Services.NetworkSpeed.uploadBytesPerSecond < 1000
    property bool idleSuppressed: false
    onIdleChanged: {
        if (!idle) {
            idleTimer.stop();
            idleSuppressed = false;
        } else if (Config.options.bar.networkSpeed?.hideWhenIdle) {
            idleTimer.restart();
        }
    }

    implicitWidth: pill.implicitWidth
    implicitHeight: barHeight * 0.7
    Layout.alignment: Qt.AlignVCenter

    Timer {
        id: idleTimer
        interval: 10000
        onTriggered: root.idleSuppressed = true
    }

    Component.onCompleted: {
        Services.NetworkSpeed.register();
        if (root.shelf)
            root.shelf.registerChipAnchor(root);
    }
    Component.onDestruction: {
        Services.NetworkSpeed.unregister();
        if (root.shelf)
            root.shelf.unregisterChipAnchor(root);
    }
    onXChanged: if (root.shelf?.publishChip) root.shelf.publishChip()

    function formatRate(bytesPerSecond) {
        const decimal = (Config.options.bar.networkSpeed?.unit ?? "decimal") === "decimal";
        const units = decimal ? ["B/s", "KB/s", "MB/s", "GB/s"] : ["B/s", "KiB/s", "MiB/s", "GiB/s"];
        const step = decimal ? 1000 : 1024;
        let value = Math.max(0, Number(bytesPerSecond) || 0);
        let unitIndex = 0;
        while (value >= step && unitIndex < units.length - 1) {
            value /= step;
            unitIndex++;
        }
        const decimals = (unitIndex > 0 && value < 10) ? 1 : 0;
        return `${value.toFixed(decimals)} ${units[unitIndex]}`;
    }

    function formatBytes(bytes) {
        const decimal = (Config.options.bar.networkSpeed?.unit ?? "decimal") === "decimal";
        const units = decimal ? ["B", "KB", "MB", "GB", "TB"] : ["B", "KiB", "MiB", "GiB", "TiB"];
        const step = decimal ? 1000 : 1024;
        let value = Math.max(0, Number(bytes) || 0);
        let unitIndex = 0;
        while (value >= step && unitIndex < units.length - 1) {
            value /= step;
            unitIndex++;
        }
        return `${value.toFixed(unitIndex > 0 && value < 10 ? 1 : 0)} ${units[unitIndex]}`;
    }

    readonly property string connectionName: Services.Network.ethernet
        ? (Services.Network.networkName || Services.Translation.tr("Ethernet"))
        : (Services.Network.wifiStatus === "connected")
            ? (Services.Network.active?.ssid || Services.Network.networkName || Services.Translation.tr("Wi-Fi"))
            : Services.Translation.tr("Not connected")
    readonly property string connectionDetails: {
        if (Services.Network.ethernet)
            return Services.Translation.tr("Ethernet · Connected")
        if (Services.Network.wifiStatus === "connected") {
            const s = Services.Network.networkStrength > 0 ? ` · ${Services.Network.networkStrength}%` : ""
            return `${Services.Translation.tr("Wi-Fi")}${s}`
        }
        switch (Services.Network.wifiStatus) {
        case "connecting": return Services.Translation.tr("Connecting")
        case "limited": return Services.Translation.tr("Limited connection")
        case "disabled": return Services.Translation.tr("Wi-Fi disabled")
        default: return Services.Translation.tr("Disconnected")
        }
    }

    TextMetrics {
        id: rateMetrics
        text: root.formatRate(999 * ((Config.options.bar.networkSpeed?.unit ?? "decimal") === "decimal" ? 1000 : 1024))
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.Medium
    }

    component SpeedLine: RowLayout {
        id: speedLine
        required property string iconName
        required property real rate
        required property color accentColor

        readonly property string rateText: root.formatRate(rate)
        readonly property bool textVisible: !root.idleSuppressed || rate >= 1000

        layoutDirection: root.iconOnRight ? Qt.RightToLeft : Qt.LeftToRight
        spacing: 4

        MaterialSymbol {
            visible: root.showIcon
            text: speedLine.iconName
            iconSize: 18
            color: speedLine.accentColor
            opacity: speedLine.rate > 0 ? 1 : 0.6

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            visible: speedLine.textVisible
            Layout.preferredWidth: rateMetrics.width
            horizontalAlignment: Text.AlignHCenter
            text: speedLine.rateText
            color: speedLine.accentColor
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            font.features: {
                "tnum": 1
            }
        }
    }

    ShelfPill {
        id: pill
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: speedColumn.implicitWidth + 18
        implicitHeight: root.barHeight * 0.7
        hovered: netMouse.containsMouse

        ColumnLayout {
            id: speedColumn
            anchors.centerIn: parent
            spacing: -2

            SpeedLine {
                iconName: "arrow_upward"
                rate: Services.NetworkSpeed.uploadBytesPerSecond
                accentColor: Appearance.colors.colTertiary
                visible: root.displayMode !== "download"
                Layout.alignment: Qt.AlignHCenter
            }
            SpeedLine {
                iconName: "arrow_downward"
                rate: Services.NetworkSpeed.downloadBytesPerSecond
                accentColor: Appearance.colors.colPrimary
                visible: root.displayMode !== "upload"
                Layout.alignment: Qt.AlignHCenter
            }
        }

        MouseArea {
            id: netMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: ms => {
                if (ms.button === Qt.LeftButton) {
                    if (root.shelf)
                        root.shelf.toggleChipPopup(netPopoverComp, 384, 200, root, Appearance.rounding.normal);
                    ms.accepted = false;
                }
            }
            onClicked: ms => {
                if (ms.button === Qt.RightButton) {
                    const modes = ["both", "download", "upload"];
                    const next = modes[(modes.indexOf(root.displayMode) + 1) % modes.length];
                    if (Config.options.bar.networkSpeed) {
                        Config.options.bar.networkSpeed.displayMode = next;
                    }
                }
            }
        }
    }

    Component {
        id: netPopoverComp
        ShelfPopupSurface {
            ColumnLayout {
                id: popCol
                anchors.fill: parent
                spacing: 10
                implicitWidth: 344

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Rectangle {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colPrimaryContainer

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: Services.Network.materialSymbol ?? "lan"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: -3

                        StyledText {
                            Layout.fillWidth: true
                            text: root.connectionName
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: root.connectionDetails
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.6
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    component SpeedCard: Rectangle {
                        id: card
                        Layout.fillWidth: true
                        implicitHeight: cardContent.implicitHeight + 22
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colSurfaceContainerHigh

                        required property string label
                        required property string iconName
                        required property real rate
                        required property color accentColor

                        ColumnLayout {
                            id: cardContent
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                MaterialSymbol {
                                    text: card.iconName
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: card.accentColor
                                }

                                StyledText {
                                    text: card.label
                                    color: Appearance.colors.colOnSurfaceVariant
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                }

                                Item { Layout.fillWidth: true }
                            }

                            StyledText {
                                text: root.formatRate(card.rate)
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.xlarge
                                font.weight: Font.DemiBold
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }
                    }

                    SpeedCard {
                        label: Services.Translation.tr("Download")
                        iconName: "arrow_downward"
                        rate: Services.NetworkSpeed.downloadBytesPerSecond
                        accentColor: Appearance.colors.colPrimary
                    }

                    SpeedCard {
                        label: Services.Translation.tr("Upload")
                        iconName: "arrow_upward"
                        rate: Services.NetworkSpeed.uploadBytesPerSecond
                        accentColor: Appearance.colors.colTertiary
                    }
                }

                InfoPill {
                    id: usagePill
                    Layout.fillWidth: true
                    icon: "data_usage"
                    containerColor: Appearance.colors.colTertiaryContainer
                    shapeColor: Appearance.colors.colTertiary
                    symbolColor: Appearance.colors.colOnTertiary
                    textColor: Appearance.colors.colOnTertiaryContainer

                    textContent: StyledText {
                        anchors.centerIn: parent
                        text: `${Services.Translation.tr("This session")}: ${root.formatBytes(Services.NetworkSpeed.downloadedBytes + Services.NetworkSpeed.uploadedBytes)}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
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
}