import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import qs.services

AbstractBackgroundWidget {
    id: root

    property bool wallpaperSafetyTriggered: false
    // Color Scheme Integration
    readonly property color cardBgColor: WidgetColorScheme.cardBgColor
    readonly property color textColorOnBg: WidgetColorScheme.textColorOnBg
    readonly property color subtextColorOnBg: WidgetColorScheme.subtextColorOnBg
    readonly property color accentColor: WidgetColorScheme.accentColor
    // Time calculations
    readonly property bool use24h: {
        const fmt = Config.options.time.format || "";
        return fmt.toLowerCase().includes("hh") || !fmt.toLowerCase().includes("a");
    }
    readonly property string hourString: {
        const rawH = DateTime.clock.hours;
        if (root.use24h) {
            return rawH.toString().padStart(2, "0");
        } else {
            const h12 = rawH % 12 || 12;
            return h12.toString().padStart(2, "0");
        }
    }
    readonly property int currentMin: DateTime.clock.minutes
    readonly property int prevMin: (currentMin - 1 + 60) % 60
    readonly property int nextMin: (currentMin + 1) % 60
    readonly property string prevMinString: prevMin.toString().padStart(2, "0")
    readonly property string currentMinString: currentMin.toString().padStart(2, "0")
    readonly property string nextMinString: nextMin.toString().padStart(2, "0")
    // Date calculations (Today, Tomorrow, Day after tomorrow)
    readonly property var todayDate: DateTime.clock.date
    readonly property var tomorrowDate: new Date(todayDate.getTime() + 8.64e+07)
    readonly property var afterTomorrowDate: new Date(todayDate.getTime() + 1.728e+08)

    function formatDateNum(d) {
        return Qt.locale().toString(d, "d");
    }

    function formatDateDay(d) {
        const s = Qt.locale().toString(d, "ddd");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    configEntryName: "nothing_wheel_clock"
    implicitWidth: 240
    implicitHeight: 240

    // Shadow Effect
    StyledDropShadow {
        id: shadowEffect

        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer

        anchors.fill: parent
        radius: Appearance.rounding.large
        color: WidgetColorScheme.tintBackground(root.cardBgColor)

        // --- Top Header: 3 Days Calendar Strip ---
        RowLayout {
            id: dateHeader

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 18
            spacing: 0

            // Column 1: Today (Active)
            Column {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    text: root.formatDateNum(root.todayDate)
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    color: root.textColorOnBg
                }

                StyledText {
                    text: root.formatDateDay(root.todayDate)
                    font.pixelSize: 13
                    font.weight: Font.Bold
                    color: root.textColorOnBg
                }

            }

            // Column 2: Tomorrow (Muted)
            Column {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    text: root.formatDateNum(root.tomorrowDate)
                    font.pixelSize: 14
                    color: root.subtextColorOnBg
                    opacity: 0.65
                }

                StyledText {
                    text: root.formatDateDay(root.tomorrowDate)
                    font.pixelSize: 13
                    color: root.subtextColorOnBg
                    opacity: 0.65
                }

            }

            // Column 3: Day After Tomorrow (Muted)
            Column {
                Layout.fillWidth: true
                spacing: 1

                StyledText {
                    text: root.formatDateNum(root.afterTomorrowDate)
                    font.pixelSize: 14
                    color: root.subtextColorOnBg
                    opacity: 0.65
                }

                StyledText {
                    text: root.formatDateDay(root.afterTomorrowDate)
                    font.pixelSize: 13
                    color: root.subtextColorOnBg
                    opacity: 0.65
                }

            }

        }

        // --- Main Content Area (Centered Hours & Minutes) ---
        Item {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: dateHeader.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.bottomMargin: 10
            clip: true

            // 3-Dot Indicator at Bottom Left
            Row {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                spacing: 5

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Qt.rgba(root.subtextColorOnBg.r, root.subtextColorOnBg.g, root.subtextColorOnBg.b, 0.45)
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Qt.rgba(root.subtextColorOnBg.r, root.subtextColorOnBg.g, root.subtextColorOnBg.b, 0.45)
                }

                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: root.accentColor
                }

            }

            // Centered Time Group (Hours + Minute Wheel side-by-side)
            Row {
                id: timeGroup

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Hour String
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hourString
                    font.pixelSize: 74
                    font.weight: Font.Bold
                    color: root.textColorOnBg
                }

                // Vertical Minute Wheel (Previous, Current [Accent], Next)
                ColumnLayout {
                    id: minuteWheel

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -24

                    // Top Minute (Previous)
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.prevMinString
                        font.pixelSize: 74
                        font.weight: Font.Bold
                        color: root.textColorOnBg
                        opacity: 0.88
                    }

                    // Middle Minute (Current - Primary Accent Color!)
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.currentMinString
                        font.pixelSize: 74
                        font.weight: Font.Bold
                        color: root.accentColor
                    }

                    // Bottom Minute (Next)
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.nextMinString
                        font.pixelSize: 74
                        font.weight: Font.Bold
                        color: root.textColorOnBg
                        opacity: 0.88
                    }

                }

            }

        }

    }

}
