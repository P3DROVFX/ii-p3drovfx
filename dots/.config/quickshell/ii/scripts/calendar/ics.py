#!/usr/bin/env python3
"""Safe, UID-addressed calendar mutations for the Quickshell timetable.

Requests and replies are JSON Lines.  Calendar data only ever travels in a
JSON request or an ICS payload on stdin to khal; no event field is interpolated
into a shell command.  New events go through ``khal import --batch`` so khal
picks the href and indexes them itself.  Editing an event that already exists
rewrites its own file instead: ``khal import`` names files after the UID, so on
a vdirsyncer collection (whose hrefs are random UUIDs) it would leave the
original file behind and the event would exist twice.
"""

from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from dateutil.rrule import rrulestr
from configobj import ConfigObj
from icalendar import Alarm, Calendar, Event
from khal.settings import get_config
from khal.settings.settings import find_configuration_file


COLOR_PREFIX = "ii/color="
CALENDAR_COLOR_VALUES = {
    "",
    "light blue",
    "light green",
    "light magenta",
    "light red",
    "light cyan",
    "yellow",
}
ICS_IMPORT_MAX_BYTES = 1024 * 1024
ICS_IMPORT_MAX_EVENTS = 1000


class CalendarError(RuntimeError):
    """A request error safe to return to the QML caller."""


@dataclass(frozen=True)
class CalendarInfo:
    name: str
    path: Path
    color: str
    read_only: bool


@dataclass
class StoredEvent:
    calendar: CalendarInfo
    path: Path
    container: Calendar
    component: Event


class CalendarStore:
    def __init__(self, config_path: str | None = None) -> None:
        config = get_config(config_path)
        self.config_path = config_path or find_configuration_file()
        self.default_calendar = str(config.get("default_calendar") or "")
        self.calendars: dict[str, CalendarInfo] = {}
        for name, raw in config.get("calendars", {}).items():
            path = Path(str(raw.get("path") or "")).expanduser()
            self.calendars[str(name)] = CalendarInfo(
                name=str(name),
                path=path,
                color=str(raw.get("color") or ""),
                # Google exposes virtual calendars as discoverable collections,
                # but rejects event mutations against them with HTTP 403.
                read_only=bool(raw.get("readonly", False)) or str(name).endswith("@virtual"),
            )
        if not self.calendars:
            raise CalendarError("No calendars are configured in khal.")

    def calendar_for(self, requested: object = "") -> CalendarInfo:
        name = str(requested or "")
        if name:
            calendar = self.calendars.get(name)
            if calendar is None:
                raise CalendarError(f'Calendar "{name}" is not configured in khal.')
            return calendar
        if self.default_calendar and self.default_calendar in self.calendars:
            return self.calendars[self.default_calendar]
        for calendar in self.calendars.values():
            if not calendar.read_only:
                return calendar
        raise CalendarError("All configured calendars are read-only.")

    def paths_for(self, calendar: CalendarInfo) -> list[Path]:
        if not calendar.path.exists():
            return []
        return sorted(calendar.path.rglob("*.ics"))

    def find(self, uid: str) -> StoredEvent | None:
        needle = str(uid or "")
        if not needle:
            return None
        for calendar in self.calendars.values():
            for path in self.paths_for(calendar):
                try:
                    container = Calendar.from_ical(path.read_bytes())
                except Exception:
                    continue
                for component in container.walk("VEVENT"):
                    if str(component.get("UID") or "") == needle and not component.get("RECURRENCE-ID"):
                        return StoredEvent(calendar, path, container, component)
        return None


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def _date_or_datetime(value: object, timezone_name: str = "") -> date | datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, date):
        return value
    text = str(value or "").strip()
    if not text:
        raise CalendarError("A date is required.")
    try:
        if "T" not in text and " " not in text:
            return date.fromisoformat(text[:10])
        normalized = text.replace("Z", "+00:00")
        parsed = datetime.fromisoformat(normalized)
        # The timetable writes local wall-clock ISO values.  An explicitly
        # supplied zone belongs to the value rather than being guessed here.
        return parsed
    except ValueError as error:
        raise CalendarError(f'Invalid ISO date "{text}".') from error


