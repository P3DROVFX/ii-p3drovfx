#!/usr/bin/env python3
"""Two-way sync between the shell's Reminders and Microsoft To Do.

Samsung Reminder's own "Sync with Microsoft To Do" makes To Do the bridge between a
Galaxy phone and this desktop: categories are To Do lists (Samsung's default category
is the default "Tasks" list), reminders are tasks.

The shell owns the reminders file; this script never touches it. It reads the whole
store and an access token as JSON on stdin, talks to Graph, and prints the merged
store as one JSON reply. What To Do has no field for (alert level, early alert, a
repeat rule finer than Graph's, the category colour) rides along in an open extension
on each task, so a round trip through the phone keeps it.

Conflicts: each side knows when it last changed (the reminder's modifiedAt, the
task's lastModifiedDateTime) and when the two last agreed (remote.todo.syncedAt /
remote.todo.lastModified). Only one side changed: it wins. Both changed: the newer
edit wins.
"""

from __future__ import annotations

import html
import json
import os
import re
import sys
import time
from datetime import date, datetime, timedelta, timezone
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

try:
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
except ImportError:  # pragma: no cover - Python < 3.9
    ZoneInfo = None  # type: ignore[assignment]
    ZoneInfoNotFoundError = Exception  # type: ignore[assignment,misc]


GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
TIMEOUT_SECONDS = 25
EXTENSION_NAME = "ii.reminders"
DEFAULT_CATEGORY = "default"
PALETTE = ["#e8574f", "#f08a3c", "#f2b33d", "#7cb342", "#3cae7a", "#2fa9a5",
           "#3d9be9", "#5c6bc0", "#8e63ce", "#c45bb4", "#8d6e63", "#78909c"]
GRAPH_DAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
MAX_PAGES = 50
COMPLETED_HORIZON_DAYS = 30


class SyncError(RuntimeError):
    """An error safe to show in the Reminders menu."""


# ── Graph ────────────────────────────────────────────────────────────────────


