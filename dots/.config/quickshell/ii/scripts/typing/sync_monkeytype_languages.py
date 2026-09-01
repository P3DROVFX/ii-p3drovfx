#!/usr/bin/env python3
"""Vendor a curated, auditable subset of Monkeytype language packs.

This is a development-only maintenance command. Quickshell never invokes it:
the typing test reads the checked-in JSON files and manifest at runtime.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import UTC, datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import urlopen


UPSTREAM = "https://raw.githubusercontent.com/monkeytypegame/monkeytype"
LICENSE = "GPL-3.0-only"
# (id, label, upstream file, bcp47, rightToLeft, joiningScript)
#
# Every entry vendors upstream's 1k list. The base packs are only ~200 words,
# which made every language but English run out of variety long before a
# 120-second test did. The ids stay as they are even where the upstream file
# gained a `_1k` suffix: they are what `search.typingTest.language` and the
# personal-best keys are stored under, so renaming one would orphan records.
LANGUAGES = (
    ("english_1k", "English", "english_1k.json", "en", False, False),
    ("portuguese", "Português", "portuguese_1k.json", "pt", False, False),
    ("spanish", "Español", "spanish_1k.json", "es", False, False),
    ("french", "Français", "french_1k.json", "fr", False, False),
    ("german", "Deutsch", "german_1k.json", "de", False, False),
    ("italian", "Italiano", "italian_1k.json", "it", False, False),
    ("russian", "Русский", "russian_1k.json", "ru", False, False),
)

# A pack thinner than this is a sign the upstream file moved or was truncated.
MINIMUM_WORDS = 500


def fetch_json(commit: str, filename: str) -> dict:
    url = f"{UPSTREAM}/{commit}/frontend/static/languages/{filename}"
    try:
        with urlopen(url, timeout=30) as response:  # nosec B310: fixed GitHub host
            payload = response.read()
    except (HTTPError, URLError) as error:
        raise RuntimeError(f"could not download {url}: {error}") from error
    try:
        return json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(f"{filename} is not valid UTF-8 JSON: {error}") from error


def validate_pack(payload: dict, language_id: str) -> list[str]:
    words = payload.get("words")
    if not isinstance(words, list) or not words:
        raise RuntimeError(f"{language_id}: expected a non-empty words array")
    if not all(isinstance(word, str) and word.strip() for word in words):
        raise RuntimeError(f"{language_id}: words must be non-empty strings")
    # Keep upstream order (usually frequency order) while preventing accidental
    # duplicate entries from distorting a deterministic test sequence.
    unique = list(dict.fromkeys(word.strip() for word in words))
    if len(unique) < MINIMUM_WORDS:
        raise RuntimeError(
            f"{language_id}: only {len(unique)} words, expected at least {MINIMUM_WORDS}")
    return unique


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True, help="immutable Monkeytype git commit")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[2] / "assets" / "typing",
        help="typing asset directory",
    )
    args = parser.parse_args()

    output = args.output.resolve()
    language_dir = output / "languages"
    language_dir.mkdir(parents=True, exist_ok=True)

    manifest_languages: list[dict] = []
    for language_id, label, upstream_file, bcp47, rtl, joining in LANGUAGES:
        payload = fetch_json(args.commit, upstream_file)
        words = validate_pack(payload, language_id)
        normalized = {
            "name": str(payload.get("name") or label),
            "bcp47": str(payload.get("bcp47") or bcp47),
            "rightToLeft": bool(payload.get("rightToLeft", rtl)),
            "joiningScript": bool(payload.get("joiningScript", joining)),
            "orderedByFrequency": bool(payload.get("orderedByFrequency", False)),
            "preferredFont": str(payload.get("preferredFont") or ""),
            "words": words,
        }
        encoded = (json.dumps(normalized, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        target = language_dir / f"{language_id}.json"
        target.write_bytes(encoded)
        manifest_languages.append(
            {
                "id": language_id,
                "label": label,
                "file": f"languages/{language_id}.json",
                "bcp47": normalized["bcp47"],
                "rightToLeft": normalized["rightToLeft"],
                "joiningScript": normalized["joiningScript"],
                "wordCount": len(words),
                "sha256": hashlib.sha256(encoded).hexdigest(),
            }
        )

    manifest = {
        "source": "monkeytypegame/monkeytype",
        "upstreamCommit": args.commit,
        "license": LICENSE,
        "syncedAt": datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "languages": manifest_languages,
    }
    (output / "languages-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"sync_monkeytype_languages.py: {error}", file=sys.stderr)
        raise SystemExit(1)
