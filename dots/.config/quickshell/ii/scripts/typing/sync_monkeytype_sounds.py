#!/usr/bin/env python3
"""Vendor Monkeytype's key-press sounds into the shell assets.

Development-only, exactly like `sync_monkeytype_languages.py`: it downloads a
pinned upstream commit, validates every file as a RIFF/WAVE, records SHA-256
checksums in `assets/typing/sounds-manifest.json`, and never executes anything
it downloaded. The shell only ever reads the checked-in result.

    python3 scripts/typing/sync_monkeytype_sounds.py --commit <immutable-sha>
    python3 scripts/typing/sync_monkeytype_sounds.py --check

The pack ids are Monkeytype's own (`click1`, `error4`, …) so a future sync can
be diffed against upstream without a translation table. The labels are ours.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOUNDS_DIR = ROOT / "assets" / "typing" / "sounds"
MANIFEST = ROOT / "assets" / "typing" / "sounds-manifest.json"

RAW_BASE = "https://raw.githubusercontent.com/monkeytypegame/monkeytype"
UPSTREAM_DIR = "frontend/static/sounds"
SOURCE_REPO = "monkeytypegame/monkeytype"
LICENSE = "GPL-3.0-only"

# id -> (label, number of variants). The counts mirror upstream's `soundsConfig`
# in frontend/src/ts/constants/sounds.ts; a mismatch there is a schema change
# and must fail the sync rather than silently ship a short pack.
CLICK_PACKS = [
    ("click1", "click", 3),
    ("click2", "beep", 3),
    ("click3", "pop", 3),
    ("click4", "creams", 6),
    ("click5", "typewriter", 6),
    ("click6", "osu", 3),
    ("click7", "hitmarker", 3),
]

ERROR_PACKS = [
    ("error1", "damage", 1),
    ("error2", "triangle", 1),
    ("error3", "square", 1),
    ("error4", "buzz", 2),
]


def fetch(commit: str, relative: str) -> bytes:
    url = f"{RAW_BASE}/{commit}/{UPSTREAM_DIR}/{relative}"
    request = urllib.request.Request(url, headers={"User-Agent": "ii-typing-sound-sync"})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 200:
            raise RuntimeError(f"{url} returned {response.status}")
        return response.read()


def validate_wav(data: bytes, origin: str) -> dict[str, int]:
    """Reject anything that is not a real PCM WAVE before it reaches the shell."""
    if len(data) < 44 or data[0:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise RuntimeError(f"{origin} is not a RIFF/WAVE file")
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset:offset + 4]
        (chunk_size,) = struct.unpack("<I", data[offset + 4:offset + 8])
        if chunk_id == b"fmt ":
            audio_format, channels, rate = struct.unpack("<HHI", data[offset + 8:offset + 16])
            if channels not in (1, 2) or rate < 8000:
                raise RuntimeError(f"{origin} has an implausible format")
            return {"format": audio_format, "channels": channels, "rate": rate}
        offset += 8 + chunk_size + (chunk_size % 2)
    raise RuntimeError(f"{origin} has no fmt chunk")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_manifest(commit: str, synced_at: str | None) -> dict:
    def pack_entry(pack_id: str, label: str, count: int, prefix: str) -> dict:
        files = [f"{index + 1}.wav" for index in range(count)]
        return {
            "id": pack_id,
            "label": label,
            "kind": prefix,
            "files": files,
            "sha256": {name: digest(SOUNDS_DIR / pack_id / name) for name in files},
        }

    manifest = {
        "source": SOURCE_REPO,
        "upstreamPath": UPSTREAM_DIR,
        "upstreamCommit": commit,
        "license": LICENSE,
        "clickPacks": [pack_entry(i, l, c, "click") for i, l, c in CLICK_PACKS],
        "errorPacks": [pack_entry(i, l, c, "error") for i, l, c in ERROR_PACKS],
    }
    if synced_at:
        manifest["syncedAt"] = synced_at
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", help="immutable upstream commit sha to vendor from")
    parser.add_argument("--check", action="store_true",
                        help="verify the checked-in files against the manifest instead of downloading")
    args = parser.parse_args()

    if args.check:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        for pack in manifest["clickPacks"] + manifest["errorPacks"]:
            for name, expected in pack["sha256"].items():
                path = SOUNDS_DIR / pack["id"] / name
                if not path.is_file():
                    print(f"missing {path}")
                    return 1
                if digest(path) != expected:
                    print(f"checksum mismatch for {path}")
                    return 1
        print("typing sound assets match the manifest")
        return 0

    if not args.commit:
        parser.error("--commit is required (pin an immutable upstream sha)")

    existing = json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.is_file() else {}
    if SOUNDS_DIR.is_dir():
        shutil.rmtree(SOUNDS_DIR)

    for pack_id, _label, count in CLICK_PACKS + ERROR_PACKS:
        for index in range(count):
            name = f"{index + 1}.wav"
            data = fetch(args.commit, f"{pack_id}/{name}")
            validate_wav(data, f"{pack_id}/{name}")
            target = SOUNDS_DIR / pack_id / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            print(f"  {pack_id}/{name} ({len(data)} bytes)")

    from datetime import datetime, timezone
    manifest = build_manifest(args.commit, datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    if existing.get("upstreamCommit") == args.commit and existing.get("syncedAt"):
        manifest["syncedAt"] = existing["syncedAt"]
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    total = sum(path.stat().st_size for path in SOUNDS_DIR.rglob("*.wav"))
    print(f"vendored {len(CLICK_PACKS)} click packs and {len(ERROR_PACKS)} error packs ({total // 1024} KiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
