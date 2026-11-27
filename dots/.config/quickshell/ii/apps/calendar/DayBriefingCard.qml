import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Deterministic "today" summary for the rail's day page.
 *
 * Every fact comes from singletons that are already loaded (AtAGlance,
 * Todo); nothing here touches the network. The optional button hands the
 * same facts to the AI chat as a seeded prompt through Ai.submit, so the
 * answer lands in the normal transcript under its usual policy gates.
 */
Rectangle {
    id: root

    property date day: new Date()

    readonly property bool isToday: {
        const now = DateTime.clock.date;
        return day.getFullYear() === now.getFullYear()
            && day.getMonth() === now.getMonth()
            && day.getDate() === now.getDate();
    }
    readonly property var nextEvent: root.isToday ? AtAGlanceService.nextEvent : null
    readonly property int todayEventCount: root.isToday ? AtAGlanceService.todayEvents.length : 0
    readonly property int overdueCount: Todo.getOverdueTasks(root.day).length

    visible: root.isToday
    radius: Appearance.rounding.small
    color: Appearance.colors.colSecondaryContainer
    implicitHeight: contentRow.implicitHeight + 20

    function timeLabel(eventData) {
        const start = new Date(eventData.startDate);
        const format = Config.options.time.format;
        return (format.includes("ap") || format.includes("AP"))
            ? Qt.formatDateTime(start, "h:mm ap")
            : Qt.formatDateTime(start, "hh:mm");
    }

    function buildPrompt() {
        const parts = [];
        parts.push(Translation.tr("Plan my day") + ".");
        if (root.todayEventCount > 0)
            parts.push(Translation.tr("%1 event(s)").arg(String(root.todayEventCount)));
        else
            parts.push(Translation.tr("No events left"));
        if (root.overdueCount > 0)
            parts.push(Translation.tr("%1 overdue task(s)").arg(String(root.overdueCount)));
        if (root.nextEvent)
            parts.push(Translation.tr("Next") + ": " + String(root.nextEvent.content ?? "") + " " + root.timeLabel(root.nextEvent));
        return parts.join(" · ");
    }

    RowLayout {
        id: contentRow
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        MaterialSymbol {
            text: "today"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnSecondaryContainer
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                text: root.nextEvent !== null
                    ? root.timeLabel(root.nextEvent) + " · " + String(root.nextEvent.content ?? "")
                    : (root.todayEventCount > 0
                        ? Translation.tr("%1 event(s)").arg(String(root.todayEventCount))
                        : Translation.tr("No events left"))
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnSecondaryContainer
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.overdueCount > 0
                text: Translation.tr("%1 overdue task(s)").arg(String(root.overdueCount))
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colOnSecondaryContainer
                opacity: 0.8
                elide: Text.ElideRight
            }
        }

        RippleButtonWithIcon {
            id: askAiButton

            readonly property string idleSymbol: "auto_awesome"
            property string currentSymbol: idleSymbol

            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            materialIcon: currentSymbol
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            mainText: ""
            onClicked: {
                const result = Ai.submit(root.buildPrompt(), null, "timetable-briefing");
                currentSymbol = result?.accepted ? "check" : "error";
                symbolResetTimer.restart();
            }

            StyledToolTip {
                extraVisibleCondition: askAiButton.hovered
                text: Translation.tr("Ask AI about today")
            }

            Timer {
                id: symbolResetTimer
                interval: 1600
                onTriggered: askAiButton.currentSymbol = askAiButton.idleSymbol
            }
        }
    }
}
