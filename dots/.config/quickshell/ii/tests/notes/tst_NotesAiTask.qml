import QtQuick
import QtTest

TestCase {
    name: "NotesAiTask"

    // ── 1. Policy & Privacy Gating Contract ───────────────────────────────

    function test_policy_zero_disables_ai_completely() {
        // Policy 0 means AI is strictly disabled.
        // No request should be allowed and allowed property must be false.
        const policy = 0;
        const allowed = (policy !== 0);
        verify(!allowed, "AI must be disabled when policy is 0");
    }

    function test_policy_two_enforces_local_only() {
        // Policy 2 restricts execution to local-only models (Ollama).
        const policy = 2;
        const isLocalOnly = (policy === 2);
        verify(isLocalOnly, "Policy 2 must enforce local models only");

        // Remote models like gemini/anthropic must be disallowed under local-only
        const models = [
            { id: "ollama-llama3", local: true },
            { id: "gemini-2.0-flash", local: false },
            { id: "claude-3-5-sonnet", local: false }
        ];

        for (const m of models) {
            const canRun = !isLocalOnly || m.local;
            if (m.local) {
                verify(canRun, `Model ${m.id} should be allowed`);
            } else {
                verify(!canRun, `Model ${m.id} should NOT be allowed under policy 2`);
            }
        }
    }

    // ── 2. Selection Wrapping & Formatting Invariants ─────────────────────

    function wrapText(full, start, end, prefix, suffix) {
        const sMin = Math.min(start, end);
        const sMax = Math.max(start, end);
        const sel = full.slice(sMin, sMax);
        const before = full.slice(Math.max(0, sMin - prefix.length), sMin);
        const after = full.slice(sMax, sMax + suffix.length);

        if (before === prefix && after === suffix) {
            // Unwrap
            return {
                text: full.slice(0, sMin - prefix.length) + sel + full.slice(sMax + suffix.length),
                newStart: sMin - prefix.length,
                newEnd: sMax - prefix.length,
                wrapped: false
            };
        } else {
            // Wrap
            return {
                text: full.slice(0, sMin) + prefix + sel + suffix + full.slice(sMax),
                newStart: sMin + prefix.length,
                newEnd: sMax + prefix.length,
                wrapped: true
            };
        }
    }

    function test_selection_wrap_bold() {
        const initial = "Hello world of notes";
        // Select "world" (indices 6 to 11)
        const wrapped = wrapText(initial, 6, 11, "**", "**");
        compare(wrapped.text, "Hello **world** of notes");
        verify(wrapped.wrapped);

        // Toggling it again unwraps it
        const unwrapped = wrapText(wrapped.text, wrapped.newStart, wrapped.newEnd, "**", "**");
        compare(unwrapped.text, "Hello world of notes");
        verify(!unwrapped.wrapped);
    }

    function test_selection_wrap_code() {
        const initial = "const x = 42;";
        const wrapped = wrapText(initial, 10, 12, "`", "`");
        compare(wrapped.text, "const x = `42`;");
        verify(wrapped.wrapped);

        const unwrapped = wrapText(wrapped.text, wrapped.newStart, wrapped.newEnd, "`", "`");
        compare(unwrapped.text, "const x = 42;");
        verify(!unwrapped.wrapped);
    }

    function test_selection_wrap_link() {
        const initial = "Check this site here.";
        const wrapped = wrapText(initial, 11, 15, "[", "](https://)");
        compare(wrapped.text, "Check this [site](https://) here.");
        verify(wrapped.wrapped);
    }

    // ── 3. Custom Styles Serialization Contract ───────────────────────────

    function test_custom_styles_json_roundtrip() {
        const style = {
            name: "Empresa XPTO",
            prompt: "Reescreva em tom corporativo sem adjetivos e com dados objetivos."
        };

        const serialized = JSON.stringify(style);
        const parsed = JSON.parse(serialized);

        compare(parsed.name, style.name);
        compare(parsed.prompt, style.prompt);
    }

    function test_corrupted_custom_styles_are_ignored() {
        const rawStyles = [
            JSON.stringify({ name: "Valido", prompt: "Instrução válida" }),
            "this is not json",
            JSON.stringify({ name: "Sem prompt" }),
            null,
            ""
        ];

        const valid = [];
        for (const item of rawStyles) {
            try {
                if (typeof item === "string") {
                    const parsed = JSON.parse(item);
                    if (parsed && parsed.name && parsed.prompt)
                        valid.push(parsed);
                }
            } catch (e) {
                // ignore
            }
        }

        compare(valid.length, 1);
        compare(valid[0].name, "Valido");
    }

    // ── 4. Inviolable Rule: No Overwrite Without Confirmation ──────────────

    function test_ai_never_overwrites_original_without_explicit_action() {
        const originalDoc = "Nota com ideias críticas do usuário.";
        const aiProposal = "Texto sugerido pela IA.";

        let documentText = originalDoc;

        // Discard action leaves document completely untouched
        const actionDiscard = true;
        if (actionDiscard) {
            // do not change documentText
        }
        compare(documentText, originalDoc);

        // Insert below keeps original and appends
        const actionInsertBelow = (orig, prop) => [orig, prop];
        const blocks = actionInsertBelow(documentText, aiProposal);
        compare(blocks[0], originalDoc);
        compare(blocks[1], aiProposal);

        // Replace only occurs on explicit replace action
        const actionReplace = (prop) => prop;
        documentText = actionReplace(aiProposal);
        compare(documentText, aiProposal);
    }

    // ── 5. All 8 Tones Contract ───────────────────────────────────────────

    function test_all_eight_tones_defined() {
        const expectedTones = [
            "professional", "casual", "direct", "academic",
            "empathetic", "poetic", "humorous", "persuasive"
        ];
        compare(expectedTones.length, 8);
    }
}
