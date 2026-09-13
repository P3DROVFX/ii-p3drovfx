#!/usr/bin/env python3
"""Regression contracts for the run-lifecycle bugs reported in production.

Four symptoms turned out to share one root cause plus one unrelated UI bug:

* The sidebar composer never cleared after sending a message.
* Closing the sidebar/overview while the model was answering made it look
  dead.
* Starting a new chat left the previous chat's model "stuck": every new
  submission — even to the brand-new chat — failed with "AI is busy with
  another conversation."
* Some workflows (asking the model to search the web) stopped answering
  right after a tool call, e.g. after it read a page.

The actual bug: `Ai.makeRequest()` is called two ways. A user-submitted
message goes through the durable staging pipeline, which explicitly calls
`AiRunCoordinator.transition(runId, "thinking", ...)` before the request is
dispatched. An *internal* continuation — the follow-up after a tool result,
`regenerate()`, `editAndResend()`, `continueMessage()` — calls
`makeRequest()` with no pending submission at all, and used to skip straight
to `requester.start()`. The run it just created stayed in `AiRunCoordinator`'s
"preparing" state, and `preparing` has no legal edge to `streaming` or
`completed` in the transition graph — every later `activity()`/`finish()`
call for that run was silently rejected as an illegal transition, so the run
never reached a terminal state. `activeRunId` therefore never cleared, and
every subsequent `runCoordinator.start()` anywhere in the shell — a brand
new chat included — was refused as "busy" until the shell was restarted.

A real session captured from production shows exactly this: `run.state`
frozen at `"preparing"`, and the final message in the transcript is the
"AI is busy with another conversation" notice, right after a `fetch_url`
tool call resolved successfully.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
RUN_COORDINATOR_QML = (ROOT / "services" / "ai" / "AiRunCoordinator.qml").read_text(encoding="utf-8")
SIDEBAR_QML = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class MakeRequestFollowUpTests(unittest.TestCase):
    """`makeRequest()` without a pending submission is the tool follow-up,
    `regenerate()`, `editAndResend()` and `continueMessage()` path — every
    one of them shares this function, so the fix has to live here once."""

    def setUp(self):
        self.body = body_between(AI_QML, "function makeRequest(submission = null", "\n    function stopGeneration")

    def test_the_run_is_started_before_the_non_pending_branch(self):
        self.assertIn("root.runCoordinator.start(", self.body)

    def test_the_non_pending_branch_moves_the_run_out_of_preparing(self):
        # Split on the pending branch's own `return`, which is the last
        # statement before control falls through to the internal-follow-up
        # path. Anything after it and before `requester.start()` runs only
        # for `submission === null`.
        non_pending_tail = self.body.split('root.failPendingSubmission("save-failed"', 1)[1]
        non_pending_tail = non_pending_tail.split("requester.start();", 1)[0]
        self.assertIn("root.runCoordinator.transition(runResult.runId,", non_pending_tail)
        self.assertIn('"thinking"', non_pending_tail)

    def test_every_internal_continuation_funnels_through_make_request(self):
        # regenerate(), editAndResend() and requestFollowUp() all call the
        # shared function with no argument — proving the fix above covers
        # them instead of needing one patch per caller.
        for anchor in ("function regenerate(messageId", "function editAndResend(messageId", "function requestFollowUp()"):
            fn = body_between(AI_QML, anchor, "\n    }\n")
            self.assertIn("root.makeRequest()", fn)
            self.assertNotIn("root.makeRequest(pending", fn)


class RunCoordinatorStateMachineTests(unittest.TestCase):
    """Executes the coordinator's actual transition graph (data, not a
    reimplementation) to prove `preparing` cannot reach a terminal state
    without first moving to `thinking` — the exact trap `makeRequest()`
    used to fall into for every internal continuation."""

    def _load_graph(self):
        block = body_between(RUN_COORDINATOR_QML, "readonly property var transitionGraph: ({", "\n    })")
        graph = {}
        for line in block.splitlines():
            line = line.strip().rstrip(",")
            if ":" not in line:
                continue
            key, _, rest = line.partition(":")
            key = key.strip()
            states = [s.strip().strip('"') for s in rest.strip().strip("[]").split(",") if s.strip()]
            graph[key] = states
        return graph

    def test_preparing_has_no_direct_edge_to_an_active_or_terminal_state(self):
        graph = self._load_graph()
        self.assertIn("preparing", graph)
        # This is the trap: only "thinking" (plus self, and giving-up states)
        # is reachable from "preparing". A run left there can never legally
        # receive a `streaming`/`toolRunning`/`searching` activity event or a
        # `completed` finish — exactly what an unfixed `makeRequest()` did.
        self.assertNotIn("streaming", graph["preparing"])
        self.assertNotIn("completed", graph["preparing"])
        self.assertIn("thinking", graph["preparing"])

    def test_the_recorded_production_deadlock_cannot_reproduce_once_fixed(self):
        """Same transition graph, replaying the exact sequence recorded in
        the broken session file: two internally-continued turns after a
        `web_search` + `fetch_url` chain, then a third submission attempt —
        with and without the `makeRequest()` fix applied."""
        graph = self._load_graph()
        terminal = {"completed", "failed", "cancelled", "interrupted", "needsInspection"}
        active = {"preparing", "thinking", "searching", "toolRunning", "needsAction", "streaming"}

        def run_sequence(apply_fix: bool):
            runs = {}
            active_run_id = [""]
            counter = [0]

            def start():
                current = runs.get(active_run_id[0])
                if current and current["state"] in active:
                    return {"accepted": False}
                counter[0] += 1
                run_id = f"run-{counter[0]}"
                runs[run_id] = {"state": "preparing"}
                active_run_id[0] = run_id
                return {"accepted": True, "runId": run_id}

            def transition(run_id, state):
                run = runs.get(run_id)
                if not run or run["state"] in terminal:
                    return False
                if state not in graph.get(run["state"], []):
                    return False
                run["state"] = state
                if state in terminal and active_run_id[0] == run_id:
                    active_run_id[0] = ""
                return True

            def activity(run_id, kind):
                run = runs.get(run_id)
                if not run or run["state"] in terminal:
                    return False
                next_state = "streaming" if kind == "stream" else kind
                return transition(run_id, next_state)

            # Turn 1 — the user's original submission. This goes through the
            # durable staging pipeline in the real Ai.qml, which already
            # calls transition(..., "thinking", ...) before dispatch, so it
            # is unaffected by the bug either way.
            r1 = start()
            transition(r1["runId"], "thinking")
            activity(r1["runId"], "stream")
            transition(r1["runId"], "completed")

            # Turn 2 — internal follow-up after web_search resolves.
            r2 = start()
            if apply_fix:
                transition(r2["runId"], "thinking")
            activity(r2["runId"], "stream")
            transition(r2["runId"], "completed")

            # Turn 3 — internal follow-up after fetch_url resolves. This is
            # the exact submission that came back "AI is busy" in production.
            r3 = start()
            return r3["accepted"]

        self.assertFalse(run_sequence(apply_fix=False), "the unfixed sequence must reproduce the busy-forever deadlock")
        self.assertTrue(run_sequence(apply_fix=True), "the fixed sequence must accept the third internal continuation")


class SidebarDraftSyncTests(unittest.TestCase):
    """The sidebar's `messageInputField` only ever pushed its text into
    `Ai.draft`, never the other way — so when `Ai.qml` cleared the draft
    after a submission was accepted (asynchronously, well after `send()`
    returned), the composer kept showing the text that was "sent"."""

    def test_the_composer_reacts_to_ai_draft_being_cleared(self):
        connections = body_between(SIDEBAR_QML, "target: Ai\n", "\n    }\n\n    Connections {\n        // Voice dictation")
        self.assertIn("function onDraftChanged()", connections)
        on_draft_changed = body_between(connections, "function onDraftChanged() {", "\n        }")
        self.assertIn("messageInputField.text = Ai.draft", on_draft_changed)

    def test_there_is_no_second_dead_clearing_path(self):
        # A previous `accept()` helper duplicated the Enter-key handling and
        # cleared `text` itself, but nothing ever called it — both the
        # keyboard and the send-button path called `handleInput()` directly
        # and left the stale text behind. It should not come back.
        self.assertNotIn("function accept() {", SIDEBAR_QML)


if __name__ == "__main__":
    unittest.main()
