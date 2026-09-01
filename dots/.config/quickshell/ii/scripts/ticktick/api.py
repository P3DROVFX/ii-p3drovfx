#!/usr/bin/env python3
"""TickTick's Open API, called without a shell.

The service used to build a `curl` command line as a string and hand it to
`bash -c`, with the JSON body interpolated between single quotes and the
access token sitting in the argument list. Two problems came with that: a task
title containing an apostrophe broke the command, and a title containing
`'; ...; '` ran whatever followed it — a title the user types, or that an
assistant composes out of an email. The token, meanwhile, was readable in
/proc/<pid>/cmdline by anything running as the user.

So the request is built here instead. One JSON object arrives on stdin,
carrying the token and the operation; one JSON object leaves on stdout,
carrying the HTTP status and the parsed body. Nothing is interpolated into a
string, nothing reaches a shell, and the token never appears in argv.

    echo '{"token": "...", "op": "list"}' | api.py

Operations:
    list      {projectId}                      → the project's tasks
    create    {projectId, title, content?, dueDate?, priority?}
    update    {projectId, taskId, title?, content?, dueDate?, priority?}
    complete  {projectId, taskId}
    delete    {projectId, taskId}
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request

API_BASE = "https://api.ticktick.com/open/v1"
TIMEOUT = 20
INBOX = "inbox"


def path_part(value: str) -> str:
    """One path segment, with everything escaped.

    `quote` keeps "/" by default, which lets an id of "../../something" climb
    out of the endpoint it was meant for. An id is never a path.
    """
    return urllib.parse.quote(str(value), safe="")


def request(token: str, method: str, path: str, payload: dict | None = None) -> dict:
    url = f"{API_BASE}{path}"
    body = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    call = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(call, timeout=TIMEOUT) as response:
            raw = response.read().decode("utf-8", errors="replace")
            return {
                "ok": True,
                "status": response.status,
                "data": json.loads(raw) if raw.strip() else None,
            }
    except urllib.error.HTTPError as error:
        detail = ""
        try:
            detail = error.read().decode("utf-8", errors="replace")[:400]
        except Exception:
            pass
        return {
            "ok": False,
            "status": error.code,
            # 401 is the one worth naming: the token expires and the service
            # otherwise just stops syncing without saying why.
            "error": "The TickTick token was refused. Reconnect the account."
            if error.code in (401, 403)
            else f"HTTP {error.code}",
            "detail": detail,
        }
    except urllib.error.URLError as error:
        return {"ok": False, "status": 0, "error": f"TickTick could not be reached: {error.reason}"}
    except json.JSONDecodeError:
        return {"ok": False, "status": 0, "error": "TickTick sent something that is not JSON"}
    except Exception as error:  # noqa: BLE001 - the caller wants one shape back
        return {"ok": False, "status": 0, "error": str(error)}


def run(payload: dict) -> dict:
    token = str(payload.get("token") or "")
    if not token:
        return {"ok": False, "status": 0, "error": "No access token"}
    op = str(payload.get("op") or "")
    project = str(payload.get("projectId") or INBOX)

    if op == "list":
        return request(token, "GET", f"/project/{path_part(project)}/data")

    if op == "create":
        title = str(payload.get("title") or "").strip()
        if not title:
            return {"ok": False, "status": 0, "error": "A task needs a title"}
        task = {"title": title, "projectId": project}
        # Optional fields are passed through untouched. They are JSON values in
        # a JSON body, so there is nothing to escape.
        for field in ("content", "desc", "dueDate", "startDate", "timeZone", "isAllDay", "priority"):
            if payload.get(field) not in (None, ""):
                task[field] = payload[field]
        return request(token, "POST", "/task", task)

    if op == "update":
        task_id = str(payload.get("taskId") or "")
        if not task_id:
            return {"ok": False, "status": 0, "error": "No task id"}
        task = {"projectId": project}
        for field in ("title", "content", "desc", "dueDate", "startDate", "timeZone", "isAllDay", "priority"):
            if field in payload and payload[field] not in (None, ""):
                task[field] = payload[field]
        if len(task) == 1:
            return {"ok": False, "status": 0, "error": "No task changes"}
        return request(token, "POST", f"/task/{path_part(task_id)}", task)

    if op in ("complete", "delete"):
        task_id = str(payload.get("taskId") or "")
        if not task_id:
            return {"ok": False, "status": 0, "error": "No task id"}
        quoted = f"/project/{path_part(project)}/task/{path_part(task_id)}"
        if op == "complete":
            return request(token, "POST", f"{quoted}/complete")
        return request(token, "DELETE", quoted)

    return {"ok": False, "status": 0, "error": f"Unknown operation {op}"}


def main() -> int:
    line = sys.stdin.readline()
    if not line.strip():
        print(json.dumps({"ok": False, "status": 0, "error": "No request given"}))
        return 0
    try:
        payload = json.loads(line)
    except json.JSONDecodeError as error:
        print(json.dumps({"ok": False, "status": 0, "error": f"Bad request: {error}"}))
        return 0
    result = run(payload)
    # The operation is echoed so a caller with several requests in flight can
    # tell the answers apart.
    result["op"] = payload.get("op", "")
    if payload.get("callId"):
        result["callId"] = payload["callId"]
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
