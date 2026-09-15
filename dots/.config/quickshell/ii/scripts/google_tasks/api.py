#!/usr/bin/env python3
import sys
import json
import urllib.request
import urllib.parse
import urllib.error
import argparse

BASE_URL = "https://tasks.googleapis.com"

def request_json(method, path, token, body=None, query=None):
    if not token:
        return {
            "ok": False,
            "code": "missing_access_token",
            "message": "No access token provided"
        }

    url = f"{BASE_URL}{path}"
    if query:
        url += f"?{urllib.parse.urlencode(query)}"

    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json"
        }
    )

    try:
        with urllib.request.urlopen(req) as resp:
            if resp.status == 204 or method == "DELETE":
                return {"ok": True, "data": {"deleted": True}}
            res_body = resp.read().decode("utf-8")
            if not res_body.strip():
                return {"ok": True, "data": {}}
            return {"ok": True, "data": json.loads(res_body)}
    except urllib.error.HTTPError as e:
        error_body = ""
        reason = e.reason
        message = str(e)
        try:
            error_body = e.read().decode("utf-8", errors="ignore")
            parsed = json.loads(error_body)
            err_obj = parsed.get("error", {})
            if isinstance(err_obj, dict):
                message = err_obj.get("message", message)
                errors_list = err_obj.get("errors", [])
                if errors_list and isinstance(errors_list[0], dict):
                    reason = errors_list[0].get("reason", reason)
        except Exception:
            pass

        return {
            "ok": False,
            "code": "http_error",
            "http_status": e.code,
            "reason": reason,
            "message": message
        }
    except urllib.error.URLError as e:
        return {
            "ok": False,
            "code": "network_error",
            "message": str(e.reason)
        }
    except Exception as e:
        return {
            "ok": False,
            "code": "unknown_error",
            "message": str(e)
        }

def list_tasklists(token):
    items = []
    page_token = None

    while True:
        query = {"maxResults": 1000}
        if page_token:
            query["pageToken"] = page_token

        res = request_json("GET", "/tasks/v1/users/@me/lists", token, query=query)
        if not res.get("ok"):
            return res

        data = res.get("data", {})
        items.extend(data.get("items", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break

    return {"ok": True, "data": {"items": items}}

def list_tasks(token, task_list_id):
    if not task_list_id:
        return {
            "ok": False,
            "code": "missing_task_list_id",
            "message": "No taskListId provided"
        }

    items = []
    page_token = None
    quoted_list_id = urllib.parse.quote(task_list_id, safe="")

    while True:
        query = {
            "maxResults": 100,
            "showCompleted": "true",
            "showHidden": "true",
            "showDeleted": "false",
            "showAssigned": "false"
        }
        if page_token:
            query["pageToken"] = page_token

        res = request_json("GET", f"/tasks/v1/lists/{quoted_list_id}/tasks", token, query=query)
        if not res.get("ok"):
            return res

        data = res.get("data", {})
        items.extend(data.get("items", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break

    return {"ok": True, "data": {"items": items}}

def create_task(token, task_list_id, body):
    if not task_list_id:
        return {
            "ok": False,
            "code": "missing_task_list_id",
            "message": "No taskListId provided"
        }

    quoted_list_id = urllib.parse.quote(task_list_id, safe="")
    return request_json("POST", f"/tasks/v1/lists/{quoted_list_id}/tasks", token, body=body)

def patch_task(token, task_list_id, task_id, body):
    if not task_list_id or not task_id:
        return {
            "ok": False,
            "code": "missing_identifiers",
            "message": "taskListId and taskId are required"
        }

    quoted_list_id = urllib.parse.quote(task_list_id, safe="")
    quoted_task_id = urllib.parse.quote(task_id, safe="")
    return request_json("PATCH", f"/tasks/v1/lists/{quoted_list_id}/tasks/{quoted_task_id}", token, body=body)

def delete_task(token, task_list_id, task_id):
    if not task_list_id or not task_id:
        return {
            "ok": False,
            "code": "missing_identifiers",
            "message": "taskListId and taskId are required"
        }

    quoted_list_id = urllib.parse.quote(task_list_id, safe="")
    quoted_task_id = urllib.parse.quote(task_id, safe="")
    return request_json("DELETE", f"/tasks/v1/lists/{quoted_list_id}/tasks/{quoted_task_id}", token)

def main():
    parser = argparse.ArgumentParser(description="Google Tasks REST API client")
    parser.add_argument("operation", choices=["tasklists", "tasks", "create", "patch", "delete"], help="Operation to execute")
    args = parser.parse_args()

    # Read context and payload via STDIN JSON
    raw_input = sys.stdin.read().strip()
    if not raw_input:
        print(json.dumps({
            "ok": False,
            "code": "empty_input",
            "message": "No JSON payload provided via stdin"
        }), flush=True)
        sys.exit(1)

    try:
        payload = json.loads(raw_input)
    except Exception as e:
        print(json.dumps({
            "ok": False,
            "code": "invalid_json",
            "message": f"Failed to parse stdin JSON: {e}"
        }), flush=True)
        sys.exit(1)

    access_token = payload.get("accessToken", "")
    task_list_id = payload.get("taskListId", "")
    task_id = payload.get("taskId", "")
    body = payload.get("body", {})

    # If title was passed directly in payload instead of body:
    if "title" in payload and not body:
        body = {"title": payload.get("title")}

    result = None
    if args.operation == "tasklists":
        result = list_tasklists(access_token)
    elif args.operation == "tasks":
        result = list_tasks(access_token, task_list_id)
    elif args.operation == "create":
        result = create_task(access_token, task_list_id, body)
    elif args.operation == "patch":
        result = patch_task(access_token, task_list_id, task_id, body)
    elif args.operation == "delete":
        result = delete_task(access_token, task_list_id, task_id)

    print(json.dumps(result), flush=True)
    sys.exit(0 if result and result.get("ok") else 1)

if __name__ == "__main__":
    main()
