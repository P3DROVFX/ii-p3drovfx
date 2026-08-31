pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    property string searchQuery: ""
    property int selectedIndex: 0
    property string noticeText: ""

    readonly property var rows: root.filteredTasks()
    readonly property var selectedTask: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
        ? root.rows[root.selectedIndex]
        : null
    readonly property string statusText: root.noticeText.length > 0
        ? root.noticeText
        : Todo.syncing
        ? Translation.tr("Syncing %1…").arg(Todo.providerName)
        : root.selectedTask
            ? String(root.selectedTask.content ?? root.selectedTask.title ?? "")
            : Translation.tr("%1 tasks · %2").arg(String(root.rows.length)).arg(Todo.providerName)

    implicitWidth: 720
    implicitHeight: scaffold.implicitHeight

    function normalizedQuery() {
        return root.searchQuery.trim().toLocaleLowerCase();
    }

    function filteredTasks() {
        const query = root.normalizedQuery();
        return Array.from(Todo.list ?? []).filter(task => {
            if (!Config.options.search.modules.tasks.showCompleted && task?.done)
                return false;
            if (query.length === 0)
                return true;
            return [task?.content, task?.title, task?.notes, task?.dueDate, task?.date]
                .join(" ").toLocaleLowerCase().includes(query);
        }).sort((left, right) => Number(left?.done ?? false) - Number(right?.done ?? false));
    }

    function taskIndex(task) {
        return Array.from(Todo.list ?? []).findIndex(candidate => candidate === task
            || String(candidate?.id ?? "") === String(task?.id ?? ""));
    }

    function taskDateLabel(task) {
        const value = task?.dueDate ?? task?.date;
        if (!value)
            return Translation.tr("No date");
        const date = new Date(value);
        if (isNaN(date.getTime()))
            return Translation.tr("No date");
        return Qt.formatDate(date, "dd MMM");
    }

    function parseQuickTask(input) {
        let title = String(input ?? "").trim();
        let dueDate = null;
        const now = new Date();
        if (/\b(amanh[ãa]|tomorrow)\b/i.test(title)) {
            const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
            dueDate = tomorrow;
            title = title.replace(/\b(amanh[ãa]|tomorrow)\b/ig, "").trim();
        } else if (/\b(hoje|today)\b/i.test(title)) {
            dueDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
            title = title.replace(/\b(hoje|today)\b/ig, "").trim();
        }
        return { title, dueDate };
    }

    function createFromQuery(): bool {
        if (!Config.options.search.modules.tasks.allowCreate)
            return false;
        if (!Todo.connected) {
            root.showNotice(Translation.tr("Connect %1 before creating a task").arg(Todo.providerName));
            return true;
        }
        const parsed = root.parseQuickTask(root.searchQuery);
        if (parsed.title.length === 0)
            return false;
        Todo.addItem({
            content: parsed.title,
            title: parsed.title,
            done: false,
            date: parsed.dueDate,
            dueDate: parsed.dueDate,
            hasDate: parsed.dueDate !== null
        });
        root.searchQuery = "";
        root.showNotice(Translation.tr("Task created in %1").arg(Todo.providerName));
        return true;
    }

    function clampSelection() {
        if (root.rows.length === 0) {
            root.selectedIndex = -1;
            return;
        }
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }

    function navigateUp(): bool {
        if (root.selectedIndex <= 0)
            return false;
        root.selectedIndex--;
        taskList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function navigateDown(): bool {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length - 1)
            return false;
        root.selectedIndex++;
        taskList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
        return true;
    }

    function activateSelected(): bool {
        const index = root.taskIndex(root.selectedTask);
        if (index < 0)
            return false;
        const wasDone = root.selectedTask.done === true;
        if (wasDone)
            Todo.markUnfinished(index);
        else
            Todo.markDone(root.selectedTask);
        root.showNotice(wasDone ? Translation.tr("Task reopened") : Translation.tr("Task completed"));
        return true;
    }

    function deleteSelected(): bool {
        const index = root.taskIndex(root.selectedTask);
        if (index < 0)
            return false;
        const taskName = String(root.selectedTask.content ?? root.selectedTask.title ?? "");
        Todo.deleteItem(index);
        root.selectedIndex = Math.max(0, root.selectedIndex - 1);
        root.showNotice(Translation.tr("Deleted %1").arg(taskName));
        return true;
    }

    function showNotice(message) {
        root.noticeText = String(message ?? "");
        noticeTimer.restart();
    }

    function focusInput(): bool {
        return false;
    }

    onRowsChanged: root.clampSelection()

    Timer {
        id: noticeTimer
        interval: 3200
        onTriggered: root.noticeText = ""
    }

    SearchPanelScaffold {
        id: scaffold
        anchors.fill: parent
        title: Translation.tr("Tasks")
        icon: "task_alt"
        accent: true
        statusText: root.statusText
        showStatus: true
        primaryHint: ({ label: root.selectedTask?.done ? Translation.tr("Reopen") : Translation.tr("Complete"), actionId: "activate", keys: ["↵"] })
        hints: [
            { label: Translation.tr("New from query"), actionId: "create", keys: ["Ctrl", "N"] },
            { label: Translation.tr("Delete"), actionId: "delete", keys: ["⇧", "Del"] }
        ]

        ColumnLayout {
            width: parent.width
            height: parent.height
            spacing: Appearance.sizes.elevationMargin

            StyledText {
                Layout.fillWidth: true
                visible: !Todo.connected
                text: Translation.tr("%1 is not connected").arg(Todo.providerName)
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.small
            }

            ListView {
                id: taskList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Appearance.sizes.elevationMargin / 2
                model: root.rows

                delegate: RippleButton {
                    required property int index
                    required property var modelData
                    width: taskList.width
                    implicitHeight: taskContent.implicitHeight + Appearance.sizes.elevationMargin * 2
                    buttonRadius: Appearance.rounding.normal
                    colBackground: root.selectedIndex === index
                        ? Appearance.colors.colPrimaryContainer
                        : Appearance.colors.colSurfaceContainerHigh
                    colBackgroundHover: root.selectedIndex === index
                        ? Appearance.colors.colPrimaryContainerHover
                        : Appearance.colors.colSurfaceContainerHighestHover
                    colRipple: root.selectedIndex === index
                        ? Appearance.colors.colPrimaryContainerActive
                        : Appearance.colors.colSurfaceContainerHighestActive
                    onClicked: {
                        root.selectedIndex = index;
                        root.activateSelected();
                    }

                    RowLayout {
                        id: taskContent
                        anchors.fill: parent
                        anchors.margins: Appearance.sizes.elevationMargin
                        spacing: Appearance.sizes.elevationMargin

                        MaterialSymbol {
                            text: modelData.done ? "check_circle" : "radio_button_unchecked"
                            iconSize: Appearance.font.pixelSize.normal
                            color: root.selectedIndex === index
                                ? Appearance.colors.colOnPrimaryContainer
                                : (modelData.done ? Appearance.colors.colPrimary : Appearance.colors.colOnSurface)
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Appearance.sizes.elevationMargin / 4

                            StyledText {
                                Layout.fillWidth: true
                                text: String(modelData.content ?? modelData.title ?? "")
                                elide: Text.ElideRight
                                font.strikeout: modelData.done
                                color: root.selectedIndex === index
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnSurface
                                opacity: modelData.done ? 0.55 : 1
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.taskDateLabel(modelData)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: root.selectedIndex === index
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colSubtext
                            }
                        }

                        ConfiguredKeyHint {
                            visible: root.selectedIndex === index && Config.options.search.appearance.showKeyHints
                            actionId: "activate"
                            fallbackKeys: ["↵"]
                            surface: Appearance.colors.colPrimaryContainer
                            onSurface: Appearance.colors.colOnPrimaryContainer
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.rows.length === 0
                    text: root.searchQuery.trim().length > 0
                        ? Translation.tr("No tasks match — Ctrl+N creates it")
                        : Translation.tr("No tasks yet")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
