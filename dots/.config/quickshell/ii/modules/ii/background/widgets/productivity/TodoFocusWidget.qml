import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * To-Do Focus (1x1). One task at a time, in big type: finish it with the check
 * key, or pass to the next one. A finished task is struck through and the next
 * rises into its place. With nothing open, a sunny burst says so.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "todo_focus"
    designWidth: 240
    designHeight: 240

    readonly property real padding: 16
    readonly property real keyHeight: 52
    readonly property real maxTitleSize: 32
    readonly property real minTitleSize: 15

    TodoSource {
        id: tasks
    }

    property int index: 0
    readonly property int count: tasks.openCount
    readonly property int shownIndex: root.count > 0 ? root.index % root.count : 0
    readonly property var task: root.count > 0 ? tasks.openTasks[root.shownIndex] : null
    readonly property bool completing: root.task !== null && tasks.isCompleting(root.task)
    readonly property string taskKey: tasks.keyOf(root.task)

    onTaskKeyChanged: {
        if (!Appearance.reducedMotion)
            arrival.restart();
    }

    // ── Header: caption + position ──
    StyledText {
        x: root.padding + 2
        y: root.padding
        text: Translation.tr("To do").toUpperCase()
        color: WidgetColorScheme.subtextColorOnBg
        font.family: Appearance.font.family.monospace
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.letterSpacing: 1.5
    }

    Rectangle {
        visible: root.count > 0 && (root.options?.showPosition ?? true)
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding - 4
        width: positionText.implicitWidth + 18
        height: 24
        radius: root.pill(height)
        color: WidgetColorScheme.pillBgColor

        StyledText {
            id: positionText
            anchors.centerIn: parent
            text: (root.shownIndex + 1) + "/" + root.count
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // ── The task ──
    Item {
        id: stage
        visible: root.count > 0
        x: root.padding + 2
        y: root.padding + 30
        width: root.designWidth - root.padding * 2 - 4
        height: root.designHeight - y - root.keyHeight - root.padding - 10

        Item {
            id: taskBlock
            width: parent.width
            height: parent.height

            transform: Translate { id: rise; y: 0 }

            StyledText {
                id: title
                width: parent.width
                height: parent.height - (dueText.visible ? dueText.height + 4 : 0)
                verticalAlignment: Text.AlignBottom
                text: String(root.task?.content ?? "")
                color: root.completing ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: root.maxTitleSize
                minimumPixelSize: root.minTitleSize
                fontSizeMode: Text.Fit
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                lineHeight: 0.92
                font.variableAxes: ({ "wght": root.completing ? 380 : 680, "wdth": 84, "ROND": 100, "opsz": 36 })

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            StyledText {
                id: dueText
                anchors.top: title.bottom
                anchors.topMargin: 4
                visible: tasks.dueLabel(root.task) !== ""
                text: tasks.dueLabel(root.task).toUpperCase()
                color: tasks.isOverdue(root.task) ? WidgetColorScheme.warningColor : WidgetColorScheme.subtextColorOnBg
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.letterSpacing: 1
            }
        }

        ParallelAnimation {
            id: arrival
            NumberAnimation { target: rise; property: "y"; from: 18; to: 0; duration: Appearance.animation.elementMove.duration; easing.type: Easing.OutCubic }
            NumberAnimation { target: taskBlock; property: "opacity"; from: 0; to: 1; duration: Appearance.animation.elementMoveFast.duration }
        }
    }

    // ── Empty ──
    Column {
        visible: root.count === 0
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -6
        spacing: 10

        MaterialShape {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitSize: 84
            shape: MaterialShape.Shape.Sunny
            color: WidgetColorScheme.accentColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "done_all"
                iconSize: 38
                color: WidgetColorScheme.onAccentColor
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Translation.tr("All clear")
            color: WidgetColorScheme.textColorOnBg
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.huge
            font.variableAxes: Appearance.font.variableAxes.titleRounded
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tasks.doneToday > 0 ? Translation.tr("%1 done today").arg(tasks.doneToday) : Translation.tr("Nothing left to do")
            color: WidgetColorScheme.subtextColorOnBg
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    // ── Keys ──
    Row {
        visible: root.count > 0
        x: root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        spacing: 8

        WidgetButton {
            width: root.keyHeight
            height: root.keyHeight
            enabled: root.count > 1 && !root.completing
            symbol: "arrow_forward"
            colFill: WidgetColorScheme.pillBgColor
            colContent: WidgetColorScheme.textColorOnBg
            onClicked: root.index = (root.shownIndex + 1) % Math.max(1, root.count)
        }

        WidgetButton {
            width: root.designWidth - root.padding * 2 - root.keyHeight - 8
            height: root.keyHeight
            symbol: "check"
            symbolSize: 24
            label: root.completing ? Translation.tr("Done") : Translation.tr("Complete")
            labelAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
            colFill: WidgetColorScheme.accentColor
            colContent: WidgetColorScheme.onAccentColor
            // A pill at rest, a rounded square while the task goes.
            restRadius: root.completing ? Appearance.rounding.normal : root.pill(height)
            onClicked: {
                if (root.task && !root.completing)
                    tasks.complete(root.task);
            }
        }
    }
}
