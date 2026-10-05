import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * AI usage: how much of an AI plan is gone and when it resets, for any
 * provider AiPlanUsage reads (Claude, ChatGPT, Antigravity pools, Z.AI, Kimi,
 * OpenCode, OpenRouter credits). The provider is chosen in Settings or the
 * panel; "auto" follows the bar widget.
 *
 * Square: a ring with the used share of the window chosen in Settings (long =
 * weekly/daily/monthly, short = the session window), the number inside; a
 * credit balance shows its amount instead. Wide: the provider's badge shape
 * holding that number, the reset over the provider and window, and the other
 * window as a small ring. Tertiary family; a window running low turns its ring
 * to error, never the whole tile.
 */
UtilityTile {
    id: tile

    readonly property var cfg: Config.options?.dock?.utilities?.aiUsage ?? null
    readonly property string targetId: {
        const chosen = String(tile.cfg?.provider ?? "claude");
        return chosen === "auto" ? AiPlanUsage.displayedProviderId : chosen;
    }
    readonly property var provider: AiPlanUsage.displayProviderById(tile.targetId)
    readonly property string providerId: String(tile.provider?.providerId ?? tile.targetId.split(":")[0])
    readonly property string providerName: String(tile.provider?.name ?? AiPlanUsage.providerName(tile.providerId))
    readonly property var items: Array.from(tile.provider?.items ?? [])
    readonly property var credits: tile.items.find(item => item.metricKind === "credits") ?? null
    readonly property var shortItem: tile.items.find(item => item.windowKind === "short" && item.metricKind !== "credits") ?? null
    readonly property var longItem: {
        for (const kind of ["weekly", "daily", "monthly"]) {
            const plain = tile.items.find(item => item.windowKind === kind && item.metricKind !== "credits" && !(item.groupName ?? ""));
            const any = tile.items.find(item => item.windowKind === kind && item.metricKind !== "credits");
            if (plain || any)
                return plain ?? any;
        }
        return null;
    }
    readonly property bool preferShort: (tile.cfg?.squareWindow ?? "long") === "short"
    readonly property var primary: tile.preferShort ? (tile.shortItem ?? tile.longItem ?? tile.credits)
        : (tile.longItem ?? tile.shortItem ?? tile.credits)
    readonly property var secondary: tile.primary === tile.longItem ? tile.shortItem
        : tile.primary === tile.shortItem ? tile.longItem : null
    readonly property bool ready: tile.primary !== null && tile.primary.available !== false
    readonly property bool isCredits: tile.ready && tile.primary.metricKind === "credits"
    readonly property bool low: tile.ready && AiPlanUsage.isLow(tile.primary)
    readonly property date minute: DateTime.clock.date

    // Each provider gets its own silhouette (Claude's burst echoes its mark).
    readonly property var shape: ({
        "claude": MaterialShape.Shape.SoftBurst,
        "chatgpt": MaterialShape.Shape.Clover8Leaf,
        "antigravity": MaterialShape.Shape.Arch,
        "zai": MaterialShape.Shape.Diamond,
        "kimi": MaterialShape.Shape.Cookie12Sided,
        "opencode": MaterialShape.Shape.Square,
        "openrouter": MaterialShape.Shape.Pill
    })[tile.providerId] ?? MaterialShape.Shape.Cookie9Sided

    function used(item) {
        return item ? Math.max(0, Math.min(100, Number(item.usedPercent) || 0)) : 0;
    }
    function valueText(item) {
        if (!item)
            return "?";
        if (item.metricKind === "credits")
            return AiPlanUsage.creditAmountText(item, true);
        return String(Math.round(tile.used(item)));
    }
    function windowName(item) {
        switch (item?.windowKind) {
        case "short": return Translation.tr("Session");
        case "daily": return Translation.tr("Day");
        case "monthly": return Translation.tr("Month");
        case "balance": return Translation.tr("Balance");
        default: return Translation.tr("Week");
        }
    }
    function resetText(item) {
        tile.minute;
        if (!item)
            return "";
        if (item.metricKind === "credits")
            return Translation.tr("%1 left").arg(AiPlanUsage.creditAmountText(item, false));
        return AiPlanUsage.formatReset(item.resetsAt);
    }

    surfaceColor: ClockStyle.colSurfaceHigh
    contentColor: ClockStyle.colOnSurface
    readonly property color accent: tile.low ? ClockStyle.colError : ClockStyle.colTertiary

    tooltipText: !tile.ready ? Translation.tr("%1 usage unavailable").arg(tile.providerName)
        : tile.isCredits ? tile.providerName + " · " + tile.resetText(tile.primary)
        : tile.providerName + " · " + Translation.tr("%1% of the %2").arg(Math.round(tile.used(tile.primary))).arg(tile.windowName(tile.primary).toLowerCase())
            + " · " + tile.resetText(tile.primary)
    panelSubtitle: tile.providerName + (tile.ready ? " · " + tile.resetText(tile.primary) : "")
    menuActions: [
        { id: "refresh", icon: "refresh", text: Translation.tr("Refresh") }
    ]
    function menuAction(actionId) {
        if (actionId === "refresh")
            AiPlanUsage.refresh(true);
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        ClockProgressRing {
            anchors.fill: parent
            anchors.margins: Math.round(tile.side * 0.08)
            visible: tile.ready && !tile.isCredits
            value: tile.used(tile.primary) / 100
            thickness: Math.max(3, Math.round(tile.side * 0.075))
            wavy: false
            colIndicator: tile.accent
            colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.12)
        }
        TileShape {
            anchors.centerIn: parent
            visible: !tile.ready || tile.isCredits
            width: Math.round(tile.side * 0.8)
            height: width
            renderScale: tile.renderScale
            shape: tile.shape
            color: ClockStyle.colTertiaryContainer
        }
        TileValue {
            anchors.centerIn: parent
            text: tile.ready ? tile.valueText(tile.primary) : "?"
            color: tile.ready && !tile.isCredits ? tile.contentColor : ClockStyle.colOnTertiaryContainer
            font.pixelSize: Math.round(tile.side * (text.length > 3 ? 0.24 : text.length > 2 ? 0.3 : 0.36))
        }
    }

    // ── Wide ────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        anchors.rightMargin: tile.pad * 1.5
        visible: tile.wide
        spacing: tile.pad

        Item {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            TileShape {
                anchors.fill: parent
                renderScale: tile.renderScale
                shape: tile.shape
                color: tile.low ? ClockStyle.colErrorContainer : ClockStyle.colTertiaryContainer
            }
            TileValue {
                anchors.centerIn: parent
                text: tile.ready ? tile.valueText(tile.primary) : "?"
                color: tile.low ? ClockStyle.colOnErrorContainer : ClockStyle.colOnTertiaryContainer
                font.pixelSize: Math.round(tile.badgeSize * (text.length > 3 ? 0.28 : 0.42))
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0
            TileText {
                Layout.fillWidth: true
                text: tile.ready ? tile.resetText(tile.primary)
                    : AiPlanUsage.refreshing ? Translation.tr("Checking…") : Translation.tr("Not signed in")
                color: tile.contentColor
                font.pixelSize: Math.round(tile.height * 0.25)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.providerName
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }

        // The other window, as a small ring with its number.
        Item {
            visible: tile.ready && tile.secondary !== null
            implicitWidth: Math.round(tile.badgeSize * 0.84)
            implicitHeight: implicitWidth
            ClockProgressRing {
                anchors.fill: parent
                value: tile.used(tile.secondary) / 100
                thickness: Math.max(2, Math.round(parent.width * 0.09))
                wavy: false
                colIndicator: tile.secondary && AiPlanUsage.isLow(tile.secondary) ? ClockStyle.colError : ClockStyle.colTertiary
                colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.12)
            }
            TileValue {
                anchors.centerIn: parent
                text: String(Math.round(tile.used(tile.secondary)))
                color: tile.contentColor
                font.pixelSize: Math.round(parent.width * 0.36)
            }
        }
    }
}
