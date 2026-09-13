#!/usr/bin/env python3
"""Gaps found auditing plan section 14 ("Matriz de testes") against the
thirty-six existing `scripts/ai/tests/*.py` files.

Most of section 14 already has a home: SSRF in `test_ai_web_ssrf.py`, Gmail
read-only invariants in `test_ai_gmail_integration_contract.py`, task
idempotency in `test_ai_tasks_idempotency.py`, and so on. This file exists
for the bullets that had no test anywhere, checked by reading every existing
test file's method names and, where a name looked close, its body.

One of those gaps was not just untested — it was a real hole. §14.1 requires
"policy Local blocks web, ESPN, Gmail, TickTick and Google Tasks", but the
task tools are declared `network: "optional"` (correctly, since the local
provider needs no network at all), which means `AiToolRegistry.availability`'s
generic `!online && network === "required"` check never touches them.
`AiTasksIntegration.resolveProvider()` — the one function every task read and
mutation funnels through — had no policy check of its own, so a connected
TickTick account stayed one tool call away from the model even under
Local-only. Fixed here; the regression tests below are what would have
caught it.

Google Tasks needs no equivalent test: `AiTasksIntegration` never learned a
`googleTasks` provider id, so the AI tools cannot reach it regardless of
policy — nothing to leak.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")
CATALOG_QML = (ROOT / "services" / "ai" / "ModelCatalog.qml").read_text(encoding="utf-8")
TASKS_INTEGRATION_QML = (ROOT / "services" / "ai" / "integrations" / "AiTasksIntegration.qml").read_text(encoding="utf-8")
REGISTRY_QML = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
AICHAT_QML = (ROOT / "modules" / "ii" / "sidebarPolicies" / "AiChat.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


class LocalOnlyPolicyLeakTests(unittest.TestCase):
    """§14.1: 'policy Local blocks web, ESPN, Gmail, TickTick and Google
    Tasks'. The generic registry check only catches `network: "required"`
    tools; TickTick hides behind `network: "optional"` because the same
    tool also serves the local provider, which needs no network at all."""

    def test_task_tools_are_declared_optional_not_required(self):
        # Documents *why* the generic availability() gate cannot be the
        # thing that blocks TickTick: it would also have to block the local
        # provider, which is exactly the case Local-only is supposed to
        # keep working.
        for tool_id in ("tasks_list", "tasks_search", "tasks_create"):
            with self.subTest(tool=tool_id):
                marker = f'id: "{tool_id}",'
                block = REGISTRY_QML[REGISTRY_QML.index(marker):][:600]
                self.assertIn('network: "optional"', block)

    def test_resolve_provider_refuses_ticktick_under_local_only(self):
        fn = body_between(TASKS_INTEGRATION_QML, "function resolveProvider(requested) {", "\n    }")
        self.assertIn("Ai.localOnly", fn)
        self.assertIn('id !== root.localProviderId', fn)
        self.assertIn("return { ok: false", fn)

    def test_the_refusal_happens_before_the_connection_check(self):
        # A provider that failed the policy check must not also be reported
        # as "not connected" — that would send the user to reconnect an
        # account that was never the problem.
        fn = body_between(TASKS_INTEGRATION_QML, "function resolveProvider(requested) {", "\n    }")
        policy_line = fn.index("Ai.localOnly")
        connection_line = fn.index("provider.available")
        self.assertLess(policy_line, connection_line)

    def test_every_task_operation_funnels_through_the_guarded_resolver(self):
        # list/search/create/update/complete/delete must not have their own
        # copy of provider selection - if even one calls TickTickService
        # directly without going through resolveProvider (or
        # normalizeCreate/normalizeRef, which call it), the guard above does
        # not cover it.
        for fn_name, start in (
            ("normalizeCreate", "function normalizeCreate(args) {"),
            ("normalizeRef", "function normalizeRef(args) {"),
        ):
            with self.subTest(function=fn_name):
                fn = body_between(TASKS_INTEGRATION_QML, start, "\n    }")
                self.assertIn("root.resolveProvider(", fn)
        # listTasks (and searchTasks, which delegates to it) resolve
        # directly since they have no create/update shape to normalize.
        list_fn = body_between(TASKS_INTEGRATION_QML, "function listTasks(args, key) {", "\n    }")
        self.assertIn("root.resolveProvider(", list_fn)

    def test_ticktick_is_not_offered_as_a_provider_under_local_only(self):
        # Hidden from the option list, not merely refused at call time - the
        # model should not be told a destination exists that every call to
        # it will then refuse.
        fn = body_between(TASKS_INTEGRATION_QML, "function availableProviders() {", "\n    }")
        self.assertIn("!Ai.localOnly", fn)

    def test_the_default_provider_falls_back_to_local_under_local_only(self):
        # With no explicit `provider` argument, the resolver used to prefer
        # a connected TickTick account outright. Under Local-only that
        # default must not silently choose the provider the policy forbids.
        fn = body_between(TASKS_INTEGRATION_QML, "function resolveProvider(requested) {", "\n        // TickTick needs")
        self.assertIn("!Ai.localOnly", fn)


class RemoteOllamaIsNotLocalTests(unittest.TestCase):
    """§14.1: 'Ollama on a remote endpoint is not accepted as local'. Local
    policy is meant to be an endpoint boundary, not a trust decision based
    on which provider name happens to be attached to a model."""

    def test_a_bare_ip_or_hostname_is_not_loopback(self):
        fn = body_between(CATALOG_QML, "function isLoopbackEndpoint(endpoint: string): bool {", "\n    }")
        # The function must resolve a real host and compare it explicitly,
        # not just check whether the string contains "localhost" anywhere -
        # http://not-localhost.example/localhost would otherwise pass.
        self.assertIn('host === "localhost"', fn)
        self.assertIn("127", fn)
        self.assertNotIn("endpoint.includes(", fn)
        self.assertNotIn('.indexOf("localhost")', fn)

    def test_the_check_is_endpoint_based_not_provider_name_based(self):
        # A custom model can be attached to the "ollama" provider while its
        # own `endpoint` points anywhere; the function must not special-case
        # the provider id as a shortcut for "trust it".
        fn = body_between(CATALOG_QML, "function isLoopbackEndpoint(endpoint: string): bool {", "\n    }")
        self.assertNotIn("ollama", fn.lower())

    def test_is_model_local_defers_entirely_to_the_endpoint_check(self):
        fn = body_between(CATALOG_QML, "function isModelLocal(model: var): bool {", "\n    }")
        self.assertIn("catalog.isLoopbackEndpoint(model.endpoint)", fn)

    def test_entry_allowed_under_local_only_also_defers_to_the_endpoint_check(self):
        # entryAllowed is what actually filters the model picker under
        # policy 2; if it used a different check than isModelLocal, the
        # picker and the runtime enforcement in canSubmit() could disagree
        # about which models are "local".
        fn = body_between(CATALOG_QML, "function entryAllowed(def: var, entry: var): bool {", "\n    }")
        self.assertIn("catalog.isLoopbackEndpoint(", fn)

    def test_canonical_localhost_forms_are_recognised(self):
        # Read as data, not executed - QML numeric/hostname literals are
        # exercised live in test_ai_rag_contract.py's Ollama round trip and
        # in production; this only pins which literal forms the function's
        # own text commits to recognising.
        fn = body_between(CATALOG_QML, "function isLoopbackEndpoint(endpoint: string): bool {", "\n    }")
        self.assertIn('"::1"', fn)
        self.assertIn(r"/^127(?:\.\d{1,3}){3}$/", fn)


class VisionGatingTests(unittest.TestCase):
    """§14.1, flagged in the plan as a regression risk (A10): a model
    without vision must never receive an image, and — the direction that
    actually regressed once — a model *with* detected vision must receive
    one rather than being caught by a stale blanket rule."""

    def test_attachment_plan_checks_the_current_models_vision_flag(self):
        fn = body_between(AI_QML, "function attachmentPlan(file: var): var {", "\n\n    /** Empty when the file may be sent")
        image_branch = fn.split('if (kind === "image") {', 1)[1].split('if (kind === "image")', 1)[0] if fn.count('kind === "image"') else fn
        self.assertIn("root.currentModelSupportsVision", image_branch)

    def test_a_model_without_vision_rejects_an_image(self):
        fn = body_between(AI_QML, "function attachmentPlan(file: var): var {", "\n\n    /** Empty when the file may be sent")
        image_branch = fn.split('if (kind === "image") {', 1)[1]
        self.assertIn("!root.currentModelTakesFiles || !root.currentModelSupportsVision", image_branch)
        self.assertIn('action: "reject"', image_branch)

    def test_a_model_with_vision_is_not_blocked_by_the_generic_document_path(self):
        # The regression: an overly broad "this model cannot take files"
        # check placed before the vision-specific branch would catch a
        # vision-capable model too. The image branch must return before
        # falling through to the document/attachments-only logic below it.
        fn = body_between(AI_QML, "function attachmentPlan(file: var): var {", "\n\n    /** Empty when the file may be sent")
        image_branch_start = fn.index('if (kind === "image") {')
        document_logic_start = fn.index("// Documents, audio, video.")
        self.assertLess(image_branch_start, document_logic_start)
        image_branch = fn[image_branch_start:document_logic_start]
        self.assertIn('action: "send"', image_branch)

    def test_the_submit_time_revalidation_checks_vision_too(self):
        # attachmentPlan runs when the file is first attached; the model can
        # be switched afterwards, so attachmentRejectionForModel — run again
        # at submit time — must re-check vision against whatever model is
        # about to receive the request, not trust the plan made earlier.
        fn = body_between(AI_QML, "function attachmentRejectionForModel(files: var, model): string {", "\n\n    /**")
        self.assertIn('kind === "image"', fn)
        self.assertIn("!model?.attachments || !model?.vision", fn)


class VisionGatedComposerControlsTests(unittest.TestCase):
    """A toggle whose only purpose is sharing an image (the screen-region
    capture) must be disabled — not merely warned about after the fact —
    when the current model cannot look at images. Mixed-purpose controls
    like "Attach files" stay enabled: a text/PDF attachment still works
    without vision, and `attachmentPlan()` already rejects an image pick
    on its own with a clear reason."""

    def test_the_screen_capture_pill_is_disabled_without_vision(self):
        block = body_between(AICHAT_QML, 'symbol: "screenshot_region"', "\n                                            }")
        self.assertIn("enabled: Ai.currentModelSupportsVision", block)

    def test_the_disabled_pill_explains_why_in_its_tooltip(self):
        block = body_between(AICHAT_QML, 'symbol: "screenshot_region"', "\n                                            }")
        self.assertIn("disabledReason:", block)

    def test_the_pill_component_shows_the_disabled_reason_instead_of_the_label(self):
        fn = body_between(AICHAT_QML, "component ComposerActionPill: RippleButton {", "\n    }")
        self.assertIn("property string disabledReason", fn)
        tooltip = body_between(fn, "StyledToolTip {", "\n        }")
        self.assertIn("actionPill.enabled", tooltip)
        self.assertIn("actionPill.disabledReason", tooltip)

    def test_attach_files_is_not_vision_gated(self):
        # Mixed-purpose: still useful for text/PDF without vision.
        block = body_between(AICHAT_QML, 'symbol: "attach_file"', "\n                                            }")
        self.assertNotIn("currentModelSupportsVision", block)


class CapabilityOverrideTests(unittest.TestCase):
    """§14.1: 'a capability override is visible and reversible'. Detected
    Ollama capabilities and the config-driven fallback must be
    distinguishable, and the fallback must not stick once real detection
    succeeds."""

    def test_the_capability_source_is_exposed_per_model(self):
        entries = body_between(CATALOG_QML, "readonly property var ollamaEntries: {", "\n        return result;")
        self.assertIn('capabilitySource: detected ? "detected" : "userOverride"', entries)

    def test_the_override_only_applies_when_nothing_was_actually_detected(self):
        entries = body_between(CATALOG_QML, "readonly property var ollamaEntries: {", "\n        return result;")
        self.assertIn("const detected = capabilities.length > 0;", entries)
        self.assertIn("tools: detected ? capabilities.indexOf(\"tools\") >= 0 : toolsAllowed", entries)

    def test_the_override_is_never_persisted_so_real_detection_can_take_back_over(self):
        # ollamaEntries is a plain computed property over ollamaModelNames,
        # not something written to Config - the moment /api/tags reports
        # real capabilities for a model, `detected` flips to true and the
        # override stops applying on its own, with nothing to unset by hand.
        self.assertIn("readonly property var ollamaEntries: {", CATALOG_QML)
        self.assertNotIn("Config.options.ai.capabilityOverride", CATALOG_QML)


if __name__ == "__main__":
    unittest.main()
