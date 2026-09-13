#!/usr/bin/env python3
"""Regression contracts for bounded local Markdown image previews."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_TEXT_BLOCK_QML = (ROOT / "services" / "ai" / "blocks" / "AiMessageTextBlock.qml").read_text(encoding="utf-8")
AI_IMAGE_PREVIEW_QML = (ROOT / "services" / "ai" / "blocks" / "AiImagePreview.qml").read_text(encoding="utf-8") if (ROOT / "services" / "ai" / "blocks" / "AiImagePreview.qml").exists() else ""


class MarkdownImagePreviewTests(unittest.TestCase):
    def test_local_markdown_images_use_a_bounded_image_component(self):
        self.assertIn('type: "image"', AI_TEXT_BLOCK_QML)
        self.assertIn("AiImagePreview", AI_TEXT_BLOCK_QML)
        self.assertIn("function splitChunkDisplaySegments", AI_TEXT_BLOCK_QML)
        self.assertIn("const imagePattern", AI_TEXT_BLOCK_QML)
        self.assertIn("lastIndex", AI_TEXT_BLOCK_QML)
        self.assertIn("Image.PreserveAspectFit", AI_IMAGE_PREVIEW_QML)
        self.assertIn("sourceSize.width", AI_IMAGE_PREVIEW_QML)
        self.assertIn("sourceSize.height", AI_IMAGE_PREVIEW_QML)

    def test_editing_and_plain_text_keep_markdown_images_as_text(self):
        body = AI_TEXT_BLOCK_QML.split("function splitDisplaySegments", 1)[1].split("function splitChunkDisplaySegments", 1)[0]
        self.assertIn("root.editing || !root.renderMarkdown", body)
        self.assertIn('return [{ type: "text", content: content }]', body)

    def test_image_preview_does_not_use_the_source_dimensions_as_layout_height(self):
        self.assertIn("previewAspectRatio", AI_IMAGE_PREVIEW_QML)
        self.assertIn("previewMaxHeight", AI_IMAGE_PREVIEW_QML)
        self.assertNotIn("height: implicitHeight", AI_IMAGE_PREVIEW_QML)


if __name__ == "__main__":
    unittest.main()
