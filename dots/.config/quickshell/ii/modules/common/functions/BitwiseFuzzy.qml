pragma Singleton
import Quickshell
import "myers.js" as Myers

/**
 * Bit-parallel fuzzy matching helpers (Myers 1999).
 *
 * Wrapper so myers.js can be reached through Quickshell's singleton imports,
 * the same arrangement Levendist uses for levendist.js.
 */
Singleton {
    /** Lowercase + NFC normalize a string. Same transform applied internally by prepare() and score(). */
    function normalize(value) {
        return Myers.normalize(value);
    }

    /** Precompute pattern state for reuse across comparisons. */
    function prepare(pattern) {
        return Myers.prepare(pattern);
    }

    /** Levenshtein edit distance. Normalizes text automatically. */
    function distance(prepared, text) {
        return Myers.distance(prepared, text);
    }

    /** Normalized similarity in [0, 1] against the whole text. */
    function score(prepared, text) {
        return Myers.score(prepared, text);
    }

    /** Best similarity across the whole text and each of its words. */
    function scoreBest(prepared, text) {
        return Myers.scoreBest(prepared, text);
    }

    /** Compute one-off similarity without prepare(). */
    function computeScore(pattern, text) {
        return Myers.computeScore(pattern, text);
    }

    /** Compatibility wrapper for Levendist.computeTextMatchScore. */
    function computeTextMatchScore(s1, s2) {
        return Myers.computeTextMatchScore(s1, s2);
    }

    /**
     * Candidates sorted by descending similarity.
     * opts: { key?: string, threshold?: number, limit?: number, wordAware?: bool }
     */
    function search(prepared, candidates, opts) {
        return Myers.search(prepared, candidates, opts);
    }
}
