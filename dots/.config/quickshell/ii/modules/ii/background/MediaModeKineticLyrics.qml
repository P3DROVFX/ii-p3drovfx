pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.services

// Kinetic typography for word-timed lyrics (BetterLyrics, lrcmux or NetEase), Immersive only.
//
// Every line is set as a block. Most blocks are stacked rows, each fitted to the
// block's width, so short words come out huge and long ones flat; some put the first
// word on its side as a column; some scatter the words down a staircase, each at its
// own size and angle. Rows take their weight/width/slant from a small set of styles,
// filler words ride small, and a word that is held long is set at the widest width.
// Words slam in when they are sung. All geometry is measured in JS (`layoutLine`),
// so blocks are placed with their real size before they exist.
//
// The blocks sit on a 2D plane, one after another along a path that turns and rolls,
// and a spring camera follows the word being sung: it pushes in on it, travels to the
// next line, and rolls with the path. The layer is smeared along the camera's motion
// and casts a soft shadow, optionally through a fisheye (shaders/kineticCamera.frag).
//
// Axes are never animated: every distinct wght/wdth is a new font face in memory.
Item {
    id: root

    property var player: null
    property color textColor: "white"
    property color shadowColor: Qt.rgba(0, 0, 0, 0.5)
    // The key word of each line, once sung.
    property color accentColor: textColor
    // What the words are painted with: never dark or see-through, whatever comes in
    // (a dark extracted colour would leave black words on the dimmed artwork).
    function legible(c) {
        const q = Qt.color(c);
        return Qt.hsla(Math.max(0, q.hslHue), q.hslSaturation, Math.max(0.68, q.hslLightness), 1);
    }
    readonly property color textInk: legible(textColor)
    readonly property color accentInk: legible(accentColor)
    property real fontScale: 1
    // Part of the screen kept clear at the bottom-left for the title and transport.
    property real bottomInset: 0
    // Barrel lens over the whole type layer, 0 for none.
    property real fisheye: 0

    // Overridable for previews; normally the lyrics service.
    property var lines: LyricsService.syncedLines
    property int currentIndex: LyricsService.currentIndex
    property bool playing: player?.isPlaying ?? false
    readonly property real rate: Math.max(0.25, player?.rate ?? 1)

    // World units: every block is this wide; the camera zoom maps it to pixels.
    readonly property real blockWidth: 1000
    readonly property real referenceSize: 100
    readonly property string fontFamily: Appearance.font.family.title

    // Scripts ------------------------------------------------------------------
    // The title font (Google Sans Flex) only covers Latin. Anything else would fall
    // back glyph by glyph inside Qt, with the flex axes (ROND above all) forced onto a
    // font that lacks them, and measured with the wrong metrics. So each line picks one
    // face for all its words: Roboto Flex for Greek/Cyrillic when installed (every axis
    // but ROND), Noto Sans CJK for CJK (wght only), Noto Sans otherwise. Axes a face
    // lacks are dropped; a missing wdth is approximated with a horizontal scale.
    readonly property var _families: Qt.fontFamilies()
    readonly property bool hasRobotoFlex: _families.indexOf("Roboto Flex") >= 0
    function scriptOf(text) {
        if (/[぀-ヿㇰ-ㇿ]/.test(text))
            return "ja";
        if (/[ᄀ-ᇿ㄰-㆏가-힯]/.test(text))
            return "ko";
        if (/[㐀-䶿一-鿿豈-﫿]/.test(text))
            return "zh";
        if (/[Ͱ-Ͽἀ-῿Ѐ-ԯᲀ-᲏ⷠ-ⷿꙀ-ꚟ]/.test(text))
            return "cyrillic";
        if (/[^\u0000-ɏ̀-ͯḀ-ỿ -⁯₠-⃏\s]/.test(text.replace(/[\p{P}\p{S}\p{N}]/gu, "")))
            return "other";
        return "latin";
    }
    function isCjk(script) {
        return script === "ja" || script === "ko" || script === "zh";
    }
    function faceFor(script, axes) {
        if (script === "latin")
            return { "family": root.fontFamily, "axes": axes, "weight": 0, "italic": false, "stretch": 1 };
        const synthetic = { "weight": 0, "italic": false, "stretch": 0.62 + 0.38 * (axes.wdth / 100) };
        if (script === "cyrillic" && root.hasRobotoFlex)
            return { "family": "Roboto Flex", "axes": { "wght": Math.max(100, axes.wght), "wdth": axes.wdth,
                     "slnt": axes.slnt, "opsz": axes.opsz }, "weight": 0, "italic": false, "stretch": 1 };
        if (root.isCjk(script))
            return Object.assign(synthetic, { "axes": { "wght": Math.max(100, Math.min(900, axes.wght)) },
                "family": script === "ja" ? "Noto Sans CJK JP" : (script === "ko" ? "Noto Sans CJK KR" : "Noto Sans CJK SC") });
        // Static fallback: weight picks the nearest instance, slant becomes oblique.
        return Object.assign(synthetic, { "family": "Noto Sans", "axes": ({}),
            "weight": Math.max(100, Math.min(900, Math.round(axes.wght / 100) * 100)), "italic": axes.slnt < 0 });
    }

    // Clock --------------------------------------------------------------------
    // MPRIS positions arrive rarely; between them the clock runs on its own and
    // each fresh position nudges it instead of snapping, so the camera never jerks.
    property real clock: 0
    property real _anchorPosition: 0
    property double _anchorMs: Date.now()
    property real syncPosition: LyricsService.syncPosition

    function estimatedPosition() {
        return root.playing ? root._anchorPosition + (Date.now() - root._anchorMs) / 1000 * root.rate
                            : root._anchorPosition;
    }
    function reanchor(hard) {
        const estimate = root.estimatedPosition();
        const target = root.syncPosition;
        root._anchorPosition = hard || Math.abs(target - estimate) > 0.3 ? target : estimate + (target - estimate) * 0.35;
        root._anchorMs = Date.now();
        root.clock = root._anchorPosition;
    }
    onSyncPositionChanged: reanchor(false)
    // An offset change is a deliberate jump, often smaller than the soft-nudge
    // threshold; apply it at once (after syncPosition has picked it up).
    readonly property int offsetMs: Config.options.background.mediaMode.lyricsOffsetMs ?? 0
    onOffsetMsChanged: Qt.callLater(root.reanchor, true)
    onPlayingChanged: reanchor(true)
    Component.onCompleted: {
        reanchor(true);
        Qt.callLater(rebuild);
    }

    // Layout -------------------------------------------------------------------
    readonly property var fillerWords: ["a", "an", "the", "of", "to", "in", "on", "and", "or", "but", "i", "i'm",
        "im", "it", "it's", "is", "my", "me", "you", "we", "be", "so", "at", "for", "as", "by", "oh", "your",
        "our", "with", "de", "da", "do", "e", "o", "os", "as", "que", "se", "em", "no", "na", "um", "uma", "eu",
        "te", "y", "el", "la", "en", "lo", "les", "le", "et", "un", "une", "je", "tu"]

    // Each style is a fixed set of axes. A handful of styles (and the one wide variant
    // of each for held words) keeps the number of font faces small.
    readonly property var rowStyles: ({
        "heavy": { "wght": 900, "wdth": 100, "slnt": 0, "ROND": 0, "opsz": 144 },
        // Lowercase bold, the mosaic's voice.
        "bold": { "wght": 800, "wdth": 100, "slnt": 0, "ROND": 0, "opsz": 144 },
        "condensed": { "wght": 820, "wdth": 35, "slnt": 0, "ROND": 0, "opsz": 144 },
        "wide": { "wght": 1000, "wdth": 151, "slnt": 0, "ROND": 0, "opsz": 144 },
        "thin": { "wght": 200, "wdth": 125, "slnt": -10, "ROND": 0, "opsz": 144 },
        "whisper": { "wght": 500, "wdth": 110, "slnt": -10, "ROND": 100, "opsz": 144 }
    })
    readonly property var styleCycle: ["heavy", "condensed", "wide", "heavy", "thin", "condensed", "wide"]
    readonly property real maxRowCapHeight: blockWidth * 0.4
    readonly property real whisperCapHeight: blockWidth * 0.075
    readonly property real rowGap: blockWidth * 0.035
    // Column composition: one word turned on its side along the block's left edge.
    readonly property real sideWidth: blockWidth * 0.22
    readonly property real sideGap: blockWidth * 0.04
    // Held words are measured against the song's own pace, per syllable: a 1 s word
    // is held in a rap verse but not in a ballad, and "everything" over 1 s is not held
    // while "who" is. `_songPace` is the median seconds per syllable of the whole song.
    property real _songPace: 0.25
    function syllables(word) {
        const bare = word.text.toLowerCase().replace(/[^\p{L}]/gu, "");
        if (root.isCjk(word.script))
            return Math.max(1, bare.length);
        const groups = (bare.length > 3 ? bare.replace(/e$/, "") : bare)
            .match(/[aeiouyàáâãäåæèéêëìíîïòóôõöøùúûüýÿąęıœăạảấầẩẫậắằẳẵặẹẻẽếềểễệỉịọỏốồổỗộớờởỡợụủứừửữựỳỵỷỹαεηιουωάέήίόύώаеёиоуыэюяіїє]+/g);
        return Math.max(1, groups ? groups.length : 1);
    }
    function isHeld(word) {
        const d = word.end - word.begin;
        const perSyllable = d / root.syllables(word);
        return (d >= 0.55 && perSyllable >= Math.max(0.42, root._songPace * 2.2))
            || (d >= 1.6 && perSyllable >= root._songPace * 1.5);
    }
    function measurePace() {
        const paces = [];
        for (const line of root.lines) {
            for (const word of root.lineWords(line)) {
                const d = word.end - word.begin;
                if (d > 0.02 && d < 4)
                    paces.push(d / root.syllables(word));
            }
        }
        paces.sort((a, b) => a - b);
        root._songPace = paces.length >= 8 ? paces[Math.floor(paces.length / 2)] : 0.25;
    }
    // Lines closer together than this belong to one stanza; a stanza is one composition
    // the camera pulls back to show whole once it has been sung.
    readonly property real stanzaGapSeconds: 2.2
    readonly property int stanzaMaximumLines: 6

    function hash(n) {
        let x = Math.imul(n ^ 0x9e3779b9, 0x85ebca6b);
        x ^= x >>> 13;
        x = Math.imul(x, 0xc2b2ae35);
        x ^= x >>> 16;
        return (x >>> 0) / 4294967296;
    }

    // Filler rides small (whisper rows, thin scatter, stacked pairs). A held word never
    // does, whatever its length: "oh" sung for two seconds is the loudest thing in the
    // line. CJK has no word-length signal, so it has no filler.
    function isFiller(word) {
        if (word.held || root.isCjk(word.script))
            return false;
        const bare = word.text.toLowerCase().replace(/[^\p{L}\p{N}']/gu, "");
        return bare.length <= 2 || root.fillerWords.indexOf(bare) >= 0;
    }

    function caseFor(style, text) {
        return style === "thin" || style === "whisper" || style === "bold" ? text.toLowerCase() : text.toUpperCase();
    }

    // Measuring: one TextMetrics, retargeted synchronously, results cached per face.
    property var _measureFace: ({ "family": root.fontFamily, "axes": ({}), "weight": 0, "italic": false, "stretch": 1 })
    property string _measureText: ""
    property var _measureCache: ({})
    TextMetrics {
        id: measurer
        font.family: root._measureFace.family
        font.pixelSize: root.referenceSize
        font.variableAxes: root._measureFace.axes
        font.weight: root._measureFace.weight > 0 ? root._measureFace.weight : Font.Normal
        font.italic: root._measureFace.italic
        text: root._measureText
    }
    function measure(text, face) {
        const key = JSON.stringify(face) + "|" + text;
        const cached = root._measureCache[key];
        if (cached)
            return cached;
        root._measureFace = face;
        root._measureText = text;
        const rect = measurer.tightBoundingRect;
        const result = { "advance": measurer.advanceWidth * face.stretch, "top": rect.y, "bottom": rect.y + rect.height };
        if (result.advance > 0)
            root._measureCache[key] = result;
        return result;
    }

    // Spans can be syllables ("romp" + "er", "brand-" + "new"), and older cache
    // entries carry no trailingSpace. Word boundaries come from the line text: a span
    // starts a new word only when whitespace separates it from the previous one. A
    // merged word runs from its first span's start to its last span's end.
    function lineWords(line) {
        const text = line?.text ?? "";
        const words = [];
        const script = root.scriptOf(text);
        const cjk = root.isCjk(script);
        let open = null;
        let cursor = 0;
        for (const span of (line?.words ?? [])) {
            const spanText = (span.text ?? "").trim();
            if (!spanText)
                continue;
            const begin = span.begin ?? span.startTime ?? 0;
            const end = span.end ?? span.endTime ?? begin + 0.3;
            const found = text.indexOf(spanText, cursor);
            // CJK is written without spaces: every span (a character or a phrase) is a word.
            const joined = open && !cjk && (found >= 0 ? !/\s/.test(text.slice(cursor, found))
                                                      : (open.trailingSpace ?? " ").length === 0);
            if (found >= 0)
                cursor = found + spanText.length;
            if (joined) {
                open.text += spanText;
                open.end = Math.max(open.end, end);
                open.trailingSpace = span.trailingSpace;
            } else {
                open = { "text": spanText, "begin": begin, "end": end, "trailingSpace": span.trailingSpace,
                         "script": script };
                words.push(open);
            }
        }
        return words;
    }

    // A piece is a run of words on one baseline, fitted by a single scale. `fit`
    // maps reference-size glyphs to world units; word x offsets are in reference units.
    // With `fixedCap` the piece is sized by the font's cap height (an "H"), so words of
    // one size share a baseline and descenders hang below it; otherwise by its own
    // ink, fitted into `length` × `thickness`.
    function makePiece(words, style, length, thickness, fixedCap) {
        const script = words[0]?.script ?? "latin";
        const axes = root.rowStyles[style];
        const base = root.faceFor(script, axes);
        // Held words are set at the widest width, in the row's own weight.
        const wide = root.faceFor(script, Object.assign({}, axes, { "wdth": 151 }));
        const space = root.isCjk(script) ? 0 : root.measure(" ", base).advance;
        let x = 0, top = 0, bottom = 0;
        const shown = [];
        for (let i = 0; i < words.length; i++) {
            const word = words[i];
            const face = word.held && style !== "whisper" ? wide : base;
            const text = root.caseFor(style, word.text);
            const m = root.measure(text, face);
            if (i > 0)
                x += space;
            shown.push({ "text": text, "face": face, "x": x, "advance": m.advance, "begin": word.begin,
                         "end": word.end, "accent": word.accent ?? false, "reveal": word.reveal ?? "pop" });
            x += m.advance;
            top = Math.min(top, m.top);
            bottom = Math.max(bottom, m.bottom);
        }
        if (fixedCap > 0) {
            // CJK ideographs fill the em box, well above a Latin cap height.
            const cap = root.measure(root.isCjk(script) ? "\u56fd" : "H", base);
            const fit = fixedCap / Math.max(1, cap.bottom - cap.top);
            return { "words": shown, "style": style, "capTop": cap.top, "fit": fit, "width": x * fit,
                     "height": fixedCap, "x": 0, "y": 0, "rotation": 0 };
        }
        const capHeight = Math.max(1, bottom - top);
        const fit = Math.min(length / Math.max(1, x), thickness / capHeight);
        return { "words": shown, "style": style, "capTop": top, "fit": fit, "width": x * fit,
                 "height": capHeight * fit, "x": 0, "y": 0, "rotation": 0 };
    }

    function layoutLine(lineIndex) {
        const words = root.lineWords(root.lines[lineIndex]);
        if (words.length === 0)
            return { "pieces": [], "width": root.blockWidth, "height": root.blockWidth * 0.2 };

        // Held words, and the key word (the longest one that is not filler).
        for (const word of words)
            word.held = root.isHeld(word);
        let key = null;
        const keyLength = root.isCjk(words[0].script) ? 2 : 4;
        for (const word of words) {
            if (!root.isFiller(word) && word.text.length >= keyLength && (!key || word.text.length > key.text.length))
                key = word;
        }
        // A held word outranks a merely long one.
        const heldKey = words.filter(w => w.held).sort((a, b) => (b.end - b.begin) - (a.end - a.begin))[0];
        if (heldKey)
            key = heldKey;
        if (key)
            key.key = true;
        // Two inks: the key word and about a third of the other content words take the
        // accent, never two filler words in a row.
        for (let i = 0; i < words.length; i++) {
            const word = words[i];
            word.accent = word.key || (!root.isFiller(word) && root.hash(lineIndex * 71 + i) < 0.32);
            // How the word lands: slam in, rise out of its own baseline, or slide in.
            const r = root.hash(lineIndex * 191 + i * 7 + 1);
            word.reveal = r < 0.4 ? "pop" : (r < 0.75 ? "rise" : "slide");
        }

        // Sung words per second. Fast lines (rap, patter) are set as mosaics and framed
        // whole; slow, sparse lines get the scatter and column compositions and a camera
        // that pushes in on each word.
        const span = Math.max(0.3, words[words.length - 1].end - words[0].begin);
        const pace = words.length / span;
        const fast = pace >= 3.2;
        const pick = root.hash(lineIndex * 389 + 5);
        let layout;
        if (!fast && words.length >= 2 && words.length <= 5 && pick > (pace < 1.6 ? 0.7 : 0.85))
            layout = root.layoutScatter(lineIndex, words);
        else if (pick < (fast ? 0.85 : 0.62))
            layout = root.layoutMosaic(lineIndex, words);
        else
            layout = root.layoutStack(lineIndex, words, fast ? 1 : (pick - 0.62) / 0.23);
        layout.pace = pace;
        return layout;
    }

    // Stacked rows, sometimes with the first word as a column on the left.
    function layoutStack(lineIndex, words, pick) {
        const rows = [];
        let row = null;
        for (const word of words) {
            const filler = root.isFiller(word);
            const chars = row ? row.words.reduce((n, w) => n + w.text.length + 1, 0) : 0;
            if (row && row.open && chars + word.text.length <= 14) {
                row.words.push(word);
                row.open = filler && row.words.length < 3;
                row.fillerOnly = row.fillerOnly && filler;
            } else {
                row = { "words": [word], "open": filler, "fillerOnly": filler };
                rows.push(row);
            }
        }

        const first = rows[0];
        const side = rows.length >= 3 && pick < 0.38 && first.words.length === 1 && !first.fillerOnly
            && first.words[0].text.length >= 3 && first.words[0].text.length <= 10;
        if (side)
            rows.shift();
        const left = side ? root.sideWidth + root.sideGap : 0;
        const rowWidth = root.blockWidth - left;

        const pieces = [];
        let y = 0;
        let cycle = Math.floor(root.hash(lineIndex * 131 + 7) * root.styleCycle.length);
        for (let r = 0; r < rows.length; r++) {
            const whisper = rows[r].fillerOnly && rows.length > 1;
            const style = whisper ? "whisper" : root.styleCycle[cycle++ % root.styleCycle.length];
            const piece = root.makePiece(rows[r].words, style, rowWidth, root.maxRowCapHeight,
                                         whisper ? root.whisperCapHeight : 0);
            const align = whisper ? (root.hash(lineIndex * 17 + r) < 0.5 ? 0 : 1) : 0.5;
            piece.x = left + (rowWidth - piece.width) * align;
            piece.y = y;
            y += piece.height + root.rowGap;
            pieces.push(piece);
        }
        const stackHeight = Math.max(0, y - root.rowGap);

        if (side) {
            // Turned to read bottom to top, as long as the stack is tall.
            const piece = root.makePiece(first.words, root.hash(lineIndex * 7) < 0.5 ? "condensed" : "heavy",
                                         stackHeight, root.sideWidth, 0);
            piece.rotation = -90;
            piece.x = (root.sideWidth - piece.height) / 2;
            piece.y = stackHeight / 2 + piece.width / 2;
            pieces.push(piece);
        }
        return { "pieces": pieces, "width": root.blockWidth, "height": Math.max(stackHeight, root.blockWidth * 0.2) };
    }

    // Words of very different sizes packed into justified rows on shared baselines.
    // Big words take the full row height, others a share of it, and two small words
    // in a row stack on top of each other beside the big ones ("this / can be").
    function layoutMosaic(lineIndex, words) {
        const unit = 100; // provisional row height; every row is scaled to the block width
        const style = root.hash(lineIndex * 43 + 9) < 0.65 ? "bold" : "heavy";
        const small = w => !w.held && (root.isFiller(w) || w.text.length <= (root.isCjk(w.script) ? 1 : 3));
        const items = [];
        for (let i = 0; i < words.length; i++) {
            const word = words[i];
            if (small(word) && !word.held && i + 1 < words.length && small(words[i + 1]) && !words[i + 1].held) {
                const top = root.makePiece([word], style, 0, 0, unit * 0.42);
                const bottom = root.makePiece([words[i + 1]], style, 0, 0, unit * 0.42);
                items.push({ "pieces": [top, bottom], "width": Math.max(top.width, bottom.width), "stack": true });
                i++;
                continue;
            }
            const big = word.key || word.held || (!small(word) && root.hash(lineIndex * 23 + i) < 0.45);
            const cap = big ? unit : (small(word) ? unit * 0.42 : unit * 0.62);
            const piece = root.makePiece([word], style, 0, 0, cap);
            items.push({ "pieces": [piece], "width": piece.width, "stack": false });
        }

        const gap = unit * 0.07;
        const maxRow = unit * 5.2;
        const rows = [];
        let row = null;
        for (const item of items) {
            if (row && row.width + gap + item.width > maxRow) {
                rows.push(row);
                row = null;
            }
            if (!row)
                row = { "items": [], "width": -gap };
            row.items.push(item);
            row.width += gap + item.width;
        }
        if (row)
            rows.push(row);

        const pieces = [];
        let y = 0;
        let lastHeight = 0;
        for (const r of rows) {
            const scale = Math.min(root.blockWidth / Math.max(1, r.width), root.blockWidth * 0.5 / unit);
            const height = unit * scale;
            let x = (root.blockWidth - r.width * scale) / 2;
            for (const item of r.items) {
                for (let k = 0; k < item.pieces.length; k++) {
                    const piece = item.pieces[k];
                    piece.fit *= scale;
                    piece.width *= scale;
                    piece.height *= scale;
                    piece.x = x;
                    // Everything sits on the row's baseline; a stack's top word hangs from the top.
                    piece.y = item.stack && k === 0 ? y : y + height - piece.height;
                    pieces.push(piece);
                }
                x += (item.width + gap) * scale;
            }
            y += height * 1.12;
            lastHeight = height;
        }
        return { "pieces": pieces, "width": root.blockWidth, "height": Math.max(1, y - lastHeight * 0.12) };
    }

    // Words thrown down a staircase, each at its own size and angle.
    function layoutScatter(lineIndex, words) {
        const pieces = [];
        let x = 0, y = 0;
        let cycle = Math.floor(root.hash(lineIndex * 61 + 3) * 3);
        for (let i = 0; i < words.length; i++) {
            const word = words[i];
            const filler = root.isFiller(word);
            const style = filler ? "thin" : (word.key ? "wide" : ["heavy", "condensed", "heavy"][cycle++ % 3]);
            const cap = root.blockWidth * (word.key ? 0.3 : (filler ? 0.1 : 0.18)) * (0.85 + 0.3 * root.hash(lineIndex * 13 + i));
            const piece = root.makePiece([word], style, root.blockWidth * 0.95, 0, cap);
            if (piece.width > root.blockWidth * 0.95) {
                const shrink = root.blockWidth * 0.95 / piece.width;
                piece.fit *= shrink;
                piece.width *= shrink;
                piece.height *= shrink;
            }
            if (i > 0) {
                const previous = pieces[i - 1];
                x = previous.x + previous.width * (0.3 + 0.3 * root.hash(lineIndex * 29 + i));
                y = previous.y + previous.height + root.blockWidth * 0.02;
            }
            piece.x = x;
            piece.y = y;
            piece.rotation = (root.hash(lineIndex * 47 + i) - 0.5) * 18;
            pieces.push(piece);
        }
        // Bounds of the turned pieces (each rotates about its top-left corner).
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const piece of pieces) {
            const a = piece.rotation * Math.PI / 180;
            for (const [cx, cy] of [[0, 0], [piece.width, 0], [0, piece.height], [piece.width, piece.height]]) {
                const px = piece.x + cx * Math.cos(a) - cy * Math.sin(a);
                const py = piece.y + cx * Math.sin(a) + cy * Math.cos(a);
                minX = Math.min(minX, px);
                maxX = Math.max(maxX, px);
                minY = Math.min(minY, py);
                maxY = Math.max(maxY, py);
            }
        }
        // Never wider than a column of the stanza.
        const shrink = Math.min(1, root.blockWidth / Math.max(1, maxX - minX));
        for (const piece of pieces) {
            piece.x = (piece.x - minX) * shrink;
            piece.y = (piece.y - minY) * shrink;
            piece.fit *= shrink;
            piece.width *= shrink;
            piece.height *= shrink;
        }
        return { "pieces": pieces, "width": (maxX - minX) * shrink, "height": (maxY - minY) * shrink };
    }

    // World placement of every line, walked from the first one. A block's position
    // is its centre; `rotation` is its roll in degrees. Lines of one stanza pack into
    // one wide composition (two masonry columns: each line goes under the shorter
    // one); the path only turns between stanzas.
    property var placements: []
    property var stanzas: []
    function rebuild() {
        root.measurePace();
        const result = [];
        const stanzas = [];
        let x = 0, y = 0, rotation = 0, previous = null, stanza = null;
        for (let i = 0; i < root.lines.length; i++) {
            const layout = root.layoutLine(i);
            const line = root.lines[i];
            const before = root.lines[i - 1];
            const newStanza = !stanza || i - stanza.start >= root.stanzaMaximumLines
                || (line.time - (before?.endTime || before?.time || 0)) > root.stanzaGapSeconds;
            if (stanza && !newStanza) {
                const column = stanza.bottoms[1] < stanza.bottoms[0] ? 1 : 0;
                const lx = column * (root.blockWidth * 1.08) + layout.width / 2;
                const ly = stanza.bottoms[column] + layout.height / 2;
                stanza.bottoms[column] += layout.height + root.blockWidth * 0.08;
                stanza.right = Math.max(stanza.right, lx + layout.width / 2);
                const a = rotation * Math.PI / 180;
                x = stanza.ox + lx * Math.cos(a) - ly * Math.sin(a);
                y = stanza.oy + lx * Math.sin(a) + ly * Math.cos(a);
            } else if (previous) {
                // The next stanza steps away from the whole previous composition.
                const a0 = rotation * Math.PI / 180;
                const w = stanza.right;
                const h = Math.max(stanza.bottoms[0], stanza.bottoms[1]) - root.blockWidth * 0.08;
                x = stanza.ox + (w / 2) * Math.cos(a0) - (h / 2) * Math.sin(a0);
                y = stanza.oy + (w / 2) * Math.sin(a0) + (h / 2) * Math.cos(a0);
                previous = { "width": w, "height": h };
                let dx = 0, dy = 0, turn = 0;
                {
                    const pick = root.hash(i * 977 + 3);
                    const gap = root.blockWidth * 0.4;
                    if (pick < 0.4) {
                        dy = previous.height / 2 + gap + layout.height / 2;
                    } else if (pick < 0.65) {
                        dx = (previous.width + layout.width) / 2 + gap;
                    } else if (pick < 0.83) {
                        turn = 90;
                        dx = (previous.width + Math.max(previous.height, layout.height)) / 2 + gap;
                    } else {
                        turn = -90;
                        dy = previous.height / 2 + gap + layout.width / 2;
                    }
                }
                const a = rotation * Math.PI / 180;
                x += dx * Math.cos(a) - dy * Math.sin(a);
                y += dx * Math.sin(a) + dy * Math.cos(a);
                if (newStanza)
                    rotation += turn + (root.hash(i * 31 + 11) < 0.35 ? (root.hash(i * 53) < 0.5 ? -6 : 6) : 0);
            }
            if (newStanza) {
                // The stanza's frame starts at its first line's top-left corner.
                const a = rotation * Math.PI / 180;
                const hx = -layout.width / 2, hy = -layout.height / 2;
                stanza = { "start": i, "end": i, "bottoms": [layout.height + root.blockWidth * 0.08, 0],
                           "right": layout.width,
                           "ox": x + hx * Math.cos(a) - hy * Math.sin(a), "oy": y + hx * Math.sin(a) + hy * Math.cos(a) };
                stanzas.push(stanza);
            }
            stanza.end = i;
            result.push({ "x": x, "y": y, "rotation": rotation, "width": layout.width, "height": layout.height,
                          "layout": layout, "stanza": stanzas.length - 1 });
            previous = layout;
        }
        root.stanzas = stanzas;
        root.placements = result;
    }
    // Deferred: during creation the measurer's font is not bound yet and reads 0.
    onLinesChanged: Qt.callLater(rebuild)

    // Window of live blocks around the current line, kept in a ListModel so blocks
    // that stay in the window are never rebuilt.
    ListModel {
        id: windowModel
    }
    readonly property int currentStanza: placements[Math.max(0, currentIndex)]?.stanza ?? 0
    readonly property int windowStart: Math.max(0, Math.min(currentIndex - 2, stanzas[currentStanza]?.start ?? 0))
    readonly property int windowEnd: Math.min(lines.length - 1, Math.max(currentIndex, 0) + 1)
    function syncWindow() {
        for (let i = windowModel.count - 1; i >= 0; i--) {
            const index = windowModel.get(i).lineIndex;
            if (index < root.windowStart || index > root.windowEnd)
                windowModel.remove(i);
        }
        for (let index = root.windowStart; index <= root.windowEnd; index++) {
            let position = 0;
            while (position < windowModel.count && windowModel.get(position).lineIndex < index)
                position++;
            if (position >= windowModel.count || windowModel.get(position).lineIndex !== index)
                windowModel.insert(position, { "lineIndex": index });
        }
    }
    onWindowStartChanged: syncWindow()
    onWindowEndChanged: syncWindow()
    onPlacementsChanged: {
        windowModel.clear();
        syncWindow();
        root.snapCamera = true;
    }

    property var blockItems: ({})

    // Camera -------------------------------------------------------------------
    property real camX: 0
    property real camY: 0
    property real camZoom: 0.5
    property real camRoll: 0
    property real _vx: 0
    property real _vy: 0
    property real _vZoom: 0
    property real _vRoll: 0
    property bool snapCamera: true
    property real wobble: 0
    // Screen-space streak for the shader.
    property vector2d streak: Qt.vector2d(0, 0)
    property real zoomStreak: 0

    readonly property real viewCenterX: width / 2
    readonly property real viewCenterY: (height - bottomInset * 0.35) / 2

    function cameraTarget() {
        const block = root.blockItems[root.currentIndex];
        const placement = root.placements[Math.max(0, root.currentIndex)];
        if (!placement)
            return null;
        const viewHeight = root.height - root.bottomInset * 0.35;
        const fit = Math.min(root.width * 0.8 / placement.width, viewHeight * 0.8 / placement.height);
        let x = placement.x, y = placement.y, zoom = fit;
        const word = block ? block.focusWord(root.clock) : null;
        if (word) {
            const p = word.mapToItem(world, word.width / 2, word.height / 2);
            // Lean towards the word being sung and push in on it. How hard depends on
            // the line's pace: a slow line is framed word by word, a fast one (several
            // words a second) mostly whole, so the camera does not whip between words.
            const pace = placement.layout.pace ?? 2;
            const tight = Math.max(0.25, Math.min(1, (4.2 - pace) / 2.6));
            x += (p.x - x) * 0.7 * tight;
            y += (p.y - y) * 0.7 * tight;
            const close = Math.min(root.width * 0.62 / Math.max(word.width, 1),
                                   viewHeight * 0.36 / Math.max(word.height, 1));
            zoom = Math.max(fit, Math.min(fit * 2.4, fit + (close - fit) * 0.65 * tight));
        }
        // No pull-back at the end of a line or stanza: the camera stays on the last
        // word until the next line starts (the stanza overview was rejected).
        const target = { "x": x, "y": y, "zoom": zoom, "rotation": placement.rotation };
        if (word)
            root.keepInFrame(target, word);
        return target;
    }

    // The lean towards the word only shifts the centre part of the way, so on a tall
    // block pushed in hard, a word at its top edge (the first words of a stanza) left
    // the frame. Measure the word's corners in the camera's frame, zoom out until it
    // fits inside a margin, then slide the centre just enough to bring it in.
    function keepInFrame(target, word) {
        const a = target.rotation * Math.PI / 180;
        const c = Math.cos(a), s = Math.sin(a);
        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
        for (const [cx, cy] of [[0, 0], [word.width, 0], [0, word.height], [word.width, word.height]]) {
            const q = word.mapToItem(world, cx, cy);
            const dx = q.x - target.x, dy = q.y - target.y;
            // World → camera frame: undo the roll.
            const lx = dx * c + dy * s;
            const ly = -dx * s + dy * c;
            minX = Math.min(minX, lx);
            maxX = Math.max(maxX, lx);
            minY = Math.min(minY, ly);
            maxY = Math.max(maxY, ly);
        }
        const margin = Math.min(root.width, root.height) * 0.06;
        const left = root.viewCenterX - margin, right = root.width - root.viewCenterX - margin;
        const up = root.viewCenterY - margin, down = root.height - root.viewCenterY - margin;
        target.zoom = Math.min(target.zoom, (left + right) / Math.max(1, maxX - minX),
                               (up + down) / Math.max(1, maxY - minY));
        let sx = 0, sy = 0;
        if (minX < -left / target.zoom)
            sx = minX + left / target.zoom;
        else if (maxX > right / target.zoom)
            sx = maxX - right / target.zoom;
        if (minY < -up / target.zoom)
            sy = minY + up / target.zoom;
        else if (maxY > down / target.zoom)
            sy = maxY - down / target.zoom;
        // Camera frame → world.
        target.x += sx * c - sy * s;
        target.y += sx * s + sy * c;
    }

    function stepCamera(dt) {
        const target = root.cameraTarget();
        if (!target)
            return;
        // Shortest way round for the roll.
        let rollTarget = target.rotation;
        while (rollTarget - root.camRoll > 180)
            rollTarget -= 360;
        while (rollTarget - root.camRoll < -180)
            rollTarget += 360;
        if (root.snapCamera) {
            root.camX = target.x;
            root.camY = target.y;
            root.camZoom = target.zoom;
            root.camRoll = rollTarget;
            root._vx = root._vy = root._vZoom = root._vRoll = 0;
            root.snapCamera = false;
            return;
        }
        // Slightly underdamped springs: the camera arrives, overshoots a touch, settles.
        const k = 40, c = 10.5;
        const ax = (target.x - root.camX) * k - root._vx * c;
        const ay = (target.y - root.camY) * k - root._vy * c;
        const logZoom = Math.log(root.camZoom);
        const az = (Math.log(target.zoom) - logZoom) * k - root._vZoom * c;
        const ar = (rollTarget - root.camRoll) * 30 - root._vRoll * 9.5;
        root._vx += ax * dt;
        root._vy += ay * dt;
        root._vZoom += az * dt;
        root._vRoll += ar * dt;
        root.camX += root._vx * dt;
        root.camY += root._vy * dt;
        root.camZoom = Math.exp(logZoom + root._vZoom * dt);
        root.camRoll += root._vRoll * dt;

        // World velocity on screen, rotated by the roll, over a short shutter.
        const shutter = 0.035;
        const a = -root.camRoll * Math.PI / 180;
        const sx = (root._vx * Math.cos(a) - root._vy * Math.sin(a)) * root.camZoom;
        const sy = (root._vx * Math.sin(a) + root._vy * Math.cos(a)) * root.camZoom;
        let ux = -sx * shutter / Math.max(1, root.width);
        let uy = -sy * shutter / Math.max(1, root.height);
        const length = Math.hypot(ux, uy);
        if (length > 0.06) {
            ux *= 0.06 / length;
            uy *= 0.06 / length;
        }
        root.streak = length < 0.0008 ? Qt.vector2d(0, 0) : Qt.vector2d(ux, uy);
        const zs = root._vZoom * shutter;
        root.zoomStreak = Math.abs(zs) < 0.002 ? 0 : Math.max(-0.08, Math.min(0.08, zs));
    }

    readonly property bool settled: Math.abs(_vx) + Math.abs(_vy) < 0.5 && Math.abs(_vZoom) < 0.001
                                    && Math.abs(_vRoll) < 0.05

    FrameAnimation {
        running: root.visible && root.lines.length > 0 && (root.playing || !root.settled || root.snapCamera)
        onTriggered: {
            root.clock = root.estimatedPosition();
            root.wobble += frameTime;
            root.stepCamera(Math.min(frameTime, 1 / 30));
        }
    }

    // Scene ----------------------------------------------------------------------
    Item {
        id: stage
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: ShaderEffect {
            property vector2d velocity: root.streak
            property real zoomRate: root.zoomStreak
            property vector2d shadowOffset: Qt.vector2d(0.004, 0.009)
            property vector2d texel: Qt.vector2d(1 / Math.max(1, stage.width), 1 / Math.max(1, stage.height))
            property real shadowBlur: 16
            property color shadowColor: root.shadowColor
            property real fisheye: root.fisheye
            property real aspect: stage.width / Math.max(1, stage.height)
            fragmentShader: Qt.resolvedUrl("shaders/kineticCamera.frag.qsb")
        }

        Item {
            id: world
            // A slow handheld drift on top of the springs.
            readonly property real driftX: Math.sin(root.wobble * 0.7) * 6 + Math.sin(root.wobble * 1.9) * 2
            readonly property real driftY: Math.cos(root.wobble * 0.53) * 5
            transform: [
                Translate {
                    x: -root.camX
                    y: -root.camY
                },
                Scale {
                    xScale: root.camZoom
                    yScale: root.camZoom
                },
                Rotation {
                    angle: -root.camRoll + Math.sin(root.wobble * 0.37) * 0.6
                },
                Translate {
                    x: root.viewCenterX + world.driftX
                    y: root.viewCenterY + world.driftY
                }
            ]

            Repeater {
                model: windowModel
                delegate: KineticBlock {}
            }
        }
    }

    component KineticBlock: Item {
        id: block
        required property int lineIndex
        readonly property var placement: root.placements[lineIndex]
        readonly property bool past: lineIndex < root.currentIndex
        property var wordItems: []

        width: placement?.width ?? root.blockWidth
        height: placement?.height ?? 0
        x: (placement?.x ?? 0) - width / 2
        y: (placement?.y ?? 0) - height / 2
        rotation: placement?.rotation ?? 0
        readonly property bool sameStanza: placement?.stanza === root.currentStanza
        // Earlier lines of the stanza stay as part of the composition; older stanzas fade.
        opacity: !past ? 1 : (sameStanza ? 0.6 : 0.14)
        Behavior on opacity {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutCubic
            }
        }

        Component.onCompleted: root.blockItems[lineIndex] = block
        Component.onDestruction: {
            if (root.blockItems[lineIndex] === block)
                delete root.blockItems[lineIndex];
        }

        // The last word whose time has come, else the first one.
        function focusWord(time) {
            let found = null;
            let first = null;
            for (const item of block.wordItems) {
                if (item.begin <= time && (!found || item.begin >= found.begin))
                    found = item;
                if (!first || item.begin < first.begin)
                    first = item;
            }
            return found ?? first;
        }

        Repeater {
            model: block.placement?.layout.pieces ?? []
            delegate: Item {
                id: piece
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.width
                height: modelData.height
                rotation: modelData.rotation
                transformOrigin: Item.TopLeft
                Repeater {
                    model: piece.modelData.words
                    delegate: KineticWord {
                        piece: piece.modelData
                        owner: block
                    }
                }
            }
        }
    }

    component KineticWord: Item {
        id: word
        required property var modelData
        required property var piece
        required property Item owner
        readonly property real begin: modelData.begin
        readonly property real end: modelData.end
        readonly property string reveal: modelData.reveal
        readonly property bool revealed: root.clock >= begin - 0.03
        property real pop: revealed ? 1 : 0

        x: modelData.x * piece.fit
        width: modelData.advance * piece.fit
        height: piece.height

        Component.onCompleted: {
            const items = owner.wordItems.slice();
            items.push(word);
            owner.wordItems = items;
        }
        Component.onDestruction: {
            if (owner)
                owner.wordItems = owner.wordItems.filter(item => item !== word);
        }

        onRevealedChanged: {
            if (revealed) {
                word.pop = 0;
                popAnimation.restart();
            } else {
                popAnimation.stop();
                word.pop = 0;
            }
        }
        NumberAnimation {
            id: popAnimation
            target: word
            property: "pop"
            to: 1
            // Fast words land faster, so a rap line is not a pile of half-finished pops.
            duration: Math.max(200, Math.min(word.reveal === "pop" ? 420 : 520, (word.end - word.begin) * 1000 * 1.2))
            easing.type: word.reveal === "pop" ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: 1.6
        }

        // A rising word comes up out of its own baseline: the window clips it, with
        // room above for accents and below for descenders.
        Item {
            id: window
            x: -word.width * 0.1
            y: -word.height * 0.35
            width: word.width * 1.2
            height: word.height * 1.75
            clip: word.reveal === "rise"

            Item {
                x: -window.x
                y: -window.y
                width: word.width
                height: word.height
                // Nothing shows before it is sung.
                opacity: word.revealed ? Math.min(1, word.pop * (word.reveal === "pop" ? 2.5 : 1.6)) : 0
                transform: [
                    Scale {
                        origin.x: word.width / 2
                        origin.y: word.height / 2
                        xScale: word.reveal === "pop" && word.revealed ? 1.22 - 0.22 * word.pop : 1
                        yScale: xScale
                    },
                    Translate {
                        x: word.reveal === "slide" ? -(1 - word.pop) * word.width * 0.6 : 0
                        y: word.reveal === "rise" ? (1 - word.pop) * word.height * 1.3 : 0
                    }
                ]
                Text {
                    id: label
                    property color ink: word.modelData.accent && word.revealed ? root.accentInk : root.textInk
                    text: word.modelData.text
                    color: ink
                    renderType: Text.CurveRendering
                    font.family: word.modelData.face.family
                    font.pixelSize: root.referenceSize
                    font.variableAxes: word.modelData.face.axes
                    font.weight: word.modelData.face.weight > 0 ? word.modelData.face.weight : Font.Normal
                    font.italic: word.modelData.face.italic
                    transform: Scale {
                        xScale: word.modelData.face.stretch
                    }
                    transformOrigin: Item.TopLeft
                    scale: word.piece.fit
                    // Put the piece's cap top on the piece's top edge.
                    y: -(baselineOffset + word.piece.capTop) * word.piece.fit
                    Behavior on ink {
                        ColorAnimation {
                            duration: 300
                        }
                    }
                }
            }
        }
    }
}
