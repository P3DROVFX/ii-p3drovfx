pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Countdown (1x1). The card is the hourglass: a fill rises from the foot to
 * the share of time still left and sinks second by second; the digits and the
 * label are drawn twice, so the part under the fill turns to the fill's own
 * content colour. With no timer, quick-start keys; a timer that ran out
 * turns the fill to the warning colour until it is restarted or dismissed.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "timer_countdown"
    designWidth: 240
    designHeight: 240

    readonly property real padding: 16
    readonly property real digitSize: 84
    readonly property real keyHeight: 44

    // The Clock app's presets (seconds), the first four.
    readonly property var presets: {
        const list = Array.from(Config.options?.time?.timer?.presets ?? []).map(Number).filter(n => n > 0);
        return list.length > 0 ? list.slice(0, 4) : [60, 300, 600, 1500];
    }

    function presetLabel(seconds) {
        if (seconds >= 3600 && seconds % 3600 === 0)
            return (seconds / 3600) + "h";
        if (seconds % 60 === 0)
            return (seconds / 60) + "m";
        return seconds + "s";
    }

    readonly property var countdowns: Array.from(TimerService.countdowns ?? [])
    // Shown: the one that runs (or waits paused) first, else the last to ring.
    readonly property var current: root.countdowns.find(c => !c.notified) ?? root.countdowns.find(c => c.notified) ?? null
    readonly property int others: Math.max(0, root.countdowns.filter(c => !c.notified).length - (root.current && !root.current.notified ? 1 : 0))
    readonly property bool finished: root.current?.notified === true
    readonly property bool paused: root.current?.paused === true
    readonly property int secondsLeft: {
        TimerService.countdownTick;
        return root.current ? TimerService.countdownSecondsLeft(root.current) : 0;
    }
    readonly property real leftFraction: {
        if (!root.current)
            return 0;
        if (root.finished)
            return 1;
        return Math.max(0, Math.min(1, root.secondsLeft / Math.max(1, Number(root.current.durationSeconds ?? 1))));
    }

    readonly property color fillColor: root.finished ? WidgetColorScheme.warningColor : WidgetColorScheme.accentColor
    readonly property color onFillColor: root.finished ? root.contentOn(WidgetColorScheme.warningColor) : WidgetColorScheme.onAccentColor

    // ── Hourglass fill ──
    Rectangle {
        id: fill
        visible: root.current !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * root.leftFraction
        // Square at the waterline unless it reaches the card's own top corners.
        topLeftRadius: height > parent.height - Appearance.rounding.large ? Appearance.rounding.large : 0
        topRightRadius: topLeftRadius
        bottomLeftRadius: Appearance.rounding.large
        bottomRightRadius: Appearance.rounding.large
        color: root.fillColor

        // A tick glides over exactly its second; a jump (+1:00, restart) eases.
        Behavior on height {
            enabled: !Appearance.reducedMotion
            NumberAnimation {
                duration: 1000
                easing.type: Easing.Linear
            }
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    // The readout, drawn once above the fill and once clipped to it.
    component Readout: Item {
        id: readout
        property color colMain
        property color colSub
        width: root.designWidth
        height: root.designHeight

        StyledText {
            x: root.padding + 2
            y: root.padding
            width: parent.width - root.padding * 2 - 50
            elide: Text.ElideRight
            text: root.finished ? Translation.tr("Time's up") : String(root.current?.label ?? "")
            color: readout.colSub
            font.pixelSize: Appearance.font.pixelSize.small
            font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
        }

        Text {
            x: root.padding - 2
            y: 30
            text: TimerService.formatCountdownDuration(root.secondsLeft)
            color: readout.colMain
            font.family: Appearance.font.family.main
            font.pixelSize: root.secondsLeft >= 3600 ? Math.round(root.digitSize * 0.74) : root.digitSize
            font.variableAxes: ({ "wght": root.paused ? 480 : 760, "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }
    }

    Item {
        visible: root.current !== null
        anchors.fill: parent

        Readout {
            colMain: WidgetColorScheme.textColorOnBg
            colSub: WidgetColorScheme.subtextColorOnBg
        }

        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: fill.height
            clip: true

            Readout {
                y: -(root.designHeight - parent.height)
                colMain: root.onFillColor
                colSub: root.onFillColor
            }
        }
    }

    // More timers than the one shown.
    Rectangle {
        visible: root.others > 0
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding - 4
        width: othersText.implicitWidth + 16
        height: 24
        radius: root.pill(height)
        color: WidgetColorScheme.pillBgColor

        StyledText {
            id: othersText
            anchors.centerIn: parent
            text: "+" + root.others
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── Keys for a timer ──
    Row {
        visible: root.current !== null
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        spacing: 6

        readonly property real keyWidth: (root.designWidth - root.padding * 2 - spacing * 2) / 3
        // On the fill the keys take its content colour as their fill, so they
        // stay keys instead of holes.
        readonly property color keyFill: ColorUtils.applyAlpha(root.onFillColor, 0.18)

        WidgetButton {
            width: parent.keyWidth
            height: root.keyHeight
            symbol: root.finished ? "close" : "delete"
            symbolSize: 20
            colFill: parent.keyFill
            colContent: root.onFillColor
            onClicked: TimerService.removeCountdown(root.current.id)
        }

        WidgetButton {
            width: parent.keyWidth
            height: root.keyHeight
            symbol: root.finished ? "replay" : (root.paused ? "play_arrow" : "pause")
            symbolSize: 24
            colFill: root.onFillColor
            colContent: root.fillColor
            restRadius: root.paused || root.finished ? root.pill(height) : Appearance.rounding.small
            onClicked: {
                if (root.finished)
                    TimerService.restartCountdown(root.current.id);
                else
                    TimerService.toggleCountdown(root.current.id);
            }
        }

        WidgetButton {
            width: parent.keyWidth
            height: root.keyHeight
            enabled: !root.finished
            label: "+1:00"
            labelAxes: ({ "wght": 650, "wdth": 90, "ROND": 100 })
            colFill: parent.keyFill
            colContent: root.onFillColor
            onClicked: TimerService.extendCountdown(root.current.id, 60)
        }
    }

    // ── No timer: quick start ──
    Item {
        visible: root.current === null
        anchors.fill: parent

        StyledText {
            x: root.padding + 2
            y: root.padding
            text: Translation.tr("Timer").toUpperCase()
            color: WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.letterSpacing: 1.5
        }

        StyledText {
            x: root.padding + 2
            y: 40
            width: parent.width - root.padding * 2
            text: Translation.tr("Start a timer")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.huge + 4
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }

        Grid {
            x: root.padding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.padding
            columns: 2
            spacing: 8

            Repeater {
                model: root.presets

                delegate: WidgetButton {
                    id: preset
                    required property var modelData
                    required property int index
                    width: (root.designWidth - root.padding * 2 - 8) / 2
                    height: 62
                    restRadius: Appearance.rounding.normal
                    colFill: preset.index === 0 ? WidgetColorScheme.pillFillColor : WidgetColorScheme.pillBgColor
                    colContent: preset.index === 0 ? WidgetColorScheme.textColorOnPillFill : WidgetColorScheme.textColorOnBg
                    onClicked: TimerService.addCountdownSeconds(Number(preset.modelData))

                    contentItem: Item {
                        Text {
                            anchors.centerIn: parent
                            text: root.presetLabel(Number(preset.modelData))
                            color: preset.colContent
                            font.family: Appearance.font.family.main
                            font.pixelSize: 34
                            font.variableAxes: ({ "wght": 700, "wdth": 60, "ROND": 100, "opsz": 72 })
                            renderType: Text.QtRendering
                        }
                    }
                }
            }
        }
    }
}
