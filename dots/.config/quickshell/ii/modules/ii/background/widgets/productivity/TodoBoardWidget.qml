pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * To-Do Board (2x1). A slab on the left carries how many tasks are open as
 * one tall condensed number - it thins as the list empties - with today's
 * finished count under it; the list on the right checks tasks off in place
 * and takes new ones from the field at its foot.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "todo_board"
    designWidth: 492
    designHeight: 240

    readonly property real padding: 12
    readonly property real slabWidth: 148
    readonly property real numberSize: 118

    TodoSource {
        id: tasks
    }

    // Heavier with more to do, so the number itself reads as the load.
    readonly property real load: Math.min(1, tasks.openCount / 8)
    property real easedLoad: root.load
    Behavior on easedLoad {
        enabled: !Appearance.reducedMotion
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // ── Count slab ──
    Rectangle {
        id: slab
        x: root.padding
        y: root.padding
        width: root.slabWidth
        height: root.designHeight - root.padding * 2
        radius: Appearance.rounding.normal
        color: WidgetColorScheme.pillFillColor

        StyledText {
            x: 16
            y: 14
            text: Translation.tr("To do").toUpperCase()
            color: WidgetColorScheme.textColorOnPillFill
            opacity: 0.8
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.letterSpacing: 1.5
        }

        Text {
            id: countText
            x: 12
            anchors.bottom: captions.top
            anchors.bottomMargin: -Math.round(root.numberSize * 0.14)
            text: String(tasks.openCount)
            color: WidgetColorScheme.textColorOnPillFill
            font.family: Appearance.font.family.main
            font.pixelSize: root.numberSize
            font.variableAxes: ({ "wght": Math.round(300 + 600 * root.easedLoad), "wdth": 40, "ROND": 100, "opsz": 144 })
            renderType: Text.QtRendering
        }

        Column {
            id: captions
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            spacing: 2

            StyledText {
                text: tasks.openCount === 1 ? Translation.tr("task left") : Translation.tr("tasks left")
                color: WidgetColorScheme.textColorOnPillFill
                font.pixelSize: Appearance.font.pixelSize.normal
                font.variableAxes: ({ "wght": 600, "wdth": 100, "ROND": 100 })
            }
            StyledText {
                text: Translation.tr("%1 done today").arg(tasks.doneToday)
                color: WidgetColorScheme.textColorOnPillFill
                opacity: 0.75
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }
    }

    // ── List ──
    Item {
        id: listArea
        anchors.left: slab.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: root.padding
        y: root.padding
        height: addField.y - y - 6

        ListView {
            id: list
            anchors.fill: parent
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: tasks.openTasks
            interactive: contentHeight > height

            delegate: TodoRow {
                required property var modelData
                width: ListView.view.width
                task: modelData
                source: tasks
                interactive: root.actionsEnabled
                maxLines: 1
            }
        }

        Row {
            visible: tasks.openCount === 0
            anchors.centerIn: parent
            spacing: 10

            MaterialShape {
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 44
                shape: MaterialShape.Shape.Cookie7Sided
                color: WidgetColorScheme.pillBgColor

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "done_all"
                    iconSize: 22
                    color: WidgetColorScheme.subtextColorOnBg
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Nothing left to do")
                color: WidgetColorScheme.subtextColorOnBg
                font.pixelSize: Appearance.font.pixelSize.normal
            }
        }
    }

    TodoAddField {
        id: addField
        anchors.left: listArea.left
        anchors.right: listArea.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.padding
        height: 44
        source: tasks
        interactive: root.actionsEnabled
    }
}
