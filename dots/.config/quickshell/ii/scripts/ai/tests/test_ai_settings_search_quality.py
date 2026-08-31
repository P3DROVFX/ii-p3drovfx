#!/usr/bin/env python3
"""A question about a setting gets the setting, in one language, and few of them.

Three faults met in one screenshot: an English conversation quoting Portuguese
toggle names, a raw index record printed into the chat, and eight results for a
question with two answers. All three came from the same place — the index was
built in a language nobody asked for, and everything it held was handed
onwards unfiltered.
"""

import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
GENERATOR = ROOT / "scripts" / "ai" / "ai_settings_index.py"
SPEC = importlib.util.spec_from_file_location("ai_settings_index", GENERATOR)
INDEX = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INDEX)
GENERATOR_SOURCE = GENERATOR.read_text(encoding="utf-8")
INTEGRATION = (ROOT / "services" / "ai" / "integrations" / "AiSettingsIntegration.qml").read_text(encoding="utf-8")
CARD = (ROOT / "services" / "ai" / "blocks" / "AiSettingResultCard.qml").read_text(encoding="utf-8")
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")

BUILT = ROOT.parent.parent.parent.parent  # unused; kept explicit for clarity


def build_fixture() -> dict:
    """A small index shaped like the real one, built by hand."""
    entries = [
        {
            "key": "battery.automaticSuspend", "type": "bool", "hasUi": True,
            "label": "Automatic suspend", "description": "Automatically suspends the system when battery is low",
            "pageId": "power", "pageName": "Power & Battery", "sectionTitle": "Power & Battery Management",
            "subPage": "", "aliases": ["Core Services", "Suspend", "Automatic suspend"],
            "keywords": ["suspend", "sleep", "dormir"], "match": "", "currentValue": True,
        },
        {
            "key": "battery.suspend", "type": "int", "hasUi": True,
            "label": "Suspend at (%)", "description": "",
            "pageId": "power", "pageName": "Power & Battery", "sectionTitle": "Power & Battery Management",
            "subPage": "", "aliases": ["Core Services", "Suspend", "Automatic suspend"],
            "keywords": ["suspend", "sleep"], "match": "", "currentValue": 3,
        },
        {
            "key": "idle.persistInhibit", "type": "string", "hasUi": True,
            "label": "persistInhibit", "description": "",
            "pageId": "power", "pageName": "Power & Battery", "sectionTitle": "Remember Keep awake",
            "subPage": "", "aliases": ["Core Services", "Suspend", "Automatic suspend"],
            "keywords": [], "match": "", "currentValue": "session",
        },
        {
            # No control anywhere, so no label of its own — the last segment of
            # the key is all there is, and it happens to be a common word.
            "key": "ai.tools.mode", "type": "string", "hasUi": False,
            "label": "", "description": "", "pageId": "", "pageName": "", "sectionTitle": "",
            "subPage": "", "aliases": [], "keywords": [], "match": "", "currentValue": "functions",
        },
        {
            "key": "light.darkMode.enabled", "type": "bool", "hasUi": True,
            "label": "Dark mode", "description": "Use the dark colour scheme",
            "pageId": "colors", "pageName": "Colors & Themes", "sectionTitle": "Appearance",
            "subPage": "", "aliases": [], "keywords": [], "match": "", "currentValue": True,
        },
    ]
    return {"schema": INDEX.SCHEMA_VERSION, "language": "en_US", "entries": entries}


