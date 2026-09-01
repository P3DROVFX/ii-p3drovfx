import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import "."
import "TimetableHelpers.js" as H

Row {
    id: headerRow
    
    property real headerHeight
    property real itemSpacing
    property int timeColumnWidth
    property real dayColumnWidth
    property var days
    property int currentDayIndex
    property date keyboardDate
    property bool keyboardNavigationActive: false
    property int allDayChipHeight
    property int allDayChipSpacing
    property int visibleAllDayRows
    property int allDayExpanderHeight
    property bool expanded: false
    property bool hasExpandableLane: false
    readonly property date referenceDate: days?.length > 0 ? days[0].sportsDate : DateTime.clock.date

    signal dayActivated(var date)
    signal sportsDayActivated(var date)
    signal allDayExpansionRequested(bool expanded)

    height: headerHeight
    spacing: itemSpacing

    Item {
        width: timeColumnWidth
        height: headerHeight

        Column {
            anchors.top: parent.top
            anchors.topMargin: 7
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: H.timezoneLabel(headerRow.referenceDate)
                font.family: Appearance.font.family.numbers
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: weekNumberText.implicitWidth + 12
                height: weekNumberText.implicitHeight + 5
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2

                StyledText {
                    id: weekNumberText
                    anchors.centerIn: parent
                    text: "W" + String(H.isoWeekNumber(headerRow.referenceDate))
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    Repeater {
        model: days
        delegate: Item {
            id: dayDelegate
            width: dayColumnWidth
            height: headerHeight

            readonly property var allDayEvents: (modelData.events ?? []).filter(event => CalendarService.isAllDayEvent(event))
            readonly property int sportsCount: Number(modelData.sportsCount ?? 0)
            readonly property date sportsDate: modelData.sportsDate ?? new Date()
            readonly property var forecast: {
                const key = H.dayKeyOf(dayDelegate.sportsDate);
                return (Weather.forecastData ?? []).find(day => String(day?.date ?? "") === key) ?? null;
            }
            readonly property bool hasHeaderChips: dayDelegate.allDayEvents.length > 0 || dayDelegate.sportsCount > 0
            readonly property int headerChipCount: dayDelegate.allDayEvents.length + (dayDelegate.sportsCount > 0 ? 1 : 0)
            readonly property int hiddenChipCount: Math.max(0, dayDelegate.headerChipCount - 2)

            RippleButton {
                id: dayTitleButton
                readonly property bool isToday: H.sameDate(dayDelegate.sportsDate, DateTime.clock.date)

                anchors.top: parent.top
                anchors.topMargin: 4
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                height: 56
                buttonRadius: Appearance.rounding.normal
                toggled: headerRow.keyboardNavigationActive && H.sameDate(headerRow.keyboardDate, dayDelegate.sportsDate)
                colBackgroundHover: Appearance.colors.colSurfaceContainerHigh
                colBackgroundActive: Appearance.colors.colSurfaceContainerHighest
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                onClicked: headerRow.dayActivated(dayDelegate.sportsDate)

                contentItem: Item {
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.formatDate(dayDelegate.sportsDate, "ddd").toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnSurfaceVariant
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.max(Appearance.font.pixelSize.large + 8, dayNumber.implicitWidth + 12)
                            height: Appearance.font.pixelSize.large + 8
                            radius: Appearance.rounding.full
                            color: dayTitleButton.isToday ? Appearance.colors.colPrimary : H.withOpacity(Appearance.colors.colSurface, 0)

                            StyledText {
                                id: dayNumber
                                anchors.centerIn: parent
                                text: String(dayDelegate.sportsDate.getDate())
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: Appearance.font.pixelSize.large
                                font.weight: Font.Bold
                                color: dayTitleButton.isToday ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurface
                            }
                        }
                    }

                    Row {
                        id: forecastRow
                        visible: dayDelegate.forecast !== null && dayDelegate.width > 104
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Image {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Appearance.font.pixelSize.large
                            height: width
                            source: WeatherIcons.getWeatherIcon(dayDelegate.forecast?.code ?? 113, false)
                            sourceSize: Qt.size(width, height)
                            fillMode: Image.PreserveAspectFit
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: -2

                            StyledText {
                                text: String(Weather.useUSCS ? dayDelegate.forecast?.maxF ?? "" : dayDelegate.forecast?.maxC ?? "") + "°"
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Bold
                                color: Appearance.colors.colOnSurface
                            }

                            StyledText {
                                text: String(Weather.useUSCS ? dayDelegate.forecast?.minF ?? "" : dayDelegate.forecast?.minC ?? "") + "°"
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }

                        HoverHandler {
                            id: forecastHover
                        }

                        StyledToolTip {
                            extraVisibleCondition: forecastHover.hovered
                            text: Translation.tr("Forecast · %1° / %2°")
                                .arg(String(Weather.useUSCS ? dayDelegate.forecast?.minF ?? "" : dayDelegate.forecast?.minC ?? ""))
                                .arg(String(Weather.useUSCS ? dayDelegate.forecast?.maxF ?? "" : dayDelegate.forecast?.maxC ?? ""))
                        }
                    }
                }

                StyledToolTip {
                    extraVisibleCondition: dayTitleButton.hovered
                    text: Qt.formatDate(dayDelegate.sportsDate, "dddd, d MMMM")
                }
            }

            StyledFlickable {
                id: allDayArea
                anchors.top: dayTitleButton.bottom
                anchors.topMargin: allDayChipSpacing
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 4
                height: headerRow.visibleAllDayRows > 0
                    ? headerRow.visibleAllDayRows * (allDayChipHeight + allDayChipSpacing) - allDayChipSpacing
                    : 0
                contentWidth: width
                contentHeight: allDayChipColumn.implicitHeight
                clip: true
                interactive: headerRow.expanded && contentHeight > height

                Connections {
                    target: headerRow
                    function onExpandedChanged() {
                        if (!headerRow.expanded)
                            allDayArea.contentY = 0;
                    }
                }

                Column {
                    id: allDayChipColumn
                    width: allDayArea.width
                    spacing: allDayChipSpacing

                    RippleButtonWithIcon {
                        id: sportsDayChip
                        visible: dayDelegate.sportsCount > 0
                        width: parent.width
                        height: visible ? allDayChipHeight : 0
                        buttonRadius: Appearance.rounding.verysmall
                        centerContent: true
                        materialIcon: "sports_score"
                        mainText: Translation.tr("Sports") + " · " + String(dayDelegate.sportsCount)
                        iconPixelSize: Appearance.font.pixelSize.smallie
                        textPixelSize: Appearance.font.pixelSize.smallest
                        colText: Appearance.colors.colOnTertiaryContainer
                        colBackground: Appearance.colors.colTertiaryContainer
                        colBackgroundHover: Appearance.colors.colTertiaryContainerHover
                        colBackgroundActive: Appearance.colors.colTertiaryActive
                        onClicked: headerRow.sportsDayActivated(dayDelegate.sportsDate)

                        StyledToolTip {
                            extraVisibleCondition: sportsDayChip.hovered
                            text: Translation.tr("Sports") + " · " + Qt.formatDate(dayDelegate.sportsDate, "dddd, d MMMM")
                        }
                    }

                    Repeater {
                        model: dayDelegate.allDayEvents
                        delegate: Rectangle {
                            width: allDayChipColumn.width
                            height: allDayChipHeight
                            color: H.chipColor(modelData, Appearance.colors, GoogleCalendarService.colorForEvent(modelData))
                            radius: Appearance.rounding.verysmall

                            StyledText {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: modelData.content ?? Translation.tr("Event")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: ColorUtils.getContrastingTextColor(parent.color)
                                elide: Text.ElideRight
                            }

                            StyledToolTip {
                                extraVisibleCondition: allDayChipHover.hovered
                                text: Translation.tr("All day event:") + "\n" + (modelData.content ?? Translation.tr("Event"))
                            }

                            HoverHandler {
                                id: allDayChipHover
                            }
                        }
                    }
                }
            }

            RippleButton {
                id: allDayExpander
                visible: headerRow.hasExpandableLane && dayDelegate.headerChipCount > 2
                anchors.top: allDayArea.bottom
                anchors.topMargin: allDayChipSpacing
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 4
                implicitHeight: headerRow.allDayExpanderHeight
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: headerRow.allDayExpansionRequested(!headerRow.expanded)

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 3

                    StyledText {
                        text: headerRow.expanded
                            ? Translation.tr("Show less")
                            : Translation.tr("%1 more").arg(String(dayDelegate.hiddenChipCount))
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                        color: Appearance.colors.colPrimary
                    }

                    MaterialSymbol {
                        text: headerRow.expanded ? "expand_less" : "expand_more"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colPrimary
                    }
                }
            }
        }
    }
}
