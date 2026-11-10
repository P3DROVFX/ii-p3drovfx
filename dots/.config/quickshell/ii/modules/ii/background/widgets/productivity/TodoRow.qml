import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/*
 * One open task on a To-Do widget: its check, the title, and the due day in
 * monospace (warning colour once overdue). Completing it strikes the title
 * through from the left while the check bursts; the source removes the task
 * once that has been seen.
 */
Item {
    id: row

    required property var task
    required property var source
    property bool interactive: true
    property real checkSize: 28
    property real textSize: Appearance.font.pixelSize.normal
    property int maxLines: 2
    property color colRow: "transparent"

    readonly property bool completing: row.source.isCompleting(row.task)
    readonly property string due: row.source.dueLabel(row.task)
    readonly property bool overdue: row.source.isOverdue(row.task)

    implicitHeight: Math.max(row.checkSize, titleColumn.implicitHeight) + 12

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: rowHover.hovered && row.interactive ? ColorUtils.applyAlpha(WidgetColorScheme.textColorOnBg, 0.06) : row.colRow

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    HoverHandler {
        id: rowHover
    }

    TodoCheck {
        id: check
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        size: row.checkSize
        checked: row.completing
        interactive: row.interactive && !row.completing
        onToggled: row.source.complete(row.task)
    }

    Column {
        id: titleColumn
        anchors.left: check.right
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Item {
            width: parent.width
            height: title.implicitHeight

            StyledText {
                id: title
                width: parent.width
                text: String(row.task?.content ?? "")
                color: row.completing ? WidgetColorScheme.subtextColorOnBg : WidgetColorScheme.textColorOnBg
                font.family: Appearance.font.family.main
                font.pixelSize: row.textSize
                font.variableAxes: ({ "wght": row.completing ? 400 : 560, "wdth": 96, "ROND": 100 })
                wrapMode: Text.Wrap
                maximumLineCount: row.maxLines
                elide: Text.ElideRight

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            // The strike, drawn from the left across the first line.
            Rectangle {
                y: Math.round(title.font.pixelSize * 0.62)
                height: 2
                radius: 1
                color: WidgetColorScheme.subtextColorOnBg
                width: row.completing ? Math.min(title.paintedWidth, parent.width) : 0

                Behavior on width {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                }
            }
        }

        StyledText {
            visible: row.due !== ""
            text: row.due.toUpperCase()
            color: row.overdue ? WidgetColorScheme.warningColor : WidgetColorScheme.subtextColorOnBg
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.letterSpacing: 1
        }
    }
}
