#!/usr/bin/env python3
"""Local retrieval (RAG) is opt-in, local-only, and never guesses a folder.

Two backends share one guardrail: `ai_rag.py` reuses `ai_attach.py`'s
`canonical_root`/`is_sensitive_path` — the same judgement `files_search`
already trusts — so indexing can never quietly disagree with it about what
is safe to read. These tests pin that reuse, the size/shape bounds on
chunking and search, and a real regression: the QML side writes a request to
each helper's stdin and must close it afterwards, because `ai_rag.py` reads
stdin to EOF rather than to a newline. A write with no close hung the helper
process forever — first caught live, running `rag_search`, `status`, and
`index` back to back.
"""

import contextlib
import importlib.util
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
SCRIPTS_AI_DIR = ROOT / "scripts" / "ai"
RAG_PATH = SCRIPTS_AI_DIR / "ai_rag.py"

# ai_rag.py imports its sibling `ai_attach` assuming sys.path[0] is its own
# directory — true when run as `python3 ai_rag.py`, not true by default when
# loaded here by file path.
if str(SCRIPTS_AI_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_AI_DIR))

RAG_SPEC = importlib.util.spec_from_file_location("ai_rag", RAG_PATH)
RAG = importlib.util.module_from_spec(RAG_SPEC)
RAG_SPEC.loader.exec_module(RAG)
RAG_SOURCE = RAG_PATH.read_text(encoding="utf-8")

