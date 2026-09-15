import QtQuick
import QtQuick.Layouts
import qs.services as Services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.popups.network

MouseArea {
    id: root

    property bool vertical: false

    readonly property string displayMode: Config.options.bar.networkSpeed?.displayMode ?? "both"
    readonly property bool showIcon: Config.options.bar.networkSpeed?.showIcon ?? true
    readonly property bool iconOnRight: (Config.options.bar.networkSpeed?.iconPosition ?? "left") === "right"

    // Idle hiding with a grace period so brief pauses don't flicker the widget
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

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : speedColumn.implicitWidth + 12
    implicitHeight: vertical ? speedColumn.implicitHeight + 8 : Appearance.sizes.baseBarHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onPressed: event => {
        if (event.button === Qt.RightButton) {
            const modes = ["both", "download", "upload"];
            const next = modes[(modes.indexOf(root.displayMode) + 1) % modes.length];
            if (Config.options.bar.networkSpeed) {
                Config.options.bar.networkSpeed.displayMode = next;
            }
        }
        // Left click is handled by the popup when click-to-show is enabled
    }

    Timer {
        id: idleTimer
        interval: 10000
        onTriggered: root.idleSuppressed = true
    }

    Component.onCompleted: Services.NetworkSpeed.register()
    Component.onDestruction: Services.NetworkSpeed.unregister()

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

        // Round to 1 significant-ish digit; below the first unit show plain bytes per second
        const decimals = (unitIndex > 0 && value < 10) ? 1 : 0;
        return `${value.toFixed(decimals)} ${units[unitIndex]}`;
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

            rotation: root.vertical ? -90 : 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        StyledText {
            visible: !root.vertical && speedLine.textVisible
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

    ColumnLayout {
        id: speedColumn
        anchors.centerIn: parent
        spacing: root.vertical ? 6 : -2

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

    NetworkSpeedPopup {
        hoverTarget: root
    }
}
