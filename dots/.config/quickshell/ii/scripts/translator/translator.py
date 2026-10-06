#!/usr/bin/env python3
"""Translator helper for the shell, on translate-shell (`trans`).

    translator.py languages
        [{"code", "name", "endonym"}, …] from `trans -list-all`.
    translator.py translate ENGINE SOURCE TARGET HOST TEXT
        HOST is the reader's language, for part-of-speech labels ("verbo"). One JSON object: the translation plus everything Google returns with it
        (transliterations, detected language, spelling correction, alternatives,
        dictionary, synonyms, definitions, examples). Other engines only fill
        `translation`.
    translator.py speak LANGUAGE_CODE TEXT
        Downloads Google's text-to-speech for TEXT and replaces itself with an
        audio player, so killing this process stops the audio.

Every failure is reported as {"ok": false, "error": "…"} on stdout with a non-zero
exit, so the shell can show it instead of guessing.
"""

import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

TIMEOUT = 15
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
LIST_ALL = re.compile(r"^(\S+)\s+(.+?)\s{2,}(.+)$")

# Caps that keep the panes readable; Google returns far more for common words.
MAX_POS = 4
MAX_WORDS = 8
MAX_DEFINITIONS = 3
MAX_SYNONYMS = 10
MAX_EXAMPLES = 4
MAX_SENTENCE_ALTERNATIVES = 4


def emit(payload, code=0):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))
    sys.stdout.flush()
    sys.exit(code)


def fail(message):
    emit({"ok": False, "error": message}, 1)


def require_trans():
    if shutil.which("trans") is None:
        fail("missing-trans")


