pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_nothing"

    implicitWidth: 240
    implicitHeight: 240

    property bool wallpaperSafetyTriggered: false

    // Dynamic config options
    readonly property var widgetOpts: Config.options.background.widgets.clock_nothing || ({})
    readonly property bool use24h: root.widgetOpts.use24h ?? true
    readonly property bool showAmPmChip: root.widgetOpts.showAmPmChip ?? true
    readonly property bool showTopLabel: root.widgetOpts.showTopLabel ?? true
    readonly property bool showDate: root.widgetOpts.showDate ?? true
    readonly property bool useAccentColor: root.widgetOpts.useAccentColor ?? false

    // Color Scheme Integration
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor
    readonly property color pillFillColor: WidgetColorScheme.pillFillColor
    readonly property color textColorOnPillFill: WidgetColorScheme.textColorOnPillFill

    // Font Loader for Ndot 57
    FontLoader {
        id: ndotFont
        source: "file://" + Directories.assetsPath + "/fonts/Ndot57-Regular.otf"
    }

    // Time calculations
    readonly property int rawHour: DateTime.clock.hours
    readonly property int rawMinute: DateTime.clock.minutes
    readonly property string hourString: {
        if (root.use24h) {
            return rawHour.toString().padStart(2, "0");
        } else {
            const h12 = rawHour % 12 || 12;
            return h12.toString().padStart(2, "0");
        }
    }
    readonly property string minuteString: rawMinute.toString().padStart(2, "0")
    readonly property string amPmString: rawHour >= 12 ? "PM" : "AM"

    // Date string (e.g., "SAT, 8 AUG")
    readonly property string dateString: Qt.locale().toString(DateTime.clock.date, "ddd, d MMM").toUpperCase()

    // Shadow Effect
    StyledDropShadow {
        id: shadowEffect
        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding
        color: WidgetColorScheme.tintBackground(root.cardBgColor)

        // Top Header: TIME label or AM/PM chip
        Row {
            id: topHeader
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 18
            spacing: 6

            // AM/PM Chip
            Rectangle {
                visible: !root.use24h && root.showAmPmChip
                implicitWidth: chipText.implicitWidth + 12
                implicitHeight: chipText.implicitHeight + 4
                radius: Appearance.rounding.full
                color: root.pillFillColor

                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: root.amPmString
                    font.family: ndotFont.name
                    font.pixelSize: 12
                    color: root.textColorOnPillFill
                    renderType: Text.QtRendering
                }
            }

            // Top Label ("TIME")
            Text {
                visible: root.showTopLabel && (root.use24h || !root.showAmPmChip)
                text: "TIME"
                font.family: ndotFont.name
                font.pixelSize: 14
                color: root.subtextColorOnBg
                renderType: Text.QtRendering
            }
        }

        // Dummy text item to measure the standard full-width digit ("0") in Ndot 57
        Text {
            id: sampleDigit
            visible: false
            text: "0"
            font.family: ndotFont.name
            font.pixelSize: Math.round(root.height * 0.38)
            renderType: Text.QtRendering
        }

        // Center: Stacked Digital Time (Hours / Minutes)
        Column {
            id: timeColumn
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(-root.height * 0.05)
            spacing: Math.round(-root.height * 0.20)

            readonly property real fontSize: Math.round(root.height * 0.38)
            readonly property real digitWidth: Math.ceil(sampleDigit.implicitWidth)

            // Hours Row (Tens + Units)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    width: timeColumn.digitWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.hourString.charAt(0)
                    font.family: ndotFont.name
                    font.pixelSize: timeColumn.fontSize
                    color: root.useAccentColor ? root.accentColor : root.textColorOnBg
                    renderType: Text.QtRendering
                }

                Text {
                    width: timeColumn.digitWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.hourString.charAt(1)
                    font.family: ndotFont.name
                    font.pixelSize: timeColumn.fontSize
                    color: root.useAccentColor ? root.accentColor : root.textColorOnBg
                    renderType: Text.QtRendering
                }
            }

            // Minutes Row (Tens + Units)
            Row {
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    width: timeColumn.digitWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.minuteString.charAt(0)
                    font.family: ndotFont.name
                    font.pixelSize: timeColumn.fontSize
                    color: root.textColorOnBg
                    renderType: Text.QtRendering
                }

                Text {
                    width: timeColumn.digitWidth
                    horizontalAlignment: Text.AlignHCenter
                    text: root.minuteString.charAt(1)
                    font.family: ndotFont.name
                    font.pixelSize: timeColumn.fontSize
                    color: root.textColorOnBg
                    renderType: Text.QtRendering
                }
            }
        }

        // Bottom: Date (e.g., "SAT, 8 AUG")
        Text {
            id: dateText
            visible: root.showDate
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 16
            text: root.dateString
            font.family: ndotFont.name
            font.pixelSize: 14
            color: root.subtextColorOnBg
            renderType: Text.QtRendering
        }
    }
}
