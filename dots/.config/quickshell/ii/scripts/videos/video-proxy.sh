#!/usr/bin/env bash
# Screen-sized copies of video wallpapers ("proxies").
#
# A 4K video on a 1080p screen is decoded and scaled at 4K every frame: about
# 600 MB more VRAM and 120 MB more RAM than a 1080p copy, for no visible gain.
# switchwall.sh plays the copy instead (mpvpaper and the shell player alike).
#
#   video-proxy.sh path <video>     print the copy to play, if one is ready
#   video-proxy.sh needed <video>   exit 0 when the video is taller than the screen
#   video-proxy.sh ensure <video>   make the copy (blocking), print its path
#
# Copies live in ~/.cache/quickshell-ii/video-proxies, keyed by path, size and
# mtime, so an edited file gets a new one. The old `<name>_1080p.mp4` next to the
# video is still honoured.
set -uo pipefail
unset LD_LIBRARY_PATH LD_PRELOAD

PROXY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-ii/video-proxies"
# Copies only pay off when the source is clearly bigger than the screen.
MARGIN_PERCENT=125

screen_height() {
    local h
    h="$(hyprctl monitors -j 2>/dev/null | jq '[.[].height] | max // empty' 2>/dev/null)"
    [[ "$h" =~ ^[0-9]+$ ]] && echo "$h" || echo 1080
}

video_height() {
    ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$1" 2>/dev/null | head -1
}

proxy_file() {
    local video="$1" height="$2" key
    key="$(stat -c '%s-%Y' "$video" 2>/dev/null)-$(realpath "$video" 2>/dev/null)"
    key="$(printf '%s' "$key" | sha1sum | cut -c1-16)"
    echo "$PROXY_DIR/$(basename "${video%.*}")-$key-${height}p.mp4"
}

needed() {
    local video="$1" vh sh
    vh="$(video_height "$video")"
    sh="$(screen_height)"
    [[ "$vh" =~ ^[0-9]+$ ]] || return 1
    (( vh * 100 > sh * MARGIN_PERCENT ))
}

cmd_path() {
    local video="$1"
    if [[ -f "${video%.*}_1080p.mp4" ]]; then
        echo "${video%.*}_1080p.mp4"
        return 0
    fi
    local out
    out="$(proxy_file "$video" "$(screen_height)")"
    [[ -s "$out" ]] && echo "$out"
    return 0
}

encode() {
    local video="$1" height="$2" tmp="$3"
    # Output options; ffmpeg only accepts them after the input.
    local out_opts=(-an -movflags +faststart)
    # Hardware first: a minute of 4K is seconds on NVENC/VAAPI, minutes on x264.
    ffmpeg -v error -y -hwaccel auto -i "$video" -vf "scale=-2:$height" \
        -c:v h264_nvenc -preset p5 -cq 23 "${out_opts[@]}" "$tmp" 2>/dev/null && return 0
    local node
    for node in /dev/dri/renderD*; do
        ffmpeg -v error -y -vaapi_device "$node" -i "$video" -vf "format=nv12,hwupload,scale_vaapi=w=-2:h=$height" \
            -c:v h264_vaapi -qp 23 "${out_opts[@]}" "$tmp" 2>/dev/null && return 0
    done
    nice -n 10 ffmpeg -v error -y -i "$video" -vf "scale=-2:$height" \
        -c:v libx264 -preset veryfast -crf 21 "${out_opts[@]}" "$tmp" 2>/dev/null
}

cmd_ensure() {
    local video="$1" existing height out tmp
    existing="$(cmd_path "$video")"
    if [[ -n "$existing" ]]; then
        echo "$existing"
        return 0
    fi
    needed "$video" || return 1
    height="$(screen_height)"
    out="$(proxy_file "$video" "$height")"
    mkdir -p "$PROXY_DIR"
    (
        # One encode per copy, however many switches ask for it.
        flock -n 9 || exit 3
        [[ -s "$out" ]] && exit 0
        tmp="$out.part.mp4"
        if encode "$video" "$height" "$tmp" && [[ -s "$tmp" ]]; then
            mv -f "$tmp" "$out"
        else
            rm -f "$tmp"
            exit 1
        fi
    ) 9>"$out.lock"
    local rc=$?
    rm -f "$out.lock"
    (( rc == 0 )) && [[ -s "$out" ]] && echo "$out"
    return $rc
}

case "${1:-}" in
    path) cmd_path "$2" ;;
    needed) needed "$2" ;;
    ensure) cmd_ensure "$2" ;;
    *)
        echo "usage: $0 path|needed|ensure <video>" >&2
        exit 2
        ;;
esac
