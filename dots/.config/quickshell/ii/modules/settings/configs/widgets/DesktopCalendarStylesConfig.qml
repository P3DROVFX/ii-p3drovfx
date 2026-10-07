import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.DateWidget
import qs.modules.settings.configs.widgets

/*
 * One page for the Date Stack, Date Banner, Date Type, Date Shapes, Week Strip,
 * Week Agenda and Month Tall widgets. The hero is the seven real widgets, live, laid out as the grid
 * cells they take on the desktop; the options follow in plain sections.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets
    readonly property var stackOptions: root.widgets.calendar_date_stack
    readonly property var bannerOptions: root.widgets.calendar_date_banner
    readonly property var stripOptions: root.widgets.calendar_week_strip
    readonly property var agendaOptions: root.widgets.calendar_week_agenda
    readonly property var monthOptions: root.widgets.calendar_month_tall
    readonly property var typeOptions: root.widgets.calendar_date_type
    readonly property var shapesOptions: root.widgets.calendar_date_shapes

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
            text: Translation.tr("Calendar Styles Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Live preview: grid cells, 4 x 4 ──
    //   [ Month ][ Agenda  ][ Stack ]
    //   [ 1x2   ][ 2x2     ][ info  ]
    //   [ Banner 2x1 ][ Strip 2x0.5 ]
    //   [ Type 2x1   ][ Shapes 2x1  ]
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
        readonly property real boardWidth: stage.cell * 4 + stage.gap * 3
        readonly property real boardHeight: stage.cell * 4 + stage.gap * 3
        readonly property real boardScale: Math.min(1, Math.max(0.1, (stage.width - stage.padding * 2) / stage.boardWidth))

        Item {
            anchors.centerIn: parent
            width: stage.boardWidth
            height: stage.boardHeight
            scale: stage.boardScale

            Slot {
                x: 0
                y: 0
                width: stage.cell
                height: stage.cell * 2 + stage.gap
                MonthTallWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.height / Math.max(1, implicitHeight)
                }
            }

            Slot {
                x: stage.step
                y: 0
                width: stage.cell * 2 + stage.gap
                height: width
                WeekAgendaWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Slot {
                x: stage.step * 3
                y: 0
                width: stage.cell
                height: stage.cell
                DateStackWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            // What the calendar holds this week
            Rectangle {
                x: stage.step * 3
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
                        text: CalendarService.khalAvailable ? "event_available" : "event_busy"
                        iconSize: 26
                        padding: 14
                        color: Appearance.colors.colPrimaryContainer
                        colSymbol: Appearance.colors.colOnPrimaryContainer
                    }

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Calendar")
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: CalendarService.khalAvailable
                            ? Translation.tr("Events come from khal.")
                            : Translation.tr("khal is not set up, so the widgets show dates without events.")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }

            Slot {
                x: 0
                y: stage.step * 2
                width: stage.cell * 2 + stage.gap
                height: stage.cell
                DateBannerWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Slot {
                x: stage.step * 2
                y: stage.step * 2
                width: stage.cell * 2 + stage.gap
                height: stage.cell
                WeekStripWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Slot {
                x: 0
                y: stage.step * 3
                width: stage.cell * 2 + stage.gap
                height: stage.cell
                DateTypeWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }

            Slot {
                x: stage.step * 2
                y: stage.step * 3
                width: stage.cell * 2 + stage.gap
                height: stage.cell
                DateShapesWidget {
                    anchors.centerIn: parent
                    isPreview: true
                    scale: parent.width / Math.max(1, implicitWidth)
                }
            }
        }
    }

    // ── Date Stack ──
    ContentSection {
        title: Translation.tr("Date Stack (1x1)")
        icon: "today"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_date_stack" }
            SizeSlider { options: root.stackOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "interests"
                    text: Translation.tr("Cookie behind the day")
                    checked: root.stackOptions.showShape ?? true
                    onCheckedChanged: root.stackOptions.showShape = checked
                    StyledToolTip {
                        text: Translation.tr("Set the day on a primary cookie shape; off, the day is drawn in the accent color on the card.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "tag"
                    text: Translation.tr("Week number")
                    checked: root.stackOptions.showWeekNumber ?? true
                    onCheckedChanged: root.stackOptions.showWeekNumber = checked
                    StyledToolTip {
                        text: Translation.tr("Show the ISO week number beside the weekday.")
                    }
                }
            }
        }
    }

    // ── Date Banner ──
    ContentSection {
        title: Translation.tr("Date Banner (2x1)")
        icon: "event_note"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_date_banner" }
            SizeSlider { options: root.bannerOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "format_italic"
                    text: Translation.tr("Italic headline")
                    checked: root.bannerOptions.italicHeadline ?? true
                    onCheckedChanged: root.bannerOptions.italicHeadline = checked
                    StyledToolTip {
                        text: Translation.tr("Slant the weekday headline; off, it is upright and rounded.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "event_upcoming"
                    text: Translation.tr("Next event")
                    checked: root.bannerOptions.showNextEvent ?? true
                    onCheckedChanged: root.bannerOptions.showNextEvent = checked
                    StyledToolTip {
                        text: Translation.tr("Show the next event of the week in the fact sheet; off, it shows how much of the year has passed.")
                    }
                }
            }
        }
    }

    // ── Date Type ──
    ContentSection {
        title: Translation.tr("Date Type (2x1)")
        icon: "text_fields"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_date_type" }
            SizeSlider { options: root.typeOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "format_bold"
                    text: Translation.tr("Heavy first")
                    checked: root.typeOptions.heavyFirst ?? true
                    onCheckedChanged: root.typeOptions.heavyFirst = checked
                    StyledToolTip {
                        text: Translation.tr("Start the weekday heavy and wide and thin it out letter by letter; off, it runs the other way.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "format_color_text"
                    text: Translation.tr("Accent weekday")
                    checked: root.typeOptions.accentWord ?? false
                    onCheckedChanged: root.typeOptions.accentWord = checked
                    StyledToolTip {
                        text: Translation.tr("Set the weekday in the accent color and the long date in the text color.")
                    }
                }
            }
        }
    }

    // ── Date Shapes ──
    ContentSection {
        title: Translation.tr("Date Shapes (2x1)")
        icon: "interests"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_date_shapes" }
            SizeSlider { options: root.shapesOptions }

            ConfigSwitch {
                buttonIcon: "more_horiz"
                text: Translation.tr("Week as shapes")
                checked: root.shapesOptions.showWeekShapes ?? true
                onCheckedChanged: root.shapesOptions.showWeekShapes = checked
                StyledToolTip {
                    text: Translation.tr("Show this week as seven little shapes: days gone filled, today a sunny burst.")
                }
            }

            ContentSubsectionLabel {
                text: Translation.tr("Day shape")
            }

            ConfigSelectionArray {
                currentValue: root.shapesOptions.dayShape ?? "Clover4Leaf"
                onSelected: value => root.shapesOptions.dayShape = value
                options: ["Clover4Leaf", "Clover8Leaf", "Cookie9Sided", "SoftBurst", "Sunny", "Flower", "Puffy", "Gem", "Ghostish", "Circle"].map(shapeName => ({
                    "displayName": "",
                    "shape": shapeName,
                    "value": shapeName
                }))
            }
        }
    }

    // ── Week Strip ──
    ContentSection {
        title: Translation.tr("Week Strip (2x0.5)")
        icon: "view_week"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_week_strip" }
            SizeSlider { options: root.stripOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "more_horiz"
                    text: Translation.tr("Event dots")
                    checked: root.stripOptions.showEventDots ?? true
                    onCheckedChanged: root.stripOptions.showEventDots = checked
                    StyledToolTip {
                        text: Translation.tr("Put a dot under a day for each of its events, up to three.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "history"
                    text: Translation.tr("Fade past days")
                    checked: root.stripOptions.dimPastDays ?? true
                    onCheckedChanged: root.stripOptions.dimPastDays = checked
                    StyledToolTip {
                        text: Translation.tr("Draw the days already gone this week at lower opacity.")
                    }
                }
            }
        }
    }

    // ── Week Agenda ──
    ContentSection {
        title: Translation.tr("Week Agenda (2x2)")
        icon: "calendar_view_week"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_week_agenda" }
            SizeSlider { options: root.agendaOptions }

            ConfigSlider {
                buttonIcon: "format_list_numbered"
                text: Translation.tr("Events per day")
                value: root.agendaOptions.maxEventsPerDay ?? 2
                from: 1
                to: 3
                stepSize: 1
                onValueChanged: root.agendaOptions.maxEventsPerDay = value
            }

            ConfigSwitch {
                buttonIcon: "history"
                text: Translation.tr("Fade past days")
                checked: root.agendaOptions.dimPastDays ?? true
                onCheckedChanged: root.agendaOptions.dimPastDays = checked
                StyledToolTip {
                    text: Translation.tr("Draw the days already gone this week at lower opacity.")
                }
            }
        }
    }

    // ── Month Tall ──
    ContentSection {
        title: Translation.tr("Month Tall (1x2)")
        icon: "calendar_month"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            PlacementNote { widgetId: "calendar_month_tall" }
            SizeSlider { options: root.monthOptions }

            ConfigRow {
                uniform: true

                ConfigSwitch {
                    buttonIcon: "more_horiz"
                    text: Translation.tr("Event dots")
                    checked: root.monthOptions.showEventDots ?? true
                    onCheckedChanged: root.monthOptions.showEventDots = checked
                    StyledToolTip {
                        text: Translation.tr("Put a dot under the days that have events.")
                    }
                }
                ConfigSwitch {
                    buttonIcon: "date_range"
                    text: Translation.tr("Other months' days")
                    checked: root.monthOptions.showOtherMonths ?? false
                    onCheckedChanged: root.monthOptions.showOtherMonths = checked
                    StyledToolTip {
                        text: Translation.tr("Fill the first and last weeks with the neighbouring months' days, faded.")
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

    component Slot: Item {}

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
}
