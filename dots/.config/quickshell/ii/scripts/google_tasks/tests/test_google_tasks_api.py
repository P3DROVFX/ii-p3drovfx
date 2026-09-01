#!/usr/bin/env python3
import unittest
from unittest.mock import patch, MagicMock
import urllib.error
import io
import json
import os
import sys

# Ensure scripts/google_tasks is on path
_tasks_dir = os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))
if _tasks_dir not in sys.path:
    sys.path.insert(0, _tasks_dir)

import api

def make_mock_response(status=200, body_dict=None, raw_bytes=None):
    mock_resp = MagicMock()
    mock_resp.status = status
    if body_dict is not None:
        mock_resp.read.return_value = json.dumps(body_dict).encode('utf-8')
    elif raw_bytes is not None:
        mock_resp.read.return_value = raw_bytes
    else:
        mock_resp.read.return_value = b""
    mock_resp.__enter__.return_value = mock_resp
    mock_resp.__exit__.return_value = None
    return mock_resp

class TestGoogleTasksApi(unittest.TestCase):

    @patch('urllib.request.urlopen')
    def test_list_tasklists_pagination(self, mock_urlopen):
        # Page 1 returns nextPageToken
        resp1 = make_mock_response(status=200, body_dict={
            "items": [{"id": "list1", "title": "My Tasks"}],
            "nextPageToken": "page2token"
        })

        # Page 2 returns no nextPageToken
        resp2 = make_mock_response(status=200, body_dict={
            "items": [{"id": "list2", "title": "Work Tasks"}]
        })

        mock_urlopen.side_effect = [resp1, resp2]

        res = api.list_tasklists("dummy_token")
        self.assertTrue(res.get("ok"))
        items = res.get("data", {}).get("items", [])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["id"], "list1")
        self.assertEqual(items[1]["id"], "list2")
        self.assertEqual(mock_urlopen.call_count, 2)

    @patch('urllib.request.urlopen')
    def test_list_tasks_query_and_pagination(self, mock_urlopen):
        resp = make_mock_response(status=200, body_dict={
            "items": [
                {"id": "task1", "title": "Task 1", "status": "needsAction"},
                {"id": "task2", "title": "Task 2", "status": "completed"}
            ]
        })
        mock_urlopen.return_value = resp

        res = api.list_tasks("dummy_token", "list@123")
        self.assertTrue(res.get("ok"))
        items = res.get("data", {}).get("items", [])
        self.assertEqual(len(items), 2)

        # Check requested URL params
        req = mock_urlopen.call_args[0][0]
        self.assertIn("list%40123/tasks", req.full_url)
        self.assertIn("showCompleted=true", req.full_url)
        self.assertIn("showHidden=true", req.full_url)
        self.assertIn("showDeleted=false", req.full_url)
        self.assertIn("showAssigned=false", req.full_url)
        self.assertIn("maxResults=100", req.full_url)
        self.assertEqual(req.headers.get("Authorization"), "Bearer dummy_token")

    @patch('urllib.request.urlopen')
    def test_create_task_with_special_characters(self, mock_urlopen):
        special_title = "Café com pão d'água \"especial\" \n $10 `test` 中文"
        resp = make_mock_response(status=200, body_dict={
            "id": "new_task_id",
            "title": special_title
        })
        mock_urlopen.return_value = resp

        res = api.create_task("dummy_token", "list1", {"title": special_title})
        self.assertTrue(res.get("ok"))
        self.assertEqual(res.get("data", {}).get("id"), "new_task_id")

        req = mock_urlopen.call_args[0][0]
        sent_body = json.loads(req.data.decode('utf-8'))
        self.assertEqual(sent_body.get("title"), special_title)

    @patch('urllib.request.urlopen')
    def test_create_task_preserves_due_timestamp(self, mock_urlopen):
        due = "2026-09-18T00:00:00.000Z"
        mock_urlopen.return_value = make_mock_response(status=200, body_dict={"id": "due-task", "due": due})

        res = api.create_task("dummy_token", "list1", {"title": "Pay rent", "due": due})
        self.assertTrue(res.get("ok"))
        req = mock_urlopen.call_args[0][0]
        self.assertEqual(json.loads(req.data.decode("utf-8"))["due"], due)

    @patch('urllib.request.urlopen')
    def test_patch_task_complete_and_uncomplete(self, mock_urlopen):
        resp1 = make_mock_response(status=200, body_dict={
            "id": "task1",
            "status": "completed"
        })
        mock_urlopen.return_value = resp1

        res_complete = api.patch_task("dummy_token", "list1", "task1", {"status": "completed"})
        self.assertTrue(res_complete.get("ok"))
        self.assertEqual(res_complete.get("data", {}).get("status"), "completed")

        resp2 = make_mock_response(status=200, body_dict={
            "id": "task1",
            "status": "needsAction"
        })
        mock_urlopen.return_value = resp2

        res_uncomplete = api.patch_task("dummy_token", "list1", "task1", {"status": "needsAction"})
        self.assertTrue(res_uncomplete.get("ok"))
        self.assertEqual(res_uncomplete.get("data", {}).get("status"), "needsAction")

    @patch('urllib.request.urlopen')
    def test_delete_task_url_escaping(self, mock_urlopen):
        resp = make_mock_response(status=204, raw_bytes=b"")
        mock_urlopen.return_value = resp

        res = api.delete_task("dummy_token", "list/with/slashes", "task#1?val")
        self.assertTrue(res.get("ok"))
        self.assertTrue(res.get("data", {}).get("deleted"))

        req = mock_urlopen.call_args[0][0]
        self.assertIn("list%2Fwith%2Fslashes/tasks/task%231%3Fval", req.full_url)
        self.assertEqual(req.get_method(), "DELETE")

    @patch('urllib.request.urlopen')
    def test_http_error_handling_api_disabled(self, mock_urlopen):
        error_json = json.dumps({
            "error": {
                "code": 403,
                "message": "Google Tasks API has not been used in project 12345 before or it is disabled.",
                "errors": [
                    {
                        "message": "Google Tasks API has not been used in project 12345 before or it is disabled.",
                        "domain": "usageLimits",
                        "reason": "accessNotConfigured"
                    }
                ]
            }
        }).encode('utf-8')

        mock_err = urllib.error.HTTPError(
            url="https://tasks.googleapis.com",
            code=403,
            msg="Forbidden",
            hdrs={},
            fp=io.BytesIO(error_json)
        )
        mock_urlopen.side_effect = mock_err

        res = api.list_tasklists("dummy_token")
        self.assertFalse(res.get("ok"))
        self.assertEqual(res.get("http_status"), 403)
        self.assertEqual(res.get("reason"), "accessNotConfigured")
        self.assertIn("Google Tasks API", res.get("message"))

    @patch('urllib.request.urlopen')
    def test_network_error_handling(self, mock_urlopen):
        mock_urlopen.side_effect = urllib.error.URLError("Connection refused")

        res = api.list_tasklists("dummy_token")
        self.assertFalse(res.get("ok"))
        self.assertEqual(res.get("code"), "network_error")
        self.assertIn("Connection refused", res.get("message"))

if __name__ == "__main__":
    unittest.main()
