pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * To-Do Column (1x2). The day's list, tall: a title with what is left, a
 * segmented bar of today (one segment per task, the finished ones filled, the
 * one being checked filling as it goes), the open tasks with their checks and
 * due days, and the field to add more at the foot.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "todo_column"
    designWidth: 240
    designHeight: 492

    readonly property real padding: 14
    readonly property int maxSegments: 12

    TodoSource {
        id: tasks
    }

    readonly property int finished: tasks.doneToday
    readonly property int total: tasks.openCount + root.finished

    // ── Header ──
    Column {
        id: header
        x: root.padding + 4
        y: root.padding + 4
        width: root.designWidth - x * 2
        spacing: 2

        StyledText {
            text: Translation.tr("To Do")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.huge + 6
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }

        StyledText {
            width: parent.width
            elide: Text.ElideRight
            text: tasks.openCount === 0 ? Translation.tr("All done for now")
                : Translation.tr("%1 left · %2 done today").arg(tasks.openCount).arg(root.finished)
            color: WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // ── Today, segmented ──
    Row {
        id: segments
        visible: root.total > 0 && (root.options?.showProgress ?? true)
        x: header.x
        anchors.top: header.bottom
        anchors.topMargin: 12
        width: header.width
        height: 8
        spacing: 3

        readonly property int count: Math.min(root.maxSegments, root.total)
        readonly property int filled: root.total > root.maxSegments
            ? Math.round(root.finished / root.total * root.maxSegments) : root.finished
        readonly property bool anyCompleting: Object.keys(tasks.completing).length > 0

        Repeater {
            model: segments.count

            delegate: Rectangle {
                id: segment
                required property int index
                readonly property bool done: segment.index < segments.filled
                readonly property bool next: segment.index === segments.filled && segments.anyCompleting
                width: (segments.width - segments.spacing * (segments.count - 1)) / Math.max(1, segments.count)
                height: segments.height
                radius: root.pill(height)
                color: WidgetColorScheme.pillBgColor

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: WidgetColorScheme.accentColor
                    width: segment.done || segment.next ? parent.width : 0

                    Behavior on width {
                        enabled: !Appearance.reducedMotion
                        NumberAnimation {
                            duration: 650
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // ── Tasks ──
    ListView {
        id: list
        anchors.top: segments.visible ? segments.bottom : header.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.leftMargin: root.padding - 4
        anchors.right: parent.right
        anchors.rightMargin: root.padding - 4
        anchors.bottom: addField.top
        anchors.bottomMargin: 8
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        model: tasks.openTasks

        delegate: TodoRow {
            required property var modelData
            width: ListView.view.width
            task: modelData
            source: tasks
            interactive: root.actionsEnabled
            checkSize: 26
            textSize: Appearance.font.pixelSize.normal
        }
    }

    Column {
        visible: tasks.openCount === 0
        anchors.centerIn: list
        spacing: 12

        MaterialShape {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: 96
            shape: MaterialShape.Shape.SoftBurst
            color: WidgetColorScheme.pillBgColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "task_alt"
                iconSize: 40
                color: WidgetColorScheme.accentColor
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("Nothing left to do")
            color: WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.normal
        }
    }

    TodoAddField {
        id: addField
        anchors.left: parent.left
        anchors.leftMargin: root.padding
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        height: 48
        source: tasks
        interactive: root.actionsEnabled
    }
}
