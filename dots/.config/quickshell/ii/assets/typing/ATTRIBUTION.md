# Typing language packs

The JSON word packs in this directory are derived from
[Monkeytype](https://github.com/monkeytypegame/monkeytype), licensed under
GPL-3.0-only. The exact upstream commit, import time, language metadata and
SHA-256 checksums are recorded in `languages-manifest.json`.

They are checked into II so the typing test is instant, private and fully
offline at runtime. Update them only with
`scripts/typing/sync_monkeytype_languages.py --commit <immutable-sha>`.

# Typing key sounds

The WAV files under `sounds/` are Monkeytype's own key-press and error sounds,
vendored from the same GPL-3.0-only repository as the word packs. The pinned
upstream commit, the upstream path, per-file SHA-256 checksums and our labels
for each pack are recorded in `sounds-manifest.json`.

They are checked in so the test stays instant, private and fully offline at
runtime. Update them only with:

```sh
python3 scripts/typing/sync_monkeytype_sounds.py --commit <immutable-sha>
python3 scripts/typing/sync_monkeytype_sounds.py --check    # verify checksums
```

The sync script validates every download as a real RIFF/WAVE file before it is
written, and never executes anything it downloaded. Pack ids (`click1`,
`error4`, …) are Monkeytype's, so a future sync can be diffed against upstream
without a translation table; the human labels are ours.
