pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs
import qs.services

/**
 * The teleprompter, expanded: the card the hover grows the island into —
 * always wider than the strip it came from (the source's `expandedWidth`).
 *
 * Three bands, top to bottom, and nothing else:
 *   1. the progress hairline, full-bleed on the top edge — the state of the
 *      whole card at a glance, warning-coloured while paused;
 *   2. the script, in the user's `expandedLines`, scrolling on the session's
 *      own `scrollY` (the same number the contracted face translates by, so
 *      the morph never jumps);
 *   3. one control bar: the reading time on the left, the adjustments
 *      (speed step, loop, mirror) and the transport (restart, play/pause,
 *      stop) grouped at the right, where the thumb expects them.
 *
 * The registry's expanded box is the cap; this file's `implicitHeight` (a pure
 * function of the configuration) is what the island grows to, so the layout
 * rows in Settings resize the card live.
 */
Item {
    id: root
    anchors.fill: parent

    /** Injectable: the Settings preview drives this same card with a demo session. */
    property var prompter: Teleprompter
    property bool isPreview: false

    readonly property real padX: 20
    readonly property real progressHeight: 3
    readonly property real bandGap: 12
    readonly property real controlsHeight: 48
    readonly property real padBottom: 12
    readonly property real textAreaHeight: Math.round(root.prompter.expandedLines * root.prompter.lineHeightPx)

    implicitHeight: Math.round(root.progressHeight + root.bandGap + root.textAreaHeight
        + root.bandGap + root.controlsHeight + root.padBottom)

    /** The one button style of the card, tinted by what it means. */
    component Action: RippleButton {
        id: action

        property string symbol: ""
        property string tip: ""
        property bool toggled: false
        property bool danger: false
        property bool accent: false
        property real diameter: 36

        implicitWidth: action.diameter
        implicitHeight: action.diameter
        buttonRadius: Appearance.rounding.full

        readonly property color base: action.danger ? Appearance.colors.colErrorContainer
            : action.accent ? Appearance.colors.colPrimary
            : action.toggled ? Appearance.colors.colPrimaryContainer
            // The island's body is a translucent surface, so container colours
            // sit on it like smudges: the neutral actions tint with the content
            // colour instead (the shell's 10/18/26 recipe), which reads on any body.
            : ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.10)
        readonly property color onBase: action.danger ? Appearance.colors.colOnErrorContainer
            : action.accent ? Appearance.colors.colOnPrimary
            : action.toggled ? Appearance.colors.colOnPrimaryContainer
            : Appearance.colors.colOnSurface

        colBackground: action.base
        colBackgroundHover: action.danger || action.accent || action.toggled
            ? ColorUtils.mix(action.base, action.onBase, 0.88)
            : ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.18)
        colBackgroundActive: action.danger || action.accent || action.toggled
            ? ColorUtils.mix(action.base, action.onBase, 0.76)
            : ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.26)
        colRipple: action.danger || action.accent || action.toggled
            ? ColorUtils.mix(action.base, action.onBase, 0.76)
            : ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.26)

        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: action.symbol
            iconSize: action.accent ? 22 : 18
            fill: action.toggled || action.accent || action.danger ? 1 : 0
            color: action.onBase
        }

        StyledToolTip {
            text: action.tip
            requireOverlay: false
        }
    }

    function fmtTime(seconds) {
        const s = Math.max(0, Math.round(seconds));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    readonly property string statusText: {
        if (root.prompter.phase === "ready")
            return Translation.tr("Ready");
        if (root.prompter.phase === "finished")
            return Translation.tr("Script complete");
        if (root.prompter.scrollExtent <= 0)
            return "";
        return Translation.tr("%1 left").arg(root.fmtTime(root.prompter.remainingSeconds));
    }

    // ── 1. The progress hairline, on the top edge ───────────────────────────
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.progressHeight
        visible: root.prompter.showProgress
        color: ColorUtils.applyAlpha(Appearance.colors.colOnSurface, 0.14)

        Rectangle {
            height: parent.height
            width: parent.width * root.prompter.progress
            color: root.prompter.paused ? Appearance.colors.colWarning : Appearance.colors.colPrimary

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // ── 2. The script ───────────────────────────────────────────────────────
    TeleprompterText {
        id: script
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.progressHeight + root.bandGap)
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.textAreaHeight
        prompter: root.prompter
        padX: root.padX
    }

    // ── 3. One control bar ──────────────────────────────────────────────────
    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.padX
        anchors.rightMargin: root.padX
        anchors.bottomMargin: root.padBottom
        height: root.controlsHeight
        spacing: 8

        // The reading time: what a presenter actually needs from the card.
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: root.statusText !== ""
            text: root.statusText
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            font.features: ({
                "tnum": 1
            })
            color: root.prompter.phase === "finished" ? Appearance.colors.colPrimary
                : root.prompter.paused ? Appearance.colors.colWarning : Appearance.colors.colSubtext

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        Item {
            Layout.fillWidth: true
        }

        // Adjustments: how the reading moves.
        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "remove"
            tip: Translation.tr("Slower")
            onClicked: root.prompter.adjustSpeed(-5)
        }

        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "add"
            tip: Translation.tr("Faster")
            onClicked: root.prompter.adjustSpeed(5)
        }

        // Loop and mirror persist to the configuration: they are the setup, not
        // the session, and the Settings page shows the same truth.
        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "repeat"
            tip: Translation.tr("Loop the script")
            toggled: root.prompter.loop
            onClicked: Config.options.dynamicIsland.widgets.teleprompter.loop = !root.prompter.loop
        }

        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "swap_horiz"
            tip: Translation.tr("Mirror for glass rigs")
            toggled: root.prompter.mirror
            onClicked: Config.options.dynamicIsland.widgets.teleprompter.mirror = !root.prompter.mirror
        }

        // The script is edited where text belongs: the Settings sub-page, deep
        // linked straight to it.
        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "edit_note"
            tip: Translation.tr("Edit script")
            onClicked: GlobalStates.openSettingsPage("dynamicIsland", "features/TeleprompterConfig.qml")
        }

        Item {
            Layout.preferredWidth: 12
        }

        // Transport: the three things a session ends or resumes with.
        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "restart_alt"
            tip: Translation.tr("Restart")
            onClicked: root.prompter.restart()
        }

        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: root.prompter.paused || root.prompter.phase === "finished" || root.prompter.phase === "ready" ? "play_arrow" : "pause"
            tip: root.prompter.phase === "finished" ? Translation.tr("Read again")
                : root.prompter.phase === "ready" ? Translation.tr("Start reading")
                : root.prompter.paused ? Translation.tr("Resume") : Translation.tr("Pause")
            diameter: 44
            onClicked: root.prompter.togglePause()
        }

        Action {
            Layout.alignment: Qt.AlignVCenter
            symbol: "stop"
            tip: Translation.tr("Finish and close")
            danger: true
            onClicked: root.prompter.stop()
        }
    }

    // The script area doubles as the pause control, like the contracted face.
    MouseArea {
        anchors.fill: script
        cursorShape: Qt.PointingHandCursor
        onClicked: root.prompter.togglePause()
    }

    WheelHandler {
        onWheel: event => {
            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 4;
            root.prompter.nudge(-delta);
        }
    }
}
