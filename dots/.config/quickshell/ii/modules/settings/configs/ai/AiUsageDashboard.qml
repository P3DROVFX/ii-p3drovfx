import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.usage

/**
 * The AI usage bento grid: what the assistant cost, at a glance.
 *
 * Everything here is real data recorded by the `AiUsage` singleton — day (or
 * hour, for today) buckets of input/output/thinking tokens, request counts,
 * per-model totals and success outcomes, captured when each response ends.
 *
 * Three independent period selectors (`AiPeriodDropdown`): the usage card's
 * `periodMode` drives the chart, requests, success donut and details; the
 * tokens card and the top models list each carry their own.
 */
GridLayout {
    id: grid

    readonly property bool compactLayout: width < 760

    Layout.fillWidth: true
    // 24 logical columns let the bento spans move in small increments
    // instead of jumping between visibly different half/half layouts.
    columns: compactLayout ? 1 : 24
    uniformCellWidths: true
    columnSpacing: 12
    rowSpacing: 12

    // ── Period selection ──────────────────────────────────────────────────
    property string periodMode: "30d"
    readonly property var periodOptions: [
        { value: "today", label: Translation.tr("Today") },
        { value: "7d", label: Translation.tr("Last 7 days") },
        { value: "14d", label: Translation.tr("Last 14 days") },
        { value: "30d", label: Translation.tr("Last 1 month") }
    ]
    readonly property int periodIndex: {
        for (let i = 0; i < grid.periodOptions.length; ++i)
            if (grid.periodOptions[i].value === grid.periodMode)
                return i;
        return grid.periodOptions.length - 1;
    }
    readonly property string periodLabel: grid.periodOptions[grid.periodIndex].label
    function daysBackFor(mode: string): int {
        if (mode === "today")
            return 0;
        if (mode === "7d")
            return 6;
        if (mode === "14d")
            return 13;
        return 29;
    }
    readonly property int periodDaysBack: grid.daysBackFor(grid.periodMode)

    // Tokens and Top models carry their own selectors, independent of the
    // usage card's period.
    property string tokensMode: "30d"
    property string modelsMode: "all"
    readonly property var modelPeriodOptions: grid.periodOptions.concat([
        { value: "all", label: Translation.tr("All time") }
    ])

    // ── Period data, one place ────────────────────────────────────────────
    readonly property var periodSeries: grid.periodMode === "today"
        ? AiUsage.hourSeries()
        : AiUsage.daySeries(grid.periodDaysBack + 1)
    readonly property var periodSeriesValues: grid.periodSeries.map(entry => entry.value)
    readonly property var periodSeriesLabels: grid.periodSeries.map(entry => entry.label)
    readonly property var periodSeriesTooltips: grid.periodSeries.map(entry => entry.tooltip)
    readonly property int periodTokens: AiUsage.totalSince(grid.periodDaysBack)
    readonly property int periodRequests: AiUsage.requestsSince(grid.periodDaysBack)
    readonly property real periodCost: AiUsage.costSince(grid.periodDaysBack)
    readonly property int periodCostResponses: AiUsage.costResponsesSince(grid.periodDaysBack)
    readonly property string periodCostLabel: grid.periodCostResponses > 0
        ? AiUsage.formatCost(grid.periodCost)
        : Translation.tr("Not reported")
    readonly property var periodSplit: AiUsage.splitSince(grid.periodDaysBack)
    readonly property var periodOutcome: AiUsage.outcomeSince(grid.periodDaysBack)
    readonly property int periodOk: grid.periodOutcome.ok
    readonly property int periodErr: grid.periodOutcome.err
    readonly property int successPct: grid.periodOk + grid.periodErr > 0
        ? Math.round(grid.periodOk * 100 / (grid.periodOk + grid.periodErr))
        : 0
    readonly property var peakEntry: {
        let peak = null;
        for (const entry of grid.periodSeries)
            if (!peak || entry.value > peak.value)
                peak = entry;
        return peak && peak.value > 0 ? peak : null;
    }
    /** "14:00" for today, "12/08" for day windows — the busiest bucket's tag. */
    function peakTag(): string {
        const peak = grid.peakEntry;
        if (!peak)
            return "";
        if (grid.periodMode === "today")
            return peak.label + ":00";
        const date = new Date(peak.key + "T00:00:00");
        return Qt.formatDate(date, "dd/MM");
    }
    readonly property int avgTokensPerDay: Math.round(grid.periodTokens / (grid.periodDaysBack + 1))
    readonly property int avgRequestsPerDay: Math.round(grid.periodRequests / (grid.periodDaysBack + 1))
    readonly property string tokensPerRequest: grid.periodRequests > 0 && grid.periodTokens > 0
        ? AiUsage.formatTokens(Math.round(grid.periodTokens / grid.periodRequests))
        : "—"
    readonly property var previousTokens: grid.periodMode === "today"
        ? AiUsage.totalSince(1) - AiUsage.totalSince(0)
        : AiUsage.totalSince(grid.periodDaysBack * 2 + 1) - AiUsage.totalSince(grid.periodDaysBack)
    readonly property var tokensDeltaPct: grid.previousTokens > 0 && grid.periodTokens > 0
        ? Math.round((grid.periodTokens - grid.previousTokens) * 100 / grid.previousTokens)
        : null

    readonly property int tokensDaysBack: grid.daysBackFor(grid.tokensMode)
    readonly property int tokensTotal: AiUsage.totalSince(grid.tokensDaysBack)
    readonly property var tokenSplitRows: {
        const split = AiUsage.splitSince(grid.tokensDaysBack);
        const total = grid.tokensTotal;
        return [
            { label: Translation.tr("Input"), symbol: "login", color: Appearance.colors.colPrimary, value: split.input },
            { label: Translation.tr("Output"), symbol: "logout", color: Appearance.colors.colTertiary, value: split.output },
            { label: Translation.tr("Thinking"), symbol: "psychology", color: Appearance.colors.colSecondary, value: split.thinking }
        ].map(row => Object.assign(row, {
            formatted: AiUsage.formatTokens(row.value),
            ratio: total > 0 ? Math.min(1, row.value / total) : 0,
            percent: total > 0 ? String(Math.round(row.value / total * 100)) + "%" : "—"
        }));
    }
    readonly property string tokensCardPerRequest: {
        const requests = AiUsage.requestsSince(grid.tokensDaysBack);
        return grid.tokensTotal > 0 && requests > 0
            ? AiUsage.formatTokens(Math.round(grid.tokensTotal / requests))
            : "—";
    }

    readonly property var usageFootnotes: {
        if (grid.periodMode === "today")
            return [
                { label: grid.peakEntry ? Translation.tr("Peak hour") + " · " + grid.peakTag() : Translation.tr("Peak hour"),
                  value: grid.peakEntry ? AiUsage.formatTokens(grid.peakEntry.value) : "—" },
                { label: Translation.tr("Requests"), value: String(grid.periodRequests) },
                { label: Translation.tr("Failed"), value: String(grid.periodErr) },
                { label: Translation.tr("Reported cost"), value: grid.periodCostLabel }
            ];
        return [
            { label: grid.peakEntry ? Translation.tr("Busiest day") + " · " + grid.peakTag() : Translation.tr("Busiest day"),
              value: grid.peakEntry ? AiUsage.formatTokens(grid.peakEntry.value) : "—" },
            { label: Translation.tr("Average / day"), value: AiUsage.formatTokens(grid.avgTokensPerDay) },
            { label: Translation.tr("vs previous"),
              value: grid.tokensDeltaPct !== null ? (grid.tokensDeltaPct > 0 ? "+" : "") + String(grid.tokensDeltaPct) + "%" : "—" },
            { label: Translation.tr("Reported cost"), value: grid.periodCostLabel }
        ];
    }

    readonly property var topModelRows: grid.modelsMode === "all"
        ? AiUsage.topModels(4)
        : AiUsage.topModelsSince(grid.daysBackFor(grid.modelsMode), 4)
    readonly property int extraModelCount: Math.max(0, (grid.modelsMode === "all"
        ? AiUsage.topModels(0).length
        : AiUsage.topModelsSince(grid.daysBackFor(grid.modelsMode), 0).length) - 4)
    readonly property real modelsTopTotal: topModelRows.length > 0 ? Math.max(1, topModelRows[0].total) : 1

    // Give every logical column the same zero-based stretch constraint, in a
    // dedicated zero-height row: overlapping them with the cards makes Qt
    // merge incompatible cell hints and collapse column groups.
    Repeater {
        model: grid.compactLayout ? 1 : 24

        delegate: Item {
            required property int index
            Layout.row: grid.compactLayout ? 6 : 3
            Layout.column: grid.compactLayout ? 0 : index
            Layout.preferredWidth: 0
            Layout.minimumWidth: 0
            Layout.fillWidth: true
            Layout.horizontalStretchFactor: 1
            Layout.preferredHeight: 0
            Layout.minimumHeight: 0
            Layout.maximumHeight: 0
            implicitHeight: 0
        }
    }

    // ── Usage: the one chart card, in four period views ───────────────────
    StyledRectangle {
        Layout.row: 0
        Layout.column: 0
        Layout.columnSpan: grid.compactLayout ? 1 : 18
        Layout.rowSpan: grid.compactLayout ? 1 : 2
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        implicitHeight: grid.compactLayout ? 304 : 356
        radius: Appearance.rounding.large
        contentLayer: StyledRectangle.ContentLayer.Group
        color: Appearance.colors.colPrimaryContainer
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    padding: 6
                    shape: MaterialShape.Shape.Sunny
                    fill: 1
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                    text: "monitoring"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Usage")
                    color: Appearance.colors.colOnPrimaryContainer
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    elide: Text.ElideRight
                }

                AiPeriodDropdown {
                    mode: grid.periodMode
                    options: grid.periodOptions
                    colText: Appearance.colors.colOnPrimaryContainer
                    onModeSelected: value => grid.periodMode = value
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: AiUsage.formatTokens(grid.periodTokens)
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.huge
                font.bold: true
                animateChange: true
                animationDistanceY: 6
            }

            StyledText {
                Layout.fillWidth: true
                text: String(grid.periodRequests) + " " + Translation.tr("requests")
                    + " · " + grid.tokensPerRequest + " / " + Translation.tr("request")
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.82
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                UsageColumnChart {
                    anchors.fill: parent
                    visible: AiUsage.hasData
                    values: grid.periodSeriesValues
                    labels: grid.periodSeriesLabels
                    tooltipLabels: grid.periodSeriesTooltips
                    barColor: Appearance.colors.colPrimary
                    emptyColor: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.84)
                    axisColor: ColorUtils.transparentize(Appearance.colors.colOnPrimaryContainer, 0.28)
                    gridLineColor: Appearance.colors.colOnPrimaryContainer
                    gridLineOpacity: 0.14
                    textureColor: Appearance.colors.colOnPrimaryContainer
                    textureOpacity: 0.30
                    // A tighter rhythm leaves enough room for visibly heavier
                    // columns even in the 30-day view, without merging them.
                    barWidth: Appearance.rounding.large
                    minimumBarWidth: grid.periodMode === "today"
                        ? Appearance.font.pixelSize.large
                        : Appearance.font.pixelSize.larger
                    barSpacing: Appearance.rounding.verysmall / 2
                    labelStride: grid.periodMode === "today"
                        ? 4
                        : Math.max(1, Math.ceil(grid.periodSeries.length / 7))
                    formatValue: value => AiUsage.formatTokens(value)
                }

                PagePlaceholder {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: !AiUsage.hasData
                    shown: visible
                    icon: "monitoring"
                    title: Translation.tr("No usage yet")
                    description: Translation.tr("Tokens land here after your next message.")
                    shape: MaterialShape.Shape.Cookie9Sided
                }
            }
        }
    }

    // ── Tokens: the split, beside top models in the last row ─────────────
    StyledRectangle {
        Layout.row: grid.compactLayout ? 1 : 2
        Layout.column: grid.compactLayout ? 0 : 10
        Layout.columnSpan: grid.compactLayout ? 1 : 8
        Layout.rowSpan: 1
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        implicitHeight: 244
        radius: Appearance.rounding.large
        contentLayer: StyledRectangle.ContentLayer.Group
        color: Appearance.colors.colLayer2
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    padding: 6
                    shape: MaterialShape.Shape.Oval
                    fill: 1
                    color: Appearance.colors.colSecondary
                    colSymbol: Appearance.colors.colOnSecondary
                    text: "token"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Tokens")
                    color: Appearance.colors.colOnLayer2
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    elide: Text.ElideRight
                }

                AiPeriodDropdown {
                    dropdownWidth: 136
                    labelPixelSize: Appearance.font.pixelSize.smallie
                    mode: grid.tokensMode
                    options: grid.periodOptions
                    colText: Appearance.colors.colOnLayer2
                    onModeSelected: value => grid.tokensMode = value
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: AiUsage.formatTokens(grid.tokensTotal)
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.huge
                font.bold: true
                animateChange: true
                animationDistanceY: 6
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("≈ %1 per request").arg(grid.tokensCardPerRequest)
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
            }

            Item {
                Layout.fillHeight: true
            }

            Repeater {
                model: grid.tokenSplitRows

                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        MaterialSymbol {
                            text: modelData.symbol
                            iconSize: Appearance.font.pixelSize.small
                            color: modelData.color
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: modelData.percent
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            Layout.preferredWidth: 36
                            horizontalAlignment: Text.AlignRight
                        }

                        StyledText {
                            text: modelData.formatted
                            color: Appearance.colors.colOnLayer2
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.bold: true
                            Layout.preferredWidth: 48
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    // Share of the period, as a thin fill over a quiet track
                    // (the RAM-pill pattern).
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: Appearance.rounding.full
                        color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.88)

                        Rectangle {
                            width: parent.width * modelData.ratio
                            height: parent.height
                            radius: Appearance.rounding.full
                            color: modelData.color

                            Behavior on width {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Requests: volume and outcome rows, top half of the right rail ────
    StyledRectangle {
        Layout.row: grid.compactLayout ? 2 : 0
        Layout.column: grid.compactLayout ? 0 : 18
        Layout.columnSpan: grid.compactLayout ? 1 : 6
        Layout.rowSpan: 1
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        implicitHeight: 172
        radius: Appearance.rounding.large
        contentLayer: StyledRectangle.ContentLayer.Group
        color: Appearance.colors.colSecondaryContainer
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    padding: 6
                    shape: MaterialShape.Shape.Pill
                    fill: 1
                    color: Appearance.colors.colSecondary
                    colSymbol: Appearance.colors.colOnSecondary
                    text: "bolt"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Requests")
                        color: Appearance.colors.colOnSecondaryContainer
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: grid.periodLabel
                        color: Appearance.colors.colOnSecondaryContainer
                        opacity: 0.72
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: String(grid.periodRequests)
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.huge
                font.bold: true
                animateChange: true
                animationDistanceY: 6
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("≈ %1 / day").arg(String(grid.avgRequestsPerDay))
                color: Appearance.colors.colOnSecondaryContainer
                opacity: 0.78
                font.pixelSize: Appearance.font.pixelSize.smaller
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "check_circle"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Successful")
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.78
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }

                StyledText {
                    text: String(grid.periodOk)
                    color: Appearance.colors.colOnSecondaryContainer
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.bold: true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "cancel"
                    iconSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colError
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Failed")
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.78
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }

                StyledText {
                    text: String(grid.periodErr)
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.bold: true
                }
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    // ── Success rate: the small donut, bottom half of the right rail ─────
    StyledRectangle {
        Layout.row: grid.compactLayout ? 3 : 1
        Layout.column: grid.compactLayout ? 0 : 18
        Layout.columnSpan: grid.compactLayout ? 1 : 6
        Layout.rowSpan: 1
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        implicitHeight: 172
        radius: Appearance.rounding.large
        contentLayer: StyledRectangle.ContentLayer.Group
        color: Appearance.colors.colLayer2
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    padding: 6
                    shape: MaterialShape.Shape.Circle
                    fill: 1
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                    text: "task_alt"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Success rate")
                        color: Appearance.colors.colOnLayer2
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: grid.periodLabel
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                UsageSemiDonut {
                    id: outcomeDonut
                    visible: grid.periodOk + grid.periodErr > 0
                    width: Math.min(parent.width, 200)
                    height: Math.min(parent.height, 84)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    values: [grid.periodOk, grid.periodErr]
                    segmentColors: [
                        Appearance.colors.colPrimary,
                        Appearance.colors.colError
                    ]
                    // Separated segments on the card surface, no full track
                    // ring competing with them (the Drive donut treatment).
                    trackColor: ColorUtils.transparentize(Appearance.colors.colLayer3, 1)
                    thickness: Math.max(Appearance.font.pixelSize.huge,
                        Appearance.rounding.normal * 2)
                    segmentCornerRadius: Appearance.rounding.small
                    gapRadians: 0.045
                    radiusScale: 1.0
                    minimumSegmentRadians: 0.30
                }

                ColumnLayout {
                    visible: outcomeDonut.visible
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: outcomeDonut.verticalCenter
                    anchors.verticalCenterOffset: outcomeDonut.height * 0.18
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: String(grid.successPct) + "%"
                        color: Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.bold: true
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("successful")
                        color: Appearance.colors.colSubtext
                    }
                }

                // The full PagePlaceholder (56px shape + title + wrapped
                // description) overflows this small card — a compact centered
                // pair is all the room there is.
                ColumnLayout {
                    visible: !outcomeDonut.visible
                    anchors.centerIn: parent
                    spacing: 6

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "task_alt"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: parent.width
                        text: Translation.tr("No outcomes yet")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── List: top models ──────────────────────────────────────────────────
    StyledRectangle {
        Layout.row: grid.compactLayout ? 4 : 2
        Layout.column: grid.compactLayout ? 0 : 0
        Layout.columnSpan: grid.compactLayout ? 1 : 10
        Layout.rowSpan: 1
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        implicitHeight: 244
        radius: Appearance.rounding.large
        contentLayer: StyledRectangle.ContentLayer.Group
        color: Appearance.colors.colLayer2
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    padding: 6
                    shape: MaterialShape.Shape.Puffy
                    fill: 1
                    color: Appearance.colors.colTertiary
                    colSymbol: Appearance.colors.colOnTertiary
                    text: "smart_toy"
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Top models")
                    color: Appearance.colors.colOnLayer2
                    font.bold: true
                    font.pixelSize: Appearance.font.pixelSize.large
                    elide: Text.ElideRight
                }

                AiPeriodDropdown {
                    mode: grid.modelsMode
                    options: grid.modelPeriodOptions
                    colText: Appearance.colors.colOnLayer2
                    onModeSelected: value => grid.modelsMode = value
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    visible: grid.topModelRows.length > 0

                    Repeater {
                        model: grid.topModelRows

                        delegate: RowLayout {
                            id: modelRow
                            required property var modelData
                            required property int index

                            readonly property var model: Ai.catalog.models[modelData.id] ?? null
                            readonly property string titleText: modelRow.model ? modelRow.model.title : modelData.id
                            readonly property string assetIcon: modelRow.model ? (modelRow.model.icon ?? "") : ""
                            readonly property string fallbackSymbol: {
                                if (modelRow.assetIcon.length > 0)
                                    return "";
                                if (modelRow.model && (modelRow.model.materialIcon ?? "").length > 0)
                                    return modelRow.model.materialIcon;
                                return "smart_toy";
                            }

                            Layout.fillWidth: true
                            spacing: 10
                            opacity: modelRowMouse.hovered ? 1.0 : 0.86

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(modelRow)
                            }

                            HoverHandler {
                                id: modelRowMouse
                            }

                            StyledToolTip {
                                text: String(modelData.requests) + " " + Translation.tr("requests")
                                extraVisibleCondition: false
                                alternativeVisibleCondition: modelRowMouse.hovered
                            }

                            Loader {
                                active: modelRow.assetIcon.length > 0
                                visible: active
                                Layout.alignment: Qt.AlignVCenter
                                sourceComponent: CustomIcon {
                                    source: modelRow.assetIcon
                                    width: 22
                                    height: 22
                                    colorize: true
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            Loader {
                                active: modelRow.fallbackSymbol.length > 0
                                visible: active
                                Layout.alignment: Qt.AlignVCenter
                                sourceComponent: MaterialSymbol {
                                    text: modelRow.fallbackSymbol
                                    iconSize: 22
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelRow.titleText
                                    color: Appearance.colors.colOnLayer2
                                    elide: Text.ElideRight
                                }

                                // Share of the busiest model, as a thin fill
                                // over a quiet track (the RAM-pill pattern).
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 5
                                    radius: Appearance.rounding.full
                                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.88)

                                    Rectangle {
                                        width: parent.width * Math.min(1, modelData.total / grid.modelsTopTotal)
                                        height: parent.height
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colPrimary

                                        Behavior on width {
                                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                        }
                                    }
                                }
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                text: AiUsage.formatTokens(modelData.total)
                                color: Appearance.colors.colOnLayer2
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.bold: true
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: grid.extraModelCount > 0
                        text: "+" + String(grid.extraModelCount) + " " + Translation.tr("more models")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                    }
                }

                PagePlaceholder {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: grid.topModelRows.length === 0
                    shown: visible
                    icon: "smart_toy"
                    title: Translation.tr("No models used yet")
                    description: Translation.tr("Your busiest models will rank here.")
                    shape: MaterialShape.Shape.Cookie9Sided
                }
            }
        }
    }

    // ── Usage details: the period footnotes, below the success donut ─────
    StyledRectangle {
        Layout.row: grid.compactLayout ? 5 : 2
        Layout.column: grid.compactLayout ? 0 : 18
        Layout.columnSpan: grid.compactLayout ? 1 : 6
        Layout.rowSpan: 1
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.preferredWidth: 0
        implicitHeight: 244
        radius: Appearance.rounding.large
        contentLayer: StyledRectangle.ContentLayer.Group
        color: Appearance.colors.colPrimaryContainer
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialShapeWrappedMaterialSymbol {
                    iconSize: Appearance.font.pixelSize.large
                    padding: 6
                    shape: MaterialShape.Shape.Cookie4Sided
                    fill: 1
                    color: Appearance.colors.colPrimary
                    colSymbol: Appearance.colors.colOnPrimary
                    text: "query_stats"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Usage details")
                        color: Appearance.colors.colOnPrimaryContainer
                        font.bold: true
                        font.pixelSize: Appearance.font.pixelSize.large
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: grid.periodLabel
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.72
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            Repeater {
                model: grid.usageFootnotes

                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.label
                        color: Appearance.colors.colOnPrimaryContainer
                        opacity: 0.72
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: modelData.value
                        color: Appearance.colors.colOnPrimaryContainer
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
