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
 * The wide tile that leads the grid, like the clock's "Next alarm": what is on right now.
 *
 * Modes: the active mode in its own accent — its name in the title face, the time it
 * started in tall condensed digits, and a large stop button; with nothing on, a plain
 * pane offering the last used mode again. Routines: the routine running (the first of
 * them, with a count of the rest) the same way, or how many wait armed.
 *
 * When automatic starts are switched off in Settings, a chip on this tile says so — every
 * surface still works by hand, but nothing starts on its own.
 */
Rectangle {
    id: root

    property bool routine: false
    property real layoutWidth: root.width

    signal openRequested(string id)

    // ── State ───────────────────────────────────────────────────────────
    readonly property var runs: Modes.routineRuns
    readonly property var current: root.routine
        ? (root.runs.length ? Modes.routineById(root.runs[0].id) : null)
        : (Modes.active ? Modes.activeMode : null)
    readonly property bool isOn: root.current !== null && root.current !== undefined
    readonly property real since: root.routine ? (root.runs[0]?.since ?? 0) : Modes.activeSince
    readonly property string source: root.routine ? (root.runs[0]?.source ?? "") : Modes.activeSource
    readonly property string colorKey: root.current?.color ?? ""
    readonly property var lastUsed: root.routine ? null : Modes.lastUsedMode
    readonly property int armedCount: Modes.routines.filter(r => r.enabled !== false && r.triggers.length > 0).length

    readonly property color colContainer: root.isOn ? ModeUi.accent(root.colorKey) : ClockStyle.colIdleCard
    readonly property color colContent: root.isOn ? ModeUi.onAccent(root.colorKey) : ClockStyle.colOnSurface
    readonly property color colContentSoft: root.isOn ? ModeUi.onAccent(root.colorKey) : ClockStyle.colOnIdleCard
    readonly property real digitSize: Math.round(Math.max(36, Math.min(root.height * 0.3, root.layoutWidth * 0.11)))
    readonly property real titleSize: Math.round(Math.max(ClockStyle.textTitle + 2, Math.min(root.height * 0.15, root.layoutWidth * 0.06)))

    readonly property string label: {
        if (root.isOn)
            return root.routine
                ? (root.runs.length > 1 ? Translation.tr("Running now · %1 more").arg(root.runs.length - 1) : Translation.tr("Running now"))
                : Translation.tr("On now");
        return root.routine ? Translation.tr("Nothing running") : Translation.tr("No mode on");
    }

    readonly property string title: {
        if (root.isOn)
            return root.current.name;
        if (root.routine) {
            if (Modes.routines.length === 0)
                return Translation.tr("No routines yet");
            return root.armedCount === 1 ? Translation.tr("1 routine armed") : Translation.tr("%1 routines armed").arg(root.armedCount);
        }
        if (Modes.modes.length === 0)
            return Translation.tr("No modes yet");
        return root.lastUsed ? Translation.tr("Last used: %1").arg(root.lastUsed.name) : Translation.tr("Every mode is off");
    }

    readonly property string detail: {
        if (root.isOn) {
            const parts = [Translation.tr("Started %1").arg(Modes.sourceText(root.source))];
            if (!root.routine && Modes.activeEndsAt > 0)
                parts.push(Translation.tr("ends %1").arg(ModeUi.clock(Modes.activeEndsAt)));
            return parts.join(" · ");
        }
        if (root.routine)
            return Translation.tr("Armed routines run on their own when their conditions hold");
        return root.lastUsed ? Translation.tr("Start it again, or let a mode start on its own")
            : Translation.tr("Turn one on below, or let one start on its own");
    }

    radius: ClockStyle.radiusCard
    color: heroHover.hovered && root.isOn ? ColorUtils.mix(root.colContainer, root.colContent, 0.92) : root.colContainer

    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: heroHover
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.isOn
        cursorShape: root.isOn ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.openRequested(root.current.id)
    }

    // The stop / start control: a circle at rest, a rounded square while something runs —
    // the clock's play button, with a stop glyph because a mode ends rather than pauses.
    component BigButton: RippleButton {
        id: big
        property bool running: false
        property color colFill: ClockStyle.colPrimary
        property color colInk: ClockStyle.colOnPrimary
        property real size: 72

        implicitWidth: big.size
        implicitHeight: big.size
        buttonRadius: big.running ? Math.min(big.size * 0.3, ClockStyle.radiusExtraLarge) : big.size / 2
        buttonRadiusPressed: ClockStyle.radiusLarge
        colBackground: big.colFill
        colBackgroundHover: ColorUtils.mix(big.colFill, big.colInk, 0.88)
        colRipple: ColorUtils.mix(big.colFill, big.colInk, 0.76)

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: big.running ? "stop" : "play_arrow"
                iconSize: big.size * 0.42
                fill: 1
                color: big.colInk
                animateChange: !ClockStyle.reducedMotion
                animationDistanceY: 0
                animationDistanceX: big.size * 0.12
            }
        }
    }

    RowLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding + 4
        }
        spacing: ClockStyle.gapLarge

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                MaterialShapeWrappedMaterialSymbol {
                    text: root.isOn ? (root.current.icon ?? "tune") : (root.routine ? "bolt" : "motion_photos_off")
                    iconSize: 22
                    padding: 10
                    shape: root.routine ? MaterialShape.Shape.Cookie6Sided : MaterialShape.Shape.Cookie9Sided
                    fill: 1
                    color: root.isOn ? root.colContent : ClockStyle.colSecondaryContainer
                    colSymbol: root.isOn ? root.colContainer : ClockStyle.colOnSecondaryContainer
                    rotation: root.isOn ? 30 : 0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.label
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textNormal + 1
                    font.weight: Font.DemiBold
                    color: root.colContent
                }

                // Engine switched off: nothing starts on its own. Said here rather than
                // discovered.
                Rectangle {
                    visible: !Modes.enabled
                    implicitWidth: offRow.implicitWidth + ClockStyle.gapLarge
                    implicitHeight: 30
                    radius: ClockStyle.radiusSmall
                    color: ClockStyle.colErrorContainer

                    RowLayout {
                        id: offRow
                        anchors.centerIn: parent
                        spacing: ClockStyle.gapTiny + 2

                        MaterialSymbol {
                            text: "motion_photos_paused"
                            iconSize: ClockStyle.iconSmall
                            color: ClockStyle.colOnErrorContainer
                        }

                        StyledText {
                            text: Translation.tr("Automatic starts are off")
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnErrorContainer
                        }
                    }

                    HoverHandler {
                        id: offHover
                    }
                    StyledToolTip {
                        extraVisibleCondition: offHover.hovered
                        text: Translation.tr("Everything still works by hand. Turn them back on in Settings → Modes & Routines.")
                    }
                }
            }

            Item {
                Layout.fillHeight: true
            }

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                wrapMode: Text.Wrap
                maximumLineCount: 2
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: root.titleSize
                color: root.colContent
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                // The start time in the clock's tall digits, for whatever is on.
                StyledText {
                    visible: root.isOn && root.since > 0
                    text: ModeUi.clock(root.since)
                    font.family: ClockStyle.fontMain
                    font.variableAxes: ClockStyle.axesDigitsBold
                    font.pixelSize: root.digitSize
                    color: root.colContent
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: root.isOn ? root.digitSize * 0.14 : 0
                    spacing: 0

                    StyledText {
                        visible: root.isOn && root.since > 0
                        text: Translation.tr("since")
                        font.family: ClockStyle.fontMain
                        font.variableAxes: ClockStyle.axesDigits
                        font.pixelSize: Math.round(Math.max(15, root.digitSize * 0.3))
                        color: root.colContent
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.detail
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        color: root.colContentSoft
                        opacity: 0.9
                    }
                }
            }
        }

        BigButton {
            Layout.alignment: Qt.AlignBottom
            visible: root.isOn || (root.lastUsed !== null && root.lastUsed !== undefined)
            running: root.isOn
            colFill: root.isOn ? root.colContent : ClockStyle.colPrimary
            colInk: root.isOn ? root.colContainer : ClockStyle.colOnPrimary
            onClicked: {
                if (root.routine) {
                    Modes.toggleRoutine(root.current.id);
                    return;
                }
                if (root.isOn)
                    Modes.toggle(root.current.id);
                else
                    Modes.toggleLast();
            }

            StyledToolTip {
                text: root.isOn
                    ? (root.routine ? Translation.tr("Stop %1").arg(root.current?.name ?? "") : Translation.tr("Turn off %1").arg(root.current?.name ?? ""))
                    : Translation.tr("Turn on %1").arg(root.lastUsed?.name ?? "")
            }
        }
    }
}
