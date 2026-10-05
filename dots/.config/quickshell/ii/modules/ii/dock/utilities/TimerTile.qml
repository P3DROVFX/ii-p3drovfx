import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.clock.components

/**
 * Timer. The ring drawn on the tile drains with the countdown the dock follows
 * (the first running, else the first paused, else one that just finished).
 * Square: the ring hugging the tile around the time left — minutes, or m:ss in
 * the last ten; idle, an hourglass on a cookie. A click pauses or resumes;
 * with nothing set it opens the quick start. Wide: ring + control, the time
 * over "of 25 min", and +1:00 — or, idle, the three preset durations.
 */
UtilityTile {
    id: tile

    readonly property int tick: TimerService.countdownTick
    readonly property var countdowns: TimerService.countdowns ?? []
    readonly property var current: {
        tile.tick;
        const list = tile.countdowns;
        return list.find(c => !c.notified && !c.paused)
            ?? list.find(c => !c.notified && c.paused)
            ?? list.find(c => c.notified)
            ?? null;
    }
    readonly property bool active: tile.current !== null && !tile.current.notified
    readonly property bool finished: tile.current?.notified ?? false
    readonly property bool paused: tile.current?.paused ?? false
    readonly property int secondsLeft: { tile.tick; return tile.current ? TimerService.countdownSecondsLeft(tile.current) : 0; }
    readonly property real remainingFraction: tile.current
        ? tile.secondsLeft / Math.max(1, tile.current.durationSeconds ?? 1) : 0
    readonly property string timeText: TimerService.formatCountdownDuration(tile.secondsLeft)
    readonly property string shortText: tile.secondsLeft >= 3600 ? Math.ceil(tile.secondsLeft / 3600) + "h"
        : tile.secondsLeft >= 600 ? String(Math.ceil(tile.secondsLeft / 60))
        : Math.floor(tile.secondsLeft / 60) + ":" + ClockFormat.pad(tile.secondsLeft % 60)
    readonly property var presets: Config.options?.dock?.utilities?.timer?.presets ?? [1, 5, 10, 25]
    readonly property int runningCount: tile.countdowns.filter(c => !c.notified).length

    surfaceColor: tile.finished ? ClockStyle.colErrorContainer
        : tile.active && !tile.paused ? ClockStyle.colPrimaryContainer
        : tile.active ? ClockStyle.colSecondaryContainer
        : ClockStyle.colSurfaceHigh
    contentColor: tile.finished ? ClockStyle.colOnErrorContainer
        : tile.active && !tile.paused ? ClockStyle.colOnPrimaryContainer
        : tile.active ? ClockStyle.colOnSecondaryContainer
        : ClockStyle.colOnSurface
    readonly property color ringColor: tile.finished ? ClockStyle.colError
        : tile.paused ? ClockStyle.colOnSecondaryContainer : ClockStyle.colPrimary

    tooltipText: tile.finished ? Translation.tr("%1 finished").arg(tile.current.label)
        : tile.active ? Translation.tr("%1 · %2 left").arg(tile.current.label).arg(tile.timeText)
        : Translation.tr("Timer")
    panelSubtitle: tile.runningCount === 0 ? Translation.tr("Nothing running")
        : tile.runningCount === 1 ? Translation.tr("1 timer") : Translation.tr("%1 timers").arg(tile.runningCount)
    menuActions: tile.active ? [
        { id: "toggle", icon: tile.paused ? "play_arrow" : "pause", text: tile.paused ? Translation.tr("Resume") : Translation.tr("Pause") },
        { id: "extend", icon: "more_time", text: Translation.tr("Add 1 minute") },
        { id: "cancel", icon: "close", text: Translation.tr("Cancel timer") }
    ] : tile.presets.slice(0, 3).map(minutes => ({
        id: "start:" + minutes, icon: "timer_play", text: Translation.tr("Start %1 min").arg(minutes)
    }))

    function durationText(seconds) {
        return seconds % 60 === 0 ? Translation.tr("%1 min").arg(seconds / 60) : ClockFormat.shortDuration(seconds);
    }

    function start(minutes) {
        TimerService.addCountdown(minutes);
    }

    function activate() {
        if (tile.finished) {
            TimerService.removeCountdown(tile.current.id);
            return true;
        }
        if (tile.active && !tile.wide && (Config.options?.dock?.utilities?.timer?.clickPauses ?? true)) {
            TimerService.toggleCountdown(tile.current.id);
            return true;
        }
        return false;
    }

    function menuAction(actionId) {
        if (actionId === "toggle")
            TimerService.toggleCountdown(tile.current.id);
        else if (actionId === "extend")
            TimerService.extendCountdown(tile.current.id, 60);
        else if (actionId === "cancel")
            TimerService.removeCountdown(tile.current.id);
        else if (actionId.indexOf("start:") === 0)
            tile.start(Number(actionId.slice(6)));
    }

    // ── Square ──────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: !tile.wide

        ClockProgressRing {
            anchors.fill: parent
            anchors.margins: Math.round(tile.side * 0.08)
            visible: tile.active || tile.finished
            value: tile.active ? tile.remainingFraction : 0
            thickness: Math.max(3, Math.round(tile.side * 0.075))
            wavy: tile.active && !tile.paused && !Appearance.reducedMotion
            waves: 9
            tickDuration: 1000
            colIndicator: tile.ringColor
            colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.14)
        }
        TileValue {
            anchors.centerIn: parent
            visible: tile.active
            text: tile.shortText
            color: tile.contentColor
            font.pixelSize: Math.round(tile.side * (tile.shortText.length > 3 ? 0.27 : 0.36))
        }
        TileBadge {
            anchors.centerIn: parent
            visible: !tile.active
            width: Math.round(tile.side * (tile.finished ? 0.58 : 0.74))
            height: width
            renderScale: tile.renderScale
            shape: tile.finished ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie7Sided
            color: tile.finished ? ClockStyle.colError : ClockStyle.colSecondaryContainer
            colSymbol: tile.finished ? ClockStyle.colOnError : ClockStyle.colOnSecondaryContainer
            text: tile.finished ? "alarm" : "hourglass_empty"
            iconScale: 0.52
        }
    }

    // ── Wide, running ───────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide && (tile.active || tile.finished)
        spacing: tile.pad

        Item {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            ClockProgressRing {
                anchors.fill: parent
                value: tile.active ? tile.remainingFraction : 0
                thickness: Math.max(3, Math.round(tile.badgeSize * 0.09))
                wavy: tile.active && !tile.paused && !Appearance.reducedMotion
                waves: 8
                tickDuration: 1000
                colIndicator: tile.ringColor
                colTrack: ColorUtils.applyAlpha(tile.contentColor, 0.14)
            }
            TileButton {
                anchors.centerIn: parent
                width: Math.round(tile.badgeSize * 0.64)
                height: width
                symbol: tile.finished ? "check" : tile.paused ? "play_arrow" : "pause"
                filled: true
                colFilled: tile.finished ? ClockStyle.colError : ClockStyle.colPrimary
                colOnFilled: tile.finished ? ClockStyle.colOnError : ClockStyle.colOnPrimary
                active: tile.active && !tile.paused
                iconScale: 0.6
                onClicked: tile.finished ? TimerService.removeCountdown(tile.current.id) : TimerService.toggleCountdown(tile.current.id)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: -2
            TileValue {
                Layout.fillWidth: true
                text: tile.finished ? Translation.tr("Done") : tile.timeText
                color: tile.contentColor
                font.pixelSize: tile.valueSize
            }
            TileCaption {
                Layout.fillWidth: true
                text: tile.current ? Translation.tr("of %1").arg(tile.durationText(tile.current.durationSeconds ?? 0))
                    + (tile.runningCount > 1 ? " · +" + (tile.runningCount - 1) : "") : ""
                color: tile.captionColor
                font.pixelSize: tile.captionSize
            }
        }

        TileButton {
            visible: tile.active
            implicitWidth: Math.round(tile.badgeSize * 0.84)
            implicitHeight: implicitWidth
            symbol: "more_time"
            tip: Translation.tr("Add 1 minute")
            colContent: tile.contentColor
            onClicked: TimerService.extendCountdown(tile.current.id, 60)
        }
    }

    // ── Wide, idle: three presets, each a pill with its minutes ─────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: tile.pad
        visible: tile.wide && !tile.active && !tile.finished
        spacing: Math.round(tile.pad * 0.7)

        TileBadge {
            implicitWidth: tile.badgeSize
            implicitHeight: tile.badgeSize
            renderScale: tile.renderScale
            shape: MaterialShape.Shape.Cookie7Sided
            color: ClockStyle.colSecondaryContainer
            colSymbol: ClockStyle.colOnSecondaryContainer
            text: "hourglass_empty"
            iconScale: 0.5
        }

        Repeater {
            model: tile.presets.slice(0, 3)
            delegate: Item {
                id: preset
                required property int modelData
                Layout.fillWidth: true
                Layout.preferredHeight: tile.badgeSize
                Rectangle {
                    anchors.fill: parent
                    radius: presetArea.pressed ? Math.round(height * 0.24) : height / 2
                    color: ColorUtils.applyAlpha(tile.contentColor, presetArea.pressed ? 0.2 : presetArea.containsMouse ? 0.14 : 0.07)
                    Behavior on radius {
                        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
                    }
                }
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 1
                    TileValue {
                        Layout.alignment: Qt.AlignBaseline
                        text: String(preset.modelData)
                        color: tile.contentColor
                        font.pixelSize: Math.round(tile.badgeSize * 0.5)
                    }
                    TileCaption {
                        Layout.alignment: Qt.AlignBaseline
                        font.capitalization: Font.MixedCase
                        text: Translation.tr("m")
                        color: tile.captionColor
                        font.pixelSize: tile.captionSize
                    }
                }
                MouseArea {
                    id: presetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tile.start(preset.modelData)
                }
            }
        }
    }
}
