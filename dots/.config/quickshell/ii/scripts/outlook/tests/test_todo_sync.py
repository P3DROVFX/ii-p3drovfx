#!/usr/bin/env python3
"""Contracts for the Reminders ↔ Microsoft To Do bridge, run against an in-memory To Do."""

from __future__ import annotations

import itertools
import re
import unittest
from datetime import datetime, timezone
from typing import Any
from urllib.parse import unquote
from zoneinfo import ZoneInfo

from scripts.outlook import todo_sync


PARIS = ZoneInfo("Europe/Paris")
NOW = int(datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc).timestamp() * 1000)


class FakeToDo:
    """Just enough of Graph's To Do API: lists, tasks, checklist items, links, extensions."""

    def __init__(self) -> None:
        self.ids = itertools.count(1)
        self.clock = NOW - 3600_000
        self.lists: dict[str, dict[str, Any]] = {}
        self.tasks: dict[str, dict[str, dict[str, Any]]] = {}
        self.calls: list[tuple[str, str]] = []
        self.add_list("Tasks", wellknown="defaultList")

    def stamp(self) -> str:
        self.clock += 1000
        return datetime.fromtimestamp(self.clock / 1000, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    def new_id(self, prefix: str) -> str:
        return f"{prefix}{next(self.ids)}"

    def add_list(self, name: str, wellknown: str = "none") -> str:
        list_id = self.new_id("L")
        self.lists[list_id] = {"id": list_id, "displayName": name, "wellknownListName": wellknown}
        self.tasks[list_id] = {}
        return list_id

    def add_task(self, list_id: str, **fields: Any) -> str:
        task_id = self.new_id("T")
        task = {"id": task_id, "title": "", "status": "notStarted", "importance": "normal",
                "body": {"content": "", "contentType": "text"}, "checklistItems": [], "linkedResources": [],
                "extensions": [], "createdDateTime": self.stamp()}
        task.update(fields)
        task["lastModifiedDateTime"] = self.stamp()
        self.tasks[list_id][task_id] = task
        return task_id

    def touch(self, list_id: str, task_id: str) -> None:
        self.tasks[list_id][task_id]["lastModifiedDateTime"] = self.stamp()

    # Graph interface used by Syncer.
    def get_all(self, path: str) -> list[dict[str, Any]]:
        self.calls.append(("GET", path))
        if path == "/me/todo/lists":
            return [dict(item) for item in self.lists.values()]
        match = re.match(r"^/me/todo/lists/([^/?]+)/tasks\?", path)
        if match:
            list_id = unquote(match.group(1))
            if list_id not in self.tasks:
                raise todo_sync.NotFound("no list")
            return [self.copy_task(task) for task in self.tasks[list_id].values()]
        raise AssertionError("unexpected GET " + path)

    def copy_task(self, task: dict[str, Any]) -> dict[str, Any]:
        import copy
        return copy.deepcopy(task)

    def request(self, method: str, path: str, body: Any = None) -> Any:
        self.calls.append((method, path))
        parts = [unquote(part) for part in path.strip("/").split("/")][3:]  # after me/todo/lists
        if not parts:
            assert method == "POST"
            return dict(self.lists[self.add_list(body["displayName"])])
        list_id = parts[0]
        if len(parts) == 1:
            if method == "DELETE":
                self.lists.pop(list_id, None)
                self.tasks.pop(list_id, None)
                return {}
            if method == "PATCH":
                self.lists[list_id].update(body)
                return dict(self.lists[list_id])
        if len(parts) == 2 and method == "POST":
            fields = {key: value for key, value in body.items()}
            task_id = self.add_task(list_id, **fields)
            return self.copy_task(self.tasks[list_id][task_id])
        task_id = parts[2]
        task = self.tasks[list_id].get(task_id)
        if len(parts) == 3:
            if method == "GET":
                return self.copy_task(task) if task else {}
            if method == "DELETE":
                self.tasks[list_id].pop(task_id, None)
                return {}
            if task is None:
                raise todo_sync.NotFound("no task")
            for key, value in body.items():
                if value is None:
                    task.pop(key, None)
                else:
                    task[key] = value
            self.touch(list_id, task_id)
            return self.copy_task(task)
        collection = parts[3]
        # Like Graph: writing a task's parts moves its modified time on.
        self.touch(list_id, task_id)
        if collection == "extensions":
            if method == "POST":
                task["extensions"] = [dict(body, id=body["extensionName"])]
            else:
                task["extensions"][0].update(body)
            return {}
        items = task[collection]
        if method == "POST":
            item = dict(body, id=self.new_id("C"))
            items.append(item)
            return dict(item)
        item_id = parts[4]
        if method == "DELETE":
            task[collection] = [item for item in items if item["id"] != item_id]
            return {}
        for item in items:
            if item["id"] == item_id:
                item.update(body)
        return {}


def store(reminders: list[dict[str, Any]] | None = None, categories: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    return {
        "categories": categories or [{"id": "default", "name": "My reminders", "color": "", "icon": "checklist", "pinned": False, "order": 0}],
        "reminders": reminders or [],
        "tombstones": [],
        "sync": {},
    }


def reminder(**fields: Any) -> dict[str, Any]:
    base = {"id": "r1", "title": "Pay rent", "notes": "", "categoryId": "default", "important": False,
            "completed": False, "completedAt": 0, "deletedAt": 0, "createdAt": NOW - 10_000, "modifiedAt": NOW - 10_000,
            "checklist": [], "attachments": [], "schedule": None, "alert": "default", "early": None,
            "snoozedUntil": 0, "firedFor": "", "earlyFiredFor": "", "remote": None}
    base.update(fields)
    return base


def run(fake: FakeToDo, data: dict[str, Any], now: int = NOW) -> dict[str, Any]:
    return todo_sync.Syncer(fake, data, now, "09:00", PARIS).run()["store"]  # type: ignore[arg-type]


class ToDoSyncTests(unittest.TestCase):
    def test_default_category_links_to_the_default_list(self) -> None:
        fake = FakeToDo()
        out = run(fake, store())
        default = out["categories"][0]
        self.assertEqual(default["remote"]["todo"]["listId"], "L1")
        self.assertEqual(default["name"], "My reminders")

    def test_new_local_reminder_is_created_with_time_repeat_checklist_and_extension(self) -> None:
        fake = FakeToDo()
        local = reminder(
            important=True, notes="Landlord",
            schedule={"date": "2026-10-05", "time": "18:30", "repeat": {
                "unit": "month", "interval": 1, "weekdays": [False] * 7, "monthDays": [5], "yearDates": [],
                "anchor": "2026-10-05", "end": {"kind": "never", "count": 1, "until": ""}}, "occurrence": 0},
            checklist=[{"id": "c0", "text": "Transfer", "done": False}],
            attachments=[{"id": "a0", "kind": "link", "url": "https://bank.example", "path": "", "name": ""}],
            alert="strong", early={"kind": "day", "at": 0})
        out = run(fake, store([local]))
        task = next(iter(fake.tasks["L1"].values()))
        self.assertEqual(task["title"], "Pay rent")
        self.assertEqual(task["importance"], "high")
        self.assertEqual(task["reminderDateTime"]["dateTime"], "2026-10-05T16:30:00.0000000")
        self.assertEqual(task["recurrence"]["pattern"], {"type": "absoluteMonthly", "interval": 1, "dayOfMonth": 5})
        self.assertEqual([item["displayName"] for item in task["checklistItems"]], ["Transfer"])
        self.assertEqual(task["linkedResources"][0]["webUrl"], "https://bank.example")
        self.assertEqual(task["extensions"][0]["alert"], "strong")
        linked = out["reminders"][0]
        self.assertEqual(linked["remote"]["todo"]["taskId"], task["id"])
        self.assertEqual(linked["checklist"][0]["id"], task["checklistItems"][0]["id"])

    def test_second_sync_without_changes_writes_nothing(self) -> None:
        fake = FakeToDo()
        first = run(fake, store([reminder(schedule={"date": "2026-10-05", "time": "", "repeat": None, "occurrence": 0})]))
        fake.calls.clear()
        second = run(fake, first, NOW + 60_000)
        writes = [call for call in fake.calls if call[0] != "GET"]
        self.assertEqual(writes, [])
        self.assertEqual(second["reminders"][0]["schedule"]["time"], "")

    def test_phone_edit_comes_across_and_keeps_local_only_fields(self) -> None:
        fake = FakeToDo()
        image = {"id": "a1", "kind": "image", "path": "/tmp/x.png", "url": "", "name": "x.png"}
        first = run(fake, store([reminder(alert="medium", attachments=[image],
                                          schedule={"date": "2026-10-05", "time": "08:00", "repeat": None, "occurrence": 0})]))
        task_id = first["reminders"][0]["remote"]["todo"]["taskId"]
        task = fake.tasks["L1"][task_id]
        task["title"] = "Pay rent today"
        task["reminderDateTime"] = {"dateTime": "2026-10-05T07:15:00.0000000", "timeZone": "UTC"}
        fake.touch("L1", task_id)
        out = run(fake, first, NOW + 60_000)
        pulled = out["reminders"][0]
        self.assertEqual(pulled["title"], "Pay rent today")
        self.assertEqual(pulled["schedule"]["time"], "09:15")
        self.assertEqual(pulled["alert"], "medium")
        self.assertEqual(pulled["attachments"], [image])

    def test_both_changed_newer_wins(self) -> None:
        fake = FakeToDo()
        first = run(fake, store([reminder()]))
        task_id = first["reminders"][0]["remote"]["todo"]["taskId"]
        fake.tasks["L1"][task_id]["title"] = "Phone title"
        fake.touch("L1", task_id)
        local = first["reminders"][0]
        local["title"] = "Desktop title"
        local["modifiedAt"] = NOW + 120_000  # edited after the phone did
        out = run(fake, first, NOW + 180_000)
        self.assertEqual(out["reminders"][0]["title"], "Desktop title")
        self.assertEqual(fake.tasks["L1"][task_id]["title"], "Desktop title")

    def test_remote_delete_bins_an_unchanged_reminder(self) -> None:
        fake = FakeToDo()
        first = run(fake, store([reminder()]))
        fake.tasks["L1"].clear()
        out = run(fake, first, NOW + 60_000)
        self.assertGreater(out["reminders"][0]["deletedAt"], 0)
        self.assertIsNone(out["reminders"][0]["remote"])

    def test_binning_here_deletes_there_and_tombstones_are_spent(self) -> None:
        fake = FakeToDo()
        first = run(fake, store([reminder(), reminder(id="r2", title="Second")]))
        first["reminders"][0]["deletedAt"] = NOW + 1
        gone = first["reminders"].pop(1)
        first["tombstones"] = [{"kind": "task", "listId": "L1", "taskId": gone["remote"]["todo"]["taskId"]}]
        out = run(fake, first, NOW + 60_000)
        self.assertEqual(fake.tasks["L1"], {})
        self.assertEqual(out["tombstones"], [])

    def test_new_phone_task_and_list_arrive(self) -> None:
        fake = FakeToDo()
        groceries = fake.add_list("Groceries")
        fake.add_task(groceries, title="Milk", importance="high",
                      dueDateTime={"dateTime": "2026-10-02T22:00:00.0000000", "timeZone": "UTC"},
                      checklistItems=[{"id": "C9", "displayName": "Oat", "isChecked": True}],
                      recurrence={"pattern": {"type": "weekly", "interval": 2, "daysOfWeek": ["saturday"]},
                                  "range": {"type": "noEnd", "startDate": "2026-10-03"}})
        out = run(fake, store())
        names = [category["name"] for category in out["categories"]]
        self.assertIn("Groceries", names)
        milk = next(item for item in out["reminders"] if item["title"] == "Milk")
        self.assertTrue(milk["important"])
        self.assertEqual(milk["schedule"]["date"], "2026-10-03")  # local date in Paris
        self.assertEqual(milk["schedule"]["time"], "")
        self.assertEqual(milk["schedule"]["repeat"]["unit"], "week")
        self.assertEqual(milk["schedule"]["repeat"]["interval"], 2)
        self.assertTrue(milk["schedule"]["repeat"]["weekdays"][6])
        self.assertEqual(milk["checklist"], [{"id": "C9", "text": "Oat", "done": True}])

    def test_old_completed_tasks_stay_history(self) -> None:
        fake = FakeToDo()
        fake.add_task("L1", title="Ancient", status="completed",
                      completedDateTime={"dateTime": "2024-01-01T10:00:00.0000000", "timeZone": "UTC"})
        fake.add_task("L1", title="Recent", status="completed",
                      completedDateTime={"dateTime": "2026-09-30T10:00:00.0000000", "timeZone": "UTC"})
        out = run(fake, store())
        self.assertEqual([item["title"] for item in out["reminders"]], ["Recent"])
        self.assertTrue(out["reminders"][0]["completed"])

    def test_category_moves_recreate_the_task_in_the_new_list(self) -> None:
        fake = FakeToDo()
        categories = [{"id": "default", "name": "My reminders", "color": "", "icon": "checklist", "pinned": False, "order": 0},
                      {"id": "work", "name": "Work", "color": "#3d9be9", "icon": "work", "pinned": False, "order": 1}]
        first = run(fake, store([reminder()], categories))
        work_list = next(c for c in first["categories"] if c["id"] == "work")["remote"]["todo"]["listId"]
        first["reminders"][0]["categoryId"] = "work"
        first["reminders"][0]["modifiedAt"] = NOW + 30_000
        out = run(fake, first, NOW + 60_000)
        self.assertEqual(fake.tasks["L1"], {})
        self.assertEqual(len(fake.tasks[work_list]), 1)
        self.assertEqual(out["reminders"][0]["remote"]["todo"]["listId"], work_list)

    def test_minute_repeats_survive_in_the_extension(self) -> None:
        fake = FakeToDo()
        rule = {"unit": "minute", "interval": 30, "weekdays": [False] * 7, "monthDays": [], "yearDates": [],
                "anchor": "2026-10-05", "end": {"kind": "never", "count": 1, "until": ""}}
        first = run(fake, store([reminder(schedule={"date": "2026-10-05", "time": "10:00", "repeat": rule, "occurrence": 0})]))
        task_id = first["reminders"][0]["remote"]["todo"]["taskId"]
        self.assertIsNone(fake.tasks["L1"][task_id].get("recurrence"))
        fake.tasks["L1"][task_id]["title"] = "Stretch"
        fake.touch("L1", task_id)
        out = run(fake, first, NOW + 60_000)
        self.assertEqual(out["reminders"][0]["schedule"]["repeat"]["unit"], "minute")
        self.assertEqual(out["reminders"][0]["schedule"]["repeat"]["interval"], 30)

    def test_list_renames_go_both_ways(self) -> None:
        fake = FakeToDo()
        categories = [{"id": "default", "name": "My reminders", "color": "", "icon": "checklist", "pinned": False, "order": 0},
                      {"id": "uni", "name": "Uni", "color": "", "icon": "school", "pinned": False, "order": 1}]
        first = run(fake, store([], categories))
        uni_list = next(c for c in first["categories"] if c["id"] == "uni")["remote"]["todo"]["listId"]
        next(c for c in first["categories"] if c["id"] == "uni")["name"] = "University"
        second = run(fake, first, NOW + 60_000)
        self.assertEqual(fake.lists[uni_list]["displayName"], "University")
        fake.lists[uni_list]["displayName"] = "M2 MCB"
        third = run(fake, second, NOW + 120_000)
        self.assertEqual(next(c for c in third["categories"] if c["id"] == "uni")["name"], "M2 MCB")


if __name__ == "__main__":
    unittest.main()
