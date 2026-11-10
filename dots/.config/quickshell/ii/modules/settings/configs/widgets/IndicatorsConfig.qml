import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Indicators & Timers")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        icon: "timer"
        title: Translation.tr("Indicators & Timers")

        ContentSubsection {
            title: Translation.tr("Timer widget style")

            ConfigSelectionArray {
                currentValue: Config.options.bar.styles.timer
                onSelected: newValue => Config.options.bar.styles.timer = String(newValue)
                options: [
                    { displayName: Translation.tr("Default"), icon: "style", value: "default" },
                    { displayName: Translation.tr("Expressive"), icon: "fluid_med", value: "expressive" },
                    { displayName: Translation.tr("Sculpt"), icon: "shapes", value: "sculpt" }
                ]
            }
        }

        ContentSubsection {
            visible: Config.options.bar.styles.timer === "sculpt"
            title: Translation.tr("Sculpt variant")

            ConfigSelectionArray {
                currentValue: Config.options.bar.timers.sculptVariant
                onSelected: newValue => Config.options.bar.timers.sculptVariant = String(newValue)
                options: [
                    { displayName: Translation.tr("Squeeze"), icon: "compress", value: "squeeze" },
                    { displayName: Translation.tr("Fill"), icon: "battery_horiz_075", value: "fill" },
                    { displayName: Translation.tr("Phases"), icon: "linear_scale", value: "phases" }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.timer === "sculpt" && Config.options.bar.timers.sculptVariant === "squeeze"
            materialIcon: "compress"
            text: Translation.tr("Tall digits that condense as the time runs out: wide when the timer is fresh, narrow in its last seconds. A break is set slanted, a paused timer light.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.timer === "sculpt" && Config.options.bar.timers.sculptVariant === "fill"
            materialIcon: "battery_horiz_075"
            text: Translation.tr("The capsule is the progress bar: the vivid tone fills it as the time goes, and the digits change colour exactly where the fill's edge crosses them.")
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: Config.options.bar.styles.timer === "sculpt" && Config.options.bar.timers.sculptVariant === "phases"
            materialIcon: "linear_scale"
            text: Translation.tr("A display label (Focus, Break, the countdown's name) over a segmented indicator with one segment per pomodoro of the cycle, beside the time.")
        }

        ExpressiveColorModeSubsection {
            visible: Config.options.bar.styles.timer === "expressive" || Config.options.bar.styles.timer === "sculpt"
            currentValue: Config.options.bar.timers.colorMode
            onSelected: newValue => Config.options.bar.timers.colorMode = String(newValue)
        }

        ConfigSwitch {
            buttonIcon: "timer"
            text: Translation.tr("Show stopwatch")
            checked: Config.options.bar.timers.showStopwatch
            onCheckedChanged: {
                Config.options.bar.timers.showStopwatch = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "search_activity"
            text: Translation.tr("Show pomodoro")
            checked: Config.options.bar.timers.showPomodoro
            onCheckedChanged: {
                Config.options.bar.timers.showPomodoro = checked;
            }
        }
        ConfigSwitch {
            buttonIcon: "hourglass_top"
            text: Translation.tr("Show countdown timers")
            checked: Config.options.bar.timers.showCountdowns
            onCheckedChanged: {
                Config.options.bar.timers.showCountdowns = checked;
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("The record indicator has its own page now — style, variant, colour and minimal mode all live there. Open it from Bar \u2192 Widgets \u2192 Record Indicator.")
            color: Appearance.colors.colOnLayer1
            opacity: 0.75
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
    }
}
