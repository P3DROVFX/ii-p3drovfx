pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One resource monitor as a fill card, ported from the desktop background's
 * ResourceFillCardsWidget: a container-coloured card whose level rises from the bottom
 * like liquid, with a circled icon, the metric's name and the reading as a large number.
 *
 * Unlike the background widget this one has no fixed size: it is given whatever the grid
 * hands it, from a 88x48 quarter of a 2x2 tile to half a 4x4 one, so every piece of its
 * chrome is derived from its own width and height and each line only appears once there
 * is room for it:
 *
 * | Card                    | What it shows                                  |
 * |-------------------------|------------------------------------------------|
 * | shorter than 74 px      | one row: icon, name (if wide), reading         |
 * | 74 px and taller        | badge, name, reading stacked                   |
 * | 104 px and taller       | + the detail line (temperature, used / total)  |
 * | 170 px, `detailed`      | + the metric's detail rows                     |
 *
 * The fill is two rectangles rather than a mask: an OpacityMask would hold an item-valued
 * property, which in the island's window is what pins a dead window and crashes the next
 * one (see the ConicalGradient case). The lower rectangle carries the card's radius so
 * the bottom corners match, and a square cap hides its rounded top edge while the level
 * is below the card's top rounding.
 */
Item {
    id: root

    /** cpu | ram | gpu | disk | swap */
    required property string metric
    /** The card's corner radius; the tile's radius when it is the whole tile. */
    property real radius: Appearance.rounding.large
    /** Give the metric its own detail rows when the card is tall enough. */
    property bool detailed: false

    // ── The metric ───────────────────────────────────────────────────────────
    readonly property real level: {
        switch (root.metric) {
        case "cpu": return ResourceUsage.cpuUsage;
        case "ram": return ResourceUsage.memoryUsedPercentage;
        case "disk": return ResourceUsage.diskUsedPercentage;
        case "gpu": return ResourceUsage.gpuUsage;
        case "swap": return ResourceUsage.swapUsedPercentage;
        }
        return 0;
    }
    readonly property int percent: Math.round(Math.max(0, Math.min(1, root.level)) * 100)
    readonly property real temperature: {
        switch (root.metric) {
        case "cpu": return ResourceUsage.cpuTemp;
        case "gpu": return ResourceUsage.gpuTemp;
        }
        return 0;
    }

    readonly property color accentColor: {
        switch (root.metric) {
        case "cpu": return Appearance.colors.colPrimary;
        case "ram": return Appearance.colors.colSecondary;
        case "disk": return Appearance.colors.colTertiary;
        case "gpu": return Appearance.m3colors.m3success;
        case "swap": return Appearance.colors.colOnSurfaceVariant;
        }
        return Appearance.colors.colPrimary;
    }
    readonly property color containerColor: {
        switch (root.metric) {
        case "cpu": return Appearance.colors.colPrimaryContainer;
        case "ram": return Appearance.colors.colSecondaryContainer;
        case "disk": return Appearance.colors.colTertiaryContainer;
        case "gpu": return Appearance.m3colors.m3successContainer;
        case "swap": return Appearance.colors.colSurfaceContainerHighest;
        }
        return Appearance.colors.colPrimaryContainer;
    }

    readonly property string symbol: {
        switch (root.metric) {
        case "cpu": return "memory";
        case "ram": return "memory_alt";
        case "disk": return "hard_drive";
        case "gpu": return "developer_board";
        case "swap": return "swap_horiz";
        }
        return "memory";
    }
    readonly property string shortTitle: {
        switch (root.metric) {
        case "cpu": return Translation.tr("CPU");
        case "ram": return Translation.tr("RAM");
        case "disk": return Translation.tr("Disk");
        case "gpu": return Translation.tr("GPU");
        case "swap": return Translation.tr("Swap");
        }
        return "";
    }
    readonly property string longTitle: {
        switch (root.metric) {
        case "cpu": return Translation.tr("CPU Usage");
        case "ram": return Translation.tr("RAM Memory");
        case "disk": return Translation.tr("Disk Storage");
        case "gpu": return Translation.tr("GPU Usage");
        case "swap": return Translation.tr("Swap Memory");
        }
        return "";
    }

    function gbFromKb(kb: real): string {
        return (kb / (1024 * 1024)).toFixed(1);
    }
    function gbFromBytes(bytes: real): string {
        return (bytes / (1024 * 1024 * 1024)).toFixed(0);
    }

    /** The one line under the title: a temperature where there is one, the amounts otherwise. */
    readonly property string subtitle: {
        switch (root.metric) {
        case "cpu":
            return root.temperature > 0 ? `${Math.round(root.temperature)}°C` : Translation.tr("Processor");
        case "gpu":
            return root.temperature > 0 ? `${Math.round(root.temperature)}°C`
                : (ResourceUsage.gpuVendor === "unknown" ? Translation.tr("No GPU detected") : Translation.tr("Graphics"));
        case "ram":
            return `${root.gbFromKb(ResourceUsage.memoryUsed)} / ${root.gbFromKb(ResourceUsage.memoryTotal)} GB`;
        case "swap":
            return `${root.gbFromKb(ResourceUsage.swapUsed)} / ${root.gbFromKb(ResourceUsage.swapTotal)} GB`;
        case "disk":
            return `${root.gbFromBytes(ResourceUsage.diskUsed)} / ${root.gbFromBytes(ResourceUsage.diskTotal)} GB`;
        }
        return "";
    }

    /** Rows for a tile given to this metric alone, shown only when it is tall enough. */
    readonly property var details: {
        switch (root.metric) {
        case "cpu": {
            const rows = [];
            if (root.temperature > 0)
                rows.push({ label: Translation.tr("Temperature"), value: `${Math.round(root.temperature)}°C` });
            if (ResourceUsage.cpuModel !== "--")
                rows.push({ label: Translation.tr("Processor"), value: ResourceUsage.cpuModel });
            return rows;
        }
        case "ram":
            return [
                { label: Translation.tr("Used"), value: `${root.gbFromKb(ResourceUsage.memoryUsed)} GB` },
                { label: Translation.tr("Total"), value: `${root.gbFromKb(ResourceUsage.memoryTotal)} GB` },
                { label: Translation.tr("Swap"), value: `${Math.round(ResourceUsage.swapUsedPercentage * 100)}%` }
            ];
        case "disk":
            return [
                { label: Translation.tr("Used"), value: `${root.gbFromBytes(ResourceUsage.diskUsed)} GB` },
                { label: Translation.tr("Free"), value: `${root.gbFromBytes(ResourceUsage.diskFree)} GB` },
                { label: Translation.tr("Total"), value: `${root.gbFromBytes(ResourceUsage.diskTotal)} GB` }
            ];
        case "gpu": {
            const rows = [];
            if (root.temperature > 0)
                rows.push({ label: Translation.tr("Temperature"), value: `${Math.round(root.temperature)}°C` });
            if (ResourceUsage.gpuModel !== "--")
                rows.push({ label: Translation.tr("Graphics"), value: ResourceUsage.gpuModel });
            return rows;
        }
        case "swap":
            return [
                { label: Translation.tr("Used"), value: `${root.gbFromKb(ResourceUsage.swapUsed)} GB` },
                { label: Translation.tr("Total"), value: `${root.gbFromKb(ResourceUsage.swapTotal)} GB` }
            ];
        }
        return [];
    }

    // ── Density: every size below is a function of the card, never of the tile ──
    readonly property bool stacked: root.height >= 74
    readonly property real pad: Math.max(5, Math.min(16, Math.round(Math.min(root.width, root.height) * 0.13)))
    readonly property real badgeSize: Math.max(22, Math.min(54,
        Math.round(Math.min(root.height * 0.30, root.width * 0.40))))
    readonly property real inlineIconSize: Math.max(13, Math.min(24,
        Math.round(Math.min(root.height * 0.42, root.width * 0.26))))
    readonly property real valueSize: root.stacked
        ? Math.max(16, Math.min(46, Math.round(Math.min(root.height * 0.26, root.width * 0.30))))
        : Math.max(12, Math.min(24, Math.round(Math.min(root.height * 0.40, root.width * 0.24))))
    readonly property real titleSize: Math.max(10, Math.min(17, Math.round(root.height * 0.12)))
    readonly property real subtitleSize: Math.max(9, Math.min(15, Math.round(root.height * 0.10)))

    readonly property bool showBadge: root.stacked && root.height >= 92 && root.width >= 76
    readonly property bool showTitle: root.stacked ? root.width >= 62 : root.width >= 148
    readonly property bool showSubtitle: root.stacked && root.height >= 108 && root.width >= 96
    readonly property bool showDetails: root.detailed && root.stacked
        && root.height >= 178 && root.width >= 140
    readonly property int detailRows: !root.showDetails ? 0
        : Math.max(0, Math.min(root.details.length, Math.floor((root.height - 170) / 22)))

    // ── The card ─────────────────────────────────────────────────────────────
    Rectangle {
        id: cardBackground
        anchors.fill: parent
        radius: root.radius
        color: root.containerColor

        // The level, as liquid rising from the bottom edge.
        //
        // A rectangular clip over the filled part, holding a copy of the card's own
        // shape: the liquid's bottom corners are then the card's corners exactly, and
        // the clip cuts the straight top edge. Rounding the fill rectangle itself does
        // not work - below twice the radius Qt shrinks its corners, and the liquid
        // spills out past the card's rounded bottom.
        Item {
            id: fillWindow

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.round(cardBackground.height * Math.max(0, Math.min(1, root.level)))
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                    easing.type: Appearance.animation.elementMoveFast.type
                    easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                }
            }

            Rectangle {
                width: cardBackground.width
                height: cardBackground.height
                y: fillWindow.height - cardBackground.height
                radius: root.radius
                color: ColorUtils.applyAlpha(root.accentColor, 0.30)
            }
        }

        // ── Short card: one row ──────────────────────────────────────────────
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.pad
            anchors.rightMargin: root.pad
            spacing: Math.round(root.pad * 0.7)
            visible: !root.stacked

            MaterialSymbol {
                text: root.symbol
                iconSize: root.inlineIconSize
                color: root.accentColor
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.showTitle
                text: root.shortTitle
                font.pixelSize: Math.max(10, Math.min(15, Math.round(root.height * 0.26)))
                font.weight: Font.DemiBold
                color: root.accentColor
                elide: Text.ElideRight
            }

            Item {
                Layout.fillWidth: true
                visible: !root.showTitle
            }

            StyledText {
                text: `${root.percent}%`
                color: root.accentColor
                font {
                    pixelSize: root.valueSize
                    weight: Font.Bold
                    family: Appearance.font.family.numbers
                    variableAxes: ({ "wght": 700, "ROND": 100 })
                }
            }
        }

        // ── Tall card: the stacked design ────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: 0
            visible: root.stacked

            Rectangle {
                Layout.preferredWidth: root.badgeSize
                Layout.preferredHeight: root.badgeSize
                radius: width / 2
                color: Appearance.colors.colSurfaceContainerHighest
                opacity: 0.95
                visible: root.showBadge

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.symbol
                    iconSize: Math.round(parent.width * 0.54)
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }

            MaterialSymbol {
                // Without room for the badge the icon still belongs above the reading.
                visible: !root.showBadge
                text: root.symbol
                iconSize: root.inlineIconSize
                color: root.accentColor
            }

            Item { Layout.fillHeight: true }

            StyledText {
                Layout.fillWidth: true
                visible: root.showTitle
                text: (root.showSubtitle && root.width >= 168) ? root.longTitle : root.shortTitle
                font.pixelSize: root.titleSize
                font.weight: Font.DemiBold
                color: root.accentColor
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.showSubtitle
                text: root.subtitle
                font.pixelSize: root.subtitleSize
                color: ColorUtils.applyAlpha(root.accentColor, 0.80)
                elide: Text.ElideRight
            }

            StyledText {
                Layout.topMargin: root.showTitle ? 2 : 0
                text: `${root.percent}%`
                color: root.accentColor
                font {
                    pixelSize: root.valueSize
                    weight: Font.Black
                    family: Appearance.font.family.numbers
                    variableAxes: ({ "wght": 900, "ROND": 100 })
                }
            }

            // The metric's own rows, for a tile given to it alone.
            ColumnLayout {
                Layout.fillWidth: true
                // A Layout nested in a Layout fills by default; the spacer above owns the slack.
                Layout.fillHeight: false
                Layout.topMargin: root.detailRows > 0 ? 6 : 0
                spacing: 2
                visible: root.detailRows > 0

                Repeater {
                    model: root.detailRows

                    delegate: RowLayout {
                        id: detailRow
                        required property int index
                        readonly property var row: root.details[detailRow.index] ?? ({ label: "", value: "" })

                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 6

                        StyledText {
                            text: detailRow.row.label
                            font.pixelSize: root.subtitleSize
                            color: ColorUtils.applyAlpha(root.accentColor, 0.70)
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            text: detailRow.row.value
                            font.pixelSize: root.subtitleSize
                            font.weight: Font.DemiBold
                            color: root.accentColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
