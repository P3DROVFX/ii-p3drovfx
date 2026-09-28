pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Today, as the one number the Limits page is about: focused time in tall condensed
 * digits inside a wavy ring that fills toward the daily limit, the time left in the
 * title face, the week behind it, and what the limits did today.
 *
 * The pane takes the hue of its state — primary while inside the budget, tertiary in
 * the warning window, error once it is spent, the plain pane while paused — and every
 * control on it is tinted with the pane's own content colour.
 */
Rectangle {
    id: root

    /// Ring beside the status instead of above it, for the stacked narrow page where
    /// a full-height pane would push every rule below the fold.
    property bool compact: false

    signal setLimitRequested()
    signal pauseRequested(bool on)

    readonly property var total: ScreenTimeLimits.totalLimit()
    readonly property bool hasTotal: root.total !== null && ScreenTimeLimits.appliesToday(root.total)
    readonly property bool paused: ScreenTimeLimits.paused
    readonly property real used: ScreenTimeLimits.totalUsed()
    readonly property real budget: root.hasTotal ? ScreenTimeLimits.budgetFor(root.total) : 0
    readonly property string limitState: root.hasTotal ? ScreenTimeLimits.stateFor(root.total) : "none"
    readonly property bool spent: root.limitState === "reached" || root.limitState === "ignored"

    readonly property color colPane: root.paused ? ClockStyle.colPane
        : root.spent ? ClockStyle.colErrorContainer
        : root.limitState === "warn" ? ClockStyle.colTertiaryContainer
        : ClockStyle.colPrimary
    readonly property color colContent: root.paused ? ClockStyle.colOnSurface
        : root.spent ? ClockStyle.colOnErrorContainer
        : root.limitState === "warn" ? ClockStyle.colOnTertiaryContainer
        : ClockStyle.colOnPrimary

    radius: ClockStyle.radiusCard
    color: root.colPane
    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    function clockDigits(seconds: real): string {
        const m = Math.floor(Math.max(0, seconds) / 60);
        return Math.floor(m / 60) + ":" + String(m % 60).padStart(2, "0");
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding + 4
        }
        spacing: ClockStyle.gap

        // ── Header ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall + 2

            MaterialShapeWrappedMaterialSymbol {
                text: root.paused ? "pause" : root.spent ? "hourglass_bottom" : "hourglass_top"
                iconSize: 20
                padding: 10
                shape: MaterialShape.Shape.Cookie7Sided
                color: root.colContent
                colSymbol: root.colPane
                fill: 1
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Today")
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: root.colContent
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Qt.locale().toString(new Date(ScreenTimeLimits.now), "dddd, d MMMM")
                    font.pixelSize: ClockStyle.textSmall
                    color: root.colContent
                    opacity: 0.8
                    elide: Text.ElideRight
                }
            }

            LimitsTintButton {
                symbol: root.paused ? "play_arrow" : "pause"
                label: root.paused ? Translation.tr("Resume") : Translation.tr("Pause today")
                colContent: root.colContent
                height_: 38
                visible: ScreenTimeLimits.hasRules || root.paused
                onClicked: root.pauseRequested(!root.paused)
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: !root.compact
            columns: root.compact ? 2 : 1
            columnSpacing: ClockStyle.gapHuge
            rowSpacing: ClockStyle.gap

            // ── Ring ────────────────────────────────────────────────────────
            Item {
                id: ringArea
                Layout.fillWidth: !root.compact
                Layout.fillHeight: !root.compact
                Layout.preferredWidth: root.compact ? 190 : -1
                Layout.preferredHeight: root.compact ? 190 : -1
                Layout.minimumHeight: 150

                readonly property real ringSize: Math.round(Math.min(width, height))

                ClockProgressRing {
                    id: ring
                    anchors.centerIn: parent
                    width: ringArea.ringSize
                    height: ringArea.ringSize
                    thickness: Math.max(10, Math.round(ringArea.ringSize * 0.055))
                    value: root.hasTotal && root.budget > 0 ? root.used / root.budget : 0
                    wavy: root.hasTotal && !root.spent && !root.paused
                    waves: 12
                    animateWave: true
                    colIndicator: root.colContent
                    colTrack: ColorUtils.applyAlpha(root.colContent, 0.18)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: ringArea.ringSize * 0.7
                    spacing: -Math.round(ringArea.ringSize * 0.02)

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.clockDigits(root.used)
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigitsBold
                        font.pixelSize: Math.round(Math.max(40, ringArea.ringSize * 0.36))
                        color: root.colContent
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: parent.width
                        text: root.hasTotal ? Translation.tr("of %1").arg(ScreenTimeLimits.formatSeconds(root.budget)) : Translation.tr("focused today")
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: root.colContent
                        opacity: 0.85
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Status ──────────────────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                columns: root.compact ? 1 : 2
                columnSpacing: ClockStyle.gap
                rowSpacing: ClockStyle.gap

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: root.compact ? Text.WordWrap : Text.NoWrap
                    maximumLineCount: 2
                    text: root.paused ? Translation.tr("Limits paused")
                        : !root.hasTotal ? (root.total ? Translation.tr("No limit today") : Translation.tr("No daily limit"))
                        : root.limitState === "ignored" ? Translation.tr("%1 over").arg(ScreenTimeLimits.formatSeconds(root.used - root.budget))
                        : root.spent ? Translation.tr("Time's up")
                        : Translation.tr("%1 left").arg(ScreenTimeLimits.formatSeconds(root.budget - root.used))
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: Math.round(Math.max(ClockStyle.textTitle, Math.min(30, root.width * 0.07)))
                    color: root.colContent
                    elide: Text.ElideRight
                }

                LimitsTintButton {
                    symbol: root.total ? "edit" : "add"
                    label: root.total ? Translation.tr("Edit") : Translation.tr("Set limit")
                    colContent: root.colContent
                    solid: !root.total
                    colSolidContent: root.colPane
                    height_: 40
                    onClicked: root.setLimitRequested()
                }
            }
        }

        // ── Week ────────────────────────────────────────────────────────
        LimitsWeekChart {
            Layout.fillWidth: true
            Layout.preferredHeight: 128
            colContent: root.colContent
            colPane: root.colPane
        }

        // ── What the limits did today ───────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            Repeater {
                model: [
                    { symbol: "block", label: Translation.tr("Reached"), value: ScreenTimeLimits.dayState.blocks ?? 0 },
                    { symbol: "more_time", label: Translation.tr("Extra time"), value: ScreenTimeLimits.dayState.ignores ?? 0 },
                    { symbol: "close", label: Translation.tr("Closed"), value: ScreenTimeLimits.dayState.closes ?? 0 }
                ]

                Rectangle {
                    id: statTile
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 64
                    radius: ClockStyle.radiusNormal
                    color: ColorUtils.applyAlpha(root.colContent, 0.1)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        spacing: -2

                        RowLayout {
                            spacing: 6

                            StyledText {
                                text: String(statTile.modelData.value)
                                font.family: ClockStyle.fontMain
                                font.variableAxes: ClockStyle.axesDigitsBold
                                font.pixelSize: 26
                                color: root.colContent
                            }

                            MaterialSymbol {
                                text: statTile.modelData.symbol
                                iconSize: ClockStyle.iconSmall
                                color: root.colContent
                                opacity: 0.8
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: statTile.modelData.label
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                            color: root.colContent
                            opacity: 0.85
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
