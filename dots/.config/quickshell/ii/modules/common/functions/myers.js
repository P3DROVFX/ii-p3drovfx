// Bit-parallel approximate string matching — Myers (1999).
// Time: O(n · ⌈m/WORD_SIZE⌉) after prepare(); O(n) for typical short queries.
//
// Ported from end-4/dots-hyprland#3447, with a word-aware scorer added on top
// (see scoreBest) because whole-string edit distance buries the one word a
// query is actually aimed at under the length of everything around it.

// 30, not 32: JS bitwise ops work on signed 32-bit integers, so
// (1 << 31) = -2147483648 and (1 << 32) wraps to 1. 30 keeps all
// mask values positive and avoids sign-bit surprises throughout.
const WORD_SIZE = 30;

// ─── Normalization ────────────────────────────────────────────────────────────

// Single normalization function used by every public API.
// NFC composes canonically equivalent sequences so "é" and "é"
// use the same representation and hash to the same character in Peq.
// Guard against older Qt/QML runtimes where String.normalize may be absent.
function normalize(value) {
    const str = String(value == null ? "" : value).toLowerCase();
    return typeof str.normalize === "function" ? str.normalize("NFC") : str;
}

// ─── Public API ───────────────────────────────────────────────────────────────

// Precompute equality bitmasks for a pattern.
// Call once per query; reuse the result across all candidate comparisons.
function prepare(pattern) {
    const norm = normalize(pattern);
    const m = norm.length;
    if (m === 0)
        return { Peq: [], m: 0, words: 0, text: "" };

    const words = Math.ceil(m / WORD_SIZE);
    const Peq = new Array(words);
    for (let w = 0; w < words; w++) Peq[w] = Object.create(null);

    for (let i = 0; i < m; i++) {
        const c = norm[i];
        const w = (i / WORD_SIZE) | 0;
        Peq[w][c] = (Peq[w][c] | 0) | (1 << (i % WORD_SIZE));
    }

    return { Peq, m, words, text: norm };
}

// Raw edit distance. text must already be normalized.
// Keeping normalization out of the hot path lets callers normalize once per batch.
// Use distance() or score() if you want automatic normalization.
function distanceNormalized(prepared, text) {
    const Peq = prepared.Peq, m = prepared.m, words = prepared.words;
    const n = text.length;
    if (m === 0) return n;
    if (n === 0) return m;
    return words === 1
        ? _distSingle(Peq[0], m, text, n)
        : _distMulti(Peq, m, words, text, n);
}

// Edit distance with automatic text normalization. Safe to call with any string.
function distance(prepared, text) {
    return distanceNormalized(prepared, normalize(text));
}

// Normalized similarity in [0, 1]. 1 = identical, 0 = completely different.
function scoreNormalized(prepared, normText) {
    const maxLen = Math.max(prepared.m, normText.length);
    if (maxLen === 0) return 1.0;
    return 1.0 - distanceNormalized(prepared, normText) / maxLen;
}

function score(prepared, text) {
    return scoreNormalized(prepared, normalize(text));
}

/**
 * Best similarity across the whole text and each of its words.
 *
 * A query is normally aimed at one word of a name — "vscdoe" at the "Code" in
 * "Visual Studio Code" — and whole-string edit distance charges it for every
 * character of the rest, so the right answer scores no better than a dozen
 * unrelated names of similar length. Scoring the words too, and keeping the
 * best, is what makes the tier rank rather than merely match.
 *
 * A word only competes when it is at least as long as the pattern minus its
 * error budget; otherwise short words win by being short.
 */
function scoreBestNormalized(prepared, normText) {
    let best = scoreNormalized(prepared, normText);
    if (prepared.m === 0 || normText.length <= prepared.m)
        return best;

    const words = normText.split(/[\s\-_./\\]+/);
    if (words.length < 2)
        return best;

    const shortest = Math.max(1, prepared.m - 2);
    for (let i = 0; i < words.length; i++) {
        const word = words[i];
        if (word.length < shortest)
            continue;
        const wordScore = scoreNormalized(prepared, word);
        if (wordScore > best)
            best = wordScore;
    }
    return best;
}

function scoreBest(prepared, text) {
    return scoreBestNormalized(prepared, normalize(text));
}

// One-off score without a separate prepare() call.
function computeScore(pattern, text) {
    return score(prepare(pattern), text);
}

// Drop-in replacement for levendist.js computeTextMatchScore.
function computeTextMatchScore(s1, s2) {
    return computeScore(s1, s2);
}

