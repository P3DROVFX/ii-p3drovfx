#!/usr/bin/env python3
"""Generate tiny, tagged local-media fixtures without storing binaries in git."""

from __future__ import annotations

import math
import shutil
import struct
import subprocess
import wave
from pathlib import Path


class FixtureGenerationError(RuntimeError):
    pass


def _write_tone(path: Path, *, seconds: float = 0.5) -> None:
    sample_rate = 8_000
    samples = (
        struct.pack("<h", int(8_000 * math.sin(2 * math.pi * 440 * index / sample_rate)))
        for index in range(int(sample_rate * seconds))
    )
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(b"".join(samples))


def _run_ffmpeg(command: list[str]) -> None:
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise FixtureGenerationError(completed.stderr.strip() or "ffmpeg failed to create a fixture")


def generate_fixture_set(destination: str | Path) -> dict[str, Path]:
    """Create WAV, MP3, FLAC, Opus, lyrics and invalid-file fixtures.

    The files are intentionally generated into a temporary directory by tests.
    That keeps the repository compact while retaining reproducible inputs for
    scanner, metadata and lyrics phases.
    """

    if shutil.which("ffmpeg") is None:
        raise FixtureGenerationError("ffmpeg is required to generate encoded fixtures")

    root = Path(destination)
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    source = root / "source.wav"
    cover = root / "cover.ppm"
    _write_tone(source)
    cover.write_text("P3\n1 1\n255\n64 128 255\n", encoding="ascii")

    tagged = root / "tagged-cover.mp3"
    _run_ffmpeg([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(source), "-i", str(cover),
        "-map", "0:a", "-map", "1:v", "-c:a", "libmp3lame", "-c:v", "mjpeg",
        "-disposition:v:0", "attached_pic", "-metadata", "title=II Fixture",
        "-metadata", "artist=II", "-metadata", "album=Local Media", str(tagged),
    ])
    flac = root / "tagged.flac"
    _run_ffmpeg([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(source), "-c:a", "flac",
        "-metadata", "title=II Fixture", "-metadata", "artist=II", str(flac),
    ])
    opus = root / "tagged.opus"
    _run_ffmpeg([
        "ffmpeg", "-y", "-loglevel", "error", "-i", str(source), "-c:a", "libopus",
        "-metadata", "title=II Fixture", "-metadata", "artist=II", str(opus),
    ])
    lyrics_lrc = root / "lyrics.lrc"
    lyrics_lrc.write_text("[00:00.00]Offline lyric\n[00:00.25]Second line\n", encoding="utf-8")
    lyrics_txt = root / "lyrics.txt"
    lyrics_txt.write_text("Offline lyric\nSecond line\n", encoding="utf-8")
    invalid = root / "invalid.audio"
    invalid.write_text("this is not audio\n", encoding="utf-8")

    return {
        "wav": source,
        "mp3": tagged,
        "flac": flac,
        "opus": opus,
        "cover": cover,
        "lrc": lyrics_lrc,
        "txt": lyrics_txt,
        "invalid": invalid,
    }
