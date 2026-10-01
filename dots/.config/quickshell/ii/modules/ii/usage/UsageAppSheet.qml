pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.usage.limits
import "UsageFormat.js" as Format

/**
 * One app over the period on screen: every figure the sampler keeps for it, the one the
 * page is ranked by first, and its daily limit.
 *
 * Opened by picking an app on the App usage page, which narrows the hero to the same
 * app — so the chart says when and this sheet says how much. The page keeps `record`
 * current as the period, the bucket or the data move; the sheet computes nothing.
 */
ClockSheet {
    id: root

    property string appKey: ""
    /// The app's summary record for the period (AppStats.summarize), or null.
    property var record: null
    property string metricKey: "fg"
    /// The app's share of the metric's total, 0–1, or -1 when it means nothing.
    property real share: -1
    property string periodText: ""

    signal limitRequested(string appKey)
    signal clearRequested()

    readonly property bool isSystem: root.appKey === AppStats.systemKey
    readonly property bool isHeadless: root.record?.headless ?? false
    readonly property bool limitsOn: (Config.options.screenTime?.enable ?? true) && !root.isSystem
    /// The app limit that already covers this app, if any.
    readonly property var limit: {
        for (const rule of ScreenTimeLimits.limits) {
            if (rule.kind !== "total" && (rule.keys ?? []).includes(root.appKey))
                return rule;
        }
        return null;
    }
    readonly property string limitState: root.limit ? ScreenTimeLimits.stateFor(root.limit) : "none"

    readonly property var figures: {
        const rec = root.record;
        const energy = rec ? (rec.mjFg ?? 0) + (rec.mjBg ?? 0) : 0;
        const list = [
            { key: "fg", symbol: "schedule", label: Translation.tr("Screen time"), value: Format.duration(rec?.fg) },
            { key: "bg", symbol: "visibility_off", label: Translation.tr("Background"), value: Format.duration(rec?.bg) },
            { key: "focus", symbol: "point_scan", label: Translation.tr("Focused"), value: Format.duration(rec?.focus) },
            { key: "energy", symbol: "bolt", label: Translation.tr("Energy"), value: Format.energyFromMj(energy) },
            { key: "cpu", symbol: "memory", label: Translation.tr("CPU time"), value: Format.duration(rec?.cpu) },
            { key: "gpu", symbol: "stadia_controller", label: Translation.tr("GPU time"), value: Format.duration(rec?.gpu) },
            { key: "ramAvg", symbol: "memory_alt", label: Translation.tr("Memory avg"), value: Format.memory(rec?.ramAvg) },
            { key: "ramPeak", symbol: "vertical_align_top", label: Translation.tr("Memory peak"), value: Format.memory(rec?.ramPeak) },
            { key: "launches", symbol: "rocket_launch", label: Translation.tr("Launches"), value: Format.count(rec?.launches) },
            // Counted every time the app came into view, which a workspace switch does
            // once per window it has open. Not the same as being opened.
            { key: "sessions", symbol: "repeat", label: Translation.tr("Appearances"), value: Format.count(rec?.sessions) }
        ];
        // The system row only ever holds energy; a grid of dashes says nothing.
        if (root.isSystem)
            return list.filter(f => f.key === "energy");
        return list;
    }
    readonly property var lead: root.figures.find(f => f.key === root.metricKey) ?? root.figures[0]

    title: AppStats.displayName(root.appKey)
    subtitle: root.periodText

    // ── Who ─────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: leadColumn.implicitHeight + ClockStyle.cardPadding * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colPrimaryContainer

        ColumnLayout {
            id: leadColumn
            anchors.fill: parent
            anchors.margins: ClockStyle.cardPadding
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                Rectangle {
                    implicitWidth: 52
                    implicitHeight: 52
                    radius: 26
                    color: ClockStyle.colPrimary

                    LimitsAppIcon {
                        anchors.centerIn: parent
                        size: 36
                        appKey: root.isSystem ? "" : root.appKey
                        fallbackSymbol: root.isSystem ? "memory" : root.isHeadless ? "terminal" : "apps"
                        colFallback: ClockStyle.colOnPrimary
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.lead.label
                        font.pixelSize: ClockStyle.textNormal + 1
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnPrimaryContainer
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.share >= 0
                        text: Translation.tr("%1 % of the total").arg(Math.round(root.share * 100))
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colOnPrimaryContainer
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }
            }

            UsageFigure {
                text: root.lead.value
                size: 56
                color: ClockStyle.colOnPrimaryContainer
            }

            StyledProgressBar {
                Layout.fillWidth: true
                visible: root.share >= 0
                valueBarHeight: 6
                value: Math.max(0, Math.min(1, root.share))
                highlightColor: ClockStyle.colOnPrimaryContainer
                trackColor: ColorUtils.applyAlpha(ClockStyle.colOnPrimaryContainer, 0.2)
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.isSystem || root.isHeadless
        text: root.isSystem
            ? Translation.tr("Energy that belongs to no app: idle draw, kernel threads, the backlight and the radios. Per-app watt-hours are modelled from CPU, GPU and memory shares, so this is the honest measure of how much weight they carry.")
            : Translation.tr("A background service: it owns no window, so it never has screen time of its own.")
        wrapMode: Text.WordWrap
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    // ── Every figure ────────────────────────────────────────────────────
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: ClockStyle.gapSmall
        rowSpacing: ClockStyle.gapSmall
        uniformCellWidths: true

        Repeater {
            model: root.figures

            Rectangle {
                id: figureTile
                required property var modelData
                required property int index
                readonly property bool current: figureTile.modelData.key === root.metricKey

                Layout.fillWidth: true
                implicitHeight: 76
                radius: ClockStyle.radiusNormal
                color: figureTile.current ? ClockStyle.colSecondaryContainer : ClockStyle.colField

                ColumnLayout {
                    anchors.fill: parent
                    anchors.leftMargin: ClockStyle.gap + 2
                    anchors.rightMargin: ClockStyle.gapSmall
                    anchors.topMargin: ClockStyle.gapSmall + 2
                    anchors.bottomMargin: ClockStyle.gapSmall
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapTiny + 2

                        MaterialSymbol {
                            text: figureTile.modelData.symbol
                            iconSize: ClockStyle.iconSmall
                            fill: figureTile.current ? 1 : 0
                            color: figureTile.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: figureTile.modelData.label
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                            color: figureTile.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    UsageFigure {
                        text: figureTile.modelData.value
                        size: 26
                        color: figureTile.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                    }
                }

                StaggeredEntrance {
                    index: figureTile.index
                    step: ClockStyle.staggerStep / 2
                    active: !ClockStyle.reducedMotion
                }
            }
        }
    }

    // ── Daily limit ─────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: ClockStyle.gapTiny
        visible: root.limitsOn && root.limit !== null
        implicitHeight: limitRow.implicitHeight + ClockStyle.gapLarge * 2
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colField

        RowLayout {
            id: limitRow
            anchors.fill: parent
            anchors.margins: ClockStyle.gapLarge
            spacing: ClockStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: "hourglass_top"
                iconSize: 18
                padding: 9
                shape: MaterialShape.Shape.Cookie7Sided
                color: root.limitState === "reached" || root.limitState === "ignored" ? ClockStyle.colErrorContainer
                    : root.limitState === "warn" ? ClockStyle.colTertiaryContainer : ClockStyle.colPrimaryContainer
                colSymbol: root.limitState === "reached" || root.limitState === "ignored" ? ClockStyle.colOnErrorContainer
                    : root.limitState === "warn" ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnPrimaryContainer
                fill: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.limit ? ScreenTimeLimits.ruleName(root.limit) : ""
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: !root.limit ? ""
                        : root.limitState === "off" ? Translation.tr("Off today")
                        : Translation.tr("%1 of %2 today")
                            .arg(ScreenTimeLimits.formatCompact(ScreenTimeLimits.usedFor(root.limit)))
                            .arg(ScreenTimeLimits.formatCompact(ScreenTimeLimits.budgetFor(root.limit)))
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                    elide: Text.ElideRight
                }
            }
        }
    }

    actions: [
        ClockSheetAction {
            visible: root.limitsOn
            primary: true
            symbol: root.limit ? "edit" : "more_time"
            label: root.limit ? Translation.tr("Edit daily limit") : Translation.tr("Set a daily limit")
            onClicked: root.limitRequested(root.appKey)
        },
        ClockSheetAction {
            symbol: "filter_alt_off"
            label: Translation.tr("Show all apps")
            onClicked: root.clearRequested()
        }
    ]
}