def _as_datetime(value: date | datetime) -> datetime:
    return value if isinstance(value, datetime) else datetime.combine(value, datetime.min.time())


def _as_iso(value: object) -> str:
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return ""


def _decoded(component: Event, key: str) -> Any:
    try:
        return component.decoded(key)
    except (KeyError, ValueError):
        return None


def _remove(component: Event, key: str) -> None:
    while key in component:
        del component[key]


def _set(component: Event, key: str, value: object) -> None:
    _remove(component, key)
    if value not in (None, ""):
        component.add(key, value)


def _categories(component: Event) -> list[str]:
    value = component.get("CATEGORIES")
    if value is None:
        return []
    raw = getattr(value, "cats", value)
    values = raw if isinstance(raw, (list, tuple, set)) else [raw]
    seen: set[str] = set()
    result: list[str] = []
    for entry in values:
        text = str(entry).strip()
        if text and text not in seen:
            seen.add(text)
            result.append(text)
    return result


def _split_categories(values: list[str]) -> tuple[list[str], str]:
    categories: list[str] = []
    color = ""
    for value in values:
        if value.startswith(COLOR_PREFIX):
            color = value[len(COLOR_PREFIX):]
        else:
            categories.append(value)
    return categories, color


def _event_categories(event: dict[str, Any], existing: Event | None) -> list[str] | None:
    has_categories = "categories" in event
    has_color = "color" in event
    if not has_categories and not has_color:
        return None
    prior, prior_color = _split_categories(_categories(existing) if existing else [])
    values = event.get("categories") if has_categories else prior
    if not isinstance(values, list):
        raise CalendarError("categories must be an array.")
    deduped: list[str] = []
    seen: set[str] = set()
    for value in values:
        text = str(value).strip()
        if text and not text.startswith(COLOR_PREFIX) and text not in seen:
            seen.add(text)
            deduped.append(text)
    color = str(event.get("color") if has_color else prior_color).strip()
    if color:
        deduped.append(COLOR_PREFIX + color)
    return deduped


def _rrule_value(recurrence: object, all_day: bool) -> dict[str, Any] | None:
    if recurrence in (None, ""):
        return None
    if not isinstance(recurrence, dict):
        raise CalendarError("recurrence must be an object or null.")
    freq = str(recurrence.get("freq") or "").upper()
    if not freq:
        return None
    if freq not in {"DAILY", "WEEKLY", "MONTHLY", "YEARLY"}:
        raise CalendarError("Unsupported recurrence frequency.")
    rule: dict[str, Any] = {"FREQ": [freq]}
    interval = recurrence.get("interval")
    if interval not in (None, "", 1, "1"):
        rule["INTERVAL"] = [int(interval)]
    by_day = recurrence.get("byDay") or []
    if by_day:
        rule["BYDAY"] = [str(value).upper() for value in by_day]
    count = recurrence.get("count")
    if count not in (None, ""):
        rule["COUNT"] = [int(count)]
    until = recurrence.get("until")
    if until not in (None, ""):
        parsed = _date_or_datetime(until)
        rule["UNTIL"] = [parsed if all_day else _as_datetime(parsed)]
    return rule


