#!/usr/bin/env python3
"""Video editor backend used by the Quickshell video editor.

The editor previously treated a CRF value as a linear percentage of the
input file size.  CRF is content-dependent, so this backend probes the input
and estimates re-encoded output by encoding short representative samples with
the same export profile used for the final file.

The JSON-line protocol is intentionally small so QML can consume it through a
SplitParser without depending on a separate service process.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def emit(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def notify(title: str, message: str, urgency: str = "normal") -> None:
    try:
        subprocess.Popen(
            ["notify-send", title, message, "-a", "Video Editor", "-i", "video-x-generic", "-u", urgency],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def run_json_command(command: list[str]) -> dict[str, Any]:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def parse_fraction(value: Any, fallback: float = 0.0) -> float:
    if not value:
        return fallback
    try:
        if isinstance(value, str) and "/" in value:
            numerator, denominator = value.split("/", 1)
            denominator_value = float(denominator)
            return float(numerator) / denominator_value if denominator_value else fallback
        return float(value)
    except (TypeError, ValueError, ZeroDivisionError):
        return fallback


def as_float(value: Any, fallback: float = 0.0) -> float:
    try:
        number = float(value)
        return number if math.isfinite(number) else fallback
    except (TypeError, ValueError):
        return fallback


def as_int(value: Any, fallback: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return fallback


def probe_video(input_file: str) -> dict[str, Any]:
    path = Path(input_file).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"Input video does not exist: {path}")

    data = run_json_command(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_entries",
            "format:stream=index,codec_type,codec_name,width,height,avg_frame_rate,r_frame_rate,bit_rate,duration,sample_rate,channels",
            "-of",
            "json",
            str(path),
        ]
    )

    streams = data.get("streams") or []
    format_data = data.get("format") or {}
    video = next((stream for stream in streams if stream.get("codec_type") == "video"), {})
    audio = next((stream for stream in streams if stream.get("codec_type") == "audio"), {})

    duration = as_float(format_data.get("duration"), as_float(video.get("duration")))
    size = as_int(format_data.get("size"), path.stat().st_size)
    fps = parse_fraction(video.get("avg_frame_rate"), parse_fraction(video.get("r_frame_rate")))
    format_bitrate = as_float(format_data.get("bit_rate"))
    video_bitrate = as_float(video.get("bit_rate"))
    audio_bitrate = as_float(audio.get("bit_rate"))

    return {
        "ok": True,
        "path": str(path),
        "size": size,
        "duration": duration,
        "format": {
            "name": format_data.get("format_name", ""),
            "bitrate": format_bitrate,
        },
        "video": {
            "codec": video.get("codec_name", ""),
            "width": as_int(video.get("width")),
            "height": as_int(video.get("height")),
            "fps": fps,
            "bitrate": video_bitrate,
        },
        "audio": {
            "present": bool(audio),
            "codec": audio.get("codec_name", ""),
            "sampleRate": as_int(audio.get("sample_rate")),
            "channels": as_int(audio.get("channels")),
            "bitrate": audio_bitrate,
        },
    }


def normalize_spec(raw: dict[str, Any]) -> dict[str, Any]:
    input_file = str(raw.get("input", "")).strip()
    if not input_file:
        raise ValueError("No input video was provided")

    start = max(0.0, as_float(raw.get("startSeconds"), 0.0))
    end = as_float(raw.get("endSeconds"), 0.0)
    duration = as_float(raw.get("duration"), 0.0)
    if end <= start and duration > 0:
        end = start + duration

    crop = raw.get("crop") or {}
    export_format = str(raw.get("format", "mp4")).strip().lower()
    if export_format not in ("mp4", "mp3", "gif"):
        export_format = "mp4"

    # GIF specific settings:
    gif_fps = max(5, min(60, as_int(raw.get("gifFps"), 15)))
    gif_scale = max(0.1, min(1.0, as_float(raw.get("gifScale"), 1.0)))
    gif_width = max(0, as_int(raw.get("gifWidth"), 0))
    gif_dither = str(raw.get("gifDither", "bayer")).strip().lower()
    if gif_dither not in ("bayer", "floyd_steinberg", "sierra2_4a", "none", "ordered"):
        gif_dither = "bayer"
    gif_bayer_scale = max(0, min(5, as_int(raw.get("gifBayerScale"), 3)))
    gif_stats_mode = str(raw.get("gifStatsMode", "diff")).strip().lower()
    if gif_stats_mode not in ("diff", "full", "single"):
        gif_stats_mode = "diff"
    gif_colors = max(16, min(256, as_int(raw.get("gifColors"), 256)))
    gif_diff_mode = str(raw.get("gifDiffMode", "rectangle")).strip().lower()
    if gif_diff_mode not in ("rectangle", "none"):
        gif_diff_mode = "rectangle"

    return {
        "input": input_file,
        "format": export_format,
        "startSeconds": start,
        "endSeconds": max(start, end),
        "crop": {
            "x": as_float(crop.get("x"), 0.0),
            "y": as_float(crop.get("y"), 0.0),
            "w": as_float(crop.get("w"), -1.0),
            "h": as_float(crop.get("h"), -1.0),
            "uiW": as_float(crop.get("uiW"), 0.0),
            "uiH": as_float(crop.get("uiH"), 0.0),
        },
        "crf": max(18, min(36, as_int(raw.get("crf"), 23))),
        "preset": str(raw.get("preset", "fast")),
        "rotation": as_int(raw.get("rotation"), 0) % 360,
        "flipHorizontal": bool(raw.get("flipHorizontal", False)),
        "flipVertical": bool(raw.get("flipVertical", False)),
        "mute": bool(raw.get("mute", False)),
        "audioBitrate": str(raw.get("audioBitrate", "192k")),
        "replaceOriginal": bool(raw.get("replaceOriginal", False)),
        "outputPath": str(raw.get("outputPath", "")).strip(),
        "outputResolution": str(raw.get("outputResolution", "original")).strip().lower(),
        "playbackRate": max(0.1, min(4.0, as_float(raw.get("playbackRate"), 1.0))),
        # GIF settings
        "gifFps": gif_fps,
        "gifScale": gif_scale,
        "gifWidth": gif_width,
        "gifDither": gif_dither,
        "gifBayerScale": gif_bayer_scale,
        "gifStatsMode": gif_stats_mode,
        "gifColors": gif_colors,
        "gifDiffMode": gif_diff_mode,
    }


def selected_duration(spec: dict[str, Any], source_duration: float) -> float:
    start = min(max(0.0, spec["startSeconds"]), source_duration)
    end = spec["endSeconds"] if spec["endSeconds"] > 0 else source_duration
    end = min(max(start, end), source_duration)
    return max(0.01, end - start)


def even_dimension(value: float, minimum: int = 2) -> int:
    result = int(max(minimum, round(value)))
    return result if result % 2 == 0 else result - 1


def crop_filter(spec: dict[str, Any], metadata: dict[str, Any]) -> str | None:
    crop = spec["crop"]
    source_w = as_int((metadata.get("video") or {}).get("width"))
    source_h = as_int((metadata.get("video") or {}).get("height"))
    ui_w = crop["uiW"]
    ui_h = crop["uiH"]
    if source_w <= 0 or source_h <= 0 or ui_w <= 0 or ui_h <= 0 or crop["w"] <= 0 or crop["h"] <= 0:
        return None

    full_width = crop["w"] >= ui_w * 0.995
    full_height = crop["h"] >= ui_h * 0.995
    origin = abs(crop["x"]) < 1.0 and abs(crop["y"]) < 1.0
    if full_width and full_height and origin:
        return None

    x = max(0, min(source_w - 2, even_dimension(crop["x"] * source_w / ui_w)))
    y = max(0, min(source_h - 2, even_dimension(crop["y"] * source_h / ui_h)))
    width = min(source_w - x, even_dimension(crop["w"] * source_w / ui_w))
    height = min(source_h - y, even_dimension(crop["h"] * source_h / ui_h))
    width = max(2, width - (width % 2))
    height = max(2, height - (height % 2))
    if x + width > source_w:
        width = max(2, (source_w - x) - ((source_w - x) % 2))
    if y + height > source_h:
        height = max(2, (source_h - y) - ((source_h - y) % 2))
    return f"crop={width}:{height}:{x}:{y}"


def build_atempo(rate: float) -> list[str]:
    """Build a chain of atempo filters (each limited to [0.5, 2.0])."""
    filters: list[str] = []
    remaining = rate
    # For speeds > 2.0, chain multiple atempo=2.0
    while remaining > 2.0 + 1e-6:
        filters.append("atempo=2.0")
        remaining /= 2.0
    # For speeds < 0.5, chain multiple atempo=0.5
    while remaining < 0.5 - 1e-6:
        filters.append("atempo=0.5")
        remaining *= 2.0
    filters.append(f"atempo={remaining:.6f}")
    return filters


def resolution_filter(spec: dict[str, Any], metadata: dict[str, Any]) -> str | None:
    """Return a scale filter if a non-original output resolution is selected."""
    target = spec.get("outputResolution", "original")
    target_heights = {"1080p": 1080, "720p": 720, "480p": 480}
    target_h = target_heights.get(target)
    if not target_h:
        return None
    source_h = as_int((metadata.get("video") or {}).get("height"))
    if source_h > 0 and source_h <= target_h:
        return None  # source already smaller or equal, skip
    return f"scale=-2:{target_h}:flags=lanczos"


def filter_chain(spec: dict[str, Any], metadata: dict[str, Any]) -> str | None:
    filters: list[str] = []
    crop = crop_filter(spec, metadata)
    if crop:
        filters.append(crop)
    if spec["rotation"] == 90:
        filters.append("transpose=1")
    elif spec["rotation"] == 180:
        filters.append("hflip")
        filters.append("vflip")
    elif spec["rotation"] == 270:
        filters.append("transpose=2")
    if spec["flipHorizontal"]:
        filters.append("hflip")
    if spec["flipVertical"]:
        filters.append("vflip")
    rate = spec.get("playbackRate", 1.0)
    if abs(rate - 1.0) > 0.01:
        filters.append(f"setpts=PTS/{rate:.6f}")
    res = resolution_filter(spec, metadata)
    if res:
        filters.append(res)
    return ",".join(filters) or None


def gif_filter_complex(spec: dict[str, Any], metadata: dict[str, Any]) -> str:
    parts: list[str] = []
    base_transforms = filter_chain(spec, metadata)
    if base_transforms:
        parts.append(base_transforms)

    gif_width = spec.get("gifWidth", 0)
    gif_scale = spec.get("gifScale", 1.0)
    if gif_width > 0:
        parts.append(f"scale=min(iw\\,{gif_width}):-2:flags=lanczos")
    elif gif_scale < 0.999:
        parts.append(f"scale=trunc(iw*{gif_scale:.4f}/2)*2:-2:flags=lanczos")

    gif_fps = spec.get("gifFps", 15)
    parts.append(f"fps={gif_fps}")

    pre_chain = ",".join(parts)
    stats_mode = spec.get("gifStatsMode", "diff")
    max_colors = spec.get("gifColors", 256)
    dither = spec.get("gifDither", "bayer")
    bayer_scale = spec.get("gifBayerScale", 3)
    diff_mode = spec.get("gifDiffMode", "rectangle")

    dither_param = f"dither={dither}"
    if dither == "bayer":
        dither_param += f":bayer_scale={bayer_scale}"

    palettegen_str = f"palettegen=stats_mode={stats_mode}:max_colors={max_colors}"
    paletteuse_str = f"paletteuse={dither_param}:diff_mode={diff_mode}"

    return f"{pre_chain},split[s0][s1];[s0]{palettegen_str}[p];[s1][p]{paletteuse_str}"


def ffmpeg_command(spec: dict[str, Any], metadata: dict[str, Any], output: str, progress: bool = False) -> list[str]:
    fmt = spec.get("format", "mp4")
    duration = selected_duration(spec, as_float(metadata.get("duration")))
    start_sec = f"{spec['startSeconds']:.3f}"
    dur_sec = f"{duration:.3f}"

    if fmt == "mp3":
        if not (metadata.get("audio") or {}).get("present"):
            raise ValueError("Input video does not contain an audio track to export as MP3")
        command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            start_sec,
            "-t",
            dur_sec,
            "-i",
            spec["input"],
            "-vn",
            "-map",
            "0:a:0?",
            "-c:a",
            "libmp3lame",
            "-b:a",
            str(spec.get("audioBitrate", "192k")),
        ]
        if progress:
            command.extend(["-progress", "pipe:1", "-nostats"])
        command.append(output)
        return command

    if fmt == "gif":
        command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            start_sec,
            "-t",
            dur_sec,
            "-i",
            spec["input"],
            "-vf",
            gif_filter_complex(spec, metadata),
        ]
        if progress:
            command.extend(["-progress", "pipe:1", "-nostats"])
        command.append(output)
        return command

    # Default: MP4
    rate = spec.get("playbackRate", 1.0)
    # When speeding up/down, we need to read more/less source material.
    # -t is specified in source time, so divide by rate to get correct source duration.
    source_dur_sec = f"{(duration / rate):.3f}" if abs(rate - 1.0) > 0.01 else dur_sec
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-i",
        spec["input"],
        "-ss",
        start_sec,
        "-t",
        source_dur_sec,
    ]
    filters = filter_chain(spec, metadata)
    if filters:
        command.extend(["-vf", filters])
    command.extend(["-map", "0:v:0", "-c:v", "libx264", "-preset", spec["preset"], "-crf", str(spec["crf"]), "-pix_fmt", "yuv420p"])
    if spec["mute"]:
        command.append("-an")
    else:
        if abs(rate - 1.0) > 0.01:
            atempo = ",".join(build_atempo(rate))
            command.extend(["-map", "0:a:0?", "-c:a", "aac", "-b:a", spec["audioBitrate"], "-af", atempo])
        else:
            command.extend(["-map", "0:a:0?", "-c:a", "aac", "-b:a", spec["audioBitrate"]])
    command.extend(["-movflags", "+faststart"])
    if progress:
        command.extend(["-progress", "pipe:1", "-nostats"])
    command.append(output)
    return command


def output_path_for(spec: dict[str, Any]) -> tuple[Path, bool]:
    source = Path(spec["input"]).expanduser()
    fmt = spec.get("format", "mp4")
    ext = f".{fmt}"

    requested = Path(spec["outputPath"]).expanduser() if spec["outputPath"] else None
    if requested:
        if requested.suffix.lower() != ext:
            requested = requested.with_suffix(ext)
        return requested, False

    if fmt == "mp4" and spec["replaceOriginal"] and source.suffix.lower() == ".mp4":
        return source, True
    if spec["replaceOriginal"]:
        return source.with_name(f"{source.stem}_edited{ext}"), False

    index = 1
    while True:
        candidate = source.with_name(f"{source.stem}_edited_{index}{ext}")
        if not candidate.exists():
            return candidate, False
        index += 1


def temporary_output_path(final_path: Path) -> Path:
    final_path.parent.mkdir(parents=True, exist_ok=True)
    return final_path.parent / f".{final_path.stem}.ii-{os.getpid()}-{next(tempfile._get_candidate_names())}{final_path.suffix}"


def estimate(spec: dict[str, Any]) -> dict[str, Any]:
    metadata = probe_video(spec["input"])
    duration = selected_duration(spec, as_float(metadata.get("duration")))
    fmt = spec.get("format", "mp4")

    if fmt == "mp3":
        raw_bitrate = spec.get("audioBitrate", "192k")
        bitrate_kbps = 192.0
        if str(raw_bitrate).endswith("k"):
            bitrate_kbps = as_float(str(raw_bitrate)[:-1], 192.0)
        estimate_bytes = max(1, int((bitrate_kbps * 1000 / 8) * duration))
        return {
            "ok": True,
            "estimatedSize": estimate_bytes,
            "low": max(1, int(estimate_bytes * 0.95)),
            "high": int(estimate_bytes * 1.05),
            "sampleCount": 1,
            "sampleDuration": duration,
            "confidence": "high",
            "method": "bitrate-exact",
        }

    sample_duration = min(4.0, duration)
    if duration <= sample_duration:
        starts = [0.0]
    else:
        starts = sorted({0.0, max(0.0, (duration - sample_duration) / 2), max(0.0, duration - sample_duration)})

    sample_root = Path(tempfile.mkdtemp(prefix="ii-video-estimate-"))
    sizes: list[int] = []
    try:
        for index, offset in enumerate(starts):
            sample_spec = dict(spec)
            sample_spec["startSeconds"] = spec["startSeconds"] + offset
            sample_spec["endSeconds"] = sample_spec["startSeconds"] + sample_duration
            sample_output = sample_root / f"sample-{index}{f'.{fmt}' if fmt != 'mp4' else '.mp4'}"
            result = subprocess.run(
                ffmpeg_command(sample_spec, metadata, str(sample_output)),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            if result.returncode == 0 and sample_output.exists():
                sizes.append(sample_output.stat().st_size)
    finally:
        shutil.rmtree(sample_root, ignore_errors=True)

    if sizes:
        bytes_per_second = sum(sizes) / len(sizes) / sample_duration
        estimate_bytes = max(1, int(bytes_per_second * duration * 1.02))
        spread = max(sizes) / max(1, min(sizes))
        confidence = "high" if len(sizes) >= 3 and spread < 2.5 else "medium"
        return {
            "ok": True,
            "estimatedSize": estimate_bytes,
            "low": max(1, int(estimate_bytes * 0.78)),
            "high": int(estimate_bytes * 1.28),
            "sampleCount": len(sizes),
            "sampleDuration": sample_duration,
            "confidence": confidence,
            "method": "sample-encode",
        }

    source_bitrate = as_float((metadata.get("format") or {}).get("bitrate"))
    if source_bitrate <= 0:
        source_bitrate = as_float(metadata.get("size")) * 8 / max(0.01, as_float(metadata.get("duration")))
    crop = spec["crop"]
    area_ratio = 1.0
    if crop["w"] > 0 and crop["h"] > 0 and crop["uiW"] > 0 and crop["uiH"] > 0:
        area_ratio = max(0.1, min(1.0, (crop["w"] * crop["h"]) / (crop["uiW"] * crop["uiH"])))
    estimate_bytes = max(1, int(source_bitrate / 8 * duration * area_ratio))
    return {
        "ok": True,
        "estimatedSize": estimate_bytes,
        "low": int(estimate_bytes * 0.5),
        "high": int(estimate_bytes * 1.8),
        "sampleCount": 0,
        "sampleDuration": 0,
        "confidence": "low",
        "method": "bitrate-fallback",
    }


def lossless_cut_video(spec: dict[str, Any]) -> int:
    """Fast trim using -c copy (no re-encode). Precision limited to keyframe boundaries."""
    input_file = spec["input"]
    metadata = probe_video(input_file)
    start_sec = f"{spec['startSeconds']:.3f}"
    duration = selected_duration(spec, as_float(metadata.get("duration")))
    dur_sec = f"{duration:.3f}"

    final_path, replaces_source = output_path_for(spec)
    if final_path.resolve() == Path(input_file).expanduser().resolve() and not spec["replaceOriginal"]:
        raise ValueError("Output path cannot be the input path")
    temporary_path = temporary_output_path(final_path)

    notify("Trimming Video…", "Lossless cut — no re-encode…")
    emit({"event": "started", "duration": duration, "outputPath": str(final_path), "format": "mp4"})

    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel", "error",
        "-y",
        "-ss", start_sec,
        "-t", dur_sec,
        "-i", input_file,
        "-c", "copy",
        "-avoid_negative_ts", "make_zero",
        "-movflags", "+faststart",
        "-progress", "pipe:1",
        "-nostats",
        str(temporary_path),
    ]

    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    assert process.stdout is not None
    for raw_line in process.stdout:
        line = raw_line.strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "out_time_ms":
            elapsed = as_float(value) / 1_000_000
            emit({"event": "progress", "value": max(0.0, min(1.0, elapsed / duration)), "elapsed": elapsed})
        elif key == "progress" and value == "end":
            emit({"event": "progress", "value": 1.0, "elapsed": duration})

    stderr = process.stderr.read() if process.stderr is not None else ""
    return_code = process.wait()
    if return_code != 0 or not temporary_path.exists():
        temporary_path.unlink(missing_ok=True)
        message = stderr.strip() or "ffmpeg lossless cut failed"
        emit({"event": "error", "message": message})
        notify("Lossless Cut Failed", message[:240], "critical")
        return 1

    os.replace(temporary_path, final_path)
    emit({
        "event": "finished",
        "outputPath": str(final_path),
        "size": final_path.stat().st_size,
        "replacedSource": replaces_source,
        "format": "mp4",
        "lossless": True,
    })
    notify("Video Trimmed", f"Lossless cut saved to {final_path}")
    return 0


def export_video(spec: dict[str, Any]) -> int:
    metadata = probe_video(spec["input"])
    fmt = spec.get("format", "mp4")
    format_titles = {
        "mp3": ("Exporting Audio…", "Exporting audio track as MP3…", "Audio Exported", "Audio Export Failed"),
        "gif": ("Exporting GIF…", "Generating GIF animation…", "GIF Exported", "GIF Export Failed"),
        "mp4": ("Editing Video…", "Exporting the selected video segment…", "Video Edited", "Video Edit Failed"),
    }
    start_title, start_msg, finish_title, error_title = format_titles.get(fmt, format_titles["mp4"])

    final_path, replaces_source = output_path_for(spec)
    if final_path.resolve() == Path(spec["input"]).expanduser().resolve() and not spec["replaceOriginal"]:
        raise ValueError("Output path cannot be the input path")
    temporary_path = temporary_output_path(final_path)
    duration = selected_duration(spec, as_float(metadata.get("duration")))
    notify(start_title, start_msg)
    emit({"event": "started", "duration": duration, "outputPath": str(final_path), "format": fmt})

    command = ffmpeg_command(spec, metadata, str(temporary_path), progress=True)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    progress_state: dict[str, str] = {}
    assert process.stdout is not None
    for raw_line in process.stdout:
        line = raw_line.strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        progress_state[key] = value
        if key == "out_time_ms":
            elapsed = as_float(value) / 1_000_000
            emit({"event": "progress", "value": max(0.0, min(1.0, elapsed / duration)), "elapsed": elapsed})
        elif key == "progress" and value == "end":
            emit({"event": "progress", "value": 1.0, "elapsed": duration})

    stderr = process.stderr.read() if process.stderr is not None else ""
    return_code = process.wait()
    if return_code != 0 or not temporary_path.exists():
        temporary_path.unlink(missing_ok=True)
        message = stderr.strip() or f"ffmpeg could not export as {fmt}"
        emit({"event": "error", "message": message})
        notify(error_title, message[:240], "critical")
        return 1

    os.replace(temporary_path, final_path)
    emit({
        "event": "finished",
        "outputPath": str(final_path),
        "size": final_path.stat().st_size,
        "replacedSource": replaces_source,
        "format": fmt,
    })
    notify(finish_title, f"Saved to {final_path}")
    return 0


def thumbnail_dir(input_file: str, base_dir: str) -> Path:
    path = Path(input_file).expanduser()
    identity = f"{path}:{path.stat().st_mtime_ns}:{path.stat().st_size}" if path.exists() else str(path)
    digest = hashlib.sha1(identity.encode("utf-8")).hexdigest()[:16]
    directory = Path(base_dir).expanduser() / "video-editor"
    directory.mkdir(parents=True, exist_ok=True)
    return directory / digest


def generate_thumbnails(input_file: str, count: int, base_dir: str) -> int:
    metadata = probe_video(input_file)
    duration = as_float(metadata.get("duration"))
    output_dir = thumbnail_dir(input_file, base_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    for index in range(max(1, count)):
        position = 0.0 if duration <= 0 else duration * index / max(1, count - 1)
        output = output_dir / f"frame-{index}.jpg"
        command = [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            f"{position:.3f}",
            "-i",
            input_file,
            "-frames:v",
            "1",
            "-vf",
            "scale=1280:-2",
            "-q:v",
            "2",
            str(output),
        ]
        result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        if result.returncode == 0 and output.exists():
            emit({"event": "thumbnail", "index": index, "time": position, "path": str(output)})
    emit({"event": "thumbnails-finished", "count": count})
    return 0


def legacy_spec(argv: list[str]) -> dict[str, Any]:
    if len(argv) < 10:
        raise ValueError("Usage: compress_video.py <input> <crop_w_ui> <crop_h_ui> <crop_x_ui> <crop_y_ui> <start_ms> <end_ms> <ui_w> <ui_h> <replace> [compress_percent]")
    compression_percent = as_float(argv[10], 100.0) if len(argv) > 10 else 100.0
    crf = round(18 + (100 - max(10.0, min(100.0, compression_percent))) * 0.35)
    return normalize_spec({
        "input": argv[0],
        "crop": {"w": argv[1], "h": argv[2], "x": argv[3], "y": argv[4], "uiW": argv[7], "uiH": argv[8]},
        "startSeconds": as_float(argv[5]) / 1000,
        "endSeconds": as_float(argv[6]) / 1000,
        "crf": crf,
        "replaceOriginal": argv[9] == "1",
    })


def snapshot_frame(raw: dict[str, Any]) -> int:
    """Extract a single frame at `positionSeconds` and save as JPEG."""
    input_file = str(raw.get("input", "")).strip()
    if not input_file:
        raise ValueError("No input video provided for snapshot")

    pos = max(0.0, as_float(raw.get("positionSeconds"), 0.0))
    out_dir = Path(str(raw.get("outputDir", ""))).expanduser() if raw.get("outputDir") else Path.home() / "Pictures"
    out_dir.mkdir(parents=True, exist_ok=True)

    stem = Path(input_file).stem
    pos_str = f"{int(pos // 60):02d}m{int(pos % 60):02d}s{int((pos % 1) * 100):02d}"
    out_path = out_dir / f"{stem}_snapshot_{pos_str}.jpg"

    # Avoid overwriting
    counter = 1
    while out_path.exists():
        out_path = out_dir / f"{stem}_snapshot_{pos_str}_{counter}.jpg"
        counter += 1

    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-ss", f"{pos:.3f}",
        "-i", input_file,
        "-frames:v", "1",
        "-q:v", "2",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not out_path.exists():
        raise RuntimeError(f"Snapshot failed: {result.stderr.strip()}")

    emit({"ok": True, "event": "snapshot_done", "path": str(out_path)})
    notify("Snapshot Saved", str(out_path), "normal")
    return 0


def main(argv: list[str]) -> int:
    try:
        if not argv:
            raise ValueError("A command is required")
        command = argv[0]
        if command == "probe":
            emit(probe_video(argv[1]))
            return 0
        if command == "estimate":
            result = estimate(normalize_spec(json.loads(argv[1])))
            emit(result)
            return 0
        if command == "thumbnails":
            return generate_thumbnails(argv[1], as_int(argv[2], 8), argv[3])
        if command == "export":
            return export_video(normalize_spec(json.loads(argv[1])))
        if command == "lossless_cut":
            return lossless_cut_video(normalize_spec(json.loads(argv[1])))
        if command == "snapshot":
            return snapshot_frame(json.loads(argv[1]))
        return export_video(legacy_spec(argv))
    except Exception as error:
        emit({"ok": False, "event": "error", "message": str(error)})
        notify("Video Edit Failed", str(error)[:240], "critical")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
