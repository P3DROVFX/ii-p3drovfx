#!/usr/bin/env python3
"""
Speed Test Runner for Quickshell / ii.
Measures Ping, Jitter, Download and Upload speeds using Cloudflare's global Anycast edge.
Streams progress events in NDJSON to stdout.
"""

import argparse
import http.client
import json
import signal
import statistics
import sys
import threading
import time
import urllib.request

USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)

stop_event = threading.Event()


def emit(event: dict):
    try:
        sys.stdout.write(json.dumps(event) + "\n")
        sys.stdout.flush()
    except (IOError, BrokenPipeError):
        sys.exit(0)


def signal_handler(signum, frame):
    stop_event.set()
    sys.exit(0)


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


def measure_ping():
    """Measures latency and jitter using a warm keep-alive HTTPS connection."""
    samples = []
    try:
        conn = http.client.HTTPSConnection("speed.cloudflare.com", timeout=4)
        conn.connect()
        # Warmup
        conn.request("GET", "/__down?bytes=0", headers={"User-Agent": USER_AGENT})
        resp = conn.getresponse()
        resp.read()

        for _ in range(5):
            if stop_event.is_set():
                break
            t0 = time.perf_counter()
            conn.request("GET", "/__down?bytes=0", headers={"User-Agent": USER_AGENT})
            resp = conn.getresponse()
            resp.read()
            dt_ms = (time.perf_counter() - t0) * 1000.0
            samples.append(dt_ms)
            time.sleep(0.05)

        conn.close()
    except Exception:
        # Fallback via urllib if http.client connection had issue
        for _ in range(4):
            if stop_event.is_set():
                break
            try:
                t0 = time.perf_counter()
                req = urllib.request.Request(
                    "https://speed.cloudflare.com/__down?bytes=0",
                    headers={"User-Agent": USER_AGENT},
                )
                with urllib.request.urlopen(req, timeout=4) as r:
                    r.read()
                samples.append((time.perf_counter() - t0) * 1000.0)
            except Exception:
                pass

    if not samples:
        return 0.0, 0.0

    median_ping = statistics.median(samples)
    jitter = (
        statistics.stdev(samples)
        if len(samples) > 1
        else (abs(samples[-1] - samples[0]) if len(samples) > 1 else 0.0)
    )
    return round(median_ping, 1), round(jitter, 1)


def run_download(duration: float, num_workers: int = 4):
    """Measures download speed over duration seconds."""
    total_bytes = 0
    bytes_lock = threading.Lock()

    # Cloudflare rate-limits 25MB requests with 429, but allows 5MB/2.5MB streams reliably.
    download_urls = [
        "https://speed.cloudflare.com/__down?bytes=5000000",
        "https://speed.cloudflare.com/__down?bytes=2500000",
        "https://proof.ovh.net/files/100Mb.dat",
    ]

    def worker(worker_id: int):
        nonlocal total_bytes
        chunk_size = 65536
        url_idx = worker_id % len(download_urls)
        while not stop_event.is_set():
            url = download_urls[url_idx % len(download_urls)]
            try:
                req = urllib.request.Request(
                    url,
                    headers={"User-Agent": USER_AGENT},
                )
                with urllib.request.urlopen(req, timeout=5) as resp:
                    if resp.status != 200:
                        url_idx += 1
                        continue
                    while not stop_event.is_set():
                        data = resp.read(chunk_size)
                        if not data:
                            break
                        with bytes_lock:
                            total_bytes += len(data)
            except Exception:
                url_idx += 1
                if stop_event.is_set():
                    break
                time.sleep(0.05)

    threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(num_workers)]
    for t in threads:
        t.start()

    start_time = time.perf_counter()
    prev_time = start_time
    prev_bytes = 0
    samples = []
    peak_speed = 0.0

    while not stop_event.is_set():
        time.sleep(0.2)
        now = time.perf_counter()
        elapsed = now - start_time
        if elapsed >= duration:
            break

        with bytes_lock:
            cur_bytes = total_bytes

        dt = now - prev_time
        if dt <= 0:
            continue

        d_bytes = cur_bytes - prev_bytes
        inst_mbps = (d_bytes * 8.0) / (dt * 1_000_000.0)
        avg_mbps = (cur_bytes * 8.0) / (elapsed * 1_000_000.0)
        peak_speed = max(peak_speed, inst_mbps)
        samples.append(round(inst_mbps, 2))

        prev_time = now
        prev_bytes = cur_bytes
        progress = min(1.0, elapsed / duration)

        emit({
            "type": "download_progress",
            "phase": "download",
            "current": round(inst_mbps, 2),
            "average": round(avg_mbps, 2),
            "peak": round(peak_speed, 2),
            "progress": round(progress, 3),
            "elapsed": round(elapsed, 1),
            "bytes": cur_bytes,
        })

    stop_event.set()
    final_time = time.perf_counter()
    with bytes_lock:
        final_bytes = total_bytes

    total_time = max(0.001, final_time - start_time)
    final_avg = (final_bytes * 8.0) / (total_time * 1_000_000.0)
    return round(final_avg, 2), round(peak_speed, 2), samples


