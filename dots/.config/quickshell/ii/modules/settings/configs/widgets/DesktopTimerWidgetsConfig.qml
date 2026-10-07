import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.productivity
import qs.modules.settings.configs.widgets

/*
 * One page for the Pomodoro, Stopwatch and Countdown widgets (1x1 each). They
 * run on the Clock app's timers, so the durations and the presets here are
 * the Clock app's own.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var pomodoro: Config.options.time.pomodoro

    WidgetPageHeader {
        title: Translation.tr("Timer Widgets Options")
        onBack: root.goBack()
    }

    WidgetPreviewStage {
        columns: 3
        rows: 1

        WidgetPreviewSlot {
            PomodoroWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 1
            StopwatchWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
        WidgetPreviewSlot {
            column: 2
            CountdownWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }
    }

    ContentSection {
        title: Translation.tr("Pomodoro (1x1)")
        icon: "timer"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "timer_pomodoro" }
            WidgetSizeSlider { options: root.widgets.timer_pomodoro }

            ConfigSwitch {
                buttonIcon: "waves"
                text: Translation.tr("Wavy ring")
                checked: root.widgets.timer_pomodoro.wavyRing ?? true
                onCheckedChanged: root.widgets.timer_pomodoro.wavyRing = checked
                StyledToolTip {
                    text: Translation.tr("Draw the phase's ring as a wave; off, it is a plain arc.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Durations (shared with the Clock app)")
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "psychiatry"
                    text: Translation.tr("Focus (min)")
                    value: Math.round(root.pomodoro.focus / 60)
                    from: 1
                    to: 180
                    stepSize: 1
                    onValueChanged: if (Math.round(root.pomodoro.focus / 60) !== value) root.pomodoro.focus = value * 60
                }
                ConfigSpinBox {
                    icon: "coffee"
                    text: Translation.tr("Break (min)")
                    value: Math.round(root.pomodoro.breakTime / 60)
                    from: 1
                    to: 60
                    stepSize: 1
                    onValueChanged: if (Math.round(root.pomodoro.breakTime / 60) !== value) root.pomodoro.breakTime = value * 60
                }
            }

            ConfigRow {
                uniform: true

                ConfigSpinBox {
                    icon: "self_improvement"
                    text: Translation.tr("Long break (min)")
                    value: Math.round(root.pomodoro.longBreak / 60)
                    from: 1
                    to: 120
                    stepSize: 1
                    onValueChanged: if (Math.round(root.pomodoro.longBreak / 60) !== value) root.pomodoro.longBreak = value * 60
                }
                ConfigSpinBox {
                    icon: "repeat"
                    text: Translation.tr("Cycles before a long break")
                    value: root.pomodoro.cyclesBeforeLongBreak
                    from: 1
                    to: 12
                    stepSize: 1
                    onValueChanged: root.pomodoro.cyclesBeforeLongBreak = value
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Stopwatch (1x1)")
        icon: "timer_play"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "timer_stopwatch" }
            WidgetSizeSlider { options: root.widgets.timer_stopwatch }
        }
    }

    ContentSection {
        title: Translation.tr("Countdown (1x1)")
        icon: "hourglass_bottom"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "timer_countdown" }
            WidgetSizeSlider { options: root.widgets.timer_countdown }

            ConfigSwitch {
                buttonIcon: "notifications"
                text: Translation.tr("Notify when a timer ends")
                checked: Config.options.time.timer.notify ?? true
                onCheckedChanged: Config.options.time.timer.notify = checked
                StyledToolTip {
                    text: Translation.tr("Send a notification as well as the sound. Shared with the Clock app.")
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("The quick-start keys are the first four presets of the Clock app's timer.")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