def run_trans(args):
    try:
        result = subprocess.run(["trans", *args], capture_output=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        fail("timeout")
    return result


# ── languages ───────────────────────────────────────────────────────────────

def languages():
    require_trans()
    result = run_trans(["-list-all", "-no-bidi"])
    rows = []
    for line in result.stdout.decode("utf-8", "replace").splitlines():
        match = LIST_ALL.match(line.rstrip())
        if match:
            code, name, endonym = match.groups()
            rows.append({"code": code, "name": name.strip(), "endonym": endonym.strip()})
    if not rows:
        fail("no-languages")
    emit(rows)


# ── translate ───────────────────────────────────────────────────────────────

def dechunk(raw: bytes) -> bytes:
    """`trans -dump` prints the HTTP body still in chunked transfer encoding."""
    stripped = raw.lstrip()
    if stripped[:1] in (b"[", b"{"):
        return stripped
    out = bytearray()
    i = 0
    while i < len(raw):
        newline = raw.find(b"\n", i)
        if newline < 0:
            break
        try:
            size = int(raw[i:newline].strip() or b"0", 16)
        except ValueError:
            return raw
        if size == 0:
            break
        start = newline + 1
        out += raw[start:start + size]
        i = start + size
        if raw[i:i + 2] == b"\r\n":
            i += 2
        elif raw[i:i + 1] == b"\n":
            i += 1
    return bytes(out)


def at(value, *path):
    """Index into Google's nested arrays without tripping over missing parts."""
    for key in path:
        if not isinstance(value, list) or not -len(value) <= key < len(value):
            return None
        value = value[key]
    return value


def strip_tags(text: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", text or ""))


def bold_only(text: str) -> str:
    """Escape for Qt's StyledText, keeping Google's <b> highlight of the word."""
    parts = re.split(r"(</?b>)", text or "")
    return "".join(p if p in ("<b>", "</b>") else html.escape(html.unescape(p)) for p in parts)


def parse_dump(data, text):
    segments = at(data, 0) or []
    translation = ""
    transliteration = ""
    source_transliteration = ""
    for segment in segments:
        if not isinstance(segment, list):
            continue
        if segment[0] is not None:
            translation += segment[0]
        elif len(segment) > 2:
            transliteration = segment[2] or ""
            source_transliteration = (segment[3] if len(segment) > 3 else "") or ""

    result = {
        "ok": True,
        "rich": True,
        "translation": translation.strip(),
        "transliteration": transliteration.strip(),
        "sourceTransliteration": source_transliteration.strip(),
        "detected": at(data, 2) or "",
        "correction": "",
        "alternatives": [],
        "dictionary": [],
        "synonyms": [],
        "definitions": [],
        "examples": [],
    }
    if result["transliteration"] == result["translation"]:
        result["transliteration"] = ""
    if result["sourceTransliteration"] == text.strip():
        result["sourceTransliteration"] = ""

    # Spelling correction: [html, plain, …]. Google already translated the
    # corrected text, so this only tells the user what it understood.
    corrected = at(data, 7, 1)
    if isinstance(corrected, str) and corrected.strip() and corrected.strip() != text.strip():
        result["correction"] = corrected.strip()

    # Dictionary: per part of speech, the target words with their back-translations.
    for entry in (at(data, 1) or [])[:MAX_POS]:
        words = []
        for word in (at(entry, 2) or [])[:MAX_WORDS]:
            if isinstance(word, list) and word and word[0]:
                words.append({"word": word[0], "back": [b for b in (at(word, 1) or []) if isinstance(b, str)][:4]})
        if words:
            result["dictionary"].append({"pos": at(entry, 0) or "", "words": words})

    # Whole-sentence alternatives, when the text is one segment (no dictionary).
    if not result["dictionary"]:
        chunks = [c for c in (at(data, 5) or []) if isinstance(c, list) and at(c, 2)]
        if len(chunks) == 1:
            seen = {result["translation"]}
            for alt in at(chunks[0], 2) or []:
                value = (at(alt, 0) or "").strip()
                if value and value not in seen:
                    seen.add(value)
                    result["alternatives"].append(value)
            result["alternatives"] = result["alternatives"][:MAX_SENTENCE_ALTERNATIVES]

    # Synonyms of the source word.
    for entry in (at(data, 11) or [])[:MAX_POS]:
        words = []
        for group in at(entry, 1) or []:
            for word in at(group, 0) or []:
                if isinstance(word, str) and word not in words:
                    words.append(word)
        if words:
            result["synonyms"].append({"pos": at(entry, 0) or "", "words": words[:MAX_SYNONYMS]})

    # Definitions of the source word, with an example when Google has one.
    for entry in (at(data, 12) or [])[:MAX_POS]:
        items = []
        for definition in (at(entry, 1) or [])[:MAX_DEFINITIONS]:
            meaning = at(definition, 0)
            if isinstance(meaning, str) and meaning:
                example = at(definition, 2)
                items.append({"text": meaning, "example": example if isinstance(example, str) else ""})
        if items:
            result["definitions"].append({"pos": at(entry, 0) or "", "items": items})

    for example in (at(data, 13, 0) or [])[:MAX_EXAMPLES]:
        value = at(example, 0)
        if isinstance(value, str) and value:
            result["examples"].append(bold_only(value))

    return result


def translate(engine, source, target, host, text):
    require_trans()
    if not text.strip():
        emit({"ok": True, "rich": False, "translation": ""})
    common = ["-no-bidi", "-no-ansi", "-source", source or "auto", "-target", target]
    if host:
        common += ["-hl", host]
    if engine in ("", "auto", "google"):
        result = run_trans(["-dump", *common, "--", text])
        if result.returncode == 0:
            try:
                data = json.loads(dechunk(result.stdout).decode("utf-8", "replace"))
                parsed = parse_dump(data, text)
                if parsed["translation"]:
                    emit(parsed)
            except (ValueError, TypeError):
                pass
    # Other engines, or a dump we could not read: the plain translation.
    brief = run_trans(["-brief", *common, *([] if engine in ("", "auto") else ["-engine", engine]), "--", text])
    output = brief.stdout.decode("utf-8", "replace").strip()
    if brief.returncode != 0 or not output:
        error = brief.stderr.decode("utf-8", "replace").strip().splitlines()
        fail(error[-1] if error else "no-result")
    emit({"ok": True, "rich": False, "translation": output})


# ── speak ───────────────────────────────────────────────────────────────────

def tts_chunks(text, limit=190):
    """Google's TTS endpoint takes ~200 characters; split on sentences, then words."""
    text = " ".join(text.split())
    chunks = []
    for sentence in re.split(r"(?<=[.!?。！？;；])\s+", text):
        while len(sentence) > limit:
            cut = sentence.rfind(" ", 0, limit)
            cut = cut if cut > 0 else limit
            chunks.append(sentence[:cut])
            sentence = sentence[cut:].lstrip()
        if sentence:
            if chunks and len(chunks[-1]) + 1 + len(sentence) <= limit:
                chunks[-1] += " " + sentence
            else:
                chunks.append(sentence)
    return chunks


def speak(language, text):
    chunks = tts_chunks(text)
    if not chunks:
        fail("empty")
    runtime = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    path = os.path.join(runtime, "ii-translator-tts.mp3")
    try:
        with open(path, "wb") as out:
            for index, chunk in enumerate(chunks):
                query = urllib.parse.urlencode({
                    "ie": "UTF-8", "client": "tw-ob", "tl": language, "q": chunk,
                    "total": len(chunks), "idx": index, "textlen": len(chunk),
                })
                request = urllib.request.Request(
                    f"https://translate.google.com/translate_tts?{query}",
                    headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                    out.write(response.read())
    except Exception as error:  # network, HTTP 4xx for unsupported voices…
        fail(f"tts: {error}")

    for player in (["pw-play", path], ["mpv", "--no-video", "--really-quiet", path],
                   ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", path],
                   ["paplay", path]):
        if shutil.which(player[0]):
            os.execvp(player[0], player)
    fail("no-player")


def main():
    if len(sys.argv) < 2:
        fail("usage")
    command, args = sys.argv[1], sys.argv[2:]
    if command == "languages":
        languages()
    elif command == "translate" and len(args) == 5:
        translate(*args)
    elif command == "speak" and len(args) == 2:
        speak(*args)
    fail("usage")


if __name__ == "__main__":
    main()
