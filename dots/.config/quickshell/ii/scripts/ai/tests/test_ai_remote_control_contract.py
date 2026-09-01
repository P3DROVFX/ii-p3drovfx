#!/usr/bin/env python3
"""Regression contract for asking the chat from outside the shell.

`qs -c ii ipc call ai ask "..."` runs a question through the exact same
`sendUserMessage` path the composer uses — same chat, same tools, same
one-run-at-a-time rule — and returns its accept/reject verdict immediately,
as JSON. The answer itself lands later: once written, in the in-memory
`lastAnswerRecord`, mirrored atomically to `Directories.aiLastAnswer` on
disk, and readable back over IPC via `ai lastAnswer`.

The one bug class worth guarding against here is the one already fixed for
desktop notifications: `markDone()` runs once per network turn, and a tool
round-trip is several turns for one exchange. Writing the last-answer file
outside that same "no more tool calls pending" gate would mean a remote
caller polling `lastAnswer()` could catch an intermediate tool-call message
— with no `answer` text yet — and mistake it for a finished exchange that
came back empty.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
DIRECTORIES_QML = (ROOT / "modules" / "common" / "Directories.qml").read_text(encoding="utf-8")
# The remote-access guidance moved off the main AI page and onto its own
# sub-page when the settings were split by subject. Same content, new home.
CONFIG_PAGE = (ROOT / "modules" / "settings" / "configs" / "ai" / "AiRemoteAccessConfig.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class DirectoryTests(unittest.TestCase):
    def test_last_answer_path_lives_next_to_the_other_ai_state(self):
        self.assertIn(
            'property string aiLastAnswer: FileUtils.trimFileProtocol(`${Directories.state}/user/ai/last_answer.json`)',
            DIRECTORIES_QML,
        )


class IpcEndpointTests(unittest.TestCase):
    def test_the_ai_ipc_target_exists_with_ask_and_last_answer(self):
        handler = body_between(AI_QML, 'IpcHandler {\n        target: "ai"', "\n    }\n\n    function transportErrorKind")
        self.assertIn("function ask(text: string): string", handler)
        self.assertIn("function lastAnswer(): string", handler)

    def test_ask_returns_send_user_message_s_own_verdict_not_a_new_one(self):
        handler = body_between(AI_QML, 'IpcHandler {\n        target: "ai"', "\n    }\n\n    function transportErrorKind")
        ask_body = body_between(handler, "function ask(text: string): string {", "\n        }")
        # It must hand off to the one function the composer itself calls —
        # accepted/busy/disabled all come from there, not reimplemented here.
        self.assertIn("root.sendUserMessage(text)", ask_body)
        self.assertIn("JSON.stringify(", ask_body)

    def test_last_answer_reads_the_in_memory_record_not_the_file(self):
        # Round-tripping through the FileView's own async load for a
        # synchronous IPC return would either block or race; the record kept
        # in memory at write time is what both the file and the IPC call
        # must agree on.
        handler = body_between(AI_QML, 'IpcHandler {\n        target: "ai"', "\n    }\n\n    function transportErrorKind")
        last_answer_body = body_between(handler, "function lastAnswer(): string {", "\n        }")
        self.assertIn("root.lastAnswerRecord", last_answer_body)
        self.assertNotIn("lastAnswerFile.text", last_answer_body)


class LastAnswerWriteTests(unittest.TestCase):
    def test_write_last_answer_file_is_gated_the_same_as_the_notification(self):
        mark_done = body_between(AI_QML, "function markDone(message: AiMessageData) {", "\n    }\n\n    /**\n     * What went wrong")
        gate = body_between(
            mark_done,
            "if ((message.toolCalls?.length ?? 0) === 0) {",
            "\n        }",
        )
        self.assertIn("root.notifyResponseFinished(message);", gate)
        self.assertIn("root.writeLastAnswerFile(message);", gate)

    def test_the_file_write_is_atomic(self):
        file_view = body_between(AI_QML, "FileView {\n        id: lastAnswerFile", "\n    }")
        self.assertIn("atomicWrites: true", file_view)

    def test_the_record_carries_enough_to_answer_a_remote_poller(self):
        writer = body_between(AI_QML, "function writeLastAnswerFile(message: AiMessageData) {", "\n    }")
        for field in ("requestText", "answer", "errorKind", "errorText", "sessionId", "model", "completedAt"):
            self.assertIn(f'"{field}"', writer)
        self.assertIn("root.lastAnswerRecord = record;", writer)


class SettingsGuideTests(unittest.TestCase):
    def test_the_ai_settings_page_documents_the_exact_ask_command(self):
        self.assertIn('qs -c ii ipc call ai ask', CONFIG_PAGE)
        self.assertIn('qs -c ii ipc call ai lastAnswer', CONFIG_PAGE)
        self.assertIn('Directories.aiLastAnswer', CONFIG_PAGE)

    def test_the_guide_warns_that_approval_gated_tools_will_hang_forever(self):
        # `run_shell_command` never auto-approves; asked with no window
        # open to click the approval card, that call has no deadline and
        # simply never returns. Silence about this would be a footgun.
        self.assertIn("NoticeBox", CONFIG_PAGE)
        remote_section = body_between(
            CONFIG_PAGE,
            'title: Translation.tr("Remote access")',
            "\n        }\n\n        ContentSection {\n            icon: \"extension\"",
        )
        self.assertIn("no deadline", remote_section)
        self.assertIn("approval", remote_section)


if __name__ == "__main__":
    unittest.main()
