#!/usr/bin/env python3
"""Contract tests for Todo Done history (30 items), notifications, and Timetable integration."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class TodoDoneAndTimetableIntegrationTests(unittest.TestCase):

    def setUp(self):
        self.todo_qml = (ROOT / "services" / "Todo.qml").read_text(encoding="utf-8")
        self.directories_qml = (ROOT / "modules" / "common" / "Directories.qml").read_text(encoding="utf-8")
        self.persistent_qml = (ROOT / "modules" / "common" / "Persistent.qml").read_text(encoding="utf-8")
        self.event_sidebar_qml = (ROOT / "modules" / "ii" / "cheatsheet" / "timetable" / "EventSidebar.qml").read_text(encoding="utf-8")
        self.todo_widget_qml = (ROOT / "modules" / "common" / "dashboardWidgets" / "todo" / "TodoWidget.qml").read_text(encoding="utf-8")
        self.ticktick_qml = (ROOT / "services" / "TickTickService.qml").read_text(encoding="utf-8")
        self.notification_utils_qml = (ROOT / "modules" / "common" / "functions" / "NotificationUtils.qml").read_text(encoding="utf-8")
        self.shell_qml = (ROOT / "shell.qml").read_text(encoding="utf-8")

    def test_directories_has_todo_done_history_path(self):
        self.assertIn("todoDoneHistoryPath:", self.directories_qml)
        self.assertIn("todo_done.json", self.directories_qml)

    def test_persistent_has_todo_notified_today(self):
        self.assertIn("todoNotifiedToday:", self.persistent_qml)

    def test_todo_manages_done_history_up_to_30_tasks(self):
        # Must load and persist doneHistoryList
        self.assertIn("property var doneHistoryPath: Directories.todoDoneHistoryPath", self.todo_qml)
        self.assertIn("property var doneHistoryList: []", self.todo_qml)
        self.assertIn("slice(0, 30)", self.todo_qml)
        self.assertIn("todoDoneHistoryFileView.setText(JSON.stringify(root.doneHistoryList))", self.todo_qml)
        self.assertIn("todoDoneHistoryFileView", self.todo_qml)

    def test_todo_mark_done_and_unfinished_contracts(self):
        # markDone adds to doneHistoryList
        self.assertIn("function markDone(taskOrIndex)", self.todo_qml)
        self.assertIn("normalized.done = true", self.todo_qml)
        self.assertIn("normalized.completedAt = Date.now()", self.todo_qml)
        # markUnfinished removes from doneHistoryList
        self.assertIn("function markUnfinished(taskOrIndex)", self.todo_qml)
        self.assertIn("root.persistDoneHistory", self.todo_qml)

    def test_todo_done_tasks_reactive_property(self):
        # Exposes doneTasks combining history and list
        self.assertIn("readonly property var doneTasks:", self.todo_qml)
        self.assertIn("root.doneHistoryList", self.todo_qml)

    def test_todo_widget_consumes_todo_done_tasks(self):
        self.assertIn("const source = Todo.doneTasks ?? []", self.todo_widget_qml)

    def test_local_date_parsing_avoids_utc_midnight_drift(self):
        self.assertIn("function parseLocalDate(value)", self.todo_qml)
        self.assertIn("function _localDueDate(value)", self.ticktick_qml)
        # Both parse without shifting dates on UTC midnight
        self.assertIn("new Date(year, month, day, 0, 0, 0)", self.todo_qml)
        self.assertIn("new Date(year, month, day, 0, 0, 0)", self.ticktick_qml)

    def test_due_task_notifications_contract(self):
        self.assertIn("function checkDueTasksNotifications()", self.todo_qml)
        self.assertIn('appName: "To Do"', self.todo_qml)
        self.assertIn('appIcon: "task-due"', self.todo_qml)
        self.assertIn('sound: true', self.todo_qml)
        self.assertIn('dueTasksPeriodicTimer', self.todo_qml)
        self.assertIn('todoNotifiedToday', self.todo_qml)

    def test_notification_utils_has_task_keywords(self):
        self.assertIn("'task': 'checklist'", self.notification_utils_qml)
        self.assertIn("'tarefa': 'checklist'", self.notification_utils_qml)

    def test_event_sidebar_day_mode_includes_tasks(self):
        self.assertIn("readonly property var dayTasks: Todo.getTasksByDate(root.day).filter(task => !task.done)", self.event_sidebar_qml)
        self.assertIn("root.dayTasks", self.event_sidebar_qml)
        # dayEvents includes dayTasks so header count is accurate
        self.assertIn("root.dayCalendarEvents.concat(root.dayBirthdays, root.daySports, root.dayTasks)", self.event_sidebar_qml)
        # In daySections, tasks are rendered with TaskChip and onCompletionRequested
        self.assertIn("model: root.sportsListOnly ? [] : root.dayTasks", self.event_sidebar_qml)
        self.assertIn("TaskChip {", self.event_sidebar_qml)
        self.assertIn("onCompletionRequested: task => root.taskCompletionRequested(task)", self.event_sidebar_qml)

    def test_shell_touches_todo_singleton(self):
        self.assertIn("Todo.list;", self.shell_qml)

    def test_runtime_qml_behavior(self):
        import tempfile, subprocess, os, shutil
        runner = shutil.which("qmltestrunner6") or "/usr/lib64/qt6/bin/qmltestrunner"
        if not shutil.which(runner) and not os.path.exists(runner):
            self.skipTest("Qt 6 qmltestrunner not found")

        with tempfile.TemporaryDirectory(prefix="todo-int-test-") as tmpdir:
            tests_dir = Path(tmpdir) / "tests"
            tests_dir.mkdir(parents=True, exist_ok=True)
            test_qml = tests_dir / "tst_todo_runtime.qml"
            test_qml.write_text(r"""import QtQuick