class Graph:
    """A small Graph client: JSON in and out, paging, and polite retries."""

    def __init__(self, access_token: str, opener: Callable[..., Any] = urlopen):
        self.token = access_token
        self.opener = opener

    def request(self, method: str, path: str, body: Any = None) -> Any:
        url = path if path.startswith("https://") else GRAPH_ROOT + path
        data = None if body is None else json.dumps(body).encode("utf-8")
        headers = {
            "Authorization": "Bearer " + self.token,
            "Prefer": 'outlook.timezone="UTC"',
        }
        if data is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(4):
            request = Request(url, data=data, headers=headers, method=method)
            try:
                with self.opener(request, timeout=TIMEOUT_SECONDS) as response:
                    raw = response.read().decode("utf-8")
                    return json.loads(raw) if raw.strip() else {}
            except HTTPError as error:
                if error.code in (429, 503, 504) and attempt < 3:
                    retry = error.headers.get("Retry-After") if error.headers else None
                    time.sleep(min(10.0, float(retry) if retry and retry.isdigit() else 1.5 * (attempt + 1)))
                    continue
                if error.code == 404 and method == "DELETE":
                    return {}
                try:
                    payload = json.loads(error.read().decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    payload = {}
                message = str(payload.get("error", {}).get("message") or f"Microsoft Graph returned HTTP {error.code}.")
                if error.code in (401, 403):
                    raise SyncError("Microsoft To Do refused access. Sign in again to grant Tasks permission.") from error
                if error.code == 404:
                    raise NotFound(message) from error
                raise SyncError(message) from error
            except (URLError, OSError) as error:
                raise SyncError(f"Microsoft To Do is unavailable: {error}.") from error
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise SyncError(f"Microsoft To Do returned invalid JSON: {error}.") from error
        raise SyncError("Microsoft To Do kept asking to slow down.")

    def get_all(self, path: str) -> list[dict[str, Any]]:
        items: list[dict[str, Any]] = []
        url: str | None = path
        for _ in range(MAX_PAGES):
            if not url:
                break
            page = self.request("GET", url)
            items.extend(item for item in page.get("value", []) if isinstance(item, dict))
            url = page.get("@odata.nextLink")
        return items


class NotFound(SyncError):
    pass


# ── Time ─────────────────────────────────────────────────────────────────────


def local_zone() -> Any:
    """The machine's zone: $TZ, else /etc/localtime's target, else the fixed offset."""
    name = os.environ.get("TZ", "").lstrip(":")
    if not name:
        try:
            target = os.readlink("/etc/localtime")
            if "zoneinfo/" in target:
                name = target.split("zoneinfo/", 1)[1]
        except OSError:
            name = ""
    if name and ZoneInfo is not None:
        try:
            return ZoneInfo(name)
        except (ZoneInfoNotFoundError, ValueError):
            pass
    return datetime.now().astimezone().tzinfo


def parse_graph_time(value: Any) -> datetime | None:
    """A Graph dateTimeTimeZone (always requested in UTC) → aware datetime."""
    if not isinstance(value, dict) or not value.get("dateTime"):
        return None
    text = str(value["dateTime"])
    text = re.sub(r"(\.\d{6})\d+", r"\1", text).rstrip("Z")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    zone_name = str(value.get("timeZone") or "UTC")
    zone: Any = timezone.utc
    if zone_name not in ("UTC", "Etc/UTC") and ZoneInfo is not None:
        try:
            zone = ZoneInfo(zone_name)
        except (ZoneInfoNotFoundError, ValueError):
            zone = timezone.utc
    return parsed.replace(tzinfo=zone)


def graph_time(moment: datetime) -> dict[str, str]:
    utc = moment.astimezone(timezone.utc)
    return {"dateTime": utc.strftime("%Y-%m-%dT%H:%M:%S.0000000"), "timeZone": "UTC"}


def parse_iso_ms(text: Any) -> int:
    if not text:
        return 0
    value = str(text)
    value = re.sub(r"(\.\d{6})\d+", r"\1", value)
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return 0
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp() * 1000)


def local_moment(day: str, hhmm: str, zone: Any) -> datetime:
    parts = [int(part) for part in day.split("-")]
    hour, minute = (int(part) for part in hhmm.split(":")) if hhmm else (0, 0)
    return datetime(parts[0], parts[1], parts[2], hour, minute, tzinfo=zone)


# ── Mapping ──────────────────────────────────────────────────────────────────


def repeat_to_recurrence(repeat: dict[str, Any] | None, start_day: str) -> dict[str, Any] | None:
    """The closest Graph patternedRecurrence; None when Graph can't say it (minutes, hours)."""
    if not repeat:
        return None
    unit = repeat.get("unit")
    interval = max(1, int(repeat.get("interval") or 1))
    start = date.fromisoformat(start_day)
    pattern: dict[str, Any]
    if unit == "day":
        pattern = {"type": "daily", "interval": interval}
    elif unit == "week":
        weekdays = repeat.get("weekdays") or []
        days = [GRAPH_DAYS[index] for index in range(7) if index < len(weekdays) and weekdays[index]]
        if not days:
            days = [GRAPH_DAYS[(start.weekday() + 1) % 7]]
        pattern = {"type": "weekly", "interval": interval, "daysOfWeek": days, "firstDayOfWeek": "monday"}
    elif unit == "month":
        month_days = repeat.get("monthDays") or [start.day]
        pattern = {"type": "absoluteMonthly", "interval": interval, "dayOfMonth": int(month_days[0])}
    elif unit == "year":
        year_dates = repeat.get("yearDates") or [start.strftime("%m-%d")]
        month, day = (int(part) for part in str(year_dates[0]).split("-"))
        pattern = {"type": "absoluteYearly", "interval": interval, "month": month, "dayOfMonth": day}
    else:
        return None
    end = repeat.get("end") or {}
    kind = end.get("kind")
    if kind == "count":
        recurrence_range = {"type": "numbered", "startDate": start_day, "numberOfOccurrences": int(end.get("count") or 1)}
    elif kind == "until" and end.get("until"):
        recurrence_range = {"type": "endDate", "startDate": start_day, "endDate": str(end["until"])}
    else:
        recurrence_range = {"type": "noEnd", "startDate": start_day}
    return {"pattern": pattern, "range": recurrence_range}


