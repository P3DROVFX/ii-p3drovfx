pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_word"
    readonly property var cfg: Config.options.background.widgets.clock_word
    implicitWidth: cfg.size ?? 240
    implicitHeight: cfg.size ?? 240

    readonly property int hourNumber: {
        const h = DateTime.clock.hours % 12;
        return h === 0 ? 12 : h;
    }
    readonly property string hourWord: numberWord(hourNumber)
    readonly property int minuteNumber: DateTime.clock.minutes
    readonly property string minuteTensWord: minuteNumber >= 10 && minuteNumber <= 19
                                             ? numberWord(minuteNumber)
                                             : numberWord(Math.floor(minuteNumber / 10) * 10)
    readonly property string minuteOnesWord: (minuteNumber >= 10 && minuteNumber <= 19) || minuteNumber % 10 === 0
                                             ? ""
                                             : numberWord(minuteNumber % 10)

    function numberWord(value) {
        const words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen", "Twenty", "Thirty", "Forty", "Fifty"];
        if (value <= 19) return words[value];
        return words[18 + Math.floor(value / 10)];
    }

    MaterialShape {
        id: backgroundShape
        anchors.fill: parent
        visible: (root.cfg.backgroundStyle ?? "shape") === "shape"
        color: WidgetColorScheme.tintBackground(WidgetColorScheme.cardBgColor)
        shapeString: root.cfg.backgroundShape ?? "Circle"
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width * 0.60
        spacing: -root.height * 0.025

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: font.pixelSize * 1.08
            text: root.hourWord
            color: WidgetColorScheme.accentColor
            font.pixelSize: Math.min(root.height * 0.16, root.width * 1.05 / Math.max(1, text.length))
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: font.pixelSize * 1.08
            text: root.minuteTensWord
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Math.min(root.height * 0.16, root.width * 1.05 / Math.max(1, text.length))
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignLeft
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? font.pixelSize * 1.08 : 0
            text: root.minuteOnesWord
            color: WidgetColorScheme.textColorOnBg
            font.pixelSize: Math.min(root.height * 0.16, root.width * 1.05 / Math.max(1, text.length))
            font.weight: Font.Bold
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            visible: text !== ""
        }
    }
}
