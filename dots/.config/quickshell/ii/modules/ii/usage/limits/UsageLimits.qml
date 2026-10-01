pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Limits tab of the usage overlay: today's focused time against the day's budget,
 * the app limits, the focus schedules, and their editors.
 *
 * Laid out like the clock app: a hero pane holds the one number the page is about, a
 * grid of tiles holds the rules, and every editor is a side sheet that pushes the page
 * instead of covering it. The page FAB adds a limit.
 */
Item {
    id: root

    // ── Layout ──────────────────────────────────────────────────────────
    /// Settled width handed down by the app, so layout doesn't shake while the rail folds.
    property real layoutWidth: width
    /// Compact window: the sheet takes the whole page instead of pushing it.
    property bool compact: false
    /// The window-level time/date picker host, so pickers centre over the whole app.
    property var pickers: null

    readonly property real sheetWidth: root.compact ? root.width
        : Math.max(ClockStyle.sheetWidthMin, Math.min(ClockStyle.sheetWidth + 20, root.layoutWidth * 0.3))
    /// Settled page width: every layout decision reads this, not the live width.
    readonly property real pageLayoutWidth: root.compact ? root.layoutWidth
        : root.layoutWidth - (sidePanel.open ? root.sheetWidth + ClockStyle.paneGap : 0)
    readonly property bool wide: !root.compact && root.pageLayoutWidth >= 820
    readonly property real heroWidth: root.wide ? Math.round(Math.max(340, Math.min(440, root.pageLayoutWidth * 0.34))) : root.pageLayoutWidth
    readonly property real gridLayoutWidth: root.wide ? root.pageLayoutWidth - root.heroWidth - ClockStyle.paneGap : root.pageLayoutWidth

    readonly property var appLimits: ScreenTimeLimits.limits.filter(l => l.kind !== "total")
    readonly property var schedules: ScreenTimeLimits.schedules

    Component.onCompleted: {
        ScreenTimeLimits.watch(true);
        AppStats.ensureDates(AppStats.recentDates(7));
    }
    Component.onDestruction: ScreenTimeLimits.watch(false)

    function handleKey(key: int): bool {
        return false;
    }

    // ── Editors ─────────────────────────────────────────────────────────
    /// Runs `action` at once, or after the PIN when edits are protected.
    function guarded(action): void {
        if (!ScreenTimeLimits.editsLocked) {
            action();
            return;
        }
        sidePanel.show(pinSheet, {
            unlockAction: action
        });
    }

    function editLimit(limit): void {
        root.guarded(() => sidePanel.show(limitSheet, {
            source: limit
        }));
    }

    function newLimit(kind: string): void {
        root.guarded(() => sidePanel.show(limitSheet, {
            source: null,
            startKind: kind
        }));
    }

    function newLimitFor(key: string): void {
        root.guarded(() => sidePanel.show(limitSheet, {
            source: null,
            startKind: "app",
            startKeys: [key]
        }));
    }

    function editSchedule(schedule): void {
        root.guarded(() => sidePanel.show(scheduleSheet, {
            source: schedule
        }));
    }

    function openSettings(): void {
        root.guarded(() => sidePanel.show(settingsSheet, {}));
    }

    readonly property string editingId: sidePanel.open ? String(sidePanel.current?.editingId ?? "") : ""

    Component {
        id: limitSheet
        LimitEditorSheet {}
    }
    Component {
        id: scheduleSheet
        ScheduleEditorSheet {}
    }
    Component {
        id: settingsSheet
        LimitsSettingsSheet {}
    }
    Component {
        id: pinSheet
        LimitsPinSheet {}
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Page ────────────────────────────────────────────────────────
        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !(root.compact && sidePanel.open)
            clip: true

            // Wide: the hero on the left at full height, the rules beside it.
            Loader {
                anchors.fill: parent
                active: root.wide
                visible: active
                sourceComponent: RowLayout {
                    spacing: ClockStyle.paneGap

                    LimitsHero {
                        Layout.preferredWidth: root.heroWidth
                        Layout.fillHeight: true
                        Behavior on Layout.preferredWidth {
                            enabled: !ClockStyle.reducedMotion
                            animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
                        }
                        onSetLimitRequested: {
                            const total = ScreenTimeLimits.totalLimit();
                            if (total)
                                root.editLimit(total);
                            else
                                root.newLimit("total");
                        }
                        onPauseRequested: on => root.guarded(() => ScreenTimeLimits.setPaused(on))
                    }

                    LimitsRules {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        layoutWidth: root.gridLayoutWidth
                        editingId: root.editingId
                        onEditLimit: limit => root.editLimit(limit)
                        onEditSchedule: schedule => root.editSchedule(schedule)
                        onNewLimit: root.newLimit("app")
                        onNewLimitFor: key => root.newLimitFor(key)
                        onNewSchedule: root.editSchedule(null)
                        onSettingsRequested: root.openSettings()
                        onGuard: action => root.guarded(action)
                    }
                }
            }

            // Narrow: one scrolling column, the hero first.
            Loader {
                anchors.fill: parent
                active: !root.wide
                visible: active
                sourceComponent: StyledFlickable {
                    contentWidth: width
                    contentHeight: narrowColumn.implicitHeight + ClockStyle.fabClearance
                    clip: true

                    ColumnLayout {
                        id: narrowColumn
                        width: parent.width
                        spacing: ClockStyle.paneGap

                        LimitsHero {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 470
                            compact: true
                            onSetLimitRequested: {
                                const total = ScreenTimeLimits.totalLimit();
                                if (total)
                                    root.editLimit(total);
                                else
                                    root.newLimit("total");
                            }
                            onPauseRequested: on => root.guarded(() => ScreenTimeLimits.setPaused(on))
                        }

                        LimitsRules {
                            Layout.fillWidth: true
                            layoutWidth: root.gridLayoutWidth
                            scrolls: false
                            editingId: root.editingId
                            onEditLimit: limit => root.editLimit(limit)
                            onEditSchedule: schedule => root.editSchedule(schedule)
                            onNewLimit: root.newLimit("app")
                            onNewLimitFor: key => root.newLimitFor(key)
                            onNewSchedule: root.editSchedule(null)
                            onSettingsRequested: root.openSettings()
                            onGuard: action => root.guarded(action)
                        }
                    }
                }
            }

            FloatingActionButton {
                id: pageFab
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: ClockStyle.gapLarge
                anchors.bottomMargin: ClockStyle.gapLarge
                z: 5
                baseSize: ClockStyle.fabSizeLarge
                iconSize: 34
                buttonRadius: Appearance.rounding.large
                buttonRadiusPressed: Appearance.rounding.normal
                iconText: "more_time"
                buttonText: Translation.tr("New limit")
                expanded: hovered
                colBackground: Appearance.colors.colPrimaryContainer
                colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                colBackgroundActive: Appearance.colors.colPrimaryContainerActive
                colRipple: Appearance.colors.colPrimaryContainerActive
                colOnBackground: Appearance.colors.colOnPrimaryContainer
                onClicked: root.newLimit("app")
            }
        }

        // ── Side sheet ──────────────────────────────────────────────────
        Item {
            id: sheetSlot
            Layout.fillHeight: true
            Layout.preferredWidth: sidePanel.open ? root.sheetWidth + (root.compact ? 0 : ClockStyle.paneGap) : 0
            visible: Layout.preferredWidth > 1
            clip: true

            Behavior on Layout.preferredWidth {
                enabled: !ClockStyle.reducedMotion
                animation: ClockStyle.motionDefault.numberAnimation.createObject(this)
            }

            ClockSidePanel {
                id: sidePanel
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                width: root.sheetWidth
                pickers: root.pickers
            }
        }
    }
}
