#!/usr/bin/env python3
# ytmusic-lyrics.py — fetch plain lyrics from YouTube Music
# Usage: ytmusic-lyrics.py <artist> <title>
# Outputs lyrics to stdout, errors to stderr, exits 1 on failure.

import signal
import sys

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

# ytmusicapi sets no network timeout, so a single slow YouTube Music response
# used to leave this one-shot alive for minutes (and, when the shell was killed
# mid-fetch, orphaned). A hard SIGALRM cap bounds the whole run no matter where
# it stalls; the per-request timeout below handles the common slow case cleanly.
def _timed_out(*_):
    eprint("[YTMusic Lyrics] Timed out")
    sys.exit(1)

signal.signal(signal.SIGALRM, _timed_out)
signal.alarm(25)

def _timeout_session():
    """A requests session that forces a timeout on every ytmusicapi call."""
    import requests

    class TimeoutSession(requests.Session):
        def request(self, *args, **kwargs):
            kwargs.setdefault("timeout", 12)
            return super().request(*args, **kwargs)

    return TimeoutSession()

def main():
    if len(sys.argv) < 3:
        eprint("[YTMusic Lyrics] Usage: ytmusic-lyrics.py <artist> <title>")
        sys.exit(1)

    artist = sys.argv[1]
    title  = sys.argv[2]

    try:
        from ytmusicapi import YTMusic
    except ImportError:
        eprint("[YTMusic Lyrics] ytmusicapi not installed. Run: uv pip install ytmusicapi")
        sys.exit(1)

    try:
        yt = YTMusic(requests_session=_timeout_session())
    except Exception as e:
        eprint(f"[YTMusic Lyrics] Failed to initialize YTMusic: {e}")
        sys.exit(1)

    query = f"{artist} {title}"
    eprint(f"[YTMusic Lyrics] Searching: {query}")

    try:
        results = yt.search(query, filter="songs", limit=5)
    except Exception as e:
        eprint(f"[YTMusic Lyrics] Search error: {e}")
        sys.exit(1)

    if not results:
        eprint("[YTMusic Lyrics] No results found.")
        sys.exit(1)

    video_id = None
    for r in results:
        if r.get("videoId"):
            video_id = r["videoId"]
            break

    if not video_id:
        eprint("[YTMusic Lyrics] No videoId in results.")
        sys.exit(1)

    eprint(f"[YTMusic Lyrics] Found videoId: {video_id}")

    try:
        watch = yt.get_watch_playlist(videoId=video_id)
    except Exception as e:
        eprint(f"[YTMusic Lyrics] get_watch_playlist error: {e}")
        sys.exit(1)

    lyrics_id = watch.get("lyrics") if watch else None
    if not lyrics_id:
        eprint("[YTMusic Lyrics] No lyrics browseId in watch playlist.")
        sys.exit(1)

    try:
        lyrics_data = yt.get_lyrics(lyrics_id)
    except Exception as e:
        eprint(f"[YTMusic Lyrics] get_lyrics error: {e}")
        sys.exit(1)

    lyrics_text = lyrics_data.get("lyrics") if lyrics_data else None
    if not lyrics_text or not lyrics_text.strip():
        eprint("[YTMusic Lyrics] Empty lyrics returned.")
        sys.exit(1)

    print(lyrics_text)

if __name__ == "__main__":
    main()
