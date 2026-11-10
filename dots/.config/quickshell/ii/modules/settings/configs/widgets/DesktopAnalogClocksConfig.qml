import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.settings.configs.widgets

/*
 * One page for the Numeral (1x1) and Duo (2x1) analog clocks. The hero is the
 * two real clocks, live, as the grid cells they take on the desktop - with or
 * without their card, as set below.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var numeralOptions: root.widgets.clock_numeral
    readonly property var duoOptions: root.widgets.clock_duo

    function placementNote(widgetId) {
        const count = Config.countWidgetInstances(widgetId);
        if (count === 0)
            return Translation.tr("Not on the desktop. Add it from Desktop Widgets; these options apply once it is there.");
        return count === 1 ? Translation.tr("On the desktop.") : Translation.tr("On the desktop %1 times.").arg(count);
    }

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
            text: Translation.tr("Analog Clocks Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Live preview: [ Numeral 1x1 ][ Duo 2x1 ] ──
    Rectangle {
        id: stage
        Layout.fillWidth: true
        implicitHeight: Math.round(stage.boardHeight * stage.boardScale) + stage.padding * 2
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        readonly property real padding: 20
        readonly property real cell: 240
        readonly property real gap: 12
        readonly property real boardWidth: stage.cell * 3 + stage.gap * 2
        readonly property real boardHeight: stage.cell
        readonly property real boardScale: Math.min(1, Math.max(0.1, (stage.width - stage.padding * 2) / stage.boardWidth))

        Item {
            anchors.centerIn: parent
            width: stage.boardWidth
            height: stage.boardHeight
            scale: stage.boardScale

            Item {
                width: stage.cell
                height: stage.cell
                NumeralClockWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Item {
                x: stage.cell + stage.gap
                width: stage.cell * 2 + stage.gap
                height: stage.cell
                DuoClockWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }
        }
    }

    // ── Numeral Clock ──
    ContentSection {
        title: Translation.tr("Numeral Clock (1x1)")
        icon: "schedule"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "clock_numeral" }
            SizeSlider { options: root.numeralOptions }
            BackgroundRow { options: root.numeralOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "format_list_numbered"
                    text: Translation.tr("Roman numerals")
                    checked: root.numeralOptions.romanNumerals ?? false
                    onCheckedChanged: root.numeralOptions.romanNumerals = checked
                    StyledToolTip {
                        text: Translation.tr("Write the dial in Roman numerals instead of Arabic ones.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "today"
                    text: Translation.tr("Date")
                    checked: root.numeralOptions.showDate ?? true
                    onCheckedChanged: root.numeralOptions.showDate = checked
                    StyledToolTip {
                        text: Translation.tr("Show the weekday and day under the centre of the dial.")
                    }
                }
            }
        }
    }

    // ── Duo Clock ──
    ContentSection {
        title: Translation.tr("Duo Clock (2x1)")
        icon: "nest_clock_farsight_analog"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "clock_duo" }
            SizeSlider { options: root.duoOptions }
            BackgroundRow { options: root.duoOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "waves"
                    text: Translation.tr("Wavy minute ring")
                    checked: root.duoOptions.wavyRing ?? true
                    onCheckedChanged: root.duoOptions.wavyRing = checked
                    StyledToolTip {
                        text: Translation.tr("Draw the minutes' progress ring as a wave; off, it is a plain arc.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "pin"
                    text: Translation.tr("Hour numerals")
                    checked: root.duoOptions.showNumerals ?? true
                    onCheckedChanged: root.duoOptions.showNumerals = checked
                    StyledToolTip {
                        text: Translation.tr("Mark 12, 3, 6 and 9 on the hour dial.")
                    }
                }
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

    component PlacementNote: StyledText {
        property string widgetId
        Layout.fillWidth: true
        text: root.placementNote(widgetId)
        color: Appearance.colors.colOnSurfaceVariant
        font.pixelSize: Appearance.font.pixelSize.small
        wrapMode: Text.Wrap
    }

    component SizeSlider: ConfigSlider {
        property var options
        buttonIcon: "aspect_ratio"
        text: Translation.tr("Widget Size")
        value: options?.widgetSize ?? 100
        from: 50
        to: 200
        stepSize: 10
        onValueChanged: if (options) options.widgetSize = value
    }

    component BackgroundRow: ConfigRow {
        id: backgroundRow
        property var options
        Layout.fillWidth: true
        uniform: true

        ConfigSwitch {
            buttonIcon: "rectangle"
            text: Translation.tr("Background")
            checked: backgroundRow.options?.showBackground ?? true
            onCheckedChanged: if (backgroundRow.options) backgroundRow.options.showBackground = checked
            StyledToolTip {
                text: Translation.tr("Draw the card behind the clock; off, the type sits straight on the wallpaper.")
            }
        }
        ConfigSwitch {
            buttonIcon: "shadow"
            text: Translation.tr("Text shadow")
            enabled: !(backgroundRow.options?.showBackground ?? true)
            checked: backgroundRow.options?.textShadow ?? true
            onCheckedChanged: if (backgroundRow.options) backgroundRow.options.textShadow = checked
            StyledToolTip {
                text: Translation.tr("Without the card, put a soft shadow under the type so it reads on busy wallpapers.")
            }
        }
    }
}
