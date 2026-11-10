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
 * The rules column of the Limits page: app limits as a dense grid of tiles, a strip of
 * suggestions drawn from today's biggest apps, and the focus schedules below.
 *
 * Column count and tile sizes are decided on the settled width (`layoutWidth`) so a
 * side sheet sliding in re-deals the tiles instead of squeezing them frame by frame.
 */
Item {
    id: root

    property real layoutWidth: root.width
    /// False when a parent flickable already scrolls (the narrow layout).
    property bool scrolls: true
    property string editingId: ""

    signal editLimit(var limit)
    signal editSchedule(var schedule)
    signal newLimit()
    signal newLimitFor(string key)
    signal newSchedule()
    signal settingsRequested()
    signal guard(var action)

    readonly property real gridGap: ClockStyle.gap
    readonly property real contentWidth: root.width - ClockStyle.gapTiny * 2
    readonly property real contentLayoutWidth: root.layoutWidth - ClockStyle.gapTiny * 2
    readonly property int columns: Math.max(1, Math.floor((root.contentLayoutWidth + root.gridGap) / (250 + root.gridGap)))
    readonly property real tileLayoutWidth: (root.contentLayoutWidth - root.gridGap * (root.columns - 1)) / root.columns
    /// One animated width shared by every tile. Each tile animating its own width
    /// while the flow shrank with the page on another curve let a row briefly hold
    /// more than it could, and its last tile dropped to the next row and back.
    property real tileWidth: root.tileLayoutWidth
    Behavior on tileWidth {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
    }
    /// Wide enough for `columns` tiles at the animated width, whatever the page does.
    readonly property real flowWidth: Math.max(root.contentWidth, root.contentLayoutWidth,
        Math.ceil(root.tileWidth * root.columns + root.gridGap * (root.columns - 1)) + 1)
    readonly property int scheduleSpan: root.columns >= 4 ? 2 : 1
    readonly property real tileHeight: Math.round(Math.max(206, Math.min(236, root.tileLayoutWidth * 0.8)))

    readonly property var appLimits: ScreenTimeLimits.limits.filter(l => l.kind !== "total")
    readonly property var schedules: ScreenTimeLimits.schedules
    /// Today's biggest apps that no limit covers yet.
    readonly property var suggestions: {
        const covered = [];
        for (const l of root.appLimits)
            for (const k of l.keys ?? [])
                covered.push(k);
        return ScreenTimeLimits.todayApps()
            .filter(e => !covered.includes(e.key) && e.seconds >= 300)
            .slice(0, Math.max(2, Math.min(5, root.columns + 1)));
    }

    implicitHeight: content.implicitHeight + (root.scrolls ? ClockStyle.fabClearance : 0)

    component SectionHeader: RowLayout {
        id: header
        property string title: ""
        property string subtitle: ""
        default property alias trailing: trailingRow.data

        Layout.fillWidth: true
        spacing: ClockStyle.gap

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: header.title
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle + 2
                color: ClockStyle.colOnBackground
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: header.subtitle.length > 0
                text: header.subtitle
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
                elide: Text.ElideRight
            }
        }

        RowLayout {
            id: trailingRow
            spacing: ClockStyle.gapSmall
        }
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.implicitHeight
        interactive: root.scrolls && contentHeight > height
        clip: root.scrolls

        ColumnLayout {
            id: content
            x: ClockStyle.gapTiny
            y: ClockStyle.gapTiny
            width: root.contentWidth
            spacing: ClockStyle.gapLarge

            SectionHeader {
                title: Translation.tr("App limits")
                subtitle: Translation.tr("Focused time only · resets at midnight")

                MaterialSymbol {
                    visible: ScreenTimeLimits.editsLocked
                    text: "lock"
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: ClockStyle.colSubtext

                    HoverHandler {
                        id: lockedHover
                    }
                    StyledToolTip {
                        extraVisibleCondition: lockedHover.hovered
                        text: Translation.tr("Changes need the PIN")
                    }
                }

                ClockIconButton {
                    symbol: "tune"
                    tooltip: Translation.tr("Limit settings")
                    onClicked: root.settingsRequested()
                }
            }

            // ── App limits ──────────────────────────────────────────────
            Flow {
                id: limitGrid
                visible: root.appLimits.length > 0
                Layout.preferredWidth: root.flowWidth
                spacing: root.gridGap

                move: Transition {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        properties: "x,y"
                        duration: ClockStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                    }
                }

                Repeater {
                    model: root.appLimits

                    LimitTile {
                        id: tile
                        required property var modelData
                        required property int index
                        width: Math.floor(root.tileWidth)
                        height: root.tileHeight
                        limit: tile.modelData
                        layoutWidth: root.tileLayoutWidth
                        editing: root.editingId === tile.modelData.id
                        onEditRequested: root.editLimit(tile.modelData)
                        onDeleteRequested: root.guard(() => ScreenTimeLimits.removeLimit(tile.modelData.id))
                        onToggleRequested: on => {
                            if (on)
                                ScreenTimeLimits.setLimitEnabled(tile.modelData.id, true);
                            else
                                root.guard(() => ScreenTimeLimits.setLimitEnabled(tile.modelData.id, false));
                        }

                        StaggeredEntrance {
                            index: tile.index
                            step: ClockStyle.staggerStep
                            active: !ClockStyle.reducedMotion
                        }
                    }
                }
            }

            // Nothing limited yet: say what a limit does and offer the first one.
            Rectangle {
                visible: root.appLimits.length === 0
                Layout.fillWidth: true
                implicitHeight: emptyRow.implicitHeight + ClockStyle.cardPadding * 2
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane

                RowLayout {
                    id: emptyRow
                    anchors.fill: parent
                    anchors.margins: ClockStyle.cardPadding
                    spacing: ClockStyle.gapHuge

                    MaterialShapeWrappedMaterialSymbol {
                        text: "timer"
                        iconSize: 40
                        padding: 22
                        shape: MaterialShape.Shape.Gem
                        color: ClockStyle.colSecondaryContainer
                        colSymbol: ClockStyle.colOnSecondaryContainer
                        fill: 1
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("No app limits yet")
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: ClockStyle.textLarge + 2
                            color: ClockStyle.colOnSurface
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Give an app a daily budget. When it runs out, the app is covered until you close it or take more time.")
                            wrapMode: Text.WordWrap
                            font.pixelSize: ClockStyle.textNormal
                            color: ClockStyle.colSubtext
                        }
                    }

                    ClockButton {
                        variant: "filled"
                        symbol: "more_time"
                        label: Translation.tr("Add a limit")
                        onClicked: root.newLimit()
                    }
                }
            }

            // ── Suggestions ─────────────────────────────────────────────
            ColumnLayout {
                visible: root.suggestions.length > 0
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: Translation.tr("Most used today")
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                    color: ClockStyle.colOnSurfaceVariant
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    Repeater {
                        model: root.suggestions

                        RippleButton {
                            id: suggestion
                            required property var modelData
                            implicitHeight: 44
                            implicitWidth: suggestionRow.implicitWidth + 28
                            buttonRadius: ClockStyle.pill(44)
                            buttonRadiusPressed: ClockStyle.radiusSmall
                            colBackground: ClockStyle.colSurfaceHigh
                            colBackgroundHover: ClockStyle.colSurfaceHover
                            colRipple: ClockStyle.colSurfaceActive
                            onClicked: root.newLimitFor(suggestion.modelData.key)

                            contentItem: Item {
                                RowLayout {
                                    id: suggestionRow
                                    anchors.centerIn: parent
                                    spacing: ClockStyle.gapSmall

                                    LimitsAppIcon {
                                        size: 24
                                        appKey: suggestion.modelData.key
                                    }

                                    StyledText {
                                        text: AppStats.displayName(suggestion.modelData.key)
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: Font.DemiBold
                                        color: ClockStyle.colOnSurface
                                    }

                                    StyledText {
                                        text: ScreenTimeLimits.formatSeconds(suggestion.modelData.seconds)
                                        font.pixelSize: ClockStyle.textSmall
                                        color: ClockStyle.colSubtext
                                    }

                                    MaterialSymbol {
                                        text: "add"
                                        iconSize: ClockStyle.iconSmall
                                        color: ClockStyle.colPrimary
                                    }
                                }
                            }

                            StyledToolTip {
                                text: Translation.tr("Limit %1").arg(AppStats.displayName(suggestion.modelData.key))
                            }
                        }
                    }
                }
            }

            // ── Schedules ───────────────────────────────────────────────
            SectionHeader {
                Layout.topMargin: ClockStyle.gapSmall
                title: Translation.tr("Focus schedules")
                subtitle: Translation.tr("Block apps between two times of day")

                ClockButton {
                    variant: "tonal"
                    symbol: "add_alarm"
                    label: Translation.tr("New schedule")
                    iconOnly: root.layoutWidth < 520
                    onClicked: root.newSchedule()
                }
            }

            Flow {
                visible: root.schedules.length > 0
                Layout.preferredWidth: root.flowWidth
                spacing: root.gridGap

                move: Transition {
                    enabled: !ClockStyle.reducedMotion
                    NumberAnimation {
                        properties: "x,y"
                        duration: ClockStyle.motionDefault.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: ClockStyle.motionDefault.bezierCurve
                    }
                }

                Repeater {
                    model: root.schedules

                    ScheduleTile {
                        id: scheduleTile
                        required property var modelData
                        required property int index
                        readonly property int span: root.scheduleSpan
                        width: Math.floor(root.tileWidth * span + root.gridGap * (span - 1))
                        height: 236
                        schedule: scheduleTile.modelData
                        layoutWidth: root.tileLayoutWidth * span
                        editing: root.editingId === "s:" + scheduleTile.modelData.id
                        onEditRequested: root.editSchedule(scheduleTile.modelData)
                        onDeleteRequested: root.guard(() => ScreenTimeLimits.removeSchedule(scheduleTile.modelData.id))
                        onToggleRequested: on => {
                            if (on)
                                ScreenTimeLimits.setScheduleEnabled(scheduleTile.modelData.id, true);
                            else
                                root.guard(() => ScreenTimeLimits.setScheduleEnabled(scheduleTile.modelData.id, false));
                        }

                        StaggeredEntrance {
                            index: scheduleTile.index + root.appLimits.length
                            step: ClockStyle.staggerStep
                            active: !ClockStyle.reducedMotion
                        }
                    }
                }
            }

            Rectangle {
                visible: root.schedules.length === 0
                Layout.fillWidth: true
                implicitHeight: 76
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: ClockStyle.cardPadding
                    anchors.rightMargin: ClockStyle.cardPadding
                    spacing: ClockStyle.gap

                    MaterialShapeWrappedMaterialSymbol {
                        text: "bedtime"
                        iconSize: 20
                        padding: 10
                        shape: MaterialShape.Shape.Fan
                        color: ClockStyle.colTertiaryContainer
                        colSymbol: ClockStyle.colOnTertiaryContainer
                        fill: 1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Keep games off during work hours, or everything off at night.")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        color: ClockStyle.colSubtext
                    }
                }
            }
        }
    }
}