CONFIG_QML = (ROOT / "modules" / "common" / "Config.qml").read_text(encoding="utf-8")
RAG_SERVICE_QML = (ROOT / "services" / "ai" / "AiRagService.qml").read_text(encoding="utf-8")
RAG_INTEGRATION_QML = (ROOT / "services" / "ai" / "integrations" / "AiRagIntegration.qml").read_text(encoding="utf-8")
REGISTRY_QML = (ROOT / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")


def body_between(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def run_index(request: dict) -> dict:
    """`index_collection` prints its result instead of returning it."""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        RAG.index_collection(request)
    lines = [line for line in buf.getvalue().splitlines() if line.strip()]
    return json.loads(lines[-1])


class TemporaryIndexDirMixin:
    def setUp(self):
        self.index_dir = tempfile.mkdtemp(prefix="ai_rag_test_index_")
        self.source_dir = tempfile.mkdtemp(prefix="ai_rag_test_source_")
        Path(self.source_dir, "note.md").write_text("Hello from a test note.\nSecond line.\n", encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.index_dir, ignore_errors=True)
        shutil.rmtree(self.source_dir, ignore_errors=True)


class IndexGuardrailTests(TemporaryIndexDirMixin, unittest.TestCase):
    def test_collection_id_is_required(self):
        with self.assertRaises(ValueError):
            RAG.index_collection({"indexDir": self.index_dir, "path": self.source_dir, "embeddingModel": "m"})

    def test_index_dir_is_required(self):
        with self.assertRaises(ValueError):
            RAG.index_collection({"collectionId": "c1", "path": self.source_dir, "embeddingModel": "m"})

    def test_the_entire_home_directory_is_refused(self):
        with self.assertRaises(ValueError) as ctx:
            RAG.index_collection({
                "collectionId": "c1", "indexDir": self.index_dir,
                "path": str(Path.home()), "embeddingModel": "m"
            })
        self.assertIn("home directory", str(ctx.exception))

    def test_a_sensitive_looking_path_is_refused(self):
        sensitive = Path(self.source_dir, ".ssh")
        sensitive.mkdir()
        with self.assertRaises(ValueError) as ctx:
            RAG.index_collection({
                "collectionId": "c1", "indexDir": self.index_dir,
                "path": str(sensitive), "embeddingModel": "m"
            })
        self.assertIn("credential", str(ctx.exception))

    def test_a_file_is_not_a_valid_root(self):
        with self.assertRaises(ValueError):
            RAG.index_collection({
                "collectionId": "c1", "indexDir": self.index_dir,
                "path": str(Path(self.source_dir, "note.md")), "embeddingModel": "m"
            })

    def test_embedding_model_is_required(self):
        with self.assertRaises(ValueError):
            RAG.index_collection({"collectionId": "c1", "indexDir": self.index_dir, "path": self.source_dir})

    def test_the_guardrails_reuse_ai_attach_not_a_second_judgement(self):
        # The whole point of sharing canonical_root/is_sensitive_path with
        # files_search is that indexing can never quietly disagree with it
        # about what is safe to read.
        body = body_between(RAG_SOURCE, "def index_collection(request: dict) -> None:", "\n\n\ndef load_collections")
        self.assertIn("ai_attach.canonical_root(", body)
        self.assertIn("ai_attach.is_sensitive_path(", body)


class IndexingProducesRealChunksTests(TemporaryIndexDirMixin, unittest.TestCase):
    def test_indexing_a_real_folder_embeds_and_writes_the_index_file(self):
        vectors = {"calls": 0}

        def fake_embed(url, model, texts):
            vectors["calls"] += 1
            return [[1.0, 0.0, 0.0] for _ in texts]

        with mock.patch.object(RAG, "ollama_embed", fake_embed):
            result = run_index({
                "collectionId": "c1", "indexDir": self.index_dir,
                "path": self.source_dir, "embeddingModel": "m"
            })
        self.assertEqual(result["event"], "done")
        self.assertEqual(result["filesIndexed"], 1)
        self.assertEqual(result["chunksTotal"], 1)
        self.assertGreater(vectors["calls"], 0)
        self.assertTrue(Path(self.index_dir, "c1.json").is_file())

    def test_reindexing_an_unchanged_file_reuses_it_without_re_embedding(self):
        with mock.patch.object(RAG, "ollama_embed", lambda url, model, texts: [[1.0, 0.0] for _ in texts]):
            run_index({"collectionId": "c1", "indexDir": self.index_dir, "path": self.source_dir, "embeddingModel": "m"})

        with mock.patch.object(RAG, "ollama_embed", mock.Mock(side_effect=AssertionError("must not re-embed an unchanged file"))):
            result = run_index({"collectionId": "c1", "indexDir": self.index_dir, "path": self.source_dir, "embeddingModel": "m"})
        self.assertEqual(result["filesReused"], 1)
        self.assertEqual(result["filesIndexed"], 0)


class ChunkingTests(unittest.TestCase):
    def test_short_content_is_still_one_chunk(self):
        chunks = RAG.chunk_lines(["one line"], chunk_chars=1200, overlap_lines=3, max_chunks=80)
        self.assertEqual(len(chunks), 1)
        self.assertEqual(chunks[0]["startLine"], 1)

    def test_chunks_overlap_so_a_boundary_fact_is_not_lost(self):
        lines = [f"line {i}" for i in range(200)]
        chunks = RAG.chunk_lines(lines, chunk_chars=50, overlap_lines=3, max_chunks=80)
        self.assertGreater(len(chunks), 1)
        for previous, current in zip(chunks, chunks[1:]):
            self.assertLess(current["startLine"], previous["endLine"] + 1)

    def test_max_chunks_is_a_hard_ceiling(self):
        lines = [f"line {i}" for i in range(10_000)]
        chunks = RAG.chunk_lines(lines, chunk_chars=10, overlap_lines=0, max_chunks=5)
        self.assertLessEqual(len(chunks), 5)

    def test_empty_content_yields_no_chunks(self):
        self.assertEqual(RAG.chunk_lines([], chunk_chars=1200, overlap_lines=3, max_chunks=80), [])


class NormalizeTests(unittest.TestCase):
    def test_a_vector_becomes_unit_length(self):
        result = RAG.normalize([3.0, 4.0])
        self.assertAlmostEqual(sum(c * c for c in result), 1.0, places=6)

    def test_a_zero_vector_is_returned_unchanged_rather_than_dividing_by_zero(self):
        self.assertEqual(RAG.normalize([0.0, 0.0, 0.0]), [0.0, 0.0, 0.0])


class SearchGuardrailTests(TemporaryIndexDirMixin, unittest.TestCase):
    def test_index_dir_is_required(self):
        with self.assertRaises(ValueError):
            RAG.run_search({"query": "q", "embeddingModel": "m"})

    def test_query_is_required(self):
        with self.assertRaises(ValueError):
            RAG.run_search({"indexDir": self.index_dir, "embeddingModel": "m"})

    def test_embedding_model_is_required(self):
        with self.assertRaises(ValueError):
            RAG.run_search({"indexDir": self.index_dir, "query": "q"})

    def test_no_collections_on_disk_is_an_empty_result_not_an_error(self):
        result = RAG.run_search({"indexDir": self.index_dir, "query": "q", "embeddingModel": "m"})
        self.assertEqual(result["results"], [])
        self.assertEqual(result["collectionsSearched"], 0)

    def test_the_result_limit_is_capped_even_if_a_huge_number_is_requested(self):
        with mock.patch.object(RAG, "ollama_embed", lambda url, model, texts: [[1.0, 0.0] for _ in texts]):
            run_index({"collectionId": "c1", "indexDir": self.index_dir, "path": self.source_dir, "embeddingModel": "m"})
            result = RAG.run_search({
                "indexDir": self.index_dir, "query": "q", "embeddingModel": "m",
                "limit": 999999
            })
        self.assertLessEqual(len(result["results"]), RAG.SEARCH_RESULT_HARD_CAP)

    def test_search_only_covers_the_named_collections_when_given(self):
        with mock.patch.object(RAG, "ollama_embed", lambda url, model, texts: [[1.0, 0.0] for _ in texts]):
            run_index({"collectionId": "c1", "indexDir": self.index_dir, "path": self.source_dir, "embeddingModel": "m"})
            result = RAG.run_search({
                "indexDir": self.index_dir, "query": "q", "embeddingModel": "m",
                "collectionIds": ["nope-does-not-exist"]
            })
        self.assertEqual(result["collectionsSearched"], 0)


class StatusAndDeleteTests(TemporaryIndexDirMixin, unittest.TestCase):
    def test_status_on_an_empty_index_dir_is_an_empty_list_not_an_error(self):
        result = RAG.run_status({"indexDir": self.index_dir})
        self.assertEqual(result["collections"], [])

    def test_status_on_a_missing_index_dir_is_also_not_an_error(self):
        result = RAG.run_status({"indexDir": str(Path(self.index_dir, "does-not-exist"))})
        self.assertEqual(result["collections"], [])

    def test_deleting_an_index_that_was_never_built_reports_no_deletion(self):
        result = RAG.run_delete({"indexDir": self.index_dir, "collectionId": "never-indexed"})
        self.assertFalse(result["deleted"])

    def test_deleting_requires_a_collection_id(self):
        with self.assertRaises(ValueError):
            RAG.run_delete({"indexDir": self.index_dir})

    def test_a_real_index_can_be_deleted(self):
        with mock.patch.object(RAG, "ollama_embed", lambda url, model, texts: [[1.0, 0.0] for _ in texts]):
            run_index({"collectionId": "c1", "indexDir": self.index_dir, "path": self.source_dir, "embeddingModel": "m"})
        result = RAG.run_delete({"indexDir": self.index_dir, "collectionId": "c1"})
        self.assertTrue(result["deleted"])
        self.assertFalse(Path(self.index_dir, "c1.json").exists())


class ConfigDefaultsAreOptInTests(unittest.TestCase):
    """Nothing is chunked, embedded, or indexed until the user adds a
    collection through Settings — the config must ship inert."""

    def test_rag_is_disabled_by_default(self):
        block = body_between(CONFIG_QML, "property JsonObject rag: JsonObject {", "\n                }")
        self.assertIn("property bool enabled: false", block)

    def test_no_embedding_model_is_assumed(self):
        block = body_between(CONFIG_QML, "property JsonObject rag: JsonObject {", "\n                }")
        self.assertIn('property string embeddingModel: ""', block)

    def test_collections_start_empty(self):
        block = body_between(CONFIG_QML, "property JsonObject rag: JsonObject {", "\n                }")
        self.assertIn("property list<var> collections: []", block)

    def test_collections_is_never_a_bare_var(self):
        # The documented JsonAdapter crash: a `var` list nested inside a
        # JsonObject corrupts memory on deserialization. list<var> is the
        # only safe shape for a nested array like this one.
        block = body_between(CONFIG_QML, "property JsonObject rag: JsonObject {", "\n                }")
        self.assertNotIn("property var collections", block)


class ServiceReadinessTests(unittest.TestCase):
    """`AiRagService.ready` is the single gate both the tool and the
    Settings page read; it must require all three preconditions."""

    def test_ready_requires_enabled_a_model_and_at_least_one_collection(self):
        line = next(line for line in RAG_SERVICE_QML.splitlines() if "readonly property bool ready:" in line)
        self.assertIn("root.enabled", line)
        self.assertIn("root.embeddingModel.length > 0", line)
        self.assertIn("root.hasCollections", line)


class StdinClosedAfterWriteTests(unittest.TestCase):
    """Regression: `ai_rag.py` reads stdin with `sys.stdin.read()`, which
    blocks until EOF, not until a newline. A `Process` left with
    `stdinEnabled: true` after `write()` hangs the helper forever — caught
    live across `status`, `index`, and the `rag_search` tool call, all of
    which share this exact pattern."""

    def test_ai_rag_py_reads_stdin_to_eof_not_a_line(self):
        # Pin the fact this helper needs the close-after-write discipline at
        # all: if it ever switches to readline(), these QML-side closes
        # become unnecessary rather than merely redundant.
        main_body = body_between(RAG_SOURCE, "def main() -> int:", "\n    call_id = request.get")
        self.assertIn("sys.stdin.read()", main_body)

    def test_status_process_closes_stdin_after_writing(self):
        fn = body_between(RAG_SERVICE_QML, "function refreshStatus() {", "\n\n    Process {\n        id: statusProc")
        self.assertIn("statusProc.stdinEnabled = true;", fn)
        self.assertIn("statusProc.write(", fn)
        self.assertIn("statusProc.stdinEnabled = false;", fn)
        self.assertLess(fn.index("statusProc.write("), fn.index("statusProc.stdinEnabled = false;"))

    def test_index_process_closes_stdin_after_writing(self):
        fn = body_between(RAG_SERVICE_QML, "function reindex(id: string) {", "\n\n    /** Kills an index run")
        self.assertIn("indexProc.stdinEnabled = true;", fn)
        self.assertIn("indexProc.write(", fn)
        self.assertIn("indexProc.stdinEnabled = false;", fn)
        self.assertLess(fn.index("indexProc.write("), fn.index("indexProc.stdinEnabled = false;"))

    def test_delete_process_closes_stdin_after_writing(self):
        fn = body_between(RAG_SERVICE_QML, "function deleteIndex(id: string) {", "\n\n    Process {\n        id: deleteProc")
        self.assertIn("deleteProc.stdinEnabled = true;", fn)
        self.assertIn("deleteProc.write(", fn)
        self.assertIn("deleteProc.stdinEnabled = false;", fn)
        self.assertLess(fn.index("deleteProc.write("), fn.index("deleteProc.stdinEnabled = false;"))

    def test_the_tool_call_process_closes_stdin_after_writing(self):
        fn = body_between(AI_QML, "function toolRagSearch(call: var): var {", "\n\n    Process {\n        id: ragToolProc")
        self.assertIn("ragToolProc.stdinEnabled = true;", fn)
        self.assertIn("ragToolProc.write(", fn)
        self.assertIn("ragToolProc.stdinEnabled = false;", fn)
        self.assertLess(fn.index("ragToolProc.write("), fn.index("ragToolProc.stdinEnabled = false;"))

    def test_every_process_re_enables_stdin_before_the_next_run(self):
        # These Process objects are static and reused across calls, unlike
        # AiGmailIntegration's fresh-per-request worker. Skipping the reset
        # means only the first call of the process's lifetime ever sends a
        # body; every later call writes to a channel already closed from the
        # previous run and the helper receives an empty request.
        for proc, fn_start, fn_end in (
            ("statusProc", "function refreshStatus() {", "\n\n    Process {\n        id: statusProc"),
            ("indexProc", "function reindex(id: string) {", "\n\n    /** Kills an index run"),
            ("deleteProc", "function deleteIndex(id: string) {", "\n\n    Process {\n        id: deleteProc"),
        ):
            with self.subTest(process=proc):
                fn = body_between(RAG_SERVICE_QML, fn_start, fn_end)
                enable_index = fn.index(f"{proc}.stdinEnabled = true;")
                run_index_ = fn.index(f"{proc}.running = true;")
                write_index = fn.index(f"{proc}.write(")
                self.assertLess(enable_index, run_index_)
                self.assertLess(run_index_, write_index)


class IntegrationAdapterTests(unittest.TestCase):
    """`AiRagIntegration` is a thin, stateless validator — it must refuse
    before building a request, never after."""

    def test_not_ready_is_refused_before_any_request_is_built(self):
        fn = body_between(RAG_INTEGRATION_QML, "function buildSearchRequest(args: var): var {", "\n    }")
        self.assertIn("if (!root.ready)", fn)
        self.assertIn("return { error:", fn)

    def test_an_empty_query_is_refused(self):
        fn = body_between(RAG_INTEGRATION_QML, "function buildSearchRequest(args: var): var {", "\n    }")
        self.assertIn("query.length === 0", fn)

    def test_limit_is_clamped_both_ways(self):
        fn = body_between(RAG_INTEGRATION_QML, "function buildSearchRequest(args: var): var {", "\n    }")
        self.assertIn("Math.max(1, Math.min(10,", fn)

    def test_unknown_collection_ids_are_dropped_not_rejected(self):
        # The model naming a collection deleted mid-conversation should
        # still search whatever remains, not fail the whole call.
        fn = body_between(RAG_INTEGRATION_QML, "function buildSearchRequest(args: var): var {", "\n    }")
        self.assertIn("knownIds.indexOf(id) >= 0", fn)
        self.assertNotIn("return { error", fn.split("requestedIds", 1)[1] if "requestedIds" in fn else fn)


class ToolRegistryTests(unittest.TestCase):
    def test_rag_search_is_local_read_only_and_never_networked(self):
        block = body_between(REGISTRY_QML, 'id: "rag_search",', "\n        },")
        self.assertIn('kind: "localRead"', block)
        self.assertIn('network: "never"', block)
        self.assertIn('idempotent: true', block)

    def test_rag_search_is_gated_behind_the_rag_service(self):
        block = body_between(REGISTRY_QML, 'id: "rag_search",', "\n        },")
        self.assertIn('requiredServices: ["rag"]', block)

    def test_the_service_gate_is_wired_to_the_integration_adapter(self):
        gate = body_between(
            (ROOT / "services" / "ai" / "AiTools.qml").read_text(encoding="utf-8"),
            "readonly property var serviceAvailability: ({", "\n        })",
        )
        self.assertIn("rag: Ai.ragIntegration.ready", gate)


class ResultStaysInTheTranscriptTests(unittest.TestCase):
    def test_rag_results_are_a_kept_result_card_not_a_transient_one(self):
        # Matches fileResults/taskResults/settingsResults: a retrieval hit is
        # the point of the call, so it must not disappear once done, the
        # same way a search engine's results page does not.
        self.assertIn('"ragResults"', body_between(AI_QML, "readonly property var resultCardKinds:", "\n"))


class StopGenerationCancelsRagSearchTests(unittest.TestCase):
    def test_stopping_generation_also_cancels_an_in_flight_rag_search(self):
        stop = body_between(AI_QML, "function stopGeneration(): bool {", "\n    /**\n     * Sends the next turn")
        self.assertIn("if (ragToolProc.running)", stop)
        self.assertIn("ragToolProc.running = false;", stop)


if __name__ == "__main__":
    unittest.main()
