import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_expressive_card"

    readonly property real contentScale: (Config.options.background.widgets.clock_expressive_card?.widgetSize ?? 100) / 100.0
    implicitWidth: 240 * contentScale
    implicitHeight: 240 * contentScale

    // Time & Date bindings
    readonly property string timeStr: DateTime.time
    readonly property string hour: timeStr.split(":")[0].padStart(2, "0")
    readonly property string minute: timeStr.split(":")[1] ? timeStr.split(":")[1].split(" ")[0].padStart(2, "0") : "00"
    readonly property string formattedTime: hour + ":" + minute

    readonly property string monthName: Qt.locale().toString(DateTime.clock.date, "MMM").toUpperCase()
    readonly property string dayNum: Qt.locale().toString(DateTime.clock.date, "dd")
    readonly property string weekDayShort: Qt.locale().toString(DateTime.clock.date, "ddd").toUpperCase()
    
    // Weather bindings from Weather service
    readonly property string locationName: (Weather.data?.city && Weather.data.city !== "" && Weather.data.city !== "City") ? Weather.data.city : (Config.options.bar.weather.city !== "" ? Config.options.bar.weather.city : "")
    readonly property string tempStr: Weather.data?.temp ? Weather.data.temp.replace("°C", "").replace("°F", "").trim() : "30"

    // Colors via WidgetColorScheme
    readonly property color bgColor: WidgetColorScheme.cardBgColor
    readonly property color mainTextColor: WidgetColorScheme.textColorOnBg
    readonly property color subTextColor: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    StyledDropShadow {
        id: bgShadow
        target: cardBackground
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: cardBackground
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.bgColor)
        radius: Appearance.rounding.large
        clip: true

        // Content Column Layout fitting 240x240
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.width * 0.06
            spacing: 0

            // Row 1: Location header (only shown if location is non-empty)
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.locationName !== ""

                MaterialSymbol {
                    text: "location_on"
                    iconSize: root.height * 0.075
                    color: root.subTextColor
                }

                StyledText {
                    text: root.locationName
                    font.pixelSize: root.height * 0.068
                    font.weight: Font.Medium
                    color: root.subTextColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Item { Layout.fillHeight: true }

            // Row 2: Big Time (HH:MM)
            StyledText {
                text: root.formattedTime
                font.pixelSize: root.height * 0.25
                font.weight: 900
                font.bold: true
                font.family: Appearance.font.family.title
                color: root.mainTextColor
                lineHeight: 0.85
            }

            Item { Layout.fillHeight: true }

            // Row 3: Month / Day + Weekday badge (MEI/19 SEL)
            RowLayout {
                spacing: root.width * 0.02
                Layout.alignment: Qt.AlignLeft

                StyledText {
                    text: root.monthName
                    font.pixelSize: root.height * 0.20
                    font.weight: 900
                    font.bold: true
                    font.family: Appearance.font.family.title
                    color: root.mainTextColor
                }

                StyledText {
                    text: "/"
                    font.pixelSize: root.height * 0.20
                    font.weight: 900
                    color: ColorUtils.mix(root.mainTextColor, root.bgColor, 0.4)
                }

                StyledText {
                    text: root.dayNum
                    font.pixelSize: root.height * 0.20
                    font.weight: 900
                    font.bold: true
                    font.family: Appearance.font.family.title
                    color: root.mainTextColor
                }

                StyledText {
                    text: root.weekDayShort
                    font.pixelSize: root.height * 0.07
                    font.weight: Font.Bold
                    font.family: Appearance.font.family.title
                    color: ColorUtils.mix(root.mainTextColor, root.bgColor, 0.3)
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Row 4: Temperature + Official Weather SVG Icon
            RowLayout {
                spacing: root.width * 0.03
                Layout.alignment: Qt.AlignLeft

                Row {
                    spacing: 1
                    StyledText {
                        text: root.tempStr
                        font.pixelSize: root.height * 0.22
                        font.weight: 900
                        font.bold: true
                        font.family: Appearance.font.family.title
                        color: root.mainTextColor
                    }
                    StyledText {
                        text: "°"
                        font.pixelSize: root.height * 0.15
                        font.weight: 900
                        color: root.mainTextColor
                    }
                }

                Image {
                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                    sourceSize: Qt.size(root.height * 0.16, root.height * 0.16)
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }
}
