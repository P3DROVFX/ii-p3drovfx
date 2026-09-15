#!/usr/bin/env python3
# ytmusic-lyrics.py — fetch plain lyrics from YouTube Music
# Usage: ytmusic-lyrics.py <artist> <title>
# Outputs lyrics to stdout, errors to stderr, exits 1 on failure.

import sys

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

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
        yt = YTMusic()
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