def recurrence_to_repeat(recurrence: Any, anchor: str) -> dict[str, Any] | None:
    if not isinstance(recurrence, dict):
        return None
    pattern = recurrence.get("pattern") or {}
    kind = pattern.get("type")
    interval = max(1, int(pattern.get("interval") or 1))
    repeat: dict[str, Any] = {"interval": interval, "weekdays": [False] * 7, "monthDays": [], "yearDates": [], "anchor": anchor}
    if kind == "daily":
        repeat["unit"] = "day"
    elif kind == "weekly":
        repeat["unit"] = "week"
        for name in pattern.get("daysOfWeek") or []:
            if str(name).lower() in GRAPH_DAYS:
                repeat["weekdays"][GRAPH_DAYS.index(str(name).lower())] = True
    elif kind in ("absoluteMonthly", "relativeMonthly"):
        repeat["unit"] = "month"
        if pattern.get("dayOfMonth"):
            repeat["monthDays"] = [int(pattern["dayOfMonth"])]
    elif kind in ("absoluteYearly", "relativeYearly"):
        repeat["unit"] = "year"
        if pattern.get("month") and pattern.get("dayOfMonth"):
            repeat["yearDates"] = [f"{int(pattern['month']):02d}-{int(pattern['dayOfMonth']):02d}"]
    else:
        return None
    recurrence_range = recurrence.get("range") or {}
    range_type = recurrence_range.get("type")
    if range_type == "numbered":
        repeat["end"] = {"kind": "count", "count": int(recurrence_range.get("numberOfOccurrences") or 1), "until": ""}
    elif range_type == "endDate" and recurrence_range.get("endDate"):
        repeat["end"] = {"kind": "until", "count": 1, "until": str(recurrence_range["endDate"])}
    else:
        repeat["end"] = {"kind": "never", "count": 1, "until": ""}
    return repeat


def same_base_rule(ours: dict[str, Any] | None, theirs: dict[str, Any] | None) -> bool:
    """Does Graph's rule still describe ours? Then keep ours — it may say more."""
    if not ours or not theirs:
        return ours is None and theirs is None
    if ours.get("unit") != theirs.get("unit") or int(ours.get("interval") or 1) != int(theirs.get("interval") or 1):
        return False
    if ours.get("unit") == "week":
        return list(ours.get("weekdays") or []) == list(theirs.get("weekdays") or [])
    if ours.get("unit") == "month":
        return (ours.get("monthDays") or [None])[0] == (theirs.get("monthDays") or [None])[0]
    if ours.get("unit") == "year":
        return (ours.get("yearDates") or [None])[0] == (theirs.get("yearDates") or [None])[0]
    return True


def strip_html(text: str) -> str:
    text = re.sub(r"(?i)<br\s*/?>|</p>|</div>", "\n", text)
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text).strip()


def task_body(reminder: dict[str, Any], zone: Any, all_day_time: str) -> dict[str, Any]:
    """The Graph fields a reminder sets. Checklist and extension go separately."""
    completed = bool(reminder.get("completed"))
    body: dict[str, Any] = {
        "title": reminder.get("title") or "",
        "body": {"content": reminder.get("notes") or "", "contentType": "text"},
        "importance": "high" if reminder.get("important") else "normal",
        "status": "completed" if completed else "notStarted",
        "linkedResources": None,
    }
    if completed and reminder.get("completedAt"):
        body["completedDateTime"] = graph_time(datetime.fromtimestamp(reminder["completedAt"] / 1000, tz=timezone.utc))
    schedule = reminder.get("schedule")
    if schedule and schedule.get("date"):
        day = str(schedule["date"])
        body["dueDateTime"] = graph_time(local_moment(day, "", zone))
        body["isReminderOn"] = not completed
        body["reminderDateTime"] = graph_time(local_moment(day, schedule.get("time") or all_day_time, zone))
        recurrence = repeat_to_recurrence(schedule.get("repeat"), day)
        body["recurrence"] = recurrence
    else:
        body["dueDateTime"] = None
        body["reminderDateTime"] = None
        body["isReminderOn"] = False
        body["recurrence"] = None
    # linkedResources can't be PATCHed in place; links are created on their own endpoint.
    del body["linkedResources"]
    return body


