#!/usr/bin/env python3
"""Small, stdin-json client for the Google Calendar v3 API.

The QML service owns OAuth tokens and mutation ordering.  Keeping this file
stateless makes every request inspectable and avoids interpolating calendar
values into a shell command.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request


BASE_URL = "https://www.googleapis.com/calendar/v3"


def request_json(method: str, path: str, token: str, body=None, query=None):
    if not token:
        return {"ok": False, "code": "missing_access_token", "message": "No access token provided"}

    url = BASE_URL + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            if response.status == 204 or method == "DELETE":
                return {"ok": True, "data": {"deleted": True}}
            raw = response.read().decode("utf-8")
            return {"ok": True, "data": json.loads(raw) if raw.strip() else {}}
    except urllib.error.HTTPError as error:
        message = str(error)
        reason = str(error.reason)
        try:
            payload = json.loads(error.read().decode("utf-8", errors="ignore"))
            remote = payload.get("error", {})
            if isinstance(remote, dict):
                message = remote.get("message", message)
                errors = remote.get("errors", [])
                if errors and isinstance(errors[0], dict):
                    reason = errors[0].get("reason", reason)
        except Exception:
            pass
        return {
            "ok": False,
            "code": "http_error",
            "http_status": error.code,
            "reason": reason,
            "message": message,
        }
    except urllib.error.URLError as error:
        return {"ok": False, "code": "network_error", "message": str(error.reason)}
    except Exception as error:
        return {"ok": False, "code": "unknown_error", "message": str(error)}


def quoted(value) -> str:
    return urllib.parse.quote(str(value or ""), safe="")


def calendar_list(token: str):
    items = []
    page_token = ""
    while True:
        query = {"maxResults": 250}
        if page_token:
            query["pageToken"] = page_token
        result = request_json("GET", "/users/me/calendarList", token, query=query)
        if not result.get("ok"):
            return result
        data = result.get("data", {})
        items.extend(data.get("items", []))
        page_token = data.get("nextPageToken", "")
        if not page_token:
            return {"ok": True, "data": {"items": items}}


def events(token: str, calendar_id: str, time_min: str, time_max: str):
    items = []
    page_token = ""
    while True:
        query = {
            "singleEvents": "true",
            "orderBy": "startTime",
            "timeMin": time_min,
            "timeMax": time_max,
            "maxResults": 250,
        }
        if page_token:
            query["pageToken"] = page_token
        result = request_json("GET", "/calendars/" + quoted(calendar_id) + "/events", token, query=query)
        if not result.get("ok"):
            return result
        data = result.get("data", {})
        items.extend(data.get("items", []))
        page_token = data.get("nextPageToken", "")
        if not page_token:
            return {"ok": True, "data": {"items": items}}


def colors(token: str):
    """The account's colour palette: id -> {background, foreground}."""
    return request_json("GET", "/colors", token)


def event_colors(token: str, calendar_id: str):
    """Map every event's iCalUID to its colour id.

    ``singleEvents=false`` is deliberate: khal stores the recurring master's UID,
    so keying on the master is what lets a colour be looked up from a calendar
    file.  Exceptions come back as their own items carrying ``recurringEventId``.

    The field projection keeps this cheap enough to run over a whole account:
    only the ids and the colour travel, never summaries or attendees.
    """
    items = []
    page_token = ""
    while True:
        query = {
            "singleEvents": "false",
            "showDeleted": "false",
            "maxResults": 2500,
            "fields": "items(id,iCalUID,colorId,recurringEventId),nextPageToken",
        }
        if page_token:
            query["pageToken"] = page_token
        result = request_json("GET", "/calendars/" + quoted(calendar_id) + "/events", token, query=query)
        if not result.get("ok"):
            return result
        data = result.get("data", {})
        items.extend(data.get("items", []))
        page_token = data.get("nextPageToken", "")
        if not page_token:
            return {"ok": True, "data": {"items": items}}


def create_event(token: str, calendar_id: str, body):
    return request_json("POST", "/calendars/" + quoted(calendar_id or "primary") + "/events", token, body=body)


def update_event(token: str, calendar_id: str, event_id: str, body):
    return request_json("PATCH", "/calendars/" + quoted(calendar_id or "primary") + "/events/" + quoted(event_id), token, body=body)


def delete_event(token: str, calendar_id: str, event_id: str):
    return request_json("DELETE", "/calendars/" + quoted(calendar_id or "primary") + "/events/" + quoted(event_id), token)


def main() -> int:
    parser = argparse.ArgumentParser(description="Google Calendar v3 client")
    parser.add_argument("operation", choices=["calendars", "events", "colors", "eventColors", "create", "update", "delete"])
    args = parser.parse_args()
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except Exception as error:
        print(json.dumps({"ok": False, "code": "invalid_json", "message": str(error)}), flush=True)
        return 1

    token = str(payload.get("accessToken", ""))
    calendar_id = str(payload.get("calendarId", ""))
    if args.operation == "calendars":
        result = calendar_list(token)
    elif args.operation == "events":
        result = events(token, calendar_id or "primary", str(payload.get("timeMin", "")), str(payload.get("timeMax", "")))
    elif args.operation == "colors":
        result = colors(token)
    elif args.operation == "eventColors":
        result = event_colors(token, calendar_id or "primary")
    elif args.operation == "create":
        result = create_event(token, calendar_id, payload.get("body", {}))
    elif args.operation == "update":
        result = update_event(token, calendar_id, str(payload.get("eventId", "")), payload.get("body", {}))
    else:
        result = delete_event(token, calendar_id, str(payload.get("eventId", "")))
    print(json.dumps(result), flush=True)
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
