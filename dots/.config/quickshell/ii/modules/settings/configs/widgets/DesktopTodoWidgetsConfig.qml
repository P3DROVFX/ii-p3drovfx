import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets.productivity
import qs.modules.settings.configs.widgets

/*
 * One page for the three To-Do widgets: Focus (1x1), Board (2x1) and Column
 * (1x2). The hero is the three of them live, as the cells they take on the
 * desktop, with the list they read from beside them.
 */
ContentPage {
    id: root
    forceWidth: false

    signal goBack

    readonly property var widgets: Config.options.background.widgets

    WidgetPageHeader {
        title: Translation.tr("To-Do Widgets Options")
        onBack: root.goBack()
    }

    // ── Live preview: [ Column ][ Board  ]
    //                  [       ][ Focus ][ list ]
    WidgetPreviewStage {
        columns: 3
        rows: 2

        WidgetPreviewSlot {
            rowSpan: 2
            TodoColumnWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.height / Math.max(1, implicitHeight)
            }
        }

        WidgetPreviewSlot {
            column: 1
            columnSpan: 2
            TodoBoardWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }

        WidgetPreviewSlot {
            column: 1
            row: 1
            TodoFocusWidget {
                anchors.centerIn: parent
                isPreview: true
                scale: parent.width / Math.max(1, implicitWidth)
            }
        }

        // Where the tasks come from.
        WidgetPreviewSlot {
            column: 2
            row: 1

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer2

                MaterialShapeWrappedMaterialSymbol {
                    x: 20
                    y: 20
                    text: Todo.remoteEnabled ? "cloud_sync" : "folder"
                    iconSize: 28
                    padding: 14
                    shape: MaterialShape.Shape.Cookie9Sided
                    color: Appearance.colors.colPrimaryContainer
                    colSymbol: Appearance.colors.colOnPrimaryContainer
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.right: parent.right
                    anchors.rightMargin: 22
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 22
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Tasks from")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: Todo.providerName
                        color: Appearance.colors.colOnLayer2
                        font.family: Appearance.font.family.title
                        font.pixelSize: Appearance.font.pixelSize.huge + 4
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                    }
                    StyledText {
                        text: Translation.tr("Same list as the sidebar")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("To-Do Focus (1x1)")
        icon: "task_alt"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "todo_focus" }
            WidgetSizeSlider { options: root.widgets.todo_focus }

            ConfigSwitch {
                buttonIcon: "pin"
                text: Translation.tr("Position in the list")
                checked: root.widgets.todo_focus.showPosition ?? true
                onCheckedChanged: root.widgets.todo_focus.showPosition = checked
                StyledToolTip {
                    text: Translation.tr("Show which task this is of how many, as 2/5, in the corner.")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("To-Do Board (2x1)")
        icon: "checklist"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "todo_board" }
            WidgetSizeSlider { options: root.widgets.todo_board }
        }
    }

    ContentSection {
        title: Translation.tr("To-Do Column (1x2)")
        icon: "list_alt"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            WidgetPlacementNote { widgetId: "todo_column" }
            WidgetSizeSlider { options: root.widgets.todo_column }

            ConfigSwitch {
                buttonIcon: "linear_scale"
                text: Translation.tr("Today's progress")
                checked: root.widgets.todo_column.showProgress ?? true
                onCheckedChanged: root.widgets.todo_column.showProgress = checked
                StyledToolTip {
                    text: Translation.tr("A segmented bar under the title: one segment per task, the finished ones filled.")
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shared")
        icon: "tune"

        DesktopWidgetVisualOptions {
            Layout.fillWidth: true
        }
    }
}
