import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import Quickshell

Item {
    id: root
    anchors.fill: parent
    property bool isExpanded: false

    // System date updates reactively via DateTime.clock.date
    readonly property var currentSystemDate: DateTime.clock.date

    // Generates 7 days with the current system date in the center (index 3)
    readonly property var dayDates: {
        let list = [];
        let today = root.currentSystemDate;
        if (!today)
            today = new Date();
        for (let i = -3; i <= 3; i++) {
            let d = new Date(today);
            d.setDate(today.getDate() + i);
            list.push(d);
        }
        return list;
    }

    // Resolves and parses all events for today from CalendarService.events
    readonly property var todayEvents: {
        if (!CalendarService.khalAvailable || !CalendarService.events)
            return [];
        let list = [];
        let today = root.currentSystemDate;
        if (!today)
            today = new Date();
        const currentDay = today.getDate();
        const currentMonth = today.getMonth();
        const currentYear = today.getFullYear();

        for (let i = 0; i < CalendarService.events.length; i++) {
            let evt = CalendarService.events[i];
            let taskDate = new Date(evt.startDate);
            if (taskDate.getDate() === currentDay && taskDate.getMonth() === currentMonth && taskDate.getFullYear() === currentYear) {
                list.push(evt);
            }
        }
        // Sort chronologically
        list.sort((a, b) => a.startDate - b.startDate);
        return list;
    }

    // Pointer to current event displaying in the widget
    property int eventIndex: 0

    // Automatically set eventIndex to the next upcoming event when todayEvents updates
    function resetEventIndex() {
        let list = root.todayEvents;
        if (list.length === 0) {
            eventIndex = 0;
            return;
        }
        let now = root.currentSystemDate;
        if (!now)
            now = new Date();
        let found = false;
        for (let i = 0; i < list.length; i++) {
            if (list[i].endDate > now) {
                eventIndex = i;
                found = true;
                break;
            }
        }
        if (!found) {
            eventIndex = 0;
        }
    }

    onTodayEventsChanged: resetEventIndex()
    Component.onCompleted: resetEventIndex()

    // Helper functions for formatting Month label
    function formatMonth(date) {
        let m = Qt.formatDateTime(date, "MMM");
        if (!m)
            return "";
        return m.charAt(0).toUpperCase() + m.slice(1);
    }

    // ── Contracted Layout: Time pill + Date block + Weather icon ──────────────
    Item {
        id: contractedLayout
        anchors.fill: parent
        visible: !root.isExpanded

        readonly property bool is12h: /a/i.test(Config.options.time.format)
        readonly property string hours: is12h ? ("0" + (DateTime.clock.date.getHours() % 12 || 12)).slice(-2) : Qt.formatDateTime(DateTime.clock.date, "HH")
        readonly property string minutes: Qt.formatDateTime(DateTime.clock.date, "mm")
        readonly property string ampm: is12h ? Qt.formatDateTime(DateTime.clock.date, Config.options.time.format.includes("AP") ? "AP" : "ap").trim() : ""
        readonly property bool showAMPM: is12h && ampm.length > 0
        readonly property string dateStr: Qt.formatDateTime(DateTime.clock.date, Config.options.time.dateFormat)
        readonly property string dayStr: Qt.formatDateTime(DateTime.clock.date, "dddd")
        readonly property string weatherIcon: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"

        readonly property real timeFontSize: Math.max(14, Math.min(28, root.height * 0.44))
        readonly property real dateFontSize: Math.max(10, Math.min(16, root.height * 0.3))
        readonly property real dayFontSize: Math.max(9, Math.min(13, root.height * 0.22))

        RowLayout {
            anchors.fill: parent
            spacing: Math.max(4, root.height * 0.15)

            // Time Pill
            Rectangle {
                id: timeRect
                Layout.fillHeight: true
                implicitWidth: timeContent.implicitWidth + (root.height * 0.6)
                radius: height / 2
                color: Appearance.colors.colPrimaryContainer

                RowLayout {
                    id: timeContent
                    anchors.centerIn: parent
                    spacing: 2

                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        text: contractedLayout.hours + ":" + contractedLayout.minutes
                        font.pixelSize: contractedLayout.timeFontSize
                        font.bold: true
                        font.features: {
                            "tnum": 1
                        }
                        color: Appearance.colors.colOnPrimaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignBaseline
                        visible: contractedLayout.showAMPM
                        text: contractedLayout.ampm
                        font.pixelSize: contractedLayout.timeFontSize * 0.55
                        font.bold: true
                        font.letterSpacing: 0
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }

            // Date Block
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colSurfaceContainerHighest

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.leftMargin: root.height * 0.25
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignLeft
                        text: contractedLayout.dateStr
                        font.pixelSize: contractedLayout.dateFontSize
                        font.bold: true
                        font.features: {
                            "tnum": 1
                        }
                        color: Appearance.colors.colOnSurface
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignLeft
                        text: contractedLayout.dayStr.charAt(0).toUpperCase() + contractedLayout.dayStr.slice(1)
                        font.pixelSize: contractedLayout.dayFontSize
                        font.weight: Font.Thin
                        font.features: {
                            "tnum": 1
                        }
                        color: Appearance.colors.colOnSurface
                        opacity: 0.65
                    }
                }
            }

            // Weather Icon
            MaterialShape {
                Layout.preferredWidth: height
                Layout.fillHeight: true
                shapeString: "Cookie9Sided"
                color: Appearance.colors.colSurfaceContainerHighest

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: contractedLayout.weatherIcon
                    iconSize: Math.max(10, (parent ? parent.height : 24) * 0.5)
                    fill: 1
                    color: Appearance.colors.colOnSurfaceVariant
                }
            }
        }
    }

    // Expanded Layout containing Header Row (Month + 7 days) and Events Row below
    ColumnLayout {
        id: expandedLayout
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 12
        anchors.bottomMargin: 8
        spacing: 8
        opacity: root.isExpanded ? 1.0 : 0.0
        visible: opacity > 0.01
        Behavior on opacity {
            NumberAnimation {
                duration: 150
            }
        }

        // Header Row: Month (left) + 7 Days (right) in a single RowLayout with mathematical distribution to fill width
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 0

            StyledText {
                text: root.formatMonth(root.currentSystemDate)
                font.bold: true
                font.pixelSize: 22
                color: Appearance.colors.colOnSurface
                Layout.alignment: Qt.AlignVCenter
            }

            // Container for the 7 days that fills the remaining width of the RowLayout
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 16

                Row {
                    anchors.fill: parent

                    Repeater {
                        model: 7
                        delegate: Column {
                            width: parent.width / 7
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            property var dayDate: root.dayDates[index]
                            property bool isToday: index === 3

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: isToday ? Qt.formatDateTime(dayDate, "ddd").toUpperCase() : Qt.formatDateTime(dayDate, "dddd").charAt(0).toUpperCase()
                                font.pixelSize: isToday ? 10 : 9
                                font.bold: isToday
                                color: isToday ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                                opacity: isToday ? 1.0 : 0.5
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: dayDate.getDate()
                                font.pixelSize: isToday ? 18 : 13
                                font.bold: isToday
                                color: isToday ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface
                                opacity: isToday ? 1.0 : 0.7
                            }
                        }
                    }
                }
            }
        }

        // Horizontal Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Appearance.colors.colLayer0Border
            opacity: 0.3
        }

        // Empty State View (visible when list is empty)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.small
            color: Appearance.colors.colSecondaryContainer
            border.width: 0
            visible: root.todayEvents.length === 0

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "event_available"
                    iconSize: 24
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.7
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Nothing for today")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSecondaryContainer
                    opacity: 0.8
                }
            }
        }

        // Event Display View with Navigation (visible when events exist)
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colSurfaceContainerHighest
            visible: root.todayEvents.length > 0

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 12

                // Backward circle button
                RippleButton {
                    id: backBtn
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    buttonRadiusPressed: 13
                    colBackground: "transparent"
                    colBackgroundHover: "transparent"
                    colRipple: "transparent"
                    enabled: root.eventIndex > 0

                    contentItem: Item {
                        implicitWidth: 26
                        implicitHeight: 26
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_left"
                            iconSize: 14
                            color: backBtn.enabled ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                            opacity: backBtn.enabled ? (backBtn.hovered ? 1.0 : 0.6) : 0.25
                        }
                    }

                    onClicked: {
                        if (root.eventIndex > 0) {
                            root.eventIndex--;
                        }
                    }
                }

                // Event Title and Time range in the center
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    readonly property var currentEvent: root.todayEvents[root.eventIndex] ?? null

                    StyledText {
                        Layout.fillWidth: true
                        text: parent.currentEvent ? parent.currentEvent.content : ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.bold: true
                        color: Appearance.colors.colOnSurface
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: parent.currentEvent ? (Qt.formatDateTime(parent.currentEvent.startDate, "hh:mm") + " - " + Qt.formatDateTime(parent.currentEvent.endDate, "hh:mm")) : ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurface
                        opacity: 0.8
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Forward circle button
                RippleButton {
                    id: forwardBtn
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: 13
                    buttonRadiusPressed: 13
                    colBackground: "transparent"
                    colBackgroundHover: "transparent"
                    colRipple: "transparent"
                    enabled: root.eventIndex < root.todayEvents.length - 1

                    contentItem: Item {
                        implicitWidth: 26
                        implicitHeight: 26
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "chevron_right"
                            iconSize: 14
                            color: forwardBtn.enabled ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                            opacity: forwardBtn.enabled ? (forwardBtn.hovered ? 1.0 : 0.6) : 0.25
                        }
                    }

                    onClicked: {
                        if (root.eventIndex < root.todayEvents.length - 1) {
                            root.eventIndex++;
                        }
                    }
                }
            }
        }
    }
}