def extension_of(task: dict[str, Any]) -> dict[str, Any]:
    for extension in task.get("extensions") or []:
        if str(extension.get("extensionName") or extension.get("id") or "").endswith(EXTENSION_NAME):
            return extension
    return {}


def extension_body(reminder: dict[str, Any]) -> dict[str, Any]:
    schedule = reminder.get("schedule") or {}
    return {
        "alert": reminder.get("alert") or "default",
        "early": json.dumps(reminder.get("early")) if reminder.get("early") else "",
        "repeat": json.dumps(schedule.get("repeat")) if schedule.get("repeat") else "",
        "time": schedule.get("time") or "",
    }


def reminder_from_task(task: dict[str, Any], base: dict[str, Any] | None, category_id: str, zone: Any,
                       now_ms: int, all_day_time: str = "09:00") -> dict[str, Any]:
    """A reminder as To Do describes it, keeping what To Do can't know from `base`."""
    reminder = json.loads(json.dumps(base)) if base else {
        "id": "td-" + re.sub(r"[^A-Za-z0-9]", "", str(task.get("id")))[-24:],
        "createdAt": parse_iso_ms(task.get("createdDateTime")) or now_ms,
        "attachments": [],
        "firedFor": "", "earlyFiredFor": "", "snoozedUntil": 0, "deletedAt": 0,
    }
    reminder["title"] = str(task.get("title") or "")
    body = task.get("body") or {}
    content = str(body.get("content") or "")
    reminder["notes"] = strip_html(content) if str(body.get("contentType")).lower() == "html" else content.strip()
    reminder["important"] = str(task.get("importance")) == "high"
    reminder["completed"] = str(task.get("status")) == "completed"
    completed_at = parse_graph_time(task.get("completedDateTime"))
    reminder["completedAt"] = int(completed_at.timestamp() * 1000) if (reminder["completed"] and completed_at) else (
        (reminder.get("completedAt") or now_ms) if reminder["completed"] else 0)
    reminder["categoryId"] = category_id

    extension = extension_of(task)
    due = parse_graph_time(task.get("dueDateTime"))
    alert_at = parse_graph_time(task.get("reminderDateTime")) if task.get("isReminderOn") or reminder["completed"] else None
    previous = (base or {}).get("schedule") or {}
    if due or alert_at:
        moment = (alert_at or due).astimezone(zone)
        day = (due.astimezone(zone) if due else moment).date().isoformat()
        # All day here travels as an alert at the all-day time; it stays all day for as
        # long as nobody moves that alert (the extension remembers it was all day).
        time_text = moment.strftime("%H:%M") if alert_at else ""
        if (alert_at and str(extension.get("time", "x")) == "" and moment.date().isoformat() == day
                and time_text == all_day_time):
            time_text = ""
        theirs = recurrence_to_repeat(task.get("recurrence"), day)
        ours = None
        if extension.get("repeat"):
            try:
                ours = json.loads(extension["repeat"])
            except (TypeError, json.JSONDecodeError):
                ours = None
        elif previous.get("repeat"):
            ours = previous.get("repeat")
        repeat = ours if (ours and (theirs is None and ours.get("unit") in ("minute", "hour") or same_base_rule(ours, theirs))) else theirs
        same_rule = json.dumps(previous.get("repeat"), sort_keys=True) == json.dumps(repeat, sort_keys=True)
        reminder["schedule"] = {
            "date": day,
            "time": time_text,
            "repeat": repeat,
            "occurrence": int(previous.get("occurrence") or 0) if same_rule else 0,
        }
    else:
        reminder["schedule"] = None

    if extension:
        alert = str(extension.get("alert") or "default")
        reminder["alert"] = alert if alert in ("default", "light", "medium", "strong") else "default"
        try:
            reminder["early"] = json.loads(extension["early"]) if extension.get("early") else None
        except (TypeError, json.JSONDecodeError):
            reminder["early"] = None
    else:
        reminder.setdefault("alert", "default")
        reminder.setdefault("early", None)

    reminder["checklist"] = [
        {"id": str(item.get("id")), "text": str(item.get("displayName") or ""), "done": bool(item.get("isChecked"))}
        for item in task.get("checklistItems") or []
    ]
    # Links come from To Do; images and files stay on this machine only.
    local_files = [item for item in reminder.get("attachments") or [] if item.get("kind") != "link"]
    links = [
        {"id": "l-" + str(item.get("id"))[-12:], "kind": "link", "url": str(item.get("webUrl") or ""),
         "path": "", "name": str(item.get("displayName") or "")}
        for item in task.get("linkedResources") or [] if item.get("webUrl")
    ]
    reminder["attachments"] = local_files + links
    return reminder


