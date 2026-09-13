#!/usr/bin/env python3
"""Mirror a bounded Microsoft Outlook calendar view into a local readonly ICS collection."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import uuid
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from icalendar import Calendar, Event


GRAPH_ROOT = "https://graph.microsoft.com/v1.0"
TIMEOUT_SECONDS = 25
MAX_EVENTS = 2000
SOURCE_VALUE = "outlook"
UID_NAMESPACE = uuid.UUID("57e019a3-386f-4aa2-9e6d-e4e6395c12a8")


class OutlookSyncError(RuntimeError):
    """An error safe to show in the Timetable source rail."""


def graph_get(url: str, access_token: str) -> dict[str, Any]:
    request = Request(url, headers={
        "Authorization": "Bearer " + access_token,
        # UTC prevents a Windows-to-IANA timezone conversion in this local
        # mirror. ImmutableId makes a moved Outlook item retain its identity.
        "Prefer": 'outlook.timezone="UTC", IdType="ImmutableId"',
    })
    try:
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            parsed = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        try:
            payload = json.loads(error.read().decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            payload = {}
        message = str(payload.get("error", {}).get("message") or f"Microsoft Graph returned HTTP {error.code}.")
        raise OutlookSyncError(message) from error
    except (URLError, OSError) as error:
        raise OutlookSyncError(f"Microsoft Graph is unavailable: {error}.") from error
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise OutlookSyncError(f"Microsoft Graph returned invalid JSON: {error}.") from error
    if not isinstance(parsed, dict):
        raise OutlookSyncError("Microsoft Graph returned an invalid response.")
    return parsed


def account_identity(access_token: str) -> str:
    profile = graph_get(GRAPH_ROOT + "/me?$select=mail,userPrincipalName", access_token)
    return str(profile.get("mail") or profile.get("userPrincipalName") or "").strip().lower()


def list_events(access_token: str, start: str, end: str) -> list[dict[str, Any]]:
    query = urlencode({
        "startDateTime": start,
        "endDateTime": end,
        "$select": "id,iCalUId,subject,bodyPreview,location,start,end,isAllDay,isCancelled,webLink,organizer,categories,lastModifiedDateTime,showAs",
        "$top": "200",
    })
    next_url: str | None = GRAPH_ROOT + "/me/calendarView?" + query
    values: list[dict[str, Any]] = []
    while next_url:
        page = graph_get(next_url, access_token)
        batch = page.get("value") or []
        if not isinstance(batch, list):
            raise OutlookSyncError("Microsoft Graph returned an invalid event list.")
        values.extend(item for item in batch if isinstance(item, dict))
        if len(values) > MAX_EVENTS:
            raise OutlookSyncError("Outlook returned too many events for one Timetable sync.")
        raw_next = page.get("@odata.nextLink")
        next_url = str(raw_next) if raw_next else None
    return values


def stable_uid(account: str, event: dict[str, Any]) -> str:
    identifier = str(event.get("id") or "").strip()
    if not identifier:
        raise OutlookSyncError("Outlook returned an event without an identity.")
    return "ii-outlook-" + str(uuid.uuid5(UID_NAMESPACE, account + "|" + identifier))


def _datetime(value: Any) -> datetime:
    text = str(value or "").strip()
    if not text:
        raise OutlookSyncError("Outlook returned an event without a time.")
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as error:
        raise OutlookSyncError("Outlook returned an invalid event time.") from error
    if parsed.tzinfo is None:
        # The request explicitly asks Graph for UTC. Be defensive if a tenant
        # omits the offset anyway, rather than interpreting it as local time.
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _all_day_date(value: Any) -> date:
    text = str(value or "").strip()
    try:
        return date.fromisoformat(text[:10])
    except ValueError as error:
        raise OutlookSyncError("Outlook returned an invalid all-day date.") from error


def event_calendar(account: str, event: dict[str, Any]) -> Calendar | None:
    """Convert one Graph item to an isolated, read-only local ICS file."""
    if bool(event.get("isCancelled")):
        return None
    start = event.get("start") if isinstance(event.get("start"), dict) else {}
    end = event.get("end") if isinstance(event.get("end"), dict) else {}
    calendar = Calendar()
    calendar.add("VERSION", "2.0")
    calendar.add("PRODID", "-//ii Quickshell//Outlook Timetable Mirror//EN")
    component = Event()
    component.add("UID", stable_uid(account, event))
    component.add("SUMMARY", str(event.get("subject") or "Untitled event")[:2048])
    component.add("X-II-TIMETABLE-SOURCE", SOURCE_VALUE)
    component.add("X-II-OUTLOOK-ACCOUNT", account)
    component.add("X-II-OUTLOOK-EVENT-ID", str(event.get("id") or ""))
    component.add("X-II-OUTLOOK-ICAL-UID", str(event.get("iCalUId") or ""))
    if bool(event.get("isAllDay")):
        component.add("DTSTART", _all_day_date(start.get("dateTime")))
        component.add("DTEND", _all_day_date(end.get("dateTime")))
    else:
        component.add("DTSTART", _datetime(start.get("dateTime")))
        component.add("DTEND", _datetime(end.get("dateTime")))
    description = str(event.get("bodyPreview") or "").strip()
    if description:
        component.add("DESCRIPTION", description[:8192])
    location = event.get("location") if isinstance(event.get("location"), dict) else {}
    display_name = str(location.get("displayName") or "").strip()
    if display_name:
        component.add("LOCATION", display_name[:2048])
    link = str(event.get("webLink") or "").strip()
    if link:
        component.add("URL", link)
    organizer = event.get("organizer") if isinstance(event.get("organizer"), dict) else {}
    address = organizer.get("emailAddress") if isinstance(organizer.get("emailAddress"), dict) else {}
    organizer_email = str(address.get("address") or "").strip()
    if organizer_email:
        component.add("ORGANIZER", "mailto:" + organizer_email)
    categories = [str(item).strip() for item in (event.get("categories") or []) if str(item).strip()]
    if categories:
        component.add("CATEGORIES", categories)
    show_as = str(event.get("showAs") or "").lower()
    if show_as == "tentative":
        component.add("STATUS", "TENTATIVE")
    elif show_as == "cancelled":
        component.add("STATUS", "CANCELLED")
    else:
        component.add("STATUS", "CONFIRMED")
    calendar.add_component(component)
    return calendar


def _atomic_write(path: Path, data: bytes) -> None:
    file_descriptor, temporary_name = tempfile.mkstemp(prefix=".ii-outlook-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(file_descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise


def _is_managed_outlook_file(path: Path) -> bool:
    try:
        calendar = Calendar.from_ical(path.read_bytes())
    except Exception:
        return False
    return any(str(component.get("X-II-TIMETABLE-SOURCE") or "").lower() == SOURCE_VALUE for component in calendar.subcomponents)


def write_collection(destination: Path, account: str, events: list[dict[str, Any]]) -> dict[str, int]:
    """Atomically update only files explicitly owned by this Outlook mirror."""
    destination.mkdir(parents=True, exist_ok=True)
    expected: set[str] = set()
    written = 0
    for event in events:
        calendar = event_calendar(account, event)
        if calendar is None:
            continue
        filename = stable_uid(account, event) + ".ics"
        expected.add(filename)
        _atomic_write(destination / filename, calendar.to_ical())
        written += 1
    removed = 0
    for existing in destination.glob("*.ics"):
        if existing.name not in expected and _is_managed_outlook_file(existing):
            existing.unlink()
            removed += 1
    return {"written": written, "removed": removed}


def run(payload: dict[str, Any]) -> dict[str, Any]:
    token = str(payload.get("accessToken") or "").strip()
    destination = Path(str(payload.get("destination") or "")).expanduser()
    start = str(payload.get("start") or "").strip()
    end = str(payload.get("end") or "").strip()
    if not token:
        raise OutlookSyncError("Microsoft authorization is unavailable.")
    if not destination.name:
        raise OutlookSyncError("Outlook calendar destination is missing.")
    if not start or not end:
        raise OutlookSyncError("Outlook calendar date range is missing.")
    account = account_identity(token)
    if not account:
        raise OutlookSyncError("Microsoft account identity is unavailable.")
    events = list_events(token, start, end)
    result = write_collection(destination, account, events)
    return {"ok": True, "account": account, "events": result["written"], "removed": result["removed"]}


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read())
        if not isinstance(payload, dict):
            raise OutlookSyncError("Outlook sync request must be an object.")
        print(json.dumps(run(payload)))
        return 0
    except (OutlookSyncError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
