#!/usr/bin/env python3
"""Contract tests for scripts/ai/claude_status_hook.py.

These lock in the three things that were wrong when the island first reported a Claude
Code session: a turn clock that restarted whenever anything was typed, token counts that
described the last API call rather than the turn, and concurrent hooks overwriting each
other's state.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import claude_status_hook as hook  # noqa: E402


class StateMachineTests(unittest.TestCase):
    def state(self, event, previous=None, **payload):
        return hook.state_for(event, dict(payload, hook_event_name=event), previous or {})

    def test_a_prompt_starts_work(self):
        self.assertEqual(self.state("UserPromptSubmit")[0], "working")

    def test_a_tool_call_names_its_tool(self):
        self.assertEqual(self.state("PreToolUse", tool_name="Bash"), ("tool", "Bash"))

    def test_a_question_is_not_work(self):
        # It blocks on the user, and the island promotes it so the answer can be given.
        self.assertEqual(self.state("PreToolUse", tool_name="AskUserQuestion")[0], "asking")

    def test_a_permission_prompt_needs_action(self):
        self.assertEqual(self.state(
            "Notification", message="Claude needs your permission to use Bash")[0],
            "needsAction")

    def test_a_nudge_about_an_open_question_is_still_a_question(self):
        asking = {"state": "asking", "tool": "AskUserQuestion"}
        for message in ("Claude needs your permission to use AskUserQuestion",
                        "Claude is waiting for your input"):
            self.assertEqual(self.state("Notification", asking, message=message),
                             ("asking", "AskUserQuestion"))

    def test_an_idle_notice_is_not_an_approval(self):
        self.assertEqual(self.state(
            "Notification", message="Claude is waiting for your input")[0], "waitingInput")

    def test_stopping_is_done(self):
        self.assertEqual(self.state("Stop")[0], "done")

    def test_a_subagent_finishing_is_not_the_turn_finishing(self):
        # It blanked the island mid-turn, and the next tool call then restarted the clock.
        self.assertEqual(self.state("SubagentStop", {"state": "tool", "tool": "Task"}),
                         ("tool", "Task"))

    def test_a_compaction_that_was_asked_for_ends_done(self):
        previous = {"state": "compacting", "compactTrigger": "manual"}
        self.assertEqual(self.state("SessionStart", previous, source="compact")[0], "done")

    def test_a_compaction_the_cli_chose_carries_the_turn_on(self):
        previous = {"state": "compacting", "compactTrigger": "auto"}
        self.assertEqual(self.state("SessionStart", previous, source="compact")[0], "working")

    def test_an_unknown_event_keeps_the_previous_state(self):
        self.assertEqual(self.state("Whatever", {"state": "tool", "tool": "Edit"}),
                         ("tool", "Edit"))


class HookRunTests(unittest.TestCase):
    """The hook as the CLI runs it: JSON on stdin, a file on disk."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = dict(os.environ, XDG_RUNTIME_DIR=self.tmp)
        self.session = "s1"
        self.path = os.path.join(self.tmp, "quickshell", "ai-status", self.session + ".json")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def send(self, event, **payload):
        payload.update({"hook_event_name": event, "session_id": self.session})
        subprocess.run([sys.executable, os.path.join(HERE, "..", "claude_status_hook.py")],
                       input=json.dumps(payload), text=True, env=self.env, check=True)
        return self.read()

    def read(self):
        with open(self.path) as handle:
            return json.load(handle)

    def test_a_session_end_removes_the_file(self):
        self.send("UserPromptSubmit")
        self.assertTrue(os.path.exists(self.path))
        subprocess.run([sys.executable, os.path.join(HERE, "..", "claude_status_hook.py")],
                       input=json.dumps({"hook_event_name": "SessionEnd",
                                         "session_id": self.session}),
                       text=True, env=self.env, check=True)
        self.assertFalse(os.path.exists(self.path))

    def test_a_queued_message_does_not_restart_the_turn(self):
        # The CLI counts one turn from when it picked the work up, and goes on counting
        # across anything typed while it works. The island has to agree with it.
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        time.sleep(1.1)
        self.send("PreToolUse", tool_name="Bash")
        self.assertEqual(self.send("UserPromptSubmit")["turnStartedAt"], first)

    def test_a_new_turn_after_rest_restarts_the_clock(self):
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        self.send("Stop")
        time.sleep(1.1)
        self.assertGreater(self.send("UserPromptSubmit")["turnStartedAt"], first)

    def transcript(self, *records):
        path = os.path.join(self.tmp, "transcript.jsonl")
        with open(path, "a") as handle:
            for record in records:
                handle.write(json.dumps(record) + "\n")
        return path

    @staticmethod
    def stamp(epoch):
        return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(epoch)) \
            + ".%03dZ" % int(epoch % 1 * 1000)

    def interrupt(self, epoch):
        return {"type": "user", "timestamp": self.stamp(epoch), "message": {
            "role": "user", "content": [{"type": "text",
                                         "text": "[Request interrupted by user]"}]}}

    def test_a_prompt_after_escape_is_a_new_turn(self):
        # Escape fires no hook: the file still says "running a tool", and the next
        # prompt used to be taken for one typed into that turn - the island carried on
        # counting the abandoned turn, minutes ahead of the CLI.
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        self.send("PreToolUse", tool_name="Bash")
        time.sleep(1.1)
        path = self.transcript(self.interrupt(time.time()))
        time.sleep(0.2)
        record = self.send("UserPromptSubmit", transcript_path=path)
        self.assertGreater(record["turnStartedAt"], first + 1)
        self.assertEqual(record["tokensOut"], 0)

    def test_a_tool_reporting_back_after_escape_does_not_reopen_the_turn(self):
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        self.send("PreToolUse", tool_name="Bash")
        path = self.transcript(self.interrupt(time.time() + 0.5))
        time.sleep(1.1)
        self.assertEqual(self.send("PostToolUse", tool_name="Bash",
                                   transcript_path=path)["turnStartedAt"], first)

    def test_a_compaction_from_rest_runs_on_its_own_clock(self):
        # The CLI counts "Compacting conversation..." from the command; the island showed
        # the previous turn's clock still running.
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        self.send("Stop")
        time.sleep(1.1)
        record = self.send("PreCompact", trigger="manual")
        self.assertEqual(record["state"], "compacting")
        self.assertGreater(record["turnStartedAt"], first + 1)
        done = self.send("SessionStart", source="compact")
        self.assertEqual(done["state"], "done")
        self.assertGreaterEqual(done["turnEndedAt"], record["turnStartedAt"])
        self.assertEqual(done["tokensIn"], 0)

    def test_a_compaction_mid_turn_keeps_the_turns_clock(self):
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        time.sleep(1.1)
        self.assertEqual(self.send("PreCompact", trigger="auto")["turnStartedAt"], first)
        after = self.send("SessionStart", source="compact")
        self.assertEqual((after["state"], after["turnStartedAt"]), ("working", first))

    def test_work_picked_up_without_a_prompt_starts_a_turn(self):
        # A background task reporting back wakes the agent with nothing typed.
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        self.send("Stop")
        time.sleep(1.1)
        self.assertGreater(self.send("PreToolUse", tool_name="Bash")["turnStartedAt"], first + 1)

    def test_concurrent_hooks_do_not_lose_the_turn_clock(self):
        # Hooks are asynchronous and several run around one tool call. Sharing a scratch
        # file between them published half-written JSON, which the next hook read as "no
        # previous state" and the clock went back to zero.
        first = self.send("UserPromptSubmit")["turnStartedAt"]
        script = os.path.join(HERE, "..", "claude_status_hook.py")
        procs = []
        for index in range(12):
            event = "PreToolUse" if index % 2 else "PostToolUse"
            payload = json.dumps({"hook_event_name": event, "session_id": self.session,
                                  "tool_name": "Bash"})
            procs.append(subprocess.Popen([sys.executable, script], stdin=subprocess.PIPE,
                                          env=self.env, text=True))
            procs[-1].stdin.write(payload)
            procs[-1].stdin.close()
        for proc in procs:
            proc.wait()
        record = self.read()                      # must still be valid JSON...
        self.assertEqual(record["turnStartedAt"], first)   # ...with the clock intact
        self.assertEqual([name for name in os.listdir(os.path.dirname(self.path))
                          if name.endswith(".tmp")], [])