class RankingTests(unittest.TestCase):
    index = build_fixture()

    def keys_for(self, query: str) -> list[str]:
        return [entry["key"] for entry in INDEX.search_entries(self.index, query)]

    def test_a_direct_question_gets_the_two_settings_that_answer_it(self):
        self.assertEqual(self.keys_for("automatic suspend"),
                         ["battery.automaticSuspend", "battery.suspend"])

    def test_a_whole_sentence_works_as_well_as_the_words_that_matter(self):
        self.assertEqual(self.keys_for("where can i enable automatic laptop suspension?"),
                         ["battery.automaticSuspend", "battery.suspend"])

    def test_sharing_a_page_is_not_an_answer(self):
        # `idle.persistInhibit` matches both words only through the aliases of
        # the page it sits on. That is not what the question was about.
        self.assertNotIn("idle.persistInhibit", self.keys_for("automatic suspend"))

    def test_a_key_with_no_control_does_not_win_on_its_last_segment(self):
        # `ai.tools.mode` used to come first for "dark mode": its last key
        # segment is exactly "mode", and one exact hit on a name nobody chose
        # outweighed two partial hits on a real label. Answering the whole
        # question now wins over answering half of it perfectly.
        results = self.keys_for("dark mode")
        self.assertEqual(results[0], "light.darkMode.enabled")
        self.assertNotIn("ai.tools.mode", results)

    def test_nothing_relevant_returns_nothing(self):
        self.assertEqual(self.keys_for("kubernetes ingress"), [])

    def test_results_are_capped_however_much_is_asked_for(self):
        self.assertLessEqual(len(INDEX.search_entries(self.index, "suspend", limit=99)), INDEX.MAX_RESULTS)

    def test_filler_words_do_not_decide_the_answer(self):
        self.assertNotIn("the", INDEX.query_tokens_of("where is the setting for the thing"))
        # A question made only of filler still tries rather than answering
        # nothing at all.
        self.assertTrue(INDEX.query_tokens_of("where is the"))

    def test_a_synonym_belongs_to_the_option_not_to_its_page(self):
        # Domain synonyms are matched against what the entry says about
        # itself. Matching them against the page as well gave every option on
        # the Power page the synonyms for "suspend", so asking about automatic
        # suspend answered with the low-battery warning threshold.
        assignment = GENERATOR_SOURCE.split("domains = [domain for domain in synonyms", 1)[0]
        haystack = assignment.rsplit("haystack = ", 1)[1]
        self.assertIn('entry["key"]', haystack)
        self.assertIn('entry["label"]', haystack)
        for borrowed in ("pageName", "sectionTitle", "aliases"):
            with self.subTest(field=borrowed):
                self.assertNotIn(borrowed, haystack)

    def test_a_synonym_can_answer_on_its_own(self):
        # It is the bridge between a question in one language and an interface
        # in another, so it has to count as the entry's own evidence.
        index = build_fixture()
        self.assertEqual([entry["key"] for entry in INDEX.search_entries(index, "dormir")],
                         ["battery.automaticSuspend"])

    def test_a_stem_matches_a_word_not_a_different_word(self):
        self.assertTrue(INDEX.stem_hit(INDEX.stem_of("suspension"), "suspend"))
        # Five characters made "suspend" match "suspect", and one page's
        # aliases mention hiding suspect wallpapers.
        self.assertFalse(INDEX.stem_hit(INDEX.stem_of("suspend"), "suspect"))


class OneLanguageTests(unittest.TestCase):
    def test_the_generator_assumes_no_language_of_its_own(self):
        # It defaulted to pt_BR, so an English interface got Portuguese labels
        # back and the section deep-link stopped matching what was on screen.
        self.assertNotIn("pt_BR", GENERATOR_SOURCE)
        self.assertIn('parser.add_argument("--lang", default=""', GENERATOR_SOURCE)

    def test_an_entry_carries_one_label_not_two(self):
        for field in ("labelLocalized", "descriptionLocalized", "sectionTitleLocalized", "pageNameLocalized"):
            with self.subTest(field=field):
                self.assertNotIn(f'"{field}"', GENERATOR_SOURCE)
                self.assertNotIn(field, INTEGRATION)
                self.assertNotIn(field, CARD)

    def test_the_shell_says_which_language_it_is_showing(self):
        self.assertIn('"--lang", root.language', INTEGRATION)
        self.assertIn("readonly property string language: Translation.languageCode", INTEGRATION)

    def test_changing_language_rebuilds_the_index(self):
        self.assertIn("onLanguageChanged: root.rebuild()", INTEGRATION)

    def test_the_deep_link_uses_the_title_the_interface_shows(self):
        opener = CARD.split("function openInSettings()", 1)[1].split("\n    }", 1)[0]
        self.assertIn("root.sectionTitle", opener)


class ModelPayloadTests(unittest.TestCase):
    def test_the_model_is_handed_a_projection_not_the_index_record(self):
        handler = AI_QML.split("function toolSettingsSearch(call: var)", 1)[1].split("function toolSettingsGetSemantic", 1)[0]
        self.assertIn("modelRefs(matches)", handler)
        # The card still gets the full record: it draws the control.
        self.assertIn("data: { matches: matches }", handler)

    def test_the_projection_drops_everything_a_model_cannot_act_on(self):
        projection = INTEGRATION.split("function modelRef(ref: var)", 1)[1].split("function modelRefs", 1)[0]
        for noise in ("aliases", "keywords", "blockStart", "blockEnd", "source", "widget", "score"):
            with self.subTest(field=noise):
                self.assertNotIn(f"{noise}:", projection)

    def test_qml_tokenises_the_same_way_the_generator_does(self):
        # Qt's JavaScript engine ignores \\p{L}, so that pattern matched
        # nothing and "automatic suspend" arrived as a single token.
        self.assertNotIn("p{L}", INTEGRATION.split("function tokens(", 1)[1].split("}", 1)[0])