# ── Sync ─────────────────────────────────────────────────────────────────────


class Syncer:
    def __init__(self, graph: Graph, store: dict[str, Any], now_ms: int, all_day_time: str = "09:00", zone: Any = None):
        self.graph = graph
        self.store = store
        self.now = now_ms
        self.all_day_time = all_day_time if re.match(r"^\d{2}:\d{2}$", all_day_time or "") else "09:00"
        self.zone = zone or local_zone()
        self.stats = {"pushed": 0, "pulled": 0, "deleted": 0, "created": 0}
        self.categories: list[dict[str, Any]] = [dict(category) for category in store.get("categories") or []]
        self.reminders: list[dict[str, Any]] = [json.loads(json.dumps(item)) for item in store.get("reminders") or []]
        self.tombstones: list[dict[str, Any]] = list(store.get("tombstones") or [])

    # Categories ↔ lists ------------------------------------------------------
    def list_id_of(self, category_id: str) -> str:
        for category in self.categories:
            if category.get("id") == category_id:
                return str(((category.get("remote") or {}).get("todo") or {}).get("listId") or "")
        return ""

    def link_category(self, category: dict[str, Any], remote_list: dict[str, Any]) -> None:
        category["remote"] = {"todo": {"listId": remote_list["id"], "name": remote_list.get("displayName") or ""}}

    def sync_lists(self) -> dict[str, dict[str, Any]]:
        for grave in [item for item in self.tombstones if item.get("kind") == "list"]:
            self.graph.request("DELETE", f"/me/todo/lists/{quote(grave['listId'])}")
            self.tombstones.remove(grave)
            self.stats["deleted"] += 1

        remote_lists = {item["id"]: item for item in self.graph.get_all("/me/todo/lists") if item.get("id")}
        linked = {self.list_id_of(category["id"]) for category in self.categories} - {""}

        # A linked list that is gone remotely takes its category (and reminders) with it.
        for category in list(self.categories):
            list_id = self.list_id_of(category["id"])
            if list_id and list_id not in remote_lists:
                if category["id"] == DEFAULT_CATEGORY:
                    category["remote"] = None
                    continue
                self.categories.remove(category)
                for reminder in self.reminders:
                    if reminder.get("categoryId") == category["id"] and not reminder.get("deletedAt"):
                        reminder["deletedAt"] = self.now
                        reminder["remote"] = None
                        reminder["categoryId"] = DEFAULT_CATEGORY

        # Remote lists nobody has yet: the default list is "My reminders"; others match
        # a category by name or become one.
        for list_id, remote_list in remote_lists.items():
            if list_id in linked:
                continue
            name = str(remote_list.get("displayName") or "")
            target = None
            if remote_list.get("wellknownListName") == "defaultList":
                target = next((c for c in self.categories if c["id"] == DEFAULT_CATEGORY and not self.list_id_of(c["id"])), None)
            if target is None:
                target = next((c for c in self.categories
                               if not self.list_id_of(c["id"]) and str(c.get("name") or "").strip().lower() == name.strip().lower()), None)
            if target is None:
                if remote_list.get("wellknownListName") == "flaggedEmails":
                    continue
                order = max([int(c.get("order") or 0) for c in self.categories] + [0]) + 1
                target = {"id": "c-td-" + re.sub(r"[^A-Za-z0-9]", "", list_id)[-16:], "name": name,
                          "color": PALETTE[len(self.categories) % len(PALETTE)], "icon": "list", "pinned": False, "order": order}
                self.categories.append(target)
                self.stats["created"] += 1
            self.link_category(target, remote_list)

        # Local categories To Do doesn't have yet; renames either way.
        for category in self.categories:
            list_id = self.list_id_of(category["id"])
            if not list_id:
                created = self.graph.request("POST", "/me/todo/lists", {"displayName": category.get("name") or "Reminders"})
                remote_lists[created["id"]] = created
                self.link_category(category, created)
                self.stats["pushed"] += 1
                continue
            remote_list = remote_lists[list_id]
            remote_name = str(remote_list.get("displayName") or "")
            last_name = str(category["remote"]["todo"].get("name") or "")
            local_name = str(category.get("name") or "")
            if category["id"] == DEFAULT_CATEGORY and remote_list.get("wellknownListName") == "defaultList":
                category["remote"]["todo"]["name"] = remote_name
                continue
            if remote_name != last_name:
                category["name"] = remote_name
            elif local_name and local_name != remote_name:
                self.graph.request("PATCH", f"/me/todo/lists/{quote(list_id)}", {"displayName": local_name})
                remote_name = local_name
                self.stats["pushed"] += 1
            category["remote"]["todo"]["name"] = remote_name
        return remote_lists

    # Tasks ↔ reminders -------------------------------------------------------
    def fetch_tasks(self, list_id: str) -> list[dict[str, Any]]:
        expand = quote(f"checklistItems,linkedResources,extensions($filter=id eq '{EXTENSION_NAME}')", safe=",()$='")
        return self.graph.get_all(f"/me/todo/lists/{quote(list_id)}/tasks?$top=100&$expand={expand}")

    def category_for_list(self, list_id: str) -> str:
        for category in self.categories:
            if self.list_id_of(category["id"]) == list_id:
                return category["id"]
        return DEFAULT_CATEGORY

    def push(self, reminder: dict[str, Any], existing: dict[str, Any] | None) -> None:
        list_id = self.list_id_of(reminder.get("categoryId") or DEFAULT_CATEGORY) or self.list_id_of(DEFAULT_CATEGORY)
        if not list_id:
            return
        todo = ((reminder.get("remote") or {}).get("todo") or {})
        body = task_body(reminder, self.zone, self.all_day_time)
        moved = bool(todo.get("taskId")) and todo.get("listId") != list_id
        if todo.get("taskId") and not moved:
            task = self.graph.request("PATCH", f"/me/todo/lists/{quote(list_id)}/tasks/{quote(todo['taskId'])}", body)
            task_id = todo["taskId"]
        else:
            # New, or moved to another list: To Do can't move a task, so it is recreated.
            if moved:
                self.graph.request("DELETE", f"/me/todo/lists/{quote(todo['listId'])}/tasks/{quote(todo['taskId'])}")
                existing = None
            body = {key: value for key, value in body.items() if value is not None}
            task = self.graph.request("POST", f"/me/todo/lists/{quote(list_id)}/tasks", body)
            task_id = task["id"]
            existing = None
        base = f"/me/todo/lists/{quote(list_id)}/tasks/{quote(task_id)}"
        self.push_checklist(reminder, base, (existing or {}).get("checklistItems") or [])
        self.push_links(reminder, base, (existing or {}).get("linkedResources") or [])
        extension = extension_body(reminder)
        if extension_of(existing or {}):
            self.graph.request("PATCH", f"{base}/extensions/{EXTENSION_NAME}", extension)
        else:
            self.graph.request("POST", f"{base}/extensions", dict(extension, **{
                "@odata.type": "microsoft.graph.openTypeExtension", "extensionName": EXTENSION_NAME}))
        # Writing checklist items or the extension moves the task's modified time on;
        # read it back so the next sync doesn't take our own write for a phone edit.
        settled = self.graph.request("GET", base) or task
        last_modified = parse_iso_ms(settled.get("lastModifiedDateTime") or task.get("lastModifiedDateTime")) or self.now
        reminder["remote"] = {"todo": {"listId": list_id, "taskId": task_id, "lastModified": last_modified,
                                       "syncedAt": max(self.now, int(reminder.get("modifiedAt") or 0))}}
        self.stats["pushed"] += 1

    def push_checklist(self, reminder: dict[str, Any], base: str, remote_items: list[dict[str, Any]]) -> None:
        remote_by_id = {str(item.get("id")): item for item in remote_items}
        kept = set()
        for item in reminder.get("checklist") or []:
            payload = {"displayName": item.get("text") or "", "isChecked": bool(item.get("done"))}
            remote = remote_by_id.get(str(item.get("id")))
            if remote:
                kept.add(str(item["id"]))
                if remote.get("displayName") != payload["displayName"] or bool(remote.get("isChecked")) != payload["isChecked"]:
                    self.graph.request("PATCH", f"{base}/checklistItems/{quote(str(item['id']))}", payload)
            else:
                created = self.graph.request("POST", f"{base}/checklistItems", payload)
                item["id"] = str(created.get("id") or item.get("id"))
                kept.add(item["id"])
        for remote_id in remote_by_id:
            if remote_id not in kept:
                self.graph.request("DELETE", f"{base}/checklistItems/{quote(remote_id)}")

    def push_links(self, reminder: dict[str, Any], base: str, remote_links: list[dict[str, Any]]) -> None:
        wanted = [item for item in reminder.get("attachments") or [] if item.get("kind") == "link" and item.get("url")]
        remote_urls = {str(item.get("webUrl")): item for item in remote_links}
        wanted_urls = {str(item["url"]) for item in wanted}
        for item in wanted:
            if item["url"] not in remote_urls:
                self.graph.request("POST", f"{base}/linkedResources", {
                    "webUrl": item["url"], "applicationName": "Reminders", "displayName": item.get("name") or item["url"]})
        for url, remote in remote_urls.items():
            if url not in wanted_urls and remote.get("id"):
                self.graph.request("DELETE", f"{base}/linkedResources/{quote(str(remote['id']))}")

    def sync_tasks(self, remote_lists: dict[str, dict[str, Any]]) -> None:
        for grave in [item for item in self.tombstones if item.get("kind") == "task"]:
            if grave.get("listId") and grave.get("taskId"):
                self.graph.request("DELETE", f"/me/todo/lists/{quote(grave['listId'])}/tasks/{quote(grave['taskId'])}")
                self.stats["deleted"] += 1
            self.tombstones.remove(grave)

        remote_tasks: dict[str, dict[str, Any]] = {}
        list_of_task: dict[str, str] = {}
        for category in self.categories:
            list_id = self.list_id_of(category["id"])
            if not list_id or list_id not in remote_lists:
                continue
            for task in self.fetch_tasks(list_id):
                if task.get("id"):
                    remote_tasks[task["id"]] = task
                    list_of_task[task["id"]] = list_id

        by_task = {}
        for reminder in self.reminders:
            task_id = ((reminder.get("remote") or {}).get("todo") or {}).get("taskId")
            if task_id:
                by_task[task_id] = reminder

        # Reminders this machine knows.
        for reminder in list(self.reminders):
            todo = (reminder.get("remote") or {}).get("todo") or {}
            task_id = todo.get("taskId")
            modified = int(reminder.get("modifiedAt") or 0)
            synced = int(todo.get("syncedAt") or 0)
            local_changed = modified > synced
            if reminder.get("deletedAt"):
                # Binned here: gone from To Do too. Restoring it later makes a new task.
                if task_id and task_id in remote_tasks:
                    self.graph.request("DELETE", f"/me/todo/lists/{quote(list_of_task[task_id])}/tasks/{quote(task_id)}")
                    self.stats["deleted"] += 1
                reminder["remote"] = None
                continue
            if not task_id:
                self.push(reminder, None)
                continue
            task = remote_tasks.get(task_id)
            if task is None:
                if local_changed:
                    reminder["remote"] = None
                    self.push(reminder, None)
                else:
                    reminder["deletedAt"] = self.now
                    reminder["remote"] = None
                    self.stats["deleted"] += 1
                continue
            remote_modified = parse_iso_ms(task.get("lastModifiedDateTime"))
            remote_changed = remote_modified > int(todo.get("lastModified") or 0)
            category_id = self.category_for_list(list_of_task[task_id])
            if remote_changed and (not local_changed or remote_modified >= modified):
                pulled = reminder_from_task(task, reminder, category_id, self.zone, self.now, self.all_day_time)
                pulled["modifiedAt"] = max(modified, remote_modified)
                pulled["remote"] = {"todo": {"listId": list_of_task[task_id], "taskId": task_id, "lastModified": remote_modified,
                                             "syncedAt": max(self.now, pulled["modifiedAt"])}}
                reminder.clear()
                reminder.update(pulled)
                self.stats["pulled"] += 1
            elif local_changed:
                self.push(reminder, task)

        # Tasks this machine has never seen.
        for task_id, task in remote_tasks.items():
            if task_id in by_task:
                continue
            # Years of finished To Do tasks are history, not reminders: only the last
            # month's completed ones come across.
            if str(task.get("status")) == "completed":
                done_at = parse_graph_time(task.get("completedDateTime"))
                if done_at and self.now - done_at.timestamp() * 1000 > COMPLETED_HORIZON_DAYS * 86400000:
                    continue
            category_id = self.category_for_list(list_of_task[task_id])
            reminder = reminder_from_task(task, None, category_id, self.zone, self.now, self.all_day_time)
            remote_modified = parse_iso_ms(task.get("lastModifiedDateTime")) or self.now
            reminder["modifiedAt"] = remote_modified
            reminder["remote"] = {"todo": {"listId": list_of_task[task_id], "taskId": task_id, "lastModified": remote_modified,
                                           "syncedAt": max(self.now, remote_modified)}}
            self.reminders.append(reminder)
            self.stats["pulled"] += 1

    def run(self) -> dict[str, Any]:
        remote_lists = self.sync_lists()
        self.sync_tasks(remote_lists)
        sync = dict(self.store.get("sync") or {})
        sync["lastSync"] = self.now
        sync["lastError"] = ""
        return {
            "ok": True,
            "store": {
                "version": 1,
                "categories": self.categories,
                "reminders": self.reminders,
                "tombstones": self.tombstones,
                "recent": self.store.get("recent") or [],
                "sync": sync,
            },
            "stats": self.stats,
        }


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
        token = str(payload.get("accessToken") or "")
        if not token:
            raise SyncError("Sign in to Microsoft first.")
        store = payload.get("store")
        if not isinstance(store, dict):
            raise SyncError("The reminders store is missing.")
        now_ms = int(payload.get("now") or time.time() * 1000)
        syncer = Syncer(Graph(token), store, now_ms, str(payload.get("allDayTime") or "09:00"))
        print(json.dumps(syncer.run()))
        return 0
    except NotFound as error:
        print(json.dumps({"ok": False, "message": str(error)}))
        return 1
    except SyncError as error:
        print(json.dumps({"ok": False, "message": str(error)}))
        return 1
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "message": f"Reminders sync failed: {error}"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
