import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.clock
import qs.modules.settings.configs.widgets

/*
 * One page for the Weight (1x1), Width (2x1) and Stack (1x2) type clocks. The
 * hero is the three real clocks, live, as the grid cells they take on the
 * desktop - with or without their card, as set below.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var weightOptions: root.widgets.clock_type_weight
    readonly property var widthOptions: root.widgets.clock_type_width
    readonly property var stackOptions: root.widgets.clock_type_stack

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
            text: Translation.tr("Type Clocks Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Live preview: [ Stack 1x2 ][ Width 2x1      ]
    //                  [           ][ Weight ][ info ]
    Rectangle {
        id: stage
        Layout.fillWidth: true
        implicitHeight: Math.round(stage.boardHeight * stage.boardScale) + stage.padding * 2
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1

        readonly property real padding: 20
        readonly property real cell: 240
        readonly property real gap: 12
        readonly property real step: stage.cell + stage.gap
        readonly property real boardWidth: stage.cell * 3 + stage.gap * 2
        readonly property real boardHeight: stage.cell * 2 + stage.gap
        readonly property real boardScale: Math.min(1, Math.max(0.1, (stage.width - stage.padding * 2) / stage.boardWidth))

        Item {
            anchors.centerIn: parent
            width: stage.boardWidth
            height: stage.boardHeight
            scale: stage.boardScale

            Item {
                x: 0
                y: 0
                width: stage.cell
                height: stage.boardHeight
                StackClockWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.height / Math.max(1, implicitHeight)
                }
            }

            Item {
                x: stage.step
                y: 0
                width: stage.cell * 2 + stage.gap
                height: stage.cell
                WidthClockWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Item {
                x: stage.step
                y: stage.step
                width: stage.cell
                height: stage.cell
                WeightClockWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Rectangle {
                x: stage.step * 2
                y: stage.step
                width: stage.cell
                height: stage.cell
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 4

                    MaterialShapeWrappedMaterialSymbol {
                        shape: MaterialShape.Shape.Cookie9Sided
                        text: "text_fields"
                        iconSize: 26
                        padding: 14
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Type clocks")
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Weights and widths move with the time, easing into each new minute.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Weight Clock ──
    ContentSection {
        title: Translation.tr("Weight Clock (1x1)")
        icon: "format_bold"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "clock_type_weight" }
            SizeSlider { options: root.weightOptions }
            BackgroundRow { options: root.weightOptions }

            ConfigSwitch {
                buttonIcon: "line_weight"
                text: Translation.tr("Minutes weigh the hour")
                checked: root.weightOptions.weightFollowsMinutes ?? true
                onCheckedChanged: root.weightOptions.weightFollowsMinutes = checked
                StyledToolTip {
                    text: Translation.tr("The minutes grow from a hairline at :00 to the hours' weight at :59; off, they stay light.")
                }
            }
        }
    }

    // ── Width Clock ──
    ContentSection {
        title: Translation.tr("Width Clock (2x1)")
        icon: "width"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "clock_type_width" }
            SizeSlider { options: root.widthOptions }
            BackgroundRow { options: root.widthOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Width follows the hour")
                    checked: root.widthOptions.widthFollowsHour ?? true
                    onCheckedChanged: root.widthOptions.widthFollowsHour = checked
                    StyledToolTip {
                        text: Translation.tr("The hours narrow and the minutes widen as the hour passes; off, the hours stay wide and the minutes narrow.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "wb_twilight"
                    text: Translation.tr("Part of the day")
                    checked: root.widthOptions.showPartOfDay ?? true
                    onCheckedChanged: root.widthOptions.showPartOfDay = checked
                    StyledToolTip {
                        text: Translation.tr("Write morning, afternoon, evening or night above the time.")
                    }
                }
            }
        }
    }

    // ── Stack Clock ──
    ContentSection {
        title: Translation.tr("Stack Clock (1x2)")
        icon: "view_agenda"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "clock_type_stack" }
            SizeSlider { options: root.stackOptions }
            BackgroundRow { options: root.stackOptions }

            ConfigSwitch {
                buttonIcon: "vertical_align_top"
                text: Translation.tr("Heavy on top")
                checked: root.stackOptions.heavyTop ?? true
                onCheckedChanged: root.stackOptions.heavyTop = checked
                StyledToolTip {
                    text: Translation.tr("Ramp the weight from the top digit down; off, the bottom digit is the heaviest.")
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