def run_upload(duration: float, num_workers: int = 4):
    """Measures upload speed over duration seconds."""
    stop_event.clear()
    total_bytes = 0
    bytes_lock = threading.Lock()
    payload = b"\x00" * (256 * 1024)

    def worker():
        nonlocal total_bytes
        while not stop_event.is_set():
            try:
                req = urllib.request.Request(
                    "https://speed.cloudflare.com/__up",
                    data=payload,
                    headers={
                        "User-Agent": USER_AGENT,
                        "Content-Type": "application/octet-stream",
                    },
                )
                with urllib.request.urlopen(req, timeout=6) as resp:
                    resp.read()
                    with bytes_lock:
                        total_bytes += len(payload)
            except Exception:
                if stop_event.is_set():
                    break
                time.sleep(0.1)

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(num_workers)]
    for t in threads:
        t.start()

    start_time = time.perf_counter()
    prev_time = start_time
    prev_bytes = 0
    samples = []
    peak_speed = 0.0

    while not stop_event.is_set():
        time.sleep(0.2)
        now = time.perf_counter()
        elapsed = now - start_time
        if elapsed >= duration:
            break

        with bytes_lock:
            cur_bytes = total_bytes

        dt = now - prev_time
        if dt <= 0:
            continue

        d_bytes = cur_bytes - prev_bytes
        inst_mbps = (d_bytes * 8.0) / (dt * 1_000_000.0)
        avg_mbps = (cur_bytes * 8.0) / (elapsed * 1_000_000.0)
        peak_speed = max(peak_speed, inst_mbps)
        samples.append(round(inst_mbps, 2))

        prev_time = now
        prev_bytes = cur_bytes
        progress = min(1.0, elapsed / duration)

        emit({
            "type": "upload_progress",
            "phase": "upload",
            "current": round(inst_mbps, 2),
            "average": round(avg_mbps, 2),
            "peak": round(peak_speed, 2),
            "progress": round(progress, 3),
            "elapsed": round(elapsed, 1),
            "bytes": cur_bytes,
        })

    stop_event.set()
    final_time = time.perf_counter()
    with bytes_lock:
        final_bytes = total_bytes

    total_time = max(0.001, final_time - start_time)
    final_avg = (final_bytes * 8.0) / (total_time * 1_000_000.0)
    return round(final_avg, 2), round(peak_speed, 2), samples


def main():
    parser = argparse.ArgumentParser(description="Internet Speed Test Runner")
    parser.add_argument("--duration", type=float, default=10.0, help="Test duration in seconds per phase")
    parser.add_argument("--mode", choices=["both", "download", "upload"], default="both", help="Test mode")
    parser.add_argument("--server", type=str, default="cloudflare", help="Test server provider")
    args = parser.parse_args()

    emit({
        "type": "init",
        "phase": "init",
        "duration": args.duration,
        "mode": args.mode,
        "server": "Cloudflare Edge",
    })

    # 1. Ping Phase
    emit({"type": "status", "phase": "ping", "message": "Measuring latency..."})
    ping, jitter = measure_ping()
    if ping <= 0.0:
        emit({
            "type": "error",
            "phase": "error",
            "error_type": "offline",
            "message": "No internet connection detected",
        })
        sys.exit(1)

    emit({
        "type": "ping_result",
        "phase": "ping",
        "ping": ping,
        "jitter": jitter,
    })

    download_avg = 0.0
    download_peak = 0.0
    download_samples = []

    upload_avg = 0.0
    upload_peak = 0.0
    upload_samples = []

    # 2. Download Phase
    if args.mode in ("both", "download"):
        emit({"type": "status", "phase": "download", "message": "Testing download..."})
        download_avg, download_peak, download_samples = run_download(args.duration)
        if download_avg <= 0.0 and not stop_event.is_set():
            emit({
                "type": "error",
                "phase": "error",
                "error_type": "connection_lost",
                "message": "Download failed or connection lost",
            })
            sys.exit(1)
        emit({
            "type": "download_result",
            "phase": "download",
            "average": download_avg,
            "peak": download_peak,
            "samples": download_samples,
        })

    # 3. Upload Phase
    if args.mode in ("both", "upload"):
        emit({"type": "status", "phase": "upload", "message": "Testing upload..."})
        upload_avg, upload_peak, upload_samples = run_upload(args.duration)
        emit({
            "type": "upload_result",
            "phase": "upload",
            "average": upload_avg,
            "peak": upload_peak,
            "samples": upload_samples,
        })

    # 4. Complete
    emit({
        "type": "complete",
        "phase": "complete",
        "ping": ping,
        "jitter": jitter,
        "downloadAvg": download_avg,
        "downloadPeak": download_peak,
        "downloadSamples": download_samples,
        "uploadAvg": upload_avg,
        "uploadPeak": upload_peak,
        "uploadSamples": upload_samples,
        "timestamp": int(time.time()),
    })


if __name__ == "__main__":
    main()