// Rank candidates by descending similarity.
// opts.key       — property name to extract text from each candidate (null = use candidate directly)
// opts.threshold — minimum score to include; results with score <= threshold are dropped.
//                  Uses > not >= so threshold=0 means "include anything with a positive score."
// opts.limit     — maximum number of results.
// opts.wordAware — score words as well as the whole text (default true).
function search(prepared, candidates, opts) {
    const key = opts != null ? opts.key : null;
    const threshold = opts != null && opts.threshold != null ? opts.threshold : 0;
    const limit = opts != null && opts.limit != null ? opts.limit : -1;
    const wordAware = opts == null || opts.wordAware !== false;
    const len = candidates.length;
    const results = [];

    for (let i = 0; i < len; i++) {
        const c = candidates[i];
        const raw = key != null ? c[key] : c;
        const normText = normalize(raw);
        const s = wordAware ? scoreBestNormalized(prepared, normText) : scoreNormalized(prepared, normText);
        if (s > threshold) results.push({ item: c, s: s, i: i });
    }

    // Secondary sort by original index keeps equal-score results stable
    // so the list doesn't visually shuffle between keystrokes.
    results.sort((a, b) => (b.s - a.s) || (a.i - b.i));

    const count = limit >= 0 ? Math.min(limit, results.length) : results.length;
    const out = new Array(count);
    for (let i = 0; i < count; i++) out[i] = results[i].item;
    return out;
}

// ─── Single-word Myers  (m ≤ WORD_SIZE = 30) ─────────────────────────────────

function _distSingle(peq, m, text, n) {
    const FULL = (1 << m) - 1;
    const TOP = 1 << (m - 1);
    let Pv = FULL, Mv = 0, score = m;

    for (let j = 0; j < n; j++) {
        const Eq = peq[text[j]] | 0;
        const Xv = Eq | Mv;
        const Xh = (((Eq & Pv) + Pv) ^ Pv) | Eq;

        let Ph = (Mv | ~(Xh | Pv)) & FULL;
        let Mh = Pv & Xh & FULL;

        if (Ph & TOP) score++;
        if (Mh & TOP) score--;

        Ph = ((Ph << 1) | 1) & FULL;
        Mh = (Mh << 1) & FULL;

        Pv = (Mh | ~(Xv | Ph)) & FULL;
        Mv = Ph & Xv & FULL;
    }

    return score;
}

// ─── Multi-word Myers  (m > WORD_SIZE) ───────────────────────────────────────
//
// Shared scratch buffers to avoid per-call allocation.
// Safe for synchronous JS; do not call re-entrantly (e.g. from a callback inside distance()).

let _sharedPv = new Int32Array(16);
let _sharedMv = new Int32Array(16);
let _sharedFull = new Int32Array(16);

function _distMulti(Peq, m, words, text, n) {
    const lastBits = m % WORD_SIZE || WORD_SIZE;

    if (words > _sharedPv.length) {
        const newSize = Math.max(words, _sharedPv.length * 2);
        _sharedPv = new Int32Array(newSize);
        _sharedMv = new Int32Array(newSize);
        _sharedFull = new Int32Array(newSize);
    }

    for (let w = 0; w < words - 1; w++) _sharedFull[w] = (1 << WORD_SIZE) - 1;
    _sharedFull[words - 1] = (1 << lastBits) - 1;

    const LAST_TOP = 1 << (lastBits - 1);

    for (let w = 0; w < words; w++) {
        _sharedPv[w] = _sharedFull[w];
        _sharedMv[w] = 0;
    }

    let score = m;

    for (let j = 0; j < n; j++) {
        const c = text[j];
        let addCarry = 0, phCarry = 1, mhCarry = 0;

        for (let w = 0; w < words; w++) {
            const fw = _sharedFull[w];
            const Eq = Peq[w][c] | 0;
            const Xv = (Eq | _sharedMv[w]) & fw;

            const sumBig = (Eq & _sharedPv[w]) + _sharedPv[w] + addCarry;
            addCarry = sumBig > fw ? 1 : 0;

            const Xh = (((sumBig & fw) ^ _sharedPv[w]) | Eq) & fw;

            let Ph = (_sharedMv[w] | ~(Xh | _sharedPv[w])) & fw;
            let Mh = _sharedPv[w] & Xh & fw;

            if (w === words - 1) {
                if (Ph & LAST_TOP) score++;
                if (Mh & LAST_TOP) score--;
            }

            const phTop = (Ph >>> (WORD_SIZE - 1)) & 1;
            const mhTop = (Mh >>> (WORD_SIZE - 1)) & 1;

            Ph = ((Ph << 1) | phCarry) & fw;
            Mh = ((Mh << 1) | mhCarry) & fw;

            phCarry = phTop;
            mhCarry = mhTop;

            _sharedPv[w] = (Mh | ~(Xv | Ph)) & fw;
            _sharedMv[w] = Ph & Xv & fw;
        }
    }

    return score;
}
