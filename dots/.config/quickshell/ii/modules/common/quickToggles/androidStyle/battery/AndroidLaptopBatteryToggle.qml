pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.quickToggles.androidStyle

/**
 * The laptop battery as a glowing level bar: the state on top ("Charging…"), the reading
 * and what is left of it below, then a thick rounded bar under a 0 / 50 / 100 scale.
 *
 * Free-form, and the layout turns with the tile rather than only shrinking:
 *
 * | Tile              | What it draws                                           |
 * |-------------------|---------------------------------------------------------|
 * | 2x1, 4x1 (short)  | one row: state icon, reading, the bar taking the rest    |
 * | 1x2 and narrower  | the bar stands up and fills from the bottom             |
 * | 2x2               | state, reading, bar                                     |
 * | 3x3 and taller    | + the 0 / 50 / 100 scale over the bar                   |
 * | 4x4 and larger    | the same, with the type and the bar growing into it     |
 *
 * The glow is three translucent rounded rectangles behind the fill rather than a blur:
 * an effect holding an item-valued property is what pins a destroyed window in the
 * island and crashes the next one.
 */
AndroidWidgetTileBase {
    id: root

    tooltipText: `${Translation.tr("Battery")}: ${root.percent}% · ${root.statusText}`

    readonly property int percent: Math.round(Math.max(0, Math.min(1, Battery.percentage)) * 100)
    readonly property real level: Math.max(0, Math.min(1, Battery.percentage))
    readonly property bool charging: Battery.isCharging
    readonly property bool plugged: Battery.isPluggedIn
    readonly property bool low: !root.plugged && Battery.percentage <= (Config.options.battery.low / 100)

    readonly property string statusText: {
        if (!Battery.available)
            return Translation.tr("No battery");
        if (Battery.chargeLimitReached)
            return Translation.tr("Charge limit reached");
        if (Battery.isCharging)
            return Translation.tr("Charging...");
        if (Battery.drainingOnAc)
            return Translation.tr("On AC, still draining");
        if (Battery.isFullyCharged)
            return Translation.tr("Battery full");
        if (Battery.isPluggedIn)
            return Translation.tr("Plugged in");
        return Translation.tr("Discharging");
    }

    readonly property string statusIcon: {
        if (!Battery.available)
            return "battery_unknown";
        if (Battery.isCharging)
            return "bolt";
        if (Battery.isPluggedIn)
            return "power";
        return root.low ? "battery_alert" : "battery_full";
    }

    readonly property real remainingSeconds: Battery.isCharging ? Battery.timeToFullEffective : Battery.timeToEmpty
    /**
     * Nothing to count down to at the ceiling, and UPower's estimate right after a plug
     * or a resume is nonsense (it reported "2843h" on a full pack), so anything past a
     * day is dropped rather than printed.
     */
    readonly property bool hasRemaining: Battery.available
        && root.remainingSeconds > 0 && root.remainingSeconds < 24 * 3600
        && !Battery.isFullyCharged && !Battery.atChargeCeiling
    readonly property string durationText: {
        if (!root.hasRemaining)
            return "";
        const hours = Math.floor(root.remainingSeconds / 3600);
        const minutes = Math.floor((root.remainingSeconds % 3600) / 60);
        return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
    }
    /** The sentence where it fits, the duration alone where it does not. */
    readonly property string remainingText: {
        if (!root.hasRemaining)
            return "";
        if (root.surface.width < 250)
            return root.durationText;
        return Battery.isCharging ? Translation.tr("%1 until charged").arg(root.durationText)
            : Translation.tr("%1 remaining").arg(root.durationText);
    }

    readonly property color levelColor: {
        if (root.charging)
            return Appearance.m3colors.m3success;
        if (root.low)
            return Appearance.colors.colError;
        return Appearance.colors.colPrimary;
    }
    readonly property color titleColor: Appearance.colors.colOnLayer2
    readonly property color mutedColor: Appearance.colors.colSubtext

    // ── Which layout ─────────────────────────────────────────────────────────
    readonly property bool verticalBar: root.surface.width < 112 && root.surface.height >= 100
    readonly property bool inlineRow: !root.verticalBar && root.surface.height < 76
    readonly property bool showHeader: !root.inlineRow && root.surface.height >= 94
    readonly property bool showScale: !root.inlineRow && !root.verticalBar
        && root.surface.height >= 150 && root.surface.width >= 160
    readonly property bool showRemaining: root.remainingText !== "" && root.surface.width >= 150

    /**
     * The bar's thickness follows the tile but is capped: at 0.38 of the height, plus the
     * rows above it, the column asked for more than the tile had and the layout squeezed
     * every row. The spacer above the scale absorbs whatever is left over instead.
     */
    readonly property real barMaxThickness: Math.max(14, Math.min(54, Math.round(root.surface.height * 0.30)))

    readonly property real pad: Math.max(8, Math.min(18, Math.round(Math.min(root.surface.width, root.surface.height) * 0.11)))
    readonly property real valueSize: Math.max(14, Math.min(34,
        Math.round(Math.min(root.surface.height * 0.20, root.surface.width * 0.13))))
    readonly property real labelSize: Math.max(10, Math.min(17, Math.round(root.surface.height * 0.10)))
    readonly property real scaleSize: Math.max(9, Math.min(13, Math.round(root.surface.height * 0.07)))

    // ── Short tiles: one row ─────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        spacing: Math.round(root.pad * 0.7)
        visible: root.inlineRow

        MaterialSymbol {
            text: root.statusIcon
            iconSize: Math.max(14, Math.min(22, Math.round(root.surface.height * 0.34)))
            color: root.levelColor
        }

        StyledText {
            text: `${root.percent}%`
            font.pixelSize: Math.max(13, Math.min(22, Math.round(root.surface.height * 0.32)))
            font.weight: Font.Bold
            color: root.titleColor
        }

        BatteryLevelBar {
            level: root.level
            fillColor: root.levelColor
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(10, Math.min(26, Math.round(root.surface.height * 0.42)))
            Layout.alignment: Qt.AlignVCenter
            visible: root.surface.width >= 130
        }
    }

    // ── Narrow tiles: the bar stands up ──────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Math.round(root.pad * 0.5)
        visible: root.verticalBar

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.statusIcon
            iconSize: Math.max(14, Math.min(24, Math.round(root.surface.height * 0.10)))
            color: root.levelColor
        }

        BatteryLevelBar {
            level: root.level
            fillColor: root.levelColor
            vertical: true
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: `${root.percent}%`
            font.pixelSize: Math.max(13, Math.min(24, Math.round(root.surface.width * 0.22)))
            font.weight: Font.Bold
            color: root.titleColor
        }
    }

    // ── Everything else: the design proper ───────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 0
        visible: !root.inlineRow && !root.verticalBar

        // State
        RowLayout {
            Layout.fillWidth: true
            // A Layout nested in a Layout fills by default; the spacer below owns the slack.
            Layout.fillHeight: false
            spacing: 4
            visible: root.showHeader

            MaterialSymbol {
                text: root.statusIcon
                iconSize: Math.round(root.labelSize * 1.25)
                color: root.mutedColor
            }

            StyledText {
                Layout.fillWidth: true
                text: root.statusText
                font.pixelSize: root.labelSize
                font.weight: Font.DemiBold
                color: root.mutedColor
                elide: Text.ElideRight
            }
        }

        // Reading
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: root.showHeader ? 2 : 0
            spacing: 6

            StyledText {
                text: `${root.percent}%`
                font.pixelSize: root.valueSize
                font.weight: Font.Bold
                color: root.titleColor
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.showRemaining
                text: `· ${root.remainingText}`
                font.pixelSize: Math.round(root.valueSize * 0.62)
                font.weight: Font.DemiBold
                color: root.mutedColor
                elide: Text.ElideRight
            }
        }

        Item {
            Layout.fillHeight: true
            Layout.minimumHeight: 2
        }

        // Scale
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.bottomMargin: 2
            spacing: 0
            visible: root.showScale

            StyledText {
                text: "0"
                font.pixelSize: root.scaleSize
                color: root.mutedColor
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: "50"
                font.pixelSize: root.scaleSize
                color: root.mutedColor
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: "100"
                font.pixelSize: root.scaleSize
                color: root.mutedColor
            }
        }

        BatteryLevelBar {
            level: root.level
            fillColor: root.levelColor
            Layout.fillWidth: true
            // The spacer above owns the slack; the bar keeps its thickness and is only
            // squeezed when the rows above it leave less than that.
            Layout.preferredHeight: root.barMaxThickness
            Layout.minimumHeight: 12
        }
    }
}
