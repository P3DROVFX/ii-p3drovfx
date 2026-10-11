import QtQuick
import QtQuick.Layouts

/**
 * The shell's digital background clock (widgets/clock/DigitalClock.qml), centred
 * as the lock centres it. Options mirror background.widgets.clock_digital; the
 * colours are the widget colour scheme the shell resolved (widget_* tokens).
 */
ColumnLayout {
    id: root
    spacing: 4

    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    readonly property bool colorful: Theme.bool("digital_colorful", false)
    readonly property bool showColon: Theme.bool("digital_show_colon", true)
    readonly property bool showSeconds: Theme.bool("digital_show_seconds", false)
    readonly property bool vertical: Theme.bool("digital_vertical", false)
    readonly property bool showDate: Theme.bool("digital_show_date", true)
    readonly property real lineSpacing: Theme.num("digital_line_spacing", 0)
    readonly property string quote: Theme.str("digital_quote", "")

    readonly property color colText: Theme.col("widget_text_color_on_bg", Theme.m3onSurfaceVariant)
    readonly property color colTextSecondary: Theme.col("widget_subtext_color_on_bg", Theme.transparentize(Theme.m3onSurfaceVariant, 0.4))
    readonly property color colTextTertiary: Theme.col("widget_accent_color", Theme.m3primary)

    readonly property string time: Qt.formatTime(root.now, Theme.timeFormat)
    readonly property string hours: time.split(":")[0].padStart(2, "0")
    readonly property string minutes: (time.split(":")[1] ?? "").split(" ")[0].padStart(2, "0")
    readonly property string seconds: Qt.formatTime(root.now, Theme.str("clock_seconds_format", "ss"))

    component ClockText: StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        renderType: Text.CurveRendering
        style: Text.Raised
        styleColor: Theme.colShadow
        font {
            family: Theme.fontExpressive
            pixelSize: 20
            weight: 350
            styleName: ""
            variableAxes: ({})
            features: ({ "tnum": 1 })
        }
    }
    component TimeText: ClockText {
        Layout.fillWidth: false
        font {
            family: Theme.fontNumbers
            pixelSize: Theme.num("digital_font_size", 90)
            weight: Theme.num("digital_font_weight", 350)
            variableAxes: ({
                    "wdth": Theme.num("digital_font_width", 100),
                    "ROND": Theme.num("digital_font_roundness", 0)
                })
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: false
        TimeText {
            text: root.hours
            color: root.colText
        }
        TimeText {
            visible: !root.vertical && root.showColon
            text: ":"
            color: root.colorful ? root.colTextSecondary : root.colText
        }
        TimeText {
            visible: !root.vertical
            text: root.minutes
            color: root.colorful ? root.colTextTertiary : root.colText
        }
        TimeText {
            visible: !root.vertical && root.showSeconds && root.showColon
            text: ":"
            color: root.colorful ? root.colTextSecondary : root.colText
        }
        TimeText {
            visible: !root.vertical && root.showSeconds
            text: root.seconds
            color: root.colorful ? root.colTextTertiary : root.colText
        }
    }

    TimeText {
        // -40 tightens the stacked lines; lineSpacing is the user's delta on top.
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: -40 + root.lineSpacing
        visible: root.vertical
        text: root.minutes + (root.showSeconds ? ":" + root.seconds : "")
        color: root.colorful ? root.colTextTertiary : root.colText
    }

    ClockText {
        visible: root.showDate
        Layout.topMargin: -20
        text: Qt.formatDate(root.now, Theme.dateFormat)
        color: root.colorful ? root.colTextSecondary : root.colText
    }

    ClockText {
        visible: root.quote.length > 0
        font.pixelSize: Theme.pxNormal
        text: root.quote
        color: root.colTextSecondary
    }
}