def _alarms(component: Event) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for child in component.subcomponents:
        if child.name != "VALARM":
            continue
        trigger = _decoded(child, "TRIGGER")
        if not isinstance(trigger, timedelta):
            continue
        minutes = int(abs(trigger.total_seconds()) // 60)
        result.append({"minutesBefore": minutes, "action": str(child.get("ACTION") or "DISPLAY")})
    return result


def _apply_alarms(component: Event, values: object) -> None:
    if not isinstance(values, list):
        raise CalendarError("alarms must be an array.")
    component.subcomponents = [item for item in component.subcomponents if item.name != "VALARM"]
    for item in values:
        if not isinstance(item, dict):
            raise CalendarError("Each alarm must be an object.")
        minutes = int(item.get("minutesBefore") or 0)
        if minutes < 0:
            raise CalendarError("minutesBefore cannot be negative.")
        alarm = Alarm()
        alarm.add("ACTION", str(item.get("action") or "DISPLAY").upper())
        alarm.add("TRIGGER", -timedelta(minutes=minutes))
        component.add_component(alarm)


def _exdates(component: Event) -> list[str]:
    result: list[str] = []
    value = component.get("EXDATE")
    values = value if isinstance(value, list) else ([value] if value is not None else [])
    for prop in values:
        for value in getattr(prop, "dts", []):
            decoded = getattr(value, "dt", None)
            if decoded is not None:
                result.append(_as_iso(decoded))
    return result


def _apply_exdates(component: Event, values: object) -> None:
    if not isinstance(values, list):
        raise CalendarError("exdates must be an array.")
    _remove(component, "EXDATE")
    for raw in values:
        component.add("EXDATE", _date_or_datetime(raw))


def _touch(component: Event, existing: bool) -> None:
    now = _now()
    _set(component, "DTSTAMP", now)
    _set(component, "LAST-MODIFIED", now)
    old = component.get("SEQUENCE")
    try:
        sequence = int(old) if old is not None else 0
    except (TypeError, ValueError):
        sequence = 0
    _set(component, "SEQUENCE", sequence + 1 if existing else sequence)


def _ensure_times(component: Event, event: dict[str, Any], existing: bool) -> bool:
    all_day = bool(event.get("allDay")) if "allDay" in event else isinstance(_decoded(component, "DTSTART"), date) and not isinstance(_decoded(component, "DTSTART"), datetime)
    if "start" in event:
        start = _date_or_datetime(event.get("start"))
    else:
        start = _decoded(component, "DTSTART")
    if start is None:
        raise CalendarError("Event start is required.")
    if all_day:
        start_date = start.date() if isinstance(start, datetime) else start
        if "end" in event:
            candidate = _date_or_datetime(event.get("end"))
            end_date = candidate.date() if isinstance(candidate, datetime) else candidate
        else:
            end_date = start_date + timedelta(days=1)
        if end_date <= start_date:
            end_date = start_date + timedelta(days=1)
        _set(component, "DTSTART", start_date)
        _set(component, "DTEND", end_date)
        return True
    start_dt = _as_datetime(start)
    if "end" in event:
        end_dt = _as_datetime(_date_or_datetime(event.get("end")))
    else:
        current_end = _decoded(component, "DTEND")
        if current_end is not None and existing:
            end_dt = _as_datetime(current_end)
        else:
            end_dt = start_dt + timedelta(hours=1)
    if end_dt <= start_dt:
        raise CalendarError("Event end must be after its start.")
    _set(component, "DTSTART", start_dt)
    _set(component, "DTEND", end_dt)
    return False


def _apply_event(component: Event, event: dict[str, Any], existing: bool) -> None:
    all_day = _ensure_times(component, event, existing)
    field_map = {
        "summary": "SUMMARY",
        "description": "DESCRIPTION",
        "location": "LOCATION",
        "url": "URL",
        "status": "STATUS",
    }
    for field, ical_name in field_map.items():
        if field in event:
            _set(component, ical_name, str(event.get(field) or ""))
    if "summary" not in event and not component.get("SUMMARY"):
        raise CalendarError("Event summary is required.")
    categories = _event_categories(event, component)
    if categories is not None:
        _set(component, "CATEGORIES", categories or None)
    if "recurrence" in event:
        _set(component, "RRULE", _rrule_value(event.get("recurrence"), all_day))
    if "exdates" in event:
        _apply_exdates(component, event.get("exdates"))
    if "alarms" in event:
        _apply_alarms(component, event.get("alarms"))
    _touch(component, existing)


def _event_dto(component: Event, calendar: CalendarInfo) -> dict[str, Any]:
    categories, color = _split_categories(_categories(component))
    rrule = component.get("RRULE")
    recurrence: dict[str, Any] | None = None
    if rrule:
        recurrence = {
            "freq": str((rrule.get("FREQ") or [""])[0]),
            "interval": int((rrule.get("INTERVAL") or [1])[0]),
            "byDay": [str(value) for value in (rrule.get("BYDAY") or [])],
            "until": _as_iso((rrule.get("UNTIL") or [None])[0]),
            "count": int((rrule.get("COUNT") or [0])[0]) or None,
        }
    start = _decoded(component, "DTSTART")
    end = _decoded(component, "DTEND")
    all_day = isinstance(start, date) and not isinstance(start, datetime)
    attendee_value = component.get("ATTENDEE")
    attendees = [str(value) for value in (attendee_value if isinstance(attendee_value, list) else ([attendee_value] if attendee_value is not None else []))]
    return {
        "uid": str(component.get("UID") or ""),
        "calendar": calendar.name,
        "summary": str(component.get("SUMMARY") or ""),
        "description": str(component.get("DESCRIPTION") or ""),
        "location": str(component.get("LOCATION") or ""),
        "url": str(component.get("URL") or ""),
        "allDay": all_day,
        "start": _as_iso(start),
        "end": _as_iso(end),
        "timezone": str(getattr(start, "tzinfo", "") or ""),
        "status": str(component.get("STATUS") or "CONFIRMED"),
        "categories": categories,
        "color": color,
        "recurrence": recurrence,
        "exdates": _exdates(component),
        "alarms": _alarms(component),
        "organizer": str(component.get("ORGANIZER") or ""),
        "attendees": attendees,
        "readOnly": calendar.read_only,
    }


def _import(store: CalendarStore, calendar: CalendarInfo, container: Calendar) -> None:
    # Build the argv separately so a configured path remains one argument.
    command = ["khal"]
    if store.config_path:
        command.extend(["--config", store.config_path])
    command.extend(["import", "-a", calendar.name, "--batch", "-"])
    result = subprocess.run(command, input=container.to_ical(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if result.returncode != 0:
        message = result.stderr.decode(errors="replace").strip() or result.stdout.decode(errors="replace").strip()
        raise CalendarError(message or "khal could not import the event.")


def _read_ics_import(request: dict[str, Any]) -> tuple[Calendar, str, Path | None]:
    """Read a bounded local or Gmail-provided ICS payload safely."""
    encoded = request.get("contentsBase64")
    source_path: Path | None = None
    if isinstance(encoded, str) and encoded:
        try:
            raw = base64.b64decode(encoded.encode("ascii"), altchars=b"-_", validate=True)
        except (UnicodeEncodeError, ValueError) as error:
            raise CalendarError("Calendar attachment is not valid base64 data.") from error
    else:
        source_value = request.get("path")
        source_path = Path(str(source_value or "")).expanduser() if source_value else None
        if source_path is None or not str(source_path):
            raise CalendarError("An ICS file path is required.")
        if source_path.suffix.lower() not in {".ics", ".ical"}:
            raise CalendarError("Choose an .ics or .ical calendar file.")
        if not source_path.is_file():
            raise CalendarError("ICS file was not found.")
        raw = source_path.read_bytes()
    if len(raw) > ICS_IMPORT_MAX_BYTES:
        raise CalendarError("ICS file is too large to import.")
    normalized = re.sub(rb"\r(?!\n)", b"", raw.replace(b"\r\r\n", b"\r\n"))
    try:
        calendar = Calendar.from_ical(normalized)
    except Exception as error:
        raise CalendarError("ICS file could not be parsed.") from error
    return calendar, hashlib.sha256(normalized).hexdigest(), source_path


def _import_ics(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    """Import VEVENTs without changing their UIDs or duplicating replays."""
    target = store.calendar_for(request.get("calendar"))
    if target.read_only:
        raise CalendarError(f'Calendar "{target.name}" is read-only.')
    source, source_digest, source_path = _read_ics_import(request)
    events = [component for component in source.subcomponents if component.name == "VEVENT"]
    if not events:
        raise CalendarError("ICS file contains no events.")
    if len(events) > ICS_IMPORT_MAX_EVENTS:
        raise CalendarError("ICS file contains too many events.")

    # Keep calendar-level metadata and time zones, but send khal only the events
    # that do not already exist in one of the configured calendars.
    imported_calendar = copy.deepcopy(source)
    imported_calendar.subcomponents = [
        copy.deepcopy(component) for component in source.subcomponents
        if component.name != "VEVENT"
    ]
    seen_source_keys: set[str] = set()
    imported = 0
    skipped = 0
    for index, original in enumerate(events):
        component = copy.deepcopy(original)
        uid = str(component.get("UID") or "").strip()
        if not uid:
            uid = str(uuid.uuid5(uuid.NAMESPACE_URL, f"ii-timetable-ics:{source_digest}:{index}"))
            component.add("UID", uid)
        recurrence_id = _as_iso(_decoded(component, "RECURRENCE-ID"))
        source_key = uid + "|" + recurrence_id
        if source_key in seen_source_keys or store.find(uid) is not None:
            skipped += 1
            continue
        seen_source_keys.add(source_key)
        imported_calendar.add_component(component)
        imported += 1

    if imported:
        _import(store, target, imported_calendar)
    if request.get("deleteSource") and source_path is not None:
        try:
            source_path.unlink()
        except OSError:
            pass
    return {"ok": True, "imported": imported, "skipped": skipped}


def _write_in_place(stored: StoredEvent) -> None:
    """Rewrite an existing event's own file, keeping its href and reindexing.

    Two reasons this is not ``khal import``.  khal names imported files after
    the UID, so on a vdirsyncer collection the original random-UUID file would
    survive next to the new one and the event would be listed twice.  And khal
    compares a collection's ctag, which is the *directory* mtime, before it
    reindexes: replacing the file atomically bumps that mtime, while writing
    over the file in place would leave khal serving the stale row.
    """
    payload = stored.container.to_ical()
    handle = tempfile.NamedTemporaryFile("wb", dir=stored.path.parent, prefix=".ii-timetable-", suffix=".tmp", delete=False)
    try:
        with handle as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(handle.name, stored.path)
    except BaseException:
        Path(handle.name).unlink(missing_ok=True)
        raise


def _delete_storage(stored: StoredEvent) -> None:
    components = [item for item in stored.container.subcomponents if item is not stored.component]
    if not components:
        stored.path.unlink(missing_ok=True)
        return
    stored.container.subcomponents = components
    _write_in_place(stored)


def _save(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    event = request.get("event")
    if not isinstance(event, dict):
        raise CalendarError("save requires an event object.")
    uid = str(event.get("uid") or "")
    stored = store.find(uid) if uid else None
    target = store.calendar_for(request.get("calendar") or event.get("calendar") or (stored.calendar.name if stored else ""))
    if target.read_only:
        raise CalendarError(f'Calendar "{target.name}" is read-only.')
    if stored and stored.calendar.read_only:
        raise CalendarError(f'Calendar "{stored.calendar.name}" is read-only.')
    if stored:
        container = stored.container
        component = stored.component
    else:
        container = Calendar()
        container.add("VERSION", "2.0")
        container.add("PRODID", "-//ii Quickshell//Timetable//EN")
        component = Event()
        component.add("UID", uid or str(uuid.uuid4()))
        container.add_component(component)
    _apply_event(component, event, stored is not None)
    if stored and stored.calendar.name == target.name:
        _write_in_place(stored)
    else:
        _import(store, target, container)
        if stored:
            _delete_storage(stored)
    return {"ok": True, "uid": str(component.get("UID"))}


def _read(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    return {"ok": True, "event": _event_dto(stored.component, stored.calendar)}


def _delete_series(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    if stored.calendar.read_only:
        raise CalendarError(f'Calendar "{stored.calendar.name}" is read-only.')
    _delete_storage(stored)
    return {"ok": True}


def _delete_occurrence(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    if stored.calendar.read_only:
        raise CalendarError(f'Calendar "{stored.calendar.name}" is read-only.')
    recurrence_id = _date_or_datetime(request.get("recurrenceId"))
    stored.component.add("EXDATE", recurrence_id)
    _touch(stored.component, True)
    _write_in_place(stored)
    return {"ok": True}


def _override_occurrence(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    if stored.calendar.read_only:
        raise CalendarError(f'Calendar "{stored.calendar.name}" is read-only.')
    fields = request.get("fields")
    if not isinstance(fields, dict):
        raise CalendarError("overrideOccurrence requires fields.")
    recurrence_id = _date_or_datetime(request.get("recurrenceId"))
    override = copy.deepcopy(stored.component)
    _remove(override, "RRULE")
    _remove(override, "EXDATE")
    _remove(override, "RECURRENCE-ID")
    override.add("RECURRENCE-ID", recurrence_id)
    duration = _as_datetime(_decoded(stored.component, "DTEND")) - _as_datetime(_decoded(stored.component, "DTSTART"))
    fields = dict(fields)
    fields.setdefault("start", _as_iso(recurrence_id))
    fields.setdefault("end", _as_iso(_as_datetime(recurrence_id) + duration))
    _apply_event(override, fields, True)
    stored.container.add_component(override)
    _write_in_place(stored)
    return {"ok": True}


def _end_series_before(component: Event, recurrence_id: date | datetime) -> None:
    """Restrict a recurring master to the occurrences before ``recurrence_id``."""
    old_rule = copy.deepcopy(component.get("RRULE"))
    if old_rule is None:
        raise CalendarError("This and future requires a recurring event.")
    _remove(component, "RRULE")
    # UNTIL gives the correct cutoff for weekly rules with multiple BYDAY values.
    # COUNT cannot express that cutoff without expanding every prior occurrence.
    old_rule.pop("COUNT", None)
    old_rule["UNTIL"] = [recurrence_id - (timedelta(days=1) if isinstance(recurrence_id, date) and not isinstance(recurrence_id, datetime) else timedelta(seconds=1))]
    component.add("RRULE", old_rule)
    _touch(component, True)


def _truncate_series(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    """Delete an occurrence and all following occurrences without touching the past."""
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    if stored.calendar.read_only:
        raise CalendarError(f'Calendar "{stored.calendar.name}" is read-only.')
    if not stored.component.get("RRULE"):
        raise CalendarError("This and future requires a recurring event.")
    _end_series_before(stored.component, _date_or_datetime(request.get("recurrenceId")))
    _write_in_place(stored)
    return {"ok": True}


def _split_series(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    """End a master immediately before one occurrence and start a new UID."""
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    if stored.calendar.read_only:
        raise CalendarError(f'Calendar "{stored.calendar.name}" is read-only.')
    recurrence_id = _date_or_datetime(request.get("recurrenceId"))
    fields = request.get("fields")
    if not isinstance(fields, dict) or not stored.component.get("RRULE"):
        raise CalendarError("This and future requires a recurring event and fields.")
    original_rule = copy.deepcopy(stored.component.get("RRULE"))
    _end_series_before(stored.component, recurrence_id)

    followup = copy.deepcopy(stored.component)
    _set(followup, "UID", str(uuid.uuid4()))
    _remove(followup, "RECURRENCE-ID")
    _remove(followup, "RRULE")
    _remove(followup, "EXDATE")
    followup.add("RRULE", original_rule)
    duration = _as_datetime(_decoded(stored.component, "DTEND")) - _as_datetime(_decoded(stored.component, "DTSTART"))
    next_fields = dict(fields)
    next_fields.pop("uid", None)
    next_fields.setdefault("start", _as_iso(recurrence_id))
    next_fields.setdefault("end", _as_iso(_as_datetime(recurrence_id) + duration))
    _apply_event(followup, next_fields, False)
    new_container = Calendar()
    new_container.add("VERSION", "2.0")
    new_container.add("PRODID", "-//ii Quickshell//Timetable//EN")
    new_container.add_component(followup)
    _write_in_place(stored)
    _import(store, stored.calendar, new_container)
    return {"ok": True, "uid": str(followup.get("UID"))}


def _expand(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    stored = store.find(str(request.get("uid") or ""))
    if stored is None:
        raise CalendarError("Event UID was not found.")
    start_bound = _as_datetime(_date_or_datetime(request.get("from")))
    end_bound = _as_datetime(_date_or_datetime(request.get("to")))
    component = stored.component
    start = _decoded(component, "DTSTART")
    end = _decoded(component, "DTEND")
    if start is None or end is None:
        raise CalendarError("Event is missing DTSTART or DTEND.")
    duration = _as_datetime(end) - _as_datetime(start)
    rrule = component.get("RRULE")
    if rrule:
        rule = rrulestr(rrule.to_ical().decode(), dtstart=_as_datetime(start))
        dates = rule.between(start_bound, end_bound, inc=True)
    else:
        dates = [_as_datetime(start)] if start_bound <= _as_datetime(start) <= end_bound else []
    excluded = set(_exdates(component))
    occurrences = []
    for occurrence in dates:
        if _as_iso(occurrence) in excluded:
            continue
        occurrences.append({
            "uid": str(component.get("UID") or ""),
            "recurrenceId": _as_iso(occurrence),
            "start": _as_iso(occurrence),
            "end": _as_iso(occurrence + duration),
        })
    return {"ok": True, "occurrences": occurrences}


def _calendar_list(store: CalendarStore, _: dict[str, Any]) -> dict[str, Any]:
    configured_default = store.calendars.get(store.default_calendar)
    default_calendar = ""
    if configured_default is not None and not configured_default.read_only:
        default_calendar = configured_default.name
    if not default_calendar:
        default_calendar = next((calendar.name for calendar in store.calendars.values() if not calendar.read_only), "")
    return {"ok": True, "defaultCalendar": default_calendar, "calendars": [
        {"name": calendar.name, "color": calendar.color, "readOnly": calendar.read_only}
        for calendar in store.calendars.values()
    ]}


def _set_calendar_color(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    """Persist a curated khal ANSI color without rewriting user config sections."""
    calendar = store.calendar_for(request.get("calendar"))
    if calendar.read_only:
        raise CalendarError(f'Calendar "{calendar.name}" is read-only.')
    color = str(request.get("color") or "").strip().lower()
    if color not in CALENDAR_COLOR_VALUES:
        raise CalendarError("Calendar color must be one of the timetable palette values.")
    if not store.config_path:
        raise CalendarError("khal configuration file could not be located.")
    config = ConfigObj(store.config_path, encoding="utf-8")
    calendars = config.get("calendars")
    if not isinstance(calendars, dict) or calendar.name not in calendars:
        raise CalendarError(f'Calendar "{calendar.name}" is not writable in khal config.')
    calendars[calendar.name]["color"] = color
    config.write()
    return {"ok": True, "calendar": calendar.name, "color": color}


def handle(store: CalendarStore, request: dict[str, Any]) -> dict[str, Any]:
    operations = {
        "read": _read,
        "save": _save,
        "deleteSeries": _delete_series,
        "deleteOccurrence": _delete_occurrence,
        "overrideOccurrence": _override_occurrence,
        "truncateSeries": _truncate_series,
        "splitSeries": _split_series,
        "expand": _expand,
        "calendars": _calendar_list,
        "setCalendarColor": _set_calendar_color,
        "importIcs": _import_ics,
    }
    operation = str(request.get("op") or "")
    handler = operations.get(operation)
    if handler is None:
        raise CalendarError(f'Unknown operation "{operation}".')
    return handler(store, request)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=None, help="khal config file (used by isolated tests)")
    args = parser.parse_args()
    try:
        store = CalendarStore(args.config)
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}), flush=True)
        return 0
    for line in sys.stdin:
        try:
            request = json.loads(line)
            if not isinstance(request, dict):
                raise CalendarError("A request must be a JSON object.")
            reply = handle(store, request)
        except (CalendarError, ValueError, TypeError) as error:
            reply = {"ok": False, "error": str(error)}
        except Exception as error:  # Never crash the QML bridge on malformed ICS.
            reply = {"ok": False, "error": f"Calendar helper failed: {error}"}
        print(json.dumps(reply), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