class OwningAgentTests(unittest.TestCase):
    """Whose pid goes in the file. The island prunes sessions on it."""

    def test_a_walk_that_finds_nothing_claims_nobody(self):
        # The shell that spawned the hook is dead the moment it exits, and the island
        # dropped the session's file on that pid: the turn clock went back to zero and
        # took the turn's tokens with it. Better no pid than a dead one.
        with mock.patch.object(hook, "read_comm", lambda pid: "sh"):
            self.assertEqual(hook.owning_agent(), (0, "claude"))

    def test_the_pid_written_last_is_kept_while_it_is_still_a_cli(self):
        with mock.patch.object(hook, "read_comm", lambda pid: "claude" if pid == 4242 else "sh"):
            self.assertEqual(hook.owning_agent(4242), (4242, "claude"))

    def test_a_remembered_pid_that_is_now_something_else_is_dropped(self):
        with mock.patch.object(hook, "read_comm", lambda pid: "sh"):
            self.assertEqual(hook.owning_agent(4242)[0], 0)


class TurnStartTests(unittest.TestCase):
    """Where the clock starts when the hook cannot say - it must be the CLI's own."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "transcript.jsonl")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, *records):
        with open(self.path, "w") as handle:
            for record in records:
                handle.write(json.dumps(record) + "\n")

    def test_the_clis_bookkeeping_and_an_interruption_are_not_prompts(self):
        for text, extra in (("[Request interrupted by user]", {}),
                            ("<local-command-stdout>ok</local-command-stdout>", {}),
                            ("<command-name>/model</command-name>", {}),
                            ("[Image: source: /tmp/x.png]", {"isMeta": True}),
                            ("This session is being continued", {"isCompactSummary": True})):
            record = dict({"type": "user", "message": {"role": "user", "content": text}}, **extra)
            self.assertFalse(hook._is_user_prompt(record), text)
        self.assertTrue(hook._is_user_prompt(
            {"type": "user", "message": {"role": "user", "content": "/compact"}}))

    def test_the_turn_starts_at_the_prompt_not_at_the_first_answer(self):
        # Thinking before the first tool call is part of the turn; reading the clock
        # from the first answer lost every second of it - half a minute, measured.
        self.write({"type": "user", "timestamp": "2026-09-20T21:00:00.000Z",
                    "message": {"role": "user", "content": "go"}},
                   {"type": "assistant", "timestamp": "2026-09-20T21:00:36.000Z",
                    "message": {"role": "assistant", "id": "m1", "content": [],
                                "usage": {"input_tokens": 1, "output_tokens": 2}}})
        usage = hook.read_usage(self.path)
        self.assertEqual(usage["turnStartedAtFromTranscript"],
                         hook._parse_timestamp("2026-09-20T21:00:00.000Z"))


class UsageTests(unittest.TestCase):
    """Token accounting: the context and the turn's output are different numbers."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "transcript.jsonl")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def write(self, *records):
        with open(self.path, "w") as handle:
            for record in records:
                handle.write(json.dumps(record) + "\n")

    @staticmethod
    def prompt(text="hi"):
        return {"type": "user", "message": {"role": "user", "content": text}}

    @staticmethod
    def tool_result():
        return {"type": "user", "message": {"role": "user", "content": [
            {"type": "tool_result", "tool_use_id": "t1", "content": "ok"}]}}

    @staticmethod
    def assistant(ident, out, context, block="text"):
        return {"type": "assistant", "message": {
            "role": "assistant", "id": ident, "model": "claude-opus-5",
            "content": [{"type": block, "text": "x"}],
            "usage": {"input_tokens": 2, "cache_read_input_tokens": context,
                      "output_tokens": out}}}

    def test_output_is_summed_over_the_turn(self):
        self.write(self.prompt(),
                   self.assistant("m1", 100, 400000),
                   self.tool_result(),
                   self.assistant("m2", 250, 401000))
        usage = hook.read_usage(self.path)
        self.assertEqual(usage["tokensOut"], 350)

    def test_the_context_is_the_newest_message_not_a_sum(self):
        # Every message re-reads the whole conversation, so summing the input side would
        # report several times the window's real size.
        self.write(self.prompt(),
                   self.assistant("m1", 100, 400000),
                   self.assistant("m2", 100, 401000))
        self.assertEqual(hook.read_usage(self.path)["tokensIn"], 401002)

    def test_one_message_is_counted_once_across_its_blocks(self):
        # thinking, text and tool_use blocks of one message each carry the same usage.
        self.write(self.prompt(),
                   self.assistant("m1", 500, 400000, block="thinking"),
                   self.assistant("m1", 500, 400000, block="text"),
                   self.assistant("m1", 500, 400000, block="tool_use"))
        self.assertEqual(hook.read_usage(self.path)["tokensOut"], 500)

    def test_the_previous_turn_is_not_counted(self):
        self.write(self.prompt(),
                   self.assistant("old", 9999, 100),
                   self.prompt("second question"),
                   self.assistant("new", 42, 200))
        self.assertEqual(hook.read_usage(self.path)["tokensOut"], 42)

    def test_a_tool_result_does_not_end_the_turn(self):
        # Tool results come back as user records; treating them as a new turn reported a
        # fraction of the turn's output.
        self.write(self.prompt(),
                   self.assistant("m1", 100, 100),
                   self.tool_result(),
                   self.assistant("m2", 100, 200))
        self.assertEqual(hook.read_usage(self.path)["tokensOut"], 200)

    def test_the_context_before_a_compaction_is_not_the_context(self):
        self.write(self.prompt(),
                   self.assistant("m1", 100, 400000),
                   {"type": "system", "subtype": "compact_boundary"})
        usage = hook.read_usage(self.path)
        self.assertEqual((usage["tokensIn"], usage["tokensOut"]), (0, 100))

    def test_a_transcript_with_no_usage_reports_nothing(self):
        self.write(self.prompt())
        self.assertIsNone(hook.read_usage(self.path))

    def test_a_missing_transcript_is_not_an_error(self):
        self.assertIsNone(hook.read_usage(os.path.join(self.tmp, "nope.jsonl")))

    def test_the_remembered_path_is_used_when_the_event_omits_it(self):
        self.write(self.prompt(), self.assistant("m1", 5, 10))
        self.assertEqual(hook.find_transcript("sid", None, self.path), self.path)


if __name__ == "__main__":
    unittest.main()