class TranscriptNoiseTests(unittest.TestCase):
    def test_no_provider_prints_the_call_into_the_answer(self):
        for name in ("OpenAiCompatStrategy", "GeminiApiStrategy", "AnthropicApiStrategy"):
            source = (ROOT / "services" / "ai" / f"{name}.qml").read_text(encoding="utf-8")
            with self.subTest(provider=name):
                self.assertNotIn("[[ Function:", source)
                # The thought still has to be closed when a call arrives.
                self.assertIn("closeThought(message)", source)

    def test_the_tool_output_turn_is_not_drawn_as_a_message(self):
        maker = AI_QML.split("function createFunctionOutputMessage(", 1)[1].split("\n    }", 1)[0]
        self.assertIn('"visibleToUser": visible === true', maker)

    def test_a_shell_command_still_shows_its_output(self):
        starter = AI_QML.split("function startShellCommand(", 1)[1].split("\n    }", 1)[0]
        self.assertIn("createFunctionOutputMessage(message.functionName, \"\", false, message.functionCallId, true)", starter)

    def test_the_model_still_receives_the_output(self):
        # Hiding the turn must not starve the model: providers read
        # functionResponse, not the rendered content.
        for name in ("OpenAiCompatStrategy", "GeminiApiStrategy", "AnthropicApiStrategy"):
            source = (ROOT / "services" / "ai" / f"{name}.qml").read_text(encoding="utf-8")
            with self.subTest(provider=name):
                self.assertIn("functionResponse", source)


class DirectControlTests(unittest.TestCase):
    """The control on the card writes the setting, and keeps following it."""

    def test_the_step_is_a_stride_not_a_rule_about_legal_values(self):
        # `stepSize` is how far one press moves the number. Treating it as a
        # constraint refused everything the arrows produced — battery.suspend
        # sat at 3, the step is 5, so every press landed on 8, 13, 18 — and
        # refused the value already stored.
        validate = INTEGRATION.split("function validate(key: string, value: var)", 1)[1].split("\n    /**", 1)[0]
        self.assertNotIn("outsideStep", validate)
        # Range is a real constraint and stays.
        self.assertIn('reason: "belowRange"', validate)
        self.assertIn('reason: "aboveRange"', validate)

    def test_the_stored_value_is_a_binding_nothing_writes_to(self):
        # Assigning it broke the binding on the first change, after which the
        # card showed its own last write and stopped following the setting.
        self.assertIn("readonly property var currentValue: root.readCurrentValue()", CARD)
        self.assertNotIn("root.currentValue =", CARD)

    def test_writing_goes_to_the_config_and_nowhere_else(self):
        write = CARD.split("function writeValue(value: var): bool {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("Config.setNestedValue(root.key, value, true)", write)

    def test_the_number_controls_commit_on_change(self):
        # `valueModified` is the signal for "the user did this", but
        # StyledSpinBox replaces the content item with a text field that
        # assigns `value` itself, and a plain assignment emits no such signal.
        # Nothing else in the repo listens for it either.
        self.assertNotIn("onValueModified", CARD)
        self.assertIn("onValueChanged: root.commitNumber(value)", CARD)
        self.assertIn("onMoved: root.commitNumber(value)", CARD)

    def test_a_control_reflecting_the_stored_value_does_not_write_it_back(self):
        commit = CARD.split("function commitNumber(value: real): bool {", 1)[1].split("\n    }", 1)[0]
        self.assertIn("Number(root.currentValue) === wanted", commit)
        self.assertIn("return false", commit)

    def test_a_control_follows_a_change_made_elsewhere(self):
        # Interacting with a SpinBox or Slider breaks the declarative binding
        # on its value, so it has to be told when the setting moves.
        self.assertIn("function onCurrentValueChanged()", CARD)
        self.assertGreaterEqual(CARD.count("function onCurrentValueChanged()"), 2)

    def test_a_refusal_is_a_sentence_not_a_code(self):
        self.assertIn("Ai.settingsIntegration.reasonText(verdict)", CARD)
        self.assertIn("function reasonText(verdict: var): string", INTEGRATION)


class LauncherTests(unittest.TestCase):
    def test_enter_reaches_the_row_through_the_loader(self):
        bar = (ROOT / "modules" / "ii" / "overview" / "SearchBar.qml").read_text(encoding="utf-8")
        accepted = bar.split("onAccepted: {", 1)[1].split("\n        }", 1)[0]
        self.assertIn("delegate?.item ?? delegate", accepted)
        self.assertNotIn("currentItem.clicked()", accepted)

    def test_a_settings_row_answers_to_enter(self):
        self.assertIn("function clicked()", CARD)

    def test_settings_do_not_flood_the_launcher(self):
        launcher = (ROOT / "services" / "LauncherSearch.qml").read_text(encoding="utf-8")
        self.assertIn("Config.options.search.modules.settingsToggles.maxInlineResults", launcher)
        self.assertIn("settingsMatches.slice(0, maxInlineSettings)", launcher)


if __name__ == "__main__":
    unittest.main()
