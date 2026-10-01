pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.modes

/**
 * One mode — or, with `routine`, one routine — as an expressive tile: its shaped icon in
 * its own colour, the name in the title face, how it starts and what it does, a chip for
 * where it stands right now, and the switch it exists for.
 *
 * A mode that is on (a routine that is running) takes its accent as the whole tile, the
 * way an enabled alarm takes the primary container; everything else sits on the pane
 * colour with only the shape tinted. Hovering reveals move earlier / later (list order is
 * priority among automatic starts), duplicate and delete, the clock's card actions.
 */
Rectangle {
    id: root

    required property var def
    property bool routine: false
    /// Place in the list (priority for modes) and the list's length, for the move actions.
    property int position: 0
    property int count: 1
    /// The keyboard cursor is on this tile.
    property bool focusRing: false
    /// The settled width to size the name by; the live width may be mid-animation.
    property real layoutWidth: root.width

    signal openRequested()
    signal moveRequested(int delta)
    signal duplicateRequested()
    signal deleteRequested()

    // ── State ───────────────────────────────────────────────────────────
    readonly property string defId: root.def?.id ?? ""
    readonly property string colorKey: root.def?.color ?? ""
    readonly property bool active: root.routine ? Modes.isRoutineRunning(root.defId) : Modes.activeModeId === root.defId
    readonly property var watcher: {
        Modes.watchersRevision;
        return root.routine ? Modes.routineWatcherFor(root.defId) : Modes.watcherFor(root.defId);
    }
    readonly property var triggers: root.def?.triggers ?? []
    readonly property var actions: root.def?.actions ?? []
    readonly property bool hasTriggers: root.triggers.length > 0
    readonly property bool automatic: root.routine ? root.def?.enabled !== false : root.def?.auto === true
    readonly property bool holds: root.hasTriggers && Modes.triggersHold(root.watcher)
    readonly property bool suppressed: root.routine ? Modes.isRoutineSuppressed(root.defId) : Modes.isSuppressed(root.defId)
    readonly property bool once: root.routine && root.def?.kind === "once"
    /// A routine switched off: it still runs by hand, so it dims rather than greys out.
    readonly property bool dimmed: root.routine && root.hasTriggers && !root.automatic && !root.active

    readonly property var chip: {
        if (root.active)
            return { symbol: "radio_button_checked", label: root.routine ? Translation.tr("Running") : Translation.tr("On") };
        if (!root.hasTriggers)
            return { symbol: "touch_app", label: Translation.tr("By hand") };
        if (!root.automatic)
            return { symbol: "motion_photos_off", label: root.routine ? Translation.tr("Off") : Translation.tr("Auto start off") };
        if (root.suppressed)
            return { symbol: "pause_circle", label: Translation.tr("Waits for a reset") };
        if (root.holds)
            return { symbol: "check_circle", label: Translation.tr("Conditions hold"), strong: true };
        return { symbol: "hourglass_empty", label: root.once ? Translation.tr("Armed") : Translation.tr("Waiting") };
    }

    // ── Words ───────────────────────────────────────────────────────────
    function actionsText(): string {
        const list = Array.from(root.actions);
        if (list.length === 0)
            return root.routine ? Translation.tr("Does nothing yet") : Translation.tr("Changes nothing yet");
        const names = list.filter(a => a.type !== "wait").map(a => ModeUi.actionLabel(a.type));
        const shown = names.slice(0, 2).join(", ");
        return names.length > 2 ? Translation.tr("%1 +%2").arg(shown).arg(names.length - 2) : shown;
    }

    function startsText(): string {
        if (!root.hasTriggers)
            return Translation.tr("Starts by hand");
        const schedule = Array.from(root.triggers).find(t => t.type === "schedule" && !t.not);
        if (schedule && root.automatic) {
            const from = schedule.from === "sunrise" ? Translation.tr("sunrise")
                : schedule.from === "sunset" ? Translation.tr("sunset") : schedule.from;
            const days = ModeUi.daysText(schedule.days);
            return Translation.tr("Starts at %1").arg(from) + (days.length ? " · " + days : "");
        }
        return ModeUi.modeStatus(root.def);
    }

    readonly property string headline: {
        if (!root.routine) {
            if (!root.active)
                return root.startsText();
            const since = Translation.tr("On since %1").arg(ModeUi.clock(Modes.activeSince));
            return Modes.activeEndsAt > 0 ? since + " · " + Translation.tr("until %1").arg(ModeUi.clock(Modes.activeEndsAt)) : since;
        }
        const then = root.actionsText();
        if (!root.hasTriggers)
            return Translation.tr("By hand → %1").arg(then);
        const first = ModeUi.triggerText(root.triggers[0]);
        const cause = root.triggers.length > 1 ? Translation.tr("%1 +%2").arg(first).arg(root.triggers.length - 1) : first;
        return Translation.tr("If %1 → %2").arg(cause).arg(then);
    }

    readonly property string footline: {
        if (!root.routine)
            return root.actionsText();
        const run = Modes.routineRun(root.defId);
        if (run)
            return Translation.tr("Running since %1").arg(ModeUi.clock(run.since));
        const last = ModeUi.lastRoutineEvent(root.defId);
        if (last)
            return Translation.tr("Last %1 · %2").arg(ModeUi.historyEventText(last).toLowerCase()).arg(ModeUi.whenText(last.t));
        return Translation.tr("Never ran");
    }

    // ── Colours ─────────────────────────────────────────────────────────
    readonly property color colContainer: root.active ? ModeUi.accent(root.colorKey) : ClockStyle.colIdleCard
    readonly property color colContainerHover: root.active
        ? ColorUtils.mix(ModeUi.accent(root.colorKey), ModeUi.onAccent(root.colorKey), 0.9) : ClockStyle.colIdleCardHover
    readonly property color colContent: root.active ? ModeUi.onAccent(root.colorKey) : ClockStyle.colOnSurface
    readonly property color colContentSoft: root.active ? ModeUi.onAccent(root.colorKey) : ClockStyle.colOnIdleCard
    readonly property real nameSize: Math.round(Math.max(20, Math.min(30, root.layoutWidth * 0.1)))

    readonly property bool engaged: cardHover.hovered || actionRow.focusInside

    radius: ClockStyle.radiusCard
    color: root.engaged ? root.colContainerHover : root.colContainer

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    // The run button of a routine: play to run it now, stop while it runs.
    component RunButton: RippleButton {
        id: runButton
        property bool running: false
        property color colFill: ClockStyle.colPrimaryContainer
        property color colInk: ClockStyle.colOnPrimaryContainer

        implicitWidth: 44
        implicitHeight: 44
        buttonRadius: runButton.running ? ClockStyle.radiusNormal : 22
        buttonRadiusPressed: ClockStyle.radiusSmall
        colBackground: runButton.colFill
        colBackgroundHover: ColorUtils.mix(runButton.colFill, runButton.colInk, 0.88)
        colRipple: ColorUtils.mix(runButton.colFill, runButton.colInk, 0.76)

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: runButton.running ? "stop" : "play_arrow"
            iconSize: ClockStyle.iconNormal
            fill: 1
            color: runButton.colInk
        }
    }

    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.openRequested()
    }

    // The keyboard cursor, drawn over the tile so it never shifts the content.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 3
        border.color: root.active ? root.colContent : ClockStyle.colPrimary
        visible: root.focusRing
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding
            topMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.gapLarge
            bottomMargin: ClockStyle.gapLarge
        }
        spacing: 0

        // ── Icon and hover actions ──────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            spacing: ClockStyle.gapSmall

            MaterialShapeWrappedMaterialSymbol {
                text: root.def?.icon ?? (root.routine ? "bolt" : "tune")
                iconSize: 22
                padding: 10
                shape: root.routine ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Cookie9Sided
                fill: root.active ? 1 : 0
                color: root.active ? ModeUi.onAccent(root.colorKey) : ModeUi.container(root.colorKey)
                colSymbol: root.active ? ModeUi.accent(root.colorKey) : ModeUi.onContainer(root.colorKey)
                rotation: root.active ? 30 : (cardHover.hovered ? 12 : 0)
                opacity: root.dimmed ? 0.55 : 1
            }

            // Says the mode may start on its own; a bare trigger does not.
            MaterialSymbol {
                visible: !root.routine && root.automatic && root.hasTriggers
                text: "autoplay"
                iconSize: ClockStyle.iconSmall
                color: root.colContentSoft

                HoverHandler {
                    id: autoHover
                }
                StyledToolTip {
                    extraVisibleCondition: autoHover.hovered
                    text: Translation.tr("Starts on its own when its conditions hold")
                }
            }

            MaterialSymbol {
                visible: root.once
                text: "bolt"
                iconSize: ClockStyle.iconSmall
                color: root.colContentSoft

                HoverHandler {
                    id: onceHover
                }
                StyledToolTip {
                    extraVisibleCondition: onceHover.hovered
                    text: Translation.tr("Fires once when its conditions become true")
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // The world clock's reveal: one animated extent slides the actions in.
            Item {
                id: actionSlot
                property real revealProgress: root.engaged ? 1 : 0

                Layout.preferredWidth: (actionRow.implicitWidth + 4) * actionSlot.revealProgress
                Layout.preferredHeight: actionRow.implicitHeight
                clip: true

                Behavior on revealProgress {
                    animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    id: actionRow
                    readonly property bool focusInside: earlierButton.activeFocus || laterButton.activeFocus
                        || duplicateButton.activeFocus || deleteButton.activeFocus

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    opacity: actionSlot.revealProgress
                    enabled: root.engaged

                    ClockCardAction {
                        id: earlierButton
                        symbol: "arrow_back"
                        tip: root.routine ? Translation.tr("Move earlier") : Translation.tr("Higher priority")
                        colContent: root.colContent
                        enabled: root.engaged && root.position > 0
                        onClicked: root.moveRequested(-1)
                    }
                    ClockCardAction {
                        id: laterButton
                        symbol: "arrow_forward"
                        tip: root.routine ? Translation.tr("Move later") : Translation.tr("Lower priority")
                        colContent: root.colContent
                        enabled: root.engaged && root.position < root.count - 1
                        onClicked: root.moveRequested(1)
                    }
                    ClockCardAction {
                        id: duplicateButton
                        symbol: "content_copy"
                        tip: Translation.tr("Duplicate")
                        colContent: root.colContent
                        onClicked: root.duplicateRequested()
                    }
                    ClockCardAction {
                        id: deleteButton
                        symbol: "delete"
                        tip: Translation.tr("Delete")
                        danger: true
                        onClicked: root.deleteRequested()
                    }
                }
            }
        }

        // ── Name ────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledText {
                id: nameText
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: ClockStyle.gapTiny
                }
                text: root.def?.name ?? ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                lineHeight: 0.92
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: root.nameSize
                color: root.colContent

                HoverHandler {
                    id: nameHover
                }
                StyledToolTip {
                    extraVisibleCondition: nameHover.hovered && nameText.truncated
                    text: nameText.text
                }
            }
        }

        StyledText {
            id: headlineText
            Layout.fillWidth: true
            text: root.headline
            elide: Text.ElideRight
            font.pixelSize: ClockStyle.textNormal + 1
            font.weight: Font.DemiBold
            color: root.colContent

            HoverHandler {
                id: headlineHover
            }
            StyledToolTip {
                extraVisibleCondition: headlineHover.hovered && headlineText.truncated
                text: headlineText.text
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.footline
            elide: Text.ElideRight
            font.pixelSize: ClockStyle.textSmall
            color: root.colContentSoft
            opacity: 0.85
        }

        // ── State and switch ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: ClockStyle.gapSmall
            Layout.preferredHeight: 44
            spacing: ClockStyle.gapSmall

            Rectangle {
                id: stateChip
                Layout.maximumWidth: Math.max(0, parent.width - 120)
                implicitWidth: chipRow.implicitWidth + ClockStyle.gap + 4
                implicitHeight: 30
                radius: ClockStyle.radiusSmall
                color: root.active ? ColorUtils.applyAlpha(root.colContent, 0.16)
                    : root.chip.strong ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
                clip: true

                readonly property color colInk: root.active ? root.colContent
                    : root.chip.strong ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant

                Behavior on color {
                    animation: ClockStyle.motionFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    id: chipRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: ClockStyle.gapSmall
                    spacing: ClockStyle.gapTiny

                    MaterialSymbol {
                        text: root.chip.symbol
                        iconSize: ClockStyle.iconSmall - 1
                        fill: root.active || root.chip.strong ? 1 : 0
                        color: stateChip.colInk
                    }

                    StyledText {
                        text: root.chip.label
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        color: stateChip.colInk
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            RunButton {
                visible: root.routine
                running: root.active
                colFill: root.active ? ModeUi.onAccent(root.colorKey) : ModeUi.container(root.colorKey)
                colInk: root.active ? ModeUi.accent(root.colorKey) : ModeUi.onContainer(root.colorKey)
                onClicked: Modes.toggleRoutine(root.defId)

                StyledToolTip {
                    text: root.active ? Translation.tr("Stop") : Translation.tr("Run now")
                }
            }

            // Modes: the switch starts and stops the mode. Routines: whether it may run
            // on its own (a routine without conditions only runs by hand).
            StyledSwitch {
                visible: !root.routine || root.hasTriggers
                sizeScale: 1.0
                checked: root.routine ? root.automatic : root.active
                checkable: false
                activeColor: root.active ? root.colContent : ClockStyle.colPrimary
                activeThumbColor: root.active ? root.colContainer : ClockStyle.colOnPrimary
                onClicked: {
                    if (root.routine)
                        Modes.upsertRoutine(Object.assign({}, root.def, { enabled: !root.automatic }));
                    else
                        Modes.toggle(root.defId);
                }

                StyledToolTip {
                    text: root.routine
                        ? (root.automatic ? Translation.tr("Runs on its own — switch off to run it by hand only")
                            : Translation.tr("Let it run on its own when its conditions hold"))
                        : (root.active ? Translation.tr("Turn off") : Translation.tr("Turn on"))
                }
            }
        }
    }
}
