import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import "."
import "TimetableHelpers.js" as H

// Shared task presentation for month cells, the week header, and Upcoming.
// Tasks are deliberately compact plates with a square checkbox, not event
// bands: calendar colours keep their event meaning while actionable work stays
// immediately recognisable.
Item {
    id: root

    required property var taskData
    property bool compact: false

    readonly property bool completed: root.taskData?.done === true
    readonly property date dueDate: root.taskData?.date ? new Date(root.taskData.date) : new Date()
    readonly property bool overdue: root.taskData?.hasDate === true
        && !root.completed
        && !isNaN(root.dueDate.getTime())
        && H.startOfDay(root.dueDate).getTime() < H.startOfDay(DateTime.clock.date).getTime()
    readonly property string titleText: String(root.taskData?.content ?? root.taskData?.title ?? Translation.tr("Task"))

    signal completionRequested(var task)

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verysmall
        color: {
            if (root.completed)
                return Appearance.colors.colLayer3;
            return root.overdue ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer;
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 3
            anchors.rightMargin: 6
            spacing: 3

            RippleButton {
                id: completeButton
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.min(parent.height, 22)
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.verysmall
                enabled: !root.completed
                colBackground: "transparent"
                colBackgroundHover: root.overdue ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover
                onClicked: root.completionRequested(root.taskData)

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.completed ? "check_box" : "check_box_outline_blank"
                    iconSize: root.compact ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
                    color: root.completed
                        ? Appearance.colors.colOnLayer3
                        : (root.overdue ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer)
                }

                StyledToolTip {
                    extraVisibleCondition: completeButton.hovered
                    text: root.completed ? Translation.tr("Completed") : Translation.tr("Mark as completed")
                }
            }

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.overdue && !root.compact
                text: "priority_high"
                iconSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOnErrorContainer
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - x)
                text: root.titleText
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: root.compact ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                font.strikeout: root.completed
                color: {
                    if (root.completed)
                        return Appearance.colors.colOnLayer3;
                    return root.overdue ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer;
                }
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: taskPointer.hovered
        text: root.overdue
            ? Translation.tr("Overdue · %1").arg(Qt.formatDate(root.dueDate, Locale.ShortFormat))
            : root.titleText
    }

    HoverHandler {
        id: taskPointer
    }
}