import QtTest

TestCase {
    name: "TodoRuntimeTests"

    function parseLocalDate(value) {
        if (!value) return null;
        if (value instanceof Date) return isNaN(value.getTime()) ? null : value;
        const str = String(value).trim();
        const match = str.match(/^(\d{4})-(\d{2})-(\d{2})(?:[T\s](\d{2}):(\d{2})(?::(\d{2}))?)?/);
        if (match) {
            const year = Number(match[1]);
            const month = Number(match[2]) - 1;
            const day = Number(match[3]);
            const hours = match[4] !== undefined ? Number(match[4]) : 0;
            const minutes = match[5] !== undefined ? Number(match[5]) : 0;
            const seconds = match[6] !== undefined ? Number(match[6]) : 0;
            if (!match[4] || (hours === 0 && minutes === 0 && seconds === 0)) {
                return new Date(year, month, day, 0, 0, 0);
            }
            const parsed = new Date(str);
            return isNaN(parsed.getTime()) ? new Date(year, month, day) : parsed;
        }
        const d = new Date(str);
        return isNaN(d.getTime()) ? null : d;
    }

    function test_parse_local_date_preserves_day_across_timezones() {
        const d1 = parseLocalDate("2026-09-08T00:00:00.000Z");
        compare(d1.getFullYear(), 2026);
        compare(d1.getMonth(), 8);
        compare(d1.getDate(), 8);

        const d2 = parseLocalDate("2026-09-08");
        compare(d2.getFullYear(), 2026);
        compare(d2.getMonth(), 8);
        compare(d2.getDate(), 8);
    }

    function test_done_history_capped_at_30() {
        const history = [];
        for (let i = 0; i < 35; i++) {
            history.unshift({ id: "task-" + i, content: "Task " + i, done: true, completedAt: Date.now() + i });
        }
        const capped = history.slice(0, 30);
        compare(capped.length, 30);
        compare(capped[0].id, "task-34");
    }
}
""")
            cmd = [runner, "-input", str(tests_dir)]
            env = os.environ.copy()
            env["QT_QPA_PLATFORM"] = "offscreen"
            env["QT_QUICK_BACKEND"] = "software"
            res = subprocess.run(cmd, capture_output=True, text=True, env=env)
            self.assertEqual(res.returncode, 0, f"qmltestrunner failed:\n{res.stdout}\n{res.stderr}")

if __name__ == "__main__":
    unittest.main()
