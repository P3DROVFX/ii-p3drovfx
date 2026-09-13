#!/usr/bin/env python3
"""Local OCR: real on this machine, gated the same way any file read is.

`tesseract` is installed here, so `image_ocr` is a real tool, not a stub. It
is gated behind the same path check every file tool uses, is marked as
untrusted content on the way back, and can be turned off even when tesseract
is present — the config toggle is the difference between "tesseract exists"
and "this shell may use it".
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
REGISTRY = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
CONFIG = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
TOOLS = (ROOT / "services" / "ai" / "AiTools.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class RegistrationTests(unittest.TestCase):
    def tool_block(self, tool_id: str) -> str:
        marker = f'id: "{tool_id}",'
        start = REGISTRY.index(marker)
        return REGISTRY[start:REGISTRY.index("\n        },", start)]

    def test_image_ocr_is_registered(self):
        self.assertIn('id: "image_ocr"', REGISTRY)

    def test_it_requires_the_ocr_service(self):
        self.assertIn('requiredServices: ["ocr"]', self.tool_block("image_ocr"))

    def test_it_marks_its_result_as_untrusted(self):
        self.assertIn("untrusted: true", self.tool_block("image_ocr"))

    def test_it_asks_for_a_path_not_raw_image_bytes(self):
        block = self.tool_block("image_ocr")
        self.assertIn("path", block)
        self.assertNotIn("base64", block.lower())


class DetectionTests(unittest.TestCase):
    def test_presence_is_checked_once_cheaply(self):
        detection = body_between(AI_QML, "property bool tesseractPresent: false", "// Boot-time index")
        self.assertIn("command -v tesseract", detection)

    def test_availability_respects_a_config_toggle_even_when_installed(self):
        gate = body_between(AI_QML, "readonly property bool ocrAvailable:", "\n")
        self.assertIn("tesseractPresent", gate)
        self.assertIn("ocrEnabled", gate)

    def test_the_toolbox_exposes_ocr_availability_to_the_registry(self):
        availability = body_between(TOOLS, "readonly property var serviceAvailability: ({", "})")
        self.assertIn("ocr: Ai.ocrAvailable", availability)

    def test_the_config_toggle_defaults_on(self):
        block = body_between(CONFIG, "property JsonObject vision: JsonObject {", "}")
        self.assertIn("property bool ocrEnabled: true", block)


class HandlerTests(unittest.TestCase):
    def test_the_handler_rechecks_the_path(self):
        body = body_between(AI_QML, "function toolImageOcr(call: var): var {", "\n    }")
        self.assertIn("root.refusedFilePath(path)", body)

    def test_only_one_ocr_run_at_a_time(self):
        body = body_between(AI_QML, "function toolImageOcr(call: var): var {", "\n    }")
        self.assertIn("if (ocrToolProc.running)", body)

    def test_tesseract_is_invoked_directly_not_through_a_shell(self):
        body = body_between(AI_QML, "function toolImageOcr(call: var): var {", "\n    }")
        self.assertIn('"tesseract"', body)
        self.assertNotIn("bash", body)

    def test_a_language_hint_can_be_given_and_defaults_sensibly(self):
        body = body_between(AI_QML, "function toolImageOcr(call: var): var {", "\n    }")
        self.assertIn("call.args.lang", body)
        self.assertIn('"eng"', body)

    def test_a_failed_run_reports_a_readable_reason(self):
        proc = body_between(AI_QML, "property Process ocrToolProc: Process {", "\n    function toolShellCommand")
        self.assertIn("exitCode !== 0", proc)
        self.assertIn("OCR failed", proc)

    def test_no_text_found_is_success_not_an_error(self):
        # An image with no readable text answered its own question; that is
        # not the same as the tool failing.
        proc = body_between(AI_QML, "property Process ocrToolProc: Process {", "\n    function toolShellCommand")
        self.assertIn('status: "success"', proc)
        self.assertIn("No text found", proc)


if __name__ == "__main__":
    unittest.main()
