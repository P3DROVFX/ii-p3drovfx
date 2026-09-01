#!/usr/bin/env bash
#
# setup-ii-p3drovfx.sh — installer, updater and fork/branch manager for the
# ii-p3drovfx Quickshell configuration.
#
# Running it bare applies the Quickshell config only. Installing the base
# illogical-impulse dotfiles underneath it is always an explicit request.
#
# The same file is symlinked to ~/.local/bin/ii-p3drovfx and every command
# below is reachable through that name too, with one difference: bare
# `ii-p3drovfx` prints help instead of applying.
#
# ── Commands ─────────────────────────────────────────────────────────────────
#
#   apply                   Apply the Quickshell config (the default)
#   install                 Install base illogical-impulse, then apply
#   update                  Refresh the fork and branch you are already on
#   switch                  Switch fork and/or branch
#   fork <x> [branch]       Shorthand for switch --fork <x> [--branch ...]
#   branch <name>           Shorthand for switch --branch <name>
#   list-forks              Show the fork presets
#   list-branches [fork]    Show a fork's remote branches
#   restart                 Restart Quickshell (alias: run)
#   doctor                  Report resolved paths, active state and tooling
#   hyprset <args>          Write a Hyprland key or animation
#   hyprmerge <args>        Merge a Hyprland config into the local one
#   remove-cli              Remove the ii-p3drovfx symlink
#   help                    Print the full surface (alias: -h, --help)
#   version                 Print the version (alias: -V, --version)
#   demo                    Render every UI primitive and exit
#
# ── Options ──────────────────────────────────────────────────────────────────
#
#   -f, --fork <preset|url>   Target fork
#   -b, --branch <name>       Target branch
#   -l, --local <path>        Deploy from a local checkout instead of GitHub
#   -y, --yes                 Skip every confirmation
#   -v, --verbose             Echo command output as it runs
#   -q, --quiet               Only errors on stdout
#       --backup              Keep the replaced config (default)
#       --no-backup           Discard the replaced config instead
#       --keep-config         Never reset ~/.config/illogical-impulse/config.json
#       --reset-config        Always reset it (a backup is kept)
#       --no-restart          Leave Quickshell alone when finished
#       --hypr                Install the fork's ~/.config/hypr files
#       --no-hypr             Never install them, never ask
#       --rebuild-quickshell  Rebuild Quickshell from source first
#       --skip-base-check     Do not require illogical-impulse to be present
#       --ii-subdir <name>    Override ii* auto-detection in the clone
#       --log-file <path>     Write the run log elsewhere
#       --no-log              Do not write a run log
#       --ascii               ASCII glyphs only
#       --no-color            Strip ANSI colour
#
# --local takes either a fork checkout (with dots/.config/quickshell/ii*) or an
# ii config dir directly. `update` will not guess a local path back: it refuses
# and prints the --local line to re-run, so a stale checkout is never silently
# redeployed.
#
# On Arch, `install` ends by putting the AUR quickshell-git back: the base
# installer builds its own pinned quickshell and this fork is written against
# master. That happens before any config lands, and asks first unless -y.
#
# Given neither --keep-config nor --reset-config, config.json is kept on
# updates and branch hops and reset on fork switches, where the schema changes.
#
# apply, install, update and switch offer to overlay the fork's Hyprland config
# on ~/.config/hypr. Given neither --hypr nor --no-hypr it is a question, and
# -y answers it "no" rather than "yes": the Settings update button runs
# unattended and must not rewrite Hyprland underneath you. --hypr is the way to
# ask for it in a script.
#
# Every successful config deployment opens the in-shell Welcome over IPC except
# `update`. This does not depend on installing the fork's Hyprland files; their
# Welcome rule only controls whether the compositor floats the window.
#
# Options take --flag=value as well as --flag value, and everything after a
# bare -- is passed through to hyprset/hyprmerge.
#
# Aliases kept for muscle memory: --no-confirm/--noconfirm (-y),
# --preserve-config (--keep-config), --force-install (--skip-base-check),
# --no-colour (--no-color), and the flag spellings --apply, --install,
# --update, --switch, --list-forks, --list-branches, --demo.

set -Eeuo pipefail

SETUP_VERSION="2.0.0"

# ── Resolve this script's real directory (follows symlinks) ──────────────────
_source="${BASH_SOURCE[0]}"
while [[ -L "$_source" ]]; do
    _dir="$(cd -P "$(dirname "$_source")" >/dev/null 2>&1 && pwd)"
    _source="$(readlink "$_source")"
    [[ "$_source" != /* ]] && _source="$_dir/$_source"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_source")" >/dev/null 2>&1 && pwd)"
SCRIPT_SELF="$(basename "$_source")"
INVOKED_AS="$(basename "${0}")"
unset _source _dir

# ── Paths ────────────────────────────────────────────────────────────────────
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

MIRROR_DIR="$XDG_DATA_HOME/ii-p3drovfx"       # installed copy of this script + libs
SETUP_STATE_DIR="$XDG_STATE_HOME/ii-p3drovfx" # logs and backups
BACKUP_BASE_DIR="$SETUP_STATE_DIR/backups"
DEFAULT_LOG_FILE="$SETUP_STATE_DIR/setup.log"
BASE_DIR="$XDG_CONFIG_HOME/illogical-impulse" # base dotfiles marker
BASE_CONFIG_FILE="$BASE_DIR/config.json"
QS_DIR="$XDG_CONFIG_HOME/quickshell"
TARGET_DIR="$QS_DIR/ii"
BIN_DIR="$HOME/.local/bin"
CLI_NAME="ii-p3drovfx"

# Paths this script used to write to, migrated on first run.
LEGACY_CLI_NAME="vynx"
LEGACY_MIRROR_DIR="$XDG_DATA_HOME/ii-vynx"
LEGACY_BACKUP_DIR="$XDG_DATA_HOME/ii-backups"
LEGACY_LOG_FILE="/tmp/ii-vynx-install.log"

BACKUPS_TO_KEEP=3

# ── Fork presets ─────────────────────────────────────────────────────────────
declare -A PRESET_URLS=(
    ["p3drovfx"]="https://github.com/P3DROVFX/ii-p3drovfx"
    ["mine"]="https://github.com/P3DROVFX/ii-p3drovfx"
    ["end4"]="https://github.com/end-4/dots-hyprland"
    ["vynx"]="https://github.com/vaguesyntax/ii-vynx"
    ["upstream"]="https://github.com/vaguesyntax/ii-vynx"
)
declare -A PRESET_BRANCHES=(
    ["p3drovfx"]="main"
    ["mine"]="main"
    ["end4"]="main"
    ["vynx"]="main"
    ["upstream"]="main"
)
# Canonical id per URL, so aliases collapse to one name in the UI and state files.
declare -A PRESET_CANONICAL=(
    ["https://github.com/P3DROVFX/ii-p3drovfx"]="p3drovfx"
    ["https://github.com/end-4/dots-hyprland"]="end4"
    ["https://github.com/vaguesyntax/ii-vynx"]="vynx"
)
FALLBACK_URL="https://github.com/P3DROVFX/ii-p3drovfx"
FALLBACK_BRANCH="main"

# Files carried across a replace, relative to the Quickshell config dir.
PROTECTED_PATTERNS=(
    ".env"
    "*.env"
    "user/generated/*.json"
    "scripts/hyprland/workspace_compactor"
    "scripts/hyprland/workspace_profile_manager"
    "scripts/osk/osk_autoshow"
    "scripts/appStats/app_stats"
    "scripts/touchGestures/touch_gestures"
)

# ── The fork's Hyprland config ───────────────────────────────────────────────
# Everything under dots/.config/hypr is overlaid on ~/.config/hypr except the
# paths below, matched against the path relative to that directory.

# The base installer owns custom/ and it is where your own edits are meant to
# live, so the fork never writes there.
HYPR_EXCLUDE_DIRS=("custom")

# Matugen rewrites both of these on every wallpaper change — see the
# [templates.hyprland] and [templates.hyprlock] blocks in matugen's config.toml.
# The repo's copies are a snapshot of whatever wallpaper was set at commit time,
# so they are seeded when missing and never overwritten afterwards.
HYPR_SEED_ONLY=("hyprland/colors.lua" "hyprlock/colors.conf")

# ── Options ──────────────────────────────────────────────────────────────────
COMMAND=""
OPT_FORK=""
OPT_BRANCH=""
OPT_LOCAL=""
OPT_VERBOSE=false
OPT_QUIET=false
OPT_ASSUME_YES=false
OPT_BACKUP=true
OPT_KEEP_CONFIG="" # "" = per-command default, true/false = explicit
OPT_REBUILD_QS=false
OPT_II_SUBDIR=""
OPT_RESTART=true
OPT_HYPR="" # "" = ask (and -y declines), true/false = explicit
OPT_SKIP_BASE_CHECK=false
OPT_ASCII=false
OPT_NO_COLOR=false
OPT_LOG=true
LOG_FILE="$DEFAULT_LOG_FILE"
LOG_READY=false
PASSTHRU_ARGS=()

# ── Run state (used by the exit trap) ────────────────────────────────────────
STAGE_DIR=""
CLONE_DIR=""
LOCAL_SRC=""  # resolved --local path; empty means "clone from GitHub"
LOCAL_KIND="" # repo | ii
DISPLACED_DIR=""
SWAP_STATE="none" # none | moved-away | done
START_EPOCH="$SECONDS"

#══════════════════════════════════════════════════════════════════════════════
# UI layer
#══════════════════════════════════════════════════════════════════════════════

UI_TTY=false
UI_COLOR=true
UI_TRUECOLOR=false
UI_GLYPHS="unicode" # nerd | unicode | ascii
UI_WIDTH=52
UI_LABELCOL=11 # shared label column, so every row type lines up
UI_SPIN_I=0
UI_LIVE=false # a step line is currently held open on the terminal
UI_STEP_LABEL=""
UI_STEP_US=0       # start of the open step, in microseconds
UI_PIPE_MARK=0     # last milestone emitted by the non-TTY progress backend
UI_ROW_FD=1        # stream ui_row writes to; ui_fail flips it to stderr
ERR_REPORTED=false # a failure has already been surfaced to the user

# ── Material palette ─────────────────────────────────────────────────────────
# Matugen regenerates this on every wallpaper change; the Settings panel watches
# the same file through MaterialThemeLoader.qml.
M3_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
M3_PRIMARY="" M3_SECONDARY="" M3_TERTIARY="" M3_ERROR="" M3_OUTLINE=""

# Pull the handful of roles we colour with straight out of the generated JSON.
# Deliberately sed and not jq: this has to work mid-`install` on a bare machine,
# before either jq or matugen exists.
ui_m3_load() {
    [[ -r "$M3_FILE" ]] || return 1
    local k v
    while IFS=$'\t' read -r k v; do
        case "$k" in
            primary) M3_PRIMARY="$v" ;;
            secondary) M3_SECONDARY="$v" ;;
            tertiary) M3_TERTIARY="$v" ;;
            error) M3_ERROR="$v" ;;
            outline) M3_OUTLINE="$v" ;;
        esac
    done < <(sed -n 's/^[[:space:]]*"\([a-z_]*\)"[[:space:]]*:[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1\t\2/p' "$M3_FILE" 2>/dev/null)
    [[ -n "$M3_PRIMARY" && -n "$M3_SECONDARY" && -n "$M3_TERTIARY" &&
        -n "$M3_ERROR" && -n "$M3_OUTLINE" ]]
}

ui_fg() {
    printf '\033[38;2;%d;%d;%dm' "$((16#${1:1:2}))" "$((16#${1:3:2}))" "$((16#${1:5:2}))"
}

# Colours. Kept on even when piped: the Settings panel parses these SGR codes.
ui_palette() {
    if [[ "$UI_COLOR" != true ]]; then
        C_RST="" C_B="" C_DIM="" C_IT="" C_UL=""
        C_ERR="" C_OK="" C_WARN="" C_STEP="" C_ACC="" C_HEAD="" C_SUB=""
        return 0
    fi
    C_RST=$'\033[0m'
    C_B=$'\033[1m'
    C_DIM=$'\033[2m'
    C_IT=$'\033[3m'
    C_UL=$'\033[4m'
    C_ERR=$'\033[0;31m'
    C_OK=$'\033[0;32m'
    C_WARN=$'\033[1;33m'
    C_STEP=$'\033[0;34m'
    C_ACC=$'\033[0;35m'
    C_HEAD=$'\033[1;36m'
    C_SUB=$'\033[0;90m'

    # On a real 24-bit terminal, repaint from the live matugen palette. Piped
    # output keeps the basic codes above on purpose: AboutConfig.qml maps them
    # onto theme roles, so the Settings log box re-themes with the wallpaper
    # instead of freezing to whatever it was when the line was written.
    if [[ "$UI_TTY" == true && "$UI_TRUECOLOR" == true ]] && ui_m3_load; then
        C_ERR="$(ui_fg "$M3_ERROR")"
        C_OK="$(ui_fg "$M3_PRIMARY")"
        C_WARN="$(ui_fg "$M3_TERTIARY")"
        C_STEP="$(ui_fg "$M3_SECONDARY")"
        C_ACC="$(ui_fg "$M3_TERTIARY")"
        C_HEAD="$(ui_fg "$M3_PRIMARY")"
        C_SUB="$(ui_fg "$M3_OUTLINE")"
    fi
}

ui_glyphset() {
    BAR_P=()
    case "$UI_GLYPHS" in
        nerd)
            G_OK=$'' G_ERR=$'' G_WARN=$'' G_STEP=$''
            G_DOT=$'' G_ARROW=$'' G_SEP="·" G_W=1
            RULE="─" ELLIPSIS="…"
            BAR_L="▕" BAR_R="▏" BAR_F="█" BAR_E="░"
            BAR_P=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
            ;;
        unicode)
            G_OK="✓" G_ERR="✗" G_WARN="⚠" G_STEP="▸"
            G_DOT="●" G_ARROW="→" G_SEP="·" G_W=1
            RULE="─" ELLIPSIS="…"
            BAR_L="▕" BAR_R="▏" BAR_F="█" BAR_E="░"
            BAR_P=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")
            SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
            ;;
        *)
            G_OK="ok" G_ERR="X" G_WARN="!" G_STEP=">"
            G_DOT="*" G_ARROW="->" G_SEP="-" G_W=2
            RULE="-" ELLIPSIS="..."
            BAR_L="[" BAR_R="]" BAR_F="#" BAR_E="-"
            SPIN=(- \\ \| /)
            ;;
    esac
}

# Operation icons, nerd only. They replace the generic tick on a completed row:
# the row is already green and already in the success position, so the glyph is
# free to say *what* finished rather than *that* it finished.
ui_icon() {
    [[ "$UI_GLYPHS" == "nerd" ]] || {
        printf '%s' "$G_OK"
        return 0
    }
    case "$1" in
        Cloned | Fetched) printf '%s' $'' ;;          # cloud-download
        Copied | Staged | Sourced) printf '%s' $'' ;; # files
        Swapped) printf '%s' $'' ;;                   # exchange
        Mirrored) printf '%s' $'' ;;                  # clone
        Restarted) printf '%s' $'' ;;                 # refresh
        Removed) printf '%s' $'' ;;                   # trash
        Reset) printf '%s' $'' ;;                     # undo
        Queried) printf '%s' $'' ;;                   # git-branch
        Deps | Configured | Compiled | Installed)
            printf '%s' $'' # package
            ;;
        *) printf '%s' "$G_OK" ;;
    esac
}

ui_has_nerd_font() {
    command -v fc-list >/dev/null 2>&1 || return 1
    # In a subshell with pipefail off: grep -q exits on the first match and
    # SIGPIPEs fc-list, which pipefail reports as 141 — indistinguishable from
    # "no patched font installed", so the upgrade never fired.
    (
        set +o pipefail
        fc-list 2>/dev/null | grep -qiE 'nerd font|nerdfont'
    )
}

# Provisional defaults so anything that fails before ui_init still renders.
ui_palette
ui_glyphset

ui_init() {
    [[ -t 1 ]] && UI_TTY=true

    if [[ "$OPT_NO_COLOR" == true || -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]]; then
        UI_COLOR=false
    fi
    case "${COLORTERM:-}" in
        truecolor | 24bit) UI_TRUECOLOR=true ;;
    esac

    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$OPT_ASCII" == true ]] || [[ -n "${NO_UNICODE:-}" ]] ||
        [[ "$loc" == "C" || "$loc" == "POSIX" || -z "$loc" ]] ||
        [[ ! "$loc" =~ [Uu][Tt][Ff]-?8 ]]; then
        UI_GLYPHS="ascii"
    elif [[ "$UI_TTY" == true ]] && ui_has_nerd_font; then
        # Only upgrade on a real terminal: the Settings panel renders with the
        # theme's monospace family, which is not necessarily patched.
        UI_GLYPHS="nerd"
    else
        UI_GLYPHS="unicode"
    fi

    if [[ "$UI_TTY" == true ]]; then
        local cols
        cols="$( (tput cols 2>/dev/null || echo 80))"
        [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
        UI_WIDTH=$((cols - 2))
        ((UI_WIDTH > 76)) && UI_WIDTH=76
        ((UI_WIDTH < 44)) && UI_WIDTH=44
    else
        # Fixed width so the layout survives the Settings log box at any panel size.
        UI_WIDTH=52
    fi

    ui_palette
    ui_glyphset
}

ui_repeat() {
    local ch="$1" n="${2:-0}" out=""
    ((n < 0)) && n=0
    while ((n-- > 0)); do out+="$ch"; done
    printf '%s' "$out"
}

ui_pad() { printf '%*s' "$(($1 > 0 ? $1 : 0))" ''; }

ui_trunc() {
    local s="$1" max="$2"
    ((max < 4)) && max=4
    if ((${#s} > max)); then
        printf '%s%s' "${s:0:max-${#ELLIPSIS}}" "$ELLIPSIS"
    else
        printf '%s' "$s"
    fi
}

# Microseconds since the epoch. EPOCHREALTIME is bash 5; the decimal separator
# is locale-dependent, so strip it rather than assuming a dot.
ui_now_us() {
    local t="${EPOCHREALTIME:-}"
    if [[ -n "$t" ]]; then
        printf '%s' "${t/[.,]/}"
    else
        printf '%s000000' "$SECONDS"
    fi
}

ui_fmt_dur() {
    local us="$1" ms s
    ((us < 0)) && us=0
    ms=$((us / 1000))
    if ((ms < 60000)); then
        printf '%d.%ds' $((ms / 1000)) $(((ms % 1000) / 100))
    else
        s=$((ms / 1000))
        printf '%dm%02ds' $((s / 60)) $((s % 60))
    fi
}

# Append a plain, timestamped line to the log file. Never touches stdout, and
# stays silent until open_log has proven the file is actually writable.
ui_logline() {
    [[ "$LOG_READY" == true ]] || return 0
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE" 2>/dev/null || true
}

ui_out() {
    [[ "$OPT_QUIET" == true ]] && return 0
    printf '%s\n' "$1"
}

# ── Rules and headers ────────────────────────────────────────────────────────

ui_rule() {
    local title="${1:-}" col="${2:-$C_SUB}"
    [[ "$OPT_QUIET" == true ]] && return 0
    if [[ -z "$title" ]]; then
        printf '%s%s%s\n' "$col" "$(ui_repeat "$RULE" "$UI_WIDTH")" "$C_RST"
        return 0
    fi
    title="$(ui_trunc "$title" $((UI_WIDTH - 8)))"
    printf '%s%s%s %s%s%s %s%s%s\n' \
        "$col" "$RULE$RULE" "$C_RST" "$C_B$col" "$title" "$C_RST" \
        "$col" "$(ui_repeat "$RULE" $((UI_WIDTH - 4 - ${#title})))" "$C_RST"
}

ui_banner() {
    local title="$1" sub="${2:-}"
    ui_logline "== $title ${sub:+- $sub}"
    [[ "$OPT_QUIET" == true ]] && return 0
    local right="" left="$title"
    [[ -n "$sub" ]] && left="$title  $sub"
    # `help` already puts the version in the subtitle; don't print it twice.
    [[ "$sub" =~ ^v[0-9] ]] || right="v$SETUP_VERSION"
    left="$(ui_trunc "$left" $((UI_WIDTH - ${#right} - 2)))"
    printf '\n%s%s%s%s%s%s%s%s%s\n' \
        "$C_B$C_HEAD" "$title" "$C_RST" \
        "$C_SUB" "${left#"$title"}" "$C_RST" \
        "$(ui_pad $((UI_WIDTH - ${#left} - ${#right})))" \
        "$C_SUB$right" "$C_RST"
    ui_rule
    printf '\n'
}

# ── Buffered key/value sections ──────────────────────────────────────────────
# Rows are collected instead of printed so the key column can be sized to the
# widest key actually present, rather than to a hardcoded guess.

UI_SECTION_TITLE=""
UI_SECTION_ROWS=()

ui_frame_open() {
    UI_SECTION_TITLE="${1:-}"
    UI_SECTION_ROWS=()
}

ui_kv() {
    local key="$1" val="$2"
    ui_logline "$key: $val"
    [[ "$OPT_QUIET" == true ]] && return 0
    UI_SECTION_ROWS+=("k"$'\t'"$key"$'\t'"$val")
}

ui_frame_row() {
    [[ "$OPT_QUIET" == true ]] && return 0
    UI_SECTION_ROWS+=("r"$'\t'"$1")
}

ui_frame_close() {
    [[ "$OPT_QUIET" == true ]] && return 0
    ((${#UI_SECTION_ROWS[@]} == 0)) && {
        UI_SECTION_TITLE=""
        return 0
    }
    local keycol=0 entry kind key val
    for entry in "${UI_SECTION_ROWS[@]}"; do
        IFS=$'\t' read -r kind key val <<<"$entry"
        [[ "$kind" == "k" ]] && ((${#key} > keycol)) && keycol=${#key}
    done
    ((keycol > 0)) && keycol=$((keycol + 2))

    ui_rule "$UI_SECTION_TITLE"
    for entry in "${UI_SECTION_ROWS[@]}"; do
        IFS=$'\t' read -r kind key val <<<"$entry"
        if [[ "$kind" == "k" ]]; then
            val="$(ui_trunc "$val" $((UI_WIDTH - 2 - keycol)))"
            printf '  %s%s%s%s%s\n' \
                "$C_SUB" "$key" "$(ui_pad $((keycol - ${#key})))" "$C_RST" "$val"
        else
            printf '  %s\n' "$(ui_trunc "$key" $((UI_WIDTH - 2)))"
        fi
    done
    printf '\n'
    UI_SECTION_TITLE=""
    UI_SECTION_ROWS=()
}

# ── Rows ─────────────────────────────────────────────────────────────────────

# One grammar for every message type, so glyph, label, detail and timing all
# land in the same columns no matter which of them printed the line.
# ui_row <colour> <glyph> <label> [detail] [timing]
ui_row() {
    local col="$1" glyph="$2" label="$3" detail="${4:-}" timing="${5:-}"
    local room used pad="" lblpad=""
    room=$((UI_WIDTH - 3 - G_W))
    [[ -n "$timing" ]] && room=$((room - ${#timing} - 2))
    ((room < 8)) && room=8
    if [[ -n "$detail" ]]; then
        ((${#label} < UI_LABELCOL)) && lblpad="$(ui_pad $((UI_LABELCOL - ${#label})))"
        detail="$(ui_trunc "$detail" $((room - ${#label} - ${#lblpad} - 1)))"
        used=$((${#label} + ${#lblpad} + 1 + ${#detail}))
    else
        label="$(ui_trunc "$label" "$room")"
        used=${#label}
    fi
    [[ -n "$timing" ]] && pad="$(ui_pad $((room + 2 - used)))"
    printf '  %s%-*s%s %s%s%s%s%s%s%s\n' \
        "$col" "$G_W" "$glyph" "$C_RST" \
        "$label" "$lblpad" "${detail:+ $C_SUB$detail$C_RST}" \
        "$pad" "$C_SUB" "$timing" "$C_RST" >&"$UI_ROW_FD"
}

# ── Steps and progress ───────────────────────────────────────────────────────

ui_spin_frame() {
    local f="${SPIN[UI_SPIN_I % ${#SPIN[@]}]}"
    UI_SPIN_I=$((UI_SPIN_I + 1))
    printf '%s' "$f"
}

ui_clear_line() {
    [[ "$UI_TTY" == true && "$UI_LIVE" == true ]] || return 0
    printf '\r\033[K'
    UI_LIVE=false
}

ui_step() {
    UI_STEP_LABEL="$1"
    UI_STEP_US="$(ui_now_us)"
    UI_PIPE_MARK=0
    ui_logline "step: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    if [[ "$UI_TTY" == true ]]; then
        printf '  %s%-*s%s %s' "$C_STEP" "$G_W" "$(ui_spin_frame)" "$C_RST" "$1"
        UI_LIVE=true
    else
        printf '  %s%-*s%s %s\n' "$C_STEP" "$G_W" "$G_STEP" "$C_RST" "$1"
    fi
}

# ui_progress <current> <total> [detail]
ui_progress() {
    local cur="$1" total="$2" detail="${3:-}"
    [[ "$OPT_QUIET" == true ]] && return 0
    ((total <= 0)) && return 0
    local pct=$((cur * 100 / total))
    ((pct > 100)) && pct=100

    if [[ "$UI_TTY" == true ]]; then
        local cells=12
        # Eighth-blocks so the bar advances smoothly instead of in 8% jumps.
        local eighths=$((pct * cells * 8 / 100))
        local whole=$((eighths / 8)) rem=$((eighths % 8)) bar
        bar="$(ui_repeat "$BAR_F" "$whole")"
        if ((rem > 0 && whole < cells && ${#BAR_P[@]} > 0)); then
            bar+="${BAR_P[rem]}"
            whole=$((whole + 1))
        fi
        bar="$BAR_L$bar$(ui_repeat "$BAR_E" $((cells - whole)))$BAR_R"
        local line
        line="$(printf '%-*s %s/%s  %s %3s%%' "$UI_LABELCOL" "$UI_STEP_LABEL" "$cur" "$total" "$bar" "$pct")"
        printf '\r\033[K  %s%-*s%s %s' "$C_STEP" "$G_W" "$(ui_spin_frame)" "$C_RST" "$(ui_trunc "$line" $((UI_WIDTH - 3 - G_W)))"
        UI_LIVE=true
    else
        # Same milestones, one discrete line each, so a piped consumer sees
        # progress without needing to interpret carriage returns.
        local mark=$((pct / 25 * 25))
        if ((mark > UI_PIPE_MARK && mark > 0 && mark < 100)); then
            UI_PIPE_MARK=$mark
            ui_row "$C_SUB" "$G_DOT" "$UI_STEP_LABEL" "$mark%${detail:+ $G_SEP $detail}"
        fi
    fi
}

ui_ok() {
    local label="$1" detail="${2:-}" timing=""
    ui_logline "ok: $label${detail:+ — $detail}"
    if ((UI_STEP_US > 0)); then
        timing="$(ui_fmt_dur $(($(ui_now_us) - UI_STEP_US)))"
        UI_STEP_US=0
    fi
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    ui_row "$C_OK" "$(ui_icon "$label")" "$label" "$detail" "$timing"
}

ui_fail() {
    local label="$1" detail="${2:-}"
    ERR_REPORTED=true
    UI_STEP_US=0
    ui_logline "fail: $label${detail:+ — $detail}"
    ui_clear_line
    UI_ROW_FD=2
    ui_row "$C_ERR" "$G_ERR" "$label" "$detail"
    UI_ROW_FD=1
}

ui_warn() {
    ui_logline "warn: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    ui_row "$C_WARN" "$G_WARN" "$1"
}

ui_info() {
    ui_logline "info: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    ui_row "$C_STEP" "$G_STEP" "$1"
}

ui_note() {
    ui_logline "note: $1"
    [[ "$OPT_QUIET" == true ]] && return 0
    ui_clear_line
    printf '    %s%s%s\n' "$C_SUB" "$(ui_trunc "$1" $((UI_WIDTH - 4)))" "$C_RST"
}

ui_verbose() {
    [[ "$OPT_VERBOSE" == true ]] || {
        ui_logline "debug: $1"
        return 0
    }
    ui_clear_line
    printf '    %s%s%s\n' "$C_DIM" "$1" "$C_RST"
    ui_logline "debug: $1"
}

# ui_result <ok|fail> <headline> [extra lines...]
ui_result() {
    local kind="$1" headline="$2"
    shift 2
    local col="$C_OK" glyph="$G_OK"
    [[ "$kind" != "ok" ]] && {
        col="$C_ERR"
        glyph="$G_ERR"
    }
    ui_logline "result($kind): $headline"
    [[ "$OPT_QUIET" == true ]] && {
        for l in "$@"; do ui_logline "  $l"; done
        return 0
    }
    ui_clear_line
    printf '\n'
    ui_rule "" "$col"
    ui_row "$col$C_B" "$glyph" "$headline"
    local line
    for line in "$@"; do
        ui_logline "  $line"
        printf '    %s%s%s\n' "$C_SUB" "$(ui_trunc "$line" $((UI_WIDTH - 4)))" "$C_RST"
    done
    printf '\n'
}

ui_die() {
    ui_fail "${1:-Failed}" "${2:-}"
    exit "${3:-1}"
}

# ui_confirm <question> [default] — honours --yes, refuses to hang on a
# non-interactive stdin. Pass "yes" as the second argument to make a bare Enter
# accept; anything else keeps the cautious no-by-default behaviour.
ui_confirm() {
    [[ "$OPT_ASSUME_YES" == true ]] && return 0
    if [[ ! -t 0 ]]; then
        ui_die "Confirmation required" "stdin is not a terminal — re-run with --yes"
    fi
    local default_yes=false hint='(y/N)'
    [[ "${2:-}" == "yes" ]] && { default_yes=true; hint='(Y/n)'; }
    ui_clear_line
    printf '  %s%-*s%s %s %s%s%s ' \
        "$C_WARN" "$G_W" "$G_WARN" "$C_RST" "$1" "$C_SUB" "$hint" "$C_RST"
    local reply
    read -r reply || reply=""
    printf '\n'
    [[ -z "$reply" && "$default_yes" == true ]] && return 0
    [[ "$reply" =~ ^[Yy]$ ]]
}

ui_elapsed() {
    local secs=$((SECONDS - START_EPOCH))
    if ((secs < 60)); then
        printf '%ds' "$secs"
    else
        printf '%dm%02ds' $((secs / 60)) $((secs % 60))
    fi
}

# ── Demo ─────────────────────────────────────────────────────────────────────
ui_demo() {
    ui_banner "ii-p3drovfx" "ui demo"
    ui_frame_open "Resolve"
    ui_kv "fork" "end4"
    ui_kv "remote" "github.com/end-4/dots-hyprland"
    ui_kv "branch" "main"
    ui_kv "target" "${TARGET_DIR/#$HOME/\~}"
    ui_frame_close
    ui_step "Cloning"
    local i
    for i in 3 25 50 75 99; do
        ui_progress "$((i * 1284 / 100))" 1284 "objects"
        [[ "$UI_TTY" == true ]] && sleep 0.12
    done
    ui_ok "Cloned" "1284 files $G_SEP 4.2 MB"
    ui_step "Staging"
    [[ "$UI_TTY" == true ]] && sleep 0.2
    ui_ok "Staged" "3 protected files carried"
    ui_step "Swapping"
    [[ "$UI_TTY" == true ]] && sleep 0.1
    ui_ok "Swapped" "backup $G_ARROW ii_end4_main_20260727-1412"
    printf '\n'
    ui_info "an informational step"
    ui_note "a dimmed aside"
    ui_warn "a warning"
    ui_fail "a failure" "with detail"
    ui_verbose "a verbose line (only with -v)"
    ui_result ok "demo complete $G_SEP $(ui_elapsed)" \
        "glyphs: $UI_GLYPHS $G_SEP width: $UI_WIDTH $G_SEP tty: $UI_TTY" \
        "palette: $([[ -n "$M3_PRIMARY" ]] && printf 'matugen %s' "$M3_PRIMARY" || printf 'ansi 16')"
    printf '%s  text styles:%s %sbold%s %sdim%s %sitalic%s %sunderline%s %saccent%s\n\n' \
        "$C_SUB" "$C_RST" "$C_B" "$C_RST" "$C_DIM" "$C_RST" \
        "$C_IT" "$C_RST" "$C_UL" "$C_RST" "$C_ACC" "$C_RST"
}

#══════════════════════════════════════════════════════════════════════════════
# Traps
#══════════════════════════════════════════════════════════════════════════════

on_err() {
    local rc=$1 line=$2 cmd=$3
    # Whatever went wrong has already been explained in the user's own terms.
    [[ "$ERR_REPORTED" == true ]] && return 0
    ui_clear_line
    ui_fail "Aborted" "line $line exited $rc"
    [[ "$OPT_VERBOSE" == true ]] && printf '%s  %s%s\n' "$C_DIM" "$cmd" "$C_RST" >&2
    ui_logline "error: line $line rc=$rc cmd=$cmd"
}

on_exit() {
    local rc=$?
    # Nothing this trap does is worth an error report, and its own `return $rc`
    # is itself a failing command on any non-zero exit — which is where the
    # spurious second "Aborted, line 1" after a clean ui_fail came from.
    trap - ERR
    [[ "$UI_TTY" == true ]] && {
        printf '\033[?25h'
        ui_clear_line
    }

    # Died between the two renames: put the previous tree back.
    if [[ "$SWAP_STATE" == "moved-away" && -n "$DISPLACED_DIR" && -d "$DISPLACED_DIR" && ! -e "$TARGET_DIR" ]]; then
        if mv "$DISPLACED_DIR" "$TARGET_DIR" 2>/dev/null; then
            ui_warn "Restored the previous config after a failed swap."
        fi
    fi

    [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]] && rm -rf "$STAGE_DIR"
    [[ -n "$CLONE_DIR" && -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
    return "$rc"
}

on_signal() {
    ui_clear_line
    ui_fail "Interrupted" "cleaning up"
    exit 130
}

trap 'on_err $? $LINENO "$BASH_COMMAND"' ERR
trap on_exit EXIT
trap on_signal INT TERM

#══════════════════════════════════════════════════════════════════════════════
# Helpers
#══════════════════════════════════════════════════════════════════════════════

have() { command -v "$1" >/dev/null 2>&1; }

tilde() { printf '%s' "${1/#$HOME/\~}"; }

# Make a string safe as a single path component. Branch names legitimately
# contain '/' (refactor/setup-p3drovfx), which would otherwise turn a backup
# name into a nested path whose parent does not exist.
path_slug() {
    local s="${1//[^A-Za-z0-9._-]/-}"
    s="${s##-}"
    printf '%s' "${s:-unknown}"
}

# Run a command, tee its output to the log, echo it only when verbose.
run_logged() {
    local rc=0
    if [[ "$OPT_VERBOSE" == true ]]; then
        "$@" 2>&1 | tee -a "$LOG_FILE" || rc=${PIPESTATUS[0]}
    else
        "$@" >>"$LOG_FILE" 2>&1 || rc=$?
    fi
    return "$rc"
}

normalize_url() {
    local raw="$1"
    raw="${raw%.git}"
    raw="${raw%/}"
    if [[ "$raw" == git@github.com:* ]]; then
        raw="https://github.com/${raw#git@github.com:}"
    elif [[ "$raw" == ssh://git@github.com/* ]]; then
        raw="https://github.com/${raw#ssh://git@github.com/}"
    elif [[ "$raw" == http://github.com/* ]]; then
        raw="https://${raw#http://}"
    fi
    printf '%s' "$raw"
}

fork_id_from_url() {
    local url
    url="$(normalize_url "$1")"
    if [[ -n "${PRESET_CANONICAL[$url]:-}" ]]; then
        printf '%s' "${PRESET_CANONICAL[$url]}"
        return 0
    fi
    printf 'custom'
}

# resolve_fork <preset|url> -- prints "url|branch"
resolve_fork() {
    local arg="$1" key
    key="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')"
    if [[ -n "${PRESET_URLS[$key]:-}" ]]; then
        printf '%s|%s' "${PRESET_URLS[$key]}" "${PRESET_BRANCHES[$key]}"
        return 0
    fi
    local norm
    norm="$(normalize_url "$arg")"
    if [[ "$norm" == https://github.com/*/* ]]; then
        printf '%s|default' "$norm"
        return 0
    fi
    ui_fail "Unknown fork" "$arg is neither a preset nor a GitHub URL"
    return 1
}

# resolve_local <path> -- prints "abspath|kind", kind being repo or ii.
# A fork checkout and the ii config dir inside one are both valid sources; the
# difference is only whether detect_ii_subdir still has work to do.
resolve_local() {
    local raw="${1/#\~/$HOME}" abs
    abs="$(cd -P -- "$raw" 2>/dev/null && pwd)" || {
        ui_fail "No such directory" "$raw"
        return 1
    }
    if [[ "$abs" == "$TARGET_DIR" ]]; then
        ui_fail "Source is the target" "$(tilde "$abs") is what gets replaced"
        return 1
    fi
    if [[ -d "$abs/dots/.config/quickshell" ]]; then
        printf '%s|repo' "$abs"
        return 0
    fi
    if [[ -f "$abs/shell.qml" ]]; then
        printf '%s|ii' "$abs"
        return 0
    fi
    ui_fail "Not a source tree" "$(tilde "$abs")"
    # 2, not 1: this is the one failure worth explaining, and the explanation
    # has to come from the caller — ui_note writes to stdout, which the command
    # substitution around this function would swallow.
    return 2
}

# Sets LOCAL_SRC and LOCAL_KIND from OPT_LOCAL, or leaves both empty.
load_local_src() {
    [[ -n "$OPT_LOCAL" ]] || return 0
    local pair rc=0
    pair="$(resolve_local "$OPT_LOCAL")" || rc=$?
    if ((rc != 0)); then
        ((rc == 2)) && ui_note "Expected dots/.config/quickshell/ii* or a shell.qml at the top."
        exit 1
    fi
    LOCAL_SRC="${pair%|*}"
    LOCAL_KIND="${pair#*|}"
}

read_state() {
    local remote="" branch="" fork=""
    [[ -f "$TARGET_DIR/.active-remote" ]] && remote="$(<"$TARGET_DIR/.active-remote")"
    [[ -f "$TARGET_DIR/.active-branch" ]] && branch="$(<"$TARGET_DIR/.active-branch")"
    [[ -f "$TARGET_DIR/.active-fork" ]] && fork="$(<"$TARGET_DIR/.active-fork")"
    remote="${remote//[$'\r\n']/}"
    branch="${branch//[$'\r\n']/}"
    fork="${fork//[$'\r\n']/}"
    [[ -z "$fork" && -n "$remote" ]] && fork="$(fork_id_from_url "$remote")"
    [[ -z "$branch" ]] && branch="$FALLBACK_BRANCH"
    printf '%s|%s|%s' "$remote" "$branch" "$fork"
}

# The local path the active config was deployed from, or empty.
read_local_state() {
    local p=""
    [[ -f "$TARGET_DIR/.active-local" ]] && p="$(<"$TARGET_DIR/.active-local")"
    printf '%s' "${p//[$'\r\n']/}"
}

require_base() {
    [[ "$OPT_SKIP_BASE_CHECK" == true ]] && return 0
    [[ -d "$BASE_DIR" ]] && return 0
    ui_fail "Base dotfiles missing" "$(tilde "$BASE_DIR") does not exist"
    ui_note "illogical-impulse is not installed. Install it explicitly:"
    ui_note "    $SCRIPT_SELF install"
    ui_note "Or skip this check with --skip-base-check if you know better."
    exit 1
}

migrate_legacy() {
    local moved=false
    mkdir -p "$SETUP_STATE_DIR"
    if [[ -d "$LEGACY_MIRROR_DIR" && ! -e "$MIRROR_DIR" ]]; then
        mv "$LEGACY_MIRROR_DIR" "$MIRROR_DIR" && moved=true
        ui_verbose "Migrated $(tilde "$LEGACY_MIRROR_DIR") to $(tilde "$MIRROR_DIR")"
    fi
    if [[ -d "$LEGACY_BACKUP_DIR" && ! -e "$BACKUP_BASE_DIR" ]]; then
        mkdir -p "$(dirname "$BACKUP_BASE_DIR")"
        mv "$LEGACY_BACKUP_DIR" "$BACKUP_BASE_DIR" && moved=true
        ui_verbose "Migrated $(tilde "$LEGACY_BACKUP_DIR") to $(tilde "$BACKUP_BASE_DIR")"
    fi
    if [[ -f "$LEGACY_LOG_FILE" && -O "$LEGACY_LOG_FILE" ]]; then
        rm -f "$LEGACY_LOG_FILE"
    fi
    # A stale symlink still pointing into the old mirror.
    if [[ -L "$BIN_DIR/$CLI_NAME" ]]; then
        local dest
        dest="$(readlink "$BIN_DIR/$CLI_NAME")"
        [[ "$dest" == "$LEGACY_MIRROR_DIR"/* ]] && install_cli
    fi
    # The CLI used to be called vynx. Retire that name, but only when it is ours
    # to retire and only once the new name is actually in place — a symlink
    # pointing anywhere else belongs to something the user installed themselves.
    if [[ -L "$BIN_DIR/$LEGACY_CLI_NAME" ]]; then
        local old
        old="$(readlink "$BIN_DIR/$LEGACY_CLI_NAME")"
        if [[ "$old" == "$MIRROR_DIR"/* || "$old" == "$LEGACY_MIRROR_DIR"/* ]]; then
            install_cli
            if [[ -L "$BIN_DIR/$CLI_NAME" ]]; then
                rm -f "$BIN_DIR/$LEGACY_CLI_NAME"
                ui_note "The CLI is now called $CLI_NAME; removed the old $LEGACY_CLI_NAME link."
            fi
        fi
    fi
    [[ "$moved" == true ]] && ui_note "Migrated legacy ii-vynx paths to ii-p3drovfx."
    return 0
}

open_log() {
    [[ "$OPT_LOG" == true ]] || return 0
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || return 0
    touch "$LOG_FILE" 2>/dev/null || return 0
    LOG_READY=true
    # Keep the log from growing without bound across many runs.
    if [[ -f "$LOG_FILE" ]]; then
        local lines
        lines="$(wc -l <"$LOG_FILE" 2>/dev/null || echo 0)"
        if ((lines > 5000)); then
            tail -n 2000 "$LOG_FILE" >"$LOG_FILE.trim" 2>/dev/null &&
                mv "$LOG_FILE.trim" "$LOG_FILE"
        fi
    fi
    ui_logline "--- $SCRIPT_SELF $SETUP_VERSION | ${COMMAND:-apply} | args: ${ORIGINAL_ARGS[*]:-} ---"
}

#══════════════════════════════════════════════════════════════════════════════
# Clone / copy with progress
#══════════════════════════════════════════════════════════════════════════════

# tree_stats <dir> — "1284 files ⋅ 4.2M", the tail of a Cloned/Sourced row
tree_stats() {
    local count size
    count="$({ find "$1" -type f -not -path '*/.git/*' 2>/dev/null || true; } | wc -l)"
    size="$(du -sh --exclude=.git "$1" 2>/dev/null | cut -f1)"
    printf '%s files%s' "$count" "${size:+ $G_SEP $size}"
}

# clone_repo <url> <branch> <dest> — <branch> may be "default"
clone_repo() {
    local url="$1" branch="$2" dest="$3"
    local args=(clone --depth=1 --recurse-submodules --progress)
    [[ "$branch" != "default" ]] && args+=(--branch "$branch")
    args+=("$url" "$dest")

    ui_step "Cloning"
    local rc=0
    set +o pipefail
    git "${args[@]}" 2>&1 | tr '\r' '\n' | while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
        # "Receiving objects:  63% (812/1284), 4.20 MiB | 2.00 MiB/s"
        case "$line" in
            Receiving* | Resolving* | Updating*)
                local frag="${line#*\(}"
                frag="${frag%%\)*}"
                if [[ "$frag" == */* && "$frag" != *[!0-9/]* ]]; then
                    ui_progress "${frag%%/*}" "${frag##*/}" "${line%%:*}"
                fi
                ;;
        esac
    done
    rc=${PIPESTATUS[0]}
    set -o pipefail

    if ((rc != 0)); then
        ui_fail "Clone failed" "branch '$branch' on $url"
        ui_note "List what exists with: $SCRIPT_SELF list-branches"
        return 1
    fi

    # --depth=1 can silently skip a submodule pinned to an unreachable SHA.
    git -C "$dest" submodule update --init --recursive --depth=1 >>"$LOG_FILE" 2>&1 || true

    ui_ok "Cloned" "$(tree_stats "$dest")"
    return 0
}

# copy_tree <src>/ <dst>/
copy_tree() {
    local src="$1" dst="$2"
    ui_step "Copying"
    mkdir -p "$dst"
    if have rsync; then
        local rc=0
        set +o pipefail
        rsync -a --info=progress2 --exclude='.git' --exclude='.gitmodules' \
            "$src/" "$dst/" 2>&1 | tr '\r' '\n' | while IFS= read -r line; do
            [[ "$line" =~ ([0-9]+)% ]] && ui_progress "${BASH_REMATCH[1]}" 100 ""
        done
        rc=${PIPESTATUS[0]}
        set -o pipefail
        ((rc == 0)) || {
            ui_fail "Copy failed" "rsync exited $rc"
            return 1
        }
    else
        cp -a "$src/." "$dst/" || {
            ui_fail "Copy failed" "cp exited $?"
            return 1
        }
        find "$dst" -name '.git' -maxdepth 3 -exec rm -rf {} + 2>/dev/null || true
    fi
    ui_ok "Copied" "$(find "$dst" -type f 2>/dev/null | wc -l) files staged"
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# Protected files, backups, atomic swap
#══════════════════════════════════════════════════════════════════════════════

# carry_protected <live_dir> <stage_dir> — prints the number of files carried
carry_protected() {
    local live="$1" stage="$2" n=0
    [[ -d "$live" ]] || {
        printf '0'
        return 0
    }
    local pattern f rel
    for pattern in "${PROTECTED_PATTERNS[@]}"; do
        while IFS= read -r -d '' f; do
            rel="${f#"$live"/}"
            mkdir -p "$stage/$(dirname "$rel")"
            cp -a "$f" "$stage/$rel"
            ui_verbose "carried $rel"
            n=$((n + 1))
        done < <(find "$live" -path "$live/$pattern" -type f -print0 2>/dev/null)
    done
    printf '%s' "$n"
}

# prune_backups [prefix] — keeps the newest BACKUPS_TO_KEEP of one family.
# The families are pruned independently: a run of config replaces must not age
# out the hypr backup that the same run just took.
prune_backups() {
    [[ -d "$BACKUP_BASE_DIR" ]] || return 0
    local prefix="${1:-ii_}" old
    while IFS= read -r old; do
        [[ -n "$old" ]] || continue
        rm -rf "$old"
        ui_verbose "pruned backup $(basename "$old")"
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "$prefix*" -printf '%T@ %p\n' 2>/dev/null |
        sort -rn | tail -n "+$((BACKUPS_TO_KEEP + 1))" | cut -d' ' -f2-)
}

# next_backup_dir <prefix> — a free, timestamped path under BACKUP_BASE_DIR.
# Second resolution is not enough for two runs in the same second.
next_backup_dir() {
    local base dir n=2
    base="$BACKUP_BASE_DIR/$1$(date +%Y%m%d-%H%M%S)"
    dir="$base"
    while [[ -e "$dir" ]]; do
        dir="$base-$n"
        n=$((n + 1))
    done
    printf '%s' "$dir"
}

# swap_in <stage> <fork_id> <branch> — atomically replaces TARGET_DIR
swap_in() {
    local stage="$1" fork="$2" branch="$3"
    ui_step "Swapping"

    local label=""
    if [[ -d "$TARGET_DIR" ]]; then
        if [[ "$OPT_BACKUP" == true ]]; then
            mkdir -p "$BACKUP_BASE_DIR"
            # A unique name matters more here than elsewhere: mv onto an
            # existing directory nests the config inside it rather than
            # replacing it, and the run after that fails outright.
            DISPLACED_DIR="$(next_backup_dir "ii_$(path_slug "$fork")_$(path_slug "$branch")_")"
            label="backup $G_ARROW $(basename "$DISPLACED_DIR")"
        else
            DISPLACED_DIR="$QS_DIR/.ii-discard-$$"
            label="previous config discarded"
        fi
        if ! mv "$TARGET_DIR" "$DISPLACED_DIR"; then
            DISPLACED_DIR=""
            ui_fail "Swap failed" "could not move the current config aside"
            return 1
        fi
        SWAP_STATE="moved-away"
    fi

    if ! mv "$stage" "$TARGET_DIR"; then
        ui_fail "Swap failed" "could not move the staged config into place"
        return 1
    fi
    STAGE_DIR=""
    SWAP_STATE="done"

    if [[ "$OPT_BACKUP" == false && -n "$DISPLACED_DIR" ]]; then
        rm -rf "$DISPLACED_DIR"
        DISPLACED_DIR=""
    else
        prune_backups
    fi

    ui_ok "Swapped" "${label:-fresh install}"
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# Repo introspection
#══════════════════════════════════════════════════════════════════════════════

detect_ii_subdir() {
    local repo="$1"
    local base="$repo/dots/.config/quickshell"
    if [[ -n "$OPT_II_SUBDIR" ]]; then
        if [[ -d "$base/$OPT_II_SUBDIR" ]]; then
            printf '%s' "$base/$OPT_II_SUBDIR"
            return 0
        fi
        ui_fail "Missing subdir" "--ii-subdir '$OPT_II_SUBDIR' not found under dots/.config/quickshell"
        return 1
    fi
    [[ -d "$base" ]] || {
        ui_fail "Not a Quickshell rice" "no dots/.config/quickshell in the repository"
        return 1
    }
    local -a found=()
    while IFS= read -r d; do found+=("$d"); done < <(
        find "$base" -mindepth 1 -maxdepth 1 -type d -name 'ii*' ! -name '*.bak*' ! -name '*.tmp*' ! -name '*backup*' 2>/dev/null | sort
    )
    if ((${#found[@]} == 0)); then
        ui_fail "Not a Quickshell rice" "no ii* directory under dots/.config/quickshell"
        return 1
    fi
    if ((${#found[@]} > 1)); then
        ui_warn "${#found[@]} ii* dirs found; using $(basename "${found[0]}")"
    fi
    printf '%s' "${found[0]}"
}

# Where a bare run should pull from: this checkout's origin and current branch.
local_origin() {
    local remote="" branch=""
    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        remote="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
        [[ -n "$remote" ]] && remote="$(normalize_url "$remote")"
        branch="$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ "$branch" == "HEAD" ]] && branch=""
    fi
    [[ -z "$remote" ]] && {
        remote="$FALLBACK_URL"
        branch="$FALLBACK_BRANCH"
    }
    [[ -z "$branch" ]] && branch="$FALLBACK_BRANCH"
    printf '%s|%s|%s' "$remote" "$branch" "$(fork_id_from_url "$remote")"
}

#══════════════════════════════════════════════════════════════════════════════
# Quickshell
#══════════════════════════════════════════════════════════════════════════════

# ensure_quickshell_git — put the AUR quickshell-git back after a base install.
#
# The base installer builds its own illogical-impulse-quickshell-git from a
# commit pinned months ago and drops quickshell-git on the way. This fork is
# written against Quickshell master, so the pinned build is normally older
# than the QML expects and the shell fails to start. Undo that before any
# config lands, which is why install is the only command that calls this.
#
# Arch only: every other distro packages Quickshell its own way, and the
# pinned PKGBUILD is an Arch-specific problem.
ensure_quickshell_git() {
    have pacman || return 0
    if pacman -Qq quickshell-git >/dev/null 2>&1; then
        ui_verbose "quickshell-git already installed"
        return 0
    fi

    local current
    current="$(pacman -Qqo /usr/bin/quickshell 2>/dev/null || true)"

    ui_frame_open "Quickshell package"
    ui_kv "installed" "${current:-none}"
    ui_kv "wanted" "quickshell-git"
    ui_frame_close
    ui_note "This fork follows Quickshell master. The pinned build the base"
    ui_note "installer ships is older, and the shell will not start on it."

    # yay first because that is what the base installer bootstraps, but paru
    # takes the same flags and plenty of people have only that one.
    local helper="" h
    for h in yay paru; do
        have "$h" && {
            helper="$h"
            break
        }
    done
    [[ -n "$helper" ]] || {
        ui_warn "No AUR helper found — install quickshell-git with yay or paru yourself."
        return 0
    }

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        local q="Install quickshell-git?"
        [[ -n "$current" ]] && q="Replace $current with quickshell-git?"
        ui_confirm "$q" || {
            ui_note "Left as is. The shell may not start."
            return 0
        }
    fi

    # Swapping the packages orphans every Qt module the meta-package pulled in
    # as a dependency, and a later `yay -Yc` would then sweep away half of what
    # the shell needs at runtime. Diff the orphan list around the swap so the
    # ones it strands can be marked wanted, without having to guess the list.
    local before after
    before="$(pacman -Qdtq 2>/dev/null | sort || true)"

    ui_info "Running $helper -S quickshell-git — its own output follows."
    printf '\n'
    local -a flags=(-S --needed)
    [[ "$OPT_ASSUME_YES" == true ]] && flags+=(--noconfirm)
    local rc=0
    "$helper" "${flags[@]}" quickshell-git || rc=$?
    printf '\n'
    if ((rc != 0)); then
        ui_warn "quickshell-git install failed (exit $rc) — fix it before starting the shell."
        return 0
    fi

    after="$(pacman -Qdtq 2>/dev/null | sort || true)"
    local -a stranded=()
    mapfile -t stranded < <(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -v '^$' || true)
    if ((${#stranded[@]} > 0)); then
        run_logged sudo pacman -D -q --asexplicit "${stranded[@]}" ||
            ui_warn "Could not mark ${#stranded[@]} stranded deps explicit."
        ui_verbose "kept: ${stranded[*]}"
        ui_ok "Kept" "${#stranded[@]} Qt deps marked explicit"
    fi

    ui_ok "Quickshell" "$(pacman -Qq quickshell-git 2>/dev/null || printf 'quickshell-git')"
}

qt_mismatch() {
    have quickshell || return 1
    local msg
    msg="$(quickshell --version 2>&1 | grep -iE 'warning|mismatch|abi|symbol' || true)"
    [[ -n "$msg" ]] || return 1
    ui_warn "Quickshell reports a Qt ABI/symbol mismatch:"
    ui_note "$msg"
    return 0
}

build_quickshell() {
    ui_step "Deps"
    if [[ -f /etc/arch-release ]]; then
        run_logged sudo pacman -Sy --needed --noconfirm cmake extra-cmake-modules \
            qt6-base qt6-declarative qt6-wayland wayland libxkbcommon gcc git ||
            ui_warn "Dependency install reported errors; continuing."
        ui_ok "Deps" "arch"
    elif [[ -f /etc/fedora-release ]]; then
        run_logged sudo dnf install -y cmake extra-cmake-modules qt6-qtbase-devel \
            qt6-qtdeclarative-devel qt6-qtwayland-devel wayland-devel \
            libxkbcommon-devel gcc-c++ git ||
            ui_warn "Dependency install reported errors; continuing."
        ui_ok "Deps" "fedora"
    elif [[ -f /etc/debian_version ]]; then
        run_logged sudo apt-get update || true
        run_logged sudo apt-get install -y cmake extra-cmake-modules qt6-base-dev \
            qt6-declarative-dev qt6-wayland-dev libwayland-dev libxkbcommon-dev g++ git ||
            ui_warn "Dependency install reported errors; continuing."
        ui_ok "Deps" "debian"
    else
        ui_warn "Unknown distribution — install cmake, Qt6 dev packages and a C++ compiler yourself."
    fi

    local build_dir
    build_dir="$(mktemp -d "${TMPDIR:-/tmp}/quickshell-build-XXXXXX")"

    ui_step "Fetching"
    if ! run_logged git clone --depth=1 --recursive \
        https://github.com/outfoxxed/quickshell.git "$build_dir"; then
        rm -rf "$build_dir"
        ui_fail "Quickshell source" "clone failed"
        return 1
    fi
    ui_ok "Fetched" "outfoxxed/quickshell"

    ui_step "Configuring"
    if ! run_logged cmake -B "$build_dir/build" -S "$build_dir" \
        -DCMAKE_INSTALL_PREFIX="$HOME/.local" -DCRASH_HANDLER=OFF; then
        rm -rf "$build_dir"
        ui_fail "Quickshell build" "cmake configure failed"
        return 1
    fi
    ui_ok "Configured" "prefix ~/.local"

    ui_step "Compiling"
    run_logged cmake --build "$build_dir/build" -t quickshell-dbus -j"$(nproc)" || true
    local rc=0
    set +o pipefail
    cmake --build "$build_dir/build" -j"$(nproc)" 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true
        [[ "$line" =~ ^\[[[:space:]]*([0-9]+)%\] ]] && ui_progress "${BASH_REMATCH[1]}" 100 ""
    done
    rc=${PIPESTATUS[0]}
    set -o pipefail
    if ((rc != 0)); then
        rm -rf "$build_dir"
        ui_fail "Quickshell build" "compilation failed (see $(tilde "$LOG_FILE"))"
        return 1
    fi
    ui_ok "Compiled" "quickshell"

    ui_step "Installing"
    if ! run_logged cmake --install "$build_dir/build"; then
        rm -rf "$build_dir"
        ui_fail "Quickshell install" "cmake --install failed"
        return 1
    fi
    rm -rf "$build_dir"
    ui_ok "Installed" "$(tilde "$HOME/.local/bin/quickshell")"
    return 0
}

# Quickshell watches its config tree and hot-reloads the moment anything in it
# changes. Swapping the tree out from under a live instance therefore makes it
# reload onto half the new config with the old process' state still loaded —
# which is how config.json ends up rewritten with defaults. Every path that
# touches the tree stops the shell first and starts it again afterwards.
# `qs` is a symlink to `quickshell`, and the process name follows whichever one
# was used to launch it, so both have to be matched. Missing one leaves a second
# instance alive writing its own schema over config.json.
quickshell_running() {
    pgrep -x qs >/dev/null 2>&1 || pgrep -x quickshell >/dev/null 2>&1
}

stop_quickshell() {
    [[ "$OPT_RESTART" == true ]] || return 0
    quickshell_running || return 0

    # A signalled Quickshell exits without reaping the processes it spawned, so
    # each restart leaves its long-lived children — the nmcli monitor above all —
    # running and reparented to init, one more every time. Asking it to quit over
    # its own IPC socket is the only shutdown that cleans up after itself, and it
    # gives Component.onDestruction, which blocks the final config.json write,
    # a proper chance to run.
    local bin=""
    have qs && bin="qs"
    [[ -n "$bin" ]] || { have quickshell && bin="quickshell"; }

    local stopped=false
    if [[ -n "$bin" ]]; then
        if [[ "$TARGET_DIR" == "$QS_DIR/ii" ]]; then
            "$bin" kill -c ii >>"$LOG_FILE" 2>&1 && stopped=true
        else
            "$bin" kill --path "$TARGET_DIR" >>"$LOG_FILE" 2>&1 && stopped=true
        fi
    fi

    # `kill` returns once the request is sent, not once the shell is gone.
    local waited=0
    while [[ "$stopped" == true ]] && (( waited < 30 )) && quickshell_running; do
        sleep 0.1
        waited=$((waited + 1))
    done

    # Wedged, or too old to answer over IPC: the blunt path, which is the one
    # that strands children, so it is only taken when it has to be.
    local killed=false
    if quickshell_running; then
        for name in qs quickshell; do
            pkill -x "$name" 2>/dev/null && killed=true
        done
        [[ "$killed" == true ]] && sleep 0.5
    fi

    [[ "$stopped" == true || "$killed" == true ]] && ui_ok "Stopped" "running Quickshell instance"
    return 0
}

start_quickshell() {
    [[ "$OPT_RESTART" == true ]] || {
        ui_note "Restart skipped (--no-restart)."
        return 0
    }
    local bin=""
    if have qs; then
        bin="qs"
    elif have quickshell; then
        bin="quickshell"
    else
        ui_warn "Neither qs nor quickshell on PATH — start Quickshell yourself."
        return 0
    fi

    ui_step "Starting"
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && have hyprctl; then
        hyprctl reload >>"$LOG_FILE" 2>&1 || ui_warn "hyprctl reload failed."
        sleep 0.5
    fi
    if [[ "$TARGET_DIR" == "$QS_DIR/ii" ]]; then
        nohup "$bin" -c ii >/dev/null 2>&1 &
        ui_ok "Started" "$bin -c ii"
    else
        nohup "$bin" --path "$TARGET_DIR" >/dev/null 2>&1 &
        ui_ok "Started" "$bin --path $(tilde "$TARGET_DIR")"
    fi
    return 0
}

open_welcome_after_start() {
    local attempt
    local ipc_bin=""

    if have qs; then
        ipc_bin="qs"
    elif have quickshell; then
        ipc_bin="quickshell"
    else
        ui_warn "Welcome couldn't be opened because neither qs nor quickshell is on PATH."
        return 0
    fi

    for attempt in {1..50}; do
        if "$ipc_bin" -c ii ipc call welcome open >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done

    ui_warn "Welcome couldn't be opened yet. Once Quickshell is ready, run: $ipc_bin -c ii ipc call welcome open"
    return 0
}

restart_quickshell() {
    [[ "$OPT_RESTART" == true ]] || {
        ui_note "Restart skipped (--no-restart)."
        return 0
    }
    if ! have qs && ! have quickshell; then
        ui_warn "Neither qs nor quickshell on PATH — start Quickshell yourself."
        return 0
    fi

    stop_quickshell
    start_quickshell
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# CLI install / removal
#══════════════════════════════════════════════════════════════════════════════

install_cli() {
    mkdir -p "$BIN_DIR"
    local script="$MIRROR_DIR/$SCRIPT_SELF"
    [[ -f "$script" ]] || script="$SCRIPT_DIR/$SCRIPT_SELF"
    [[ -f "$script" ]] || return 0
    chmod +x "$script" 2>/dev/null || true
    ln -sfn "$script" "$BIN_DIR/$CLI_NAME"
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
        ui_warn "$(tilde "$BIN_DIR") is not on PATH."
        ui_note "Add to your shell rc:  set -gx PATH \$HOME/.local/bin \$PATH"
    fi
    return 0
}

mirror_scripts() {
    local from="$1"
    ui_step "Mirroring"
    mkdir -p "$MIRROR_DIR"
    local copied=0 f
    for f in "$SCRIPT_SELF" setup update-fork.sh; do
        if [[ -e "$from/$f" ]]; then
            cp -a "$from/$f" "$MIRROR_DIR/$f"
            chmod +x "$MIRROR_DIR/$f" 2>/dev/null || true
            copied=$((copied + 1))
        fi
    done
    # A fork whose remote has not picked up the rename yet still gets a working
    # mirror: fall back to the copy that is running right now.
    if [[ ! -f "$MIRROR_DIR/$SCRIPT_SELF" && -f "$SCRIPT_DIR/$SCRIPT_SELF" ]]; then
        cp -a "$SCRIPT_DIR/$SCRIPT_SELF" "$MIRROR_DIR/$SCRIPT_SELF"
        chmod +x "$MIRROR_DIR/$SCRIPT_SELF"
        copied=$((copied + 1))
    fi
    if [[ -d "$from/sdata" ]]; then
        rm -rf "$MIRROR_DIR/sdata"
        cp -a "$from/sdata" "$MIRROR_DIR/sdata"
        find "$MIRROR_DIR/sdata" -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
        copied=$((copied + 1))
    fi
    # Scripts that used to live here and no longer ship.
    local obsolete
    for obsolete in setup-ii-vynx.sh update-with-customs.sh; do
        rm -f "${MIRROR_DIR:?}/$obsolete"
    done
    install_cli
    ui_ok "Mirrored" "$copied items $G_ARROW $(tilde "$MIRROR_DIR")"
}

remove_cli() {
    local target="$BIN_DIR/$CLI_NAME"
    if [[ -L "$target" ]]; then
        ui_confirm "Remove the $CLI_NAME CLI from $(tilde "$target")?" || {
            ui_note "Cancelled."
            return 0
        }
        rm -f "$target"
        ui_ok "Removed" "$(tilde "$target")"
        ui_note "$(tilde "$MIRROR_DIR") is left intact."
    else
        ui_warn "No $CLI_NAME symlink at $(tilde "$target")."
        local alt
        alt="$(command -v "$CLI_NAME" 2>/dev/null || true)"
        [[ -n "$alt" ]] && ui_note "Found $CLI_NAME at $alt — remove that one by hand."
    fi
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# The pipeline
#══════════════════════════════════════════════════════════════════════════════

backup_hyprland_config() {
    local dest="$XDG_CONFIG_HOME/hypr"
    [[ -d "$dest" ]] || return 0
    [[ "$OPT_BACKUP" == true ]] || return 0

    local backup_dir entry
    # Its own family under the shared backup dir, next to the ii ones, so the
    # snapshots are pruned like every other family instead of piling up inside
    # ~/.config/hypr forever. The prefix must not be matched by the "hypr_"
    # glob, or pruning replaced files would age these out too.
    backup_dir="$(next_backup_dir "hyprland_")"
    mkdir -p "$backup_dir" || {
        ui_warn "Could not create Hyprland backup directory: $(tilde "$backup_dir")"
        return 1
    }

    # Snapshots older versions of this script left in place are skipped: they
    # are backups themselves, and copying them would nest one inside the next.
    while IFS= read -r -d '' entry; do
        cp -a "$entry" "$backup_dir/" || {
            ui_warn "Could not back up Hyprland config entry: $(basename "$entry")"
            return 1
        }
    done < <(find "$dest" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | while IFS= read -r -d '' entry; do
        [[ "$(basename "$entry")" == hyprland_backup_* ]] || printf '%s\0' "$entry"
    done)

    prune_backups "hyprland_"
    ui_note "Hyprland backup: $(tilde "$backup_dir")"
}

# install_hypr_config <repo_root>
#
# Overlays the fork's dots/.config/hypr onto ~/.config/hypr. An overlay and not
# a replace: files the repo does not ship — monitors.conf, your own scripts —
# stay exactly where they are. Anything overwritten is copied to the backup dir
# first unless --no-backup, and identical files are left alone so a re-run
# neither writes nor backs anything up.
install_hypr_config() {
    local repo_root="${1:-}"
    local dest="$XDG_CONFIG_HOME/hypr"

    [[ "$OPT_HYPR" == false ]] && return 0

    local src="$repo_root/dots/.config/hypr"
    if [[ -z "$repo_root" || ! -d "$src" ]]; then
        # Worth a word only when it was actually asked for. Otherwise the
        # source simply has no hypr dots to offer — an ii config dir passed to
        # --local never does — and silence is the right answer.
        [[ "$OPT_HYPR" == true ]] &&
            ui_warn "No dots/.config/hypr in the source — nothing to install."
        return 0
    fi

    if [[ -z "$OPT_HYPR" ]]; then
        # -y declines this one instead of accepting it. The Settings update
        # button runs unattended, and unattended is no time to rewrite the
        # compositor's config underneath somebody. --hypr is the explicit yes.
        if [[ "$OPT_ASSUME_YES" == true ]]; then
            ui_note "Left $(tilde "$dest") alone. Pass --hypr to install it."
            return 0
        fi
        ui_confirm "Also install this fork's Hyprland config into $(tilde "$dest")?" yes || {
            ui_note "Left $(tilde "$dest") alone."
            return 0
        }
    fi
    backup_hyprland_config || return 1

    ui_step "Hyprland"
    local backup_dir="" added=0 replaced=0 seeded=0 kept=0 same=0
    local f rel excluded seed d

    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"

        excluded=false
        for d in "${HYPR_EXCLUDE_DIRS[@]}"; do
            [[ "$rel" == "$d/"* ]] && {
                excluded=true
                break
            }
        done
        [[ "$excluded" == true ]] && continue

        seed=false
        for d in "${HYPR_SEED_ONLY[@]}"; do
            [[ "$rel" == "$d" ]] && {
                seed=true
                break
            }
        done

        if [[ -e "$dest/$rel" ]]; then
            if [[ "$seed" == true ]]; then
                kept=$((kept + 1))
                ui_verbose "kept generated $rel"
                continue
            fi
            if cmp -s "$f" "$dest/$rel"; then
                same=$((same + 1))
                continue
            fi
            if [[ "$OPT_BACKUP" == true ]]; then
                [[ -n "$backup_dir" ]] || {
                    backup_dir="$(next_backup_dir "hypr_")"
                    mkdir -p "$backup_dir"
                }
                mkdir -p "$backup_dir/$(dirname "$rel")"
                cp -a "$dest/$rel" "$backup_dir/$rel"
            fi
            replaced=$((replaced + 1))
        elif [[ "$seed" == true ]]; then
            seeded=$((seeded + 1))
        else
            added=$((added + 1))
        fi

        mkdir -p "$dest/$(dirname "$rel")"
        cp -a "$f" "$dest/$rel"
        [[ "$rel" == *.sh ]] && chmod +x "$dest/$rel" 2>/dev/null
        ui_verbose "wrote $rel"
    done < <(find "$src" -mindepth 1 -type f -print0 2>/dev/null | sort -z)

    local touched=$((added + replaced + seeded))
    if ((touched == 0)); then
        ui_ok "Hyprland" "already current $G_DOT $((same + kept)) files unchanged"
        return 0
    fi

    [[ -n "$backup_dir" ]] && prune_backups "hypr_"
    local detail="$replaced replaced, $added new"
    ((seeded > 0)) && detail="$detail, $seeded seeded"
    ((kept > 0)) && detail="$detail, $kept generated kept"
    ui_ok "Hyprland" "$detail"
    [[ -n "$backup_dir" ]] && ui_note "Replaced files: $(tilde "$backup_dir")"

    # Sub-files of the config are not watched, so nothing would pick these up
    # until the next relog. No-op when Hyprland is not the session, which is
    # exactly the case mid-install on a bare machine.
    if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && have hyprctl; then
        hyprctl reload >/dev/null 2>&1 || ui_warn "hyprctl reload failed — relog to apply."
    fi
    return 0
}

# apply_config <url> <branch> <fork_id> <verb>
apply_config() {
    local url="$1" branch="$2" fork="$3" verb="$4"
    local head="" source_dir="" dirty=""

    if [[ -n "$LOCAL_SRC" ]]; then
        # A local deploy has no remote to speak of, so everything the state
        # files normally carry comes off the checkout instead. .active-local
        # marks the result, which is what makes `update` refuse later rather
        # than silently redeploy a path it only guessed at.
        fork="local"
        url="$LOCAL_SRC"
        branch="$(git -C "$LOCAL_SRC" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        [[ -z "$branch" || "$branch" == "HEAD" ]] && branch="nobranch"
        head="$(git -C "$LOCAL_SRC" rev-parse HEAD 2>/dev/null || true)"
        git -C "$LOCAL_SRC" diff --quiet HEAD 2>/dev/null || dirty="uncommitted changes"
    else
        url="$(normalize_url "$url")"
        [[ -z "$fork" ]] && fork="$(fork_id_from_url "$url")"
        [[ -z "$branch" ]] && branch="$FALLBACK_BRANCH"
    fi

    ui_frame_open "Resolve"
    if [[ -n "$LOCAL_SRC" ]]; then
        ui_kv "source" "local $LOCAL_KIND"
        ui_kv "path" "$(tilde "$LOCAL_SRC")"
        ui_kv "branch" "$branch"
        [[ -n "$dirty" ]] && ui_kv "state" "$dirty"
    else
        ui_kv "fork" "$fork"
        ui_kv "remote" "${url#https://}"
        ui_kv "branch" "$branch"
    fi
    ui_kv "target" "$(tilde "$TARGET_DIR")"
    ui_kv "backup" "$([[ "$OPT_BACKUP" == true ]] && printf '%s' "$(tilde "$BACKUP_BASE_DIR")" || printf 'disabled')"
    ui_frame_close

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        local with="$fork/$branch"
        [[ -n "$LOCAL_SRC" ]] && with="$(tilde "$LOCAL_SRC")"
        ui_confirm "Replace $(tilde "$TARGET_DIR") with $with?" yes || {
            ui_note "Cancelled."
            return 0
        }
    fi

    if [[ -n "$LOCAL_SRC" ]]; then
        if [[ "$LOCAL_KIND" == "repo" ]]; then
            source_dir="$(detect_ii_subdir "$LOCAL_SRC")" || return 1
        else
            source_dir="$LOCAL_SRC"
        fi
        ui_ok "Sourced" "$(tree_stats "$source_dir")"
        ui_verbose "source: $source_dir"
    else
        CLONE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-clone-XXXXXX")"
        clone_repo "$url" "$branch" "$CLONE_DIR" || return 1

        # Clone with branch "default" resolves to whatever HEAD points at.
        if [[ "$branch" == "default" ]]; then
            branch="$(git -C "$CLONE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main')"
        fi
        head="$(git -C "$CLONE_DIR" rev-parse HEAD 2>/dev/null || true)"

        source_dir="$(detect_ii_subdir "$CLONE_DIR")" || return 1
        ui_verbose "source: ${source_dir#"$CLONE_DIR"/}"
    fi

    mkdir -p "$QS_DIR"
    STAGE_DIR="$(mktemp -d "$QS_DIR/.ii-stage-XXXXXX")"
    copy_tree "$source_dir" "$STAGE_DIR" || return 1

    ui_step "Staging"
    local carried
    carried="$(carry_protected "$TARGET_DIR" "$STAGE_DIR")"
    printf '%s\n' "$url" >"$STAGE_DIR/.active-remote"
    printf '%s\n' "$branch" >"$STAGE_DIR/.active-branch"
    printf '%s\n' "$fork" >"$STAGE_DIR/.active-fork"
    if [[ -n "$LOCAL_SRC" ]]; then
        printf '%s\n' "$LOCAL_SRC" >"$STAGE_DIR/.active-local"
    else
        # Copied from a source tree that may itself have been deployed locally.
        rm -f "$STAGE_DIR/.active-local"
    fi
    [[ -n "$head" ]] && printf '%s\n' "$head" >"$STAGE_DIR/.active-commit"
    if [[ -d "$STAGE_DIR/scripts" ]]; then
        find "$STAGE_DIR/scripts" -type f \
            \( -name '*.sh' -o -name '*.py' -o -name '*.js' \) \
            -exec chmod +x {} + 2>/dev/null || true
    fi
    chmod 0755 "$STAGE_DIR"
    ui_ok "Staged" "$carried protected file$([[ "$carried" == "1" ]] || printf 's') carried"

    # Mirror before the swap, never after. The settings panel runs the mirrored
    # copy, so a fault in swap_in used to be self-perpetuating: the swap failed,
    # the mirror was never refreshed, and the panel kept running the same broken
    # script with no way to heal itself. A clone that reached this point is
    # sound, so its manager is always safe to install.
    # The hypr dots sit beside the ii config dir rather than inside it, so the
    # source tree has to survive until they have been read out of it.
    local repo_root=""
    if [[ -n "$LOCAL_SRC" ]]; then
        [[ "$LOCAL_KIND" == "repo" ]] && repo_root="$LOCAL_SRC"
        mirror_scripts "$LOCAL_SRC"
    else
        repo_root="$CLONE_DIR"
        mirror_scripts "$CLONE_DIR"
    fi

    # Stop before the swap, not after. swap_in moves the live tree aside and
    # deletes it, and a running Quickshell reacts to that by hot-reloading onto
    # whatever is at the path by then. Its config singleton reloads mid-swap and
    # can persist QML defaults over the user's config.json — the reset people
    # end up fixing by deleting the file. Nothing touches the tree until the
    # shell is down.
    stop_quickshell

    swap_in "$STAGE_DIR" "$fork" "$branch" || return 1

    # After the swap: a swap that failed leaves ~/.config/hypr untouched too,
    # so a half-applied pair of configs is not a state you can end up in.
    install_hypr_config "$repo_root"

    if [[ -z "$LOCAL_SRC" && -n "$CLONE_DIR" ]]; then
        rm -rf "$CLONE_DIR"
        CLONE_DIR=""
    fi

    handle_base_config "$verb"

    start_quickshell

    # Applying again is still an installation experience, and switching a fork
    # introduces a potentially different shell. Only an in-place update should
    # preserve the current session without reopening onboarding. `fork` and
    # `branch` are normalized to `switch` before reaching this function.
    if [[ "$verb" != "update" ]]; then
        open_welcome_after_start
    fi

    local summary="$fork/$branch${head:+ @ ${head:0:8}}"
    [[ -n "$LOCAL_SRC" ]] && summary="local $G_ARROW $(tilde "$LOCAL_SRC")"
    ui_result ok "$verb complete $G_DOT $(ui_elapsed)" \
        "$summary" \
        "$(tilde "$TARGET_DIR")"
    return 0
}

# The real user config lives outside the Quickshell dir, so replacing ii never
# touches it. Reset it only when the schema is likely to have changed.
handle_base_config() {
    local verb="$1"
    [[ -f "$BASE_CONFIG_FILE" ]] || return 0

    local keep="$OPT_KEEP_CONFIG"
    if [[ -z "$keep" ]]; then
        # Fork switches change the option schema; updates and branch hops do not.
        [[ "$verb" == "switch" ]] && keep=false || keep=true
    fi
    if [[ "$keep" == true ]]; then
        ui_note "Kept $(tilde "$BASE_CONFIG_FILE")."
        return 0
    fi

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        ui_confirm "Reset $(tilde "$BASE_CONFIG_FILE")? A backup is kept." || {
            ui_note "Kept the existing config."
            return 0
        }
    fi
    local dest
    dest="${BASE_CONFIG_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$BASE_CONFIG_FILE" "$dest"
    ui_ok "Reset" "config.json $G_ARROW $(basename "$dest")"
    return 0
}

#══════════════════════════════════════════════════════════════════════════════
# Commands
#══════════════════════════════════════════════════════════════════════════════

cmd_apply() {
    require_base
    load_local_src
    local origin url branch fork
    origin="$(local_origin)"
    url="${origin%%|*}"
    local rest="${origin#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"
    [[ -n "$OPT_FORK" ]] && {
        local pair
        pair="$(resolve_fork "$OPT_FORK")" || exit 1
        url="${pair%|*}"
        branch="${pair#*|}"
        fork="$(fork_id_from_url "$url")"
    }
    [[ -n "$OPT_BRANCH" ]] && branch="$OPT_BRANCH"

    ui_banner "ii-p3drovfx" "apply"
    apply_config "$url" "$branch" "$fork" "apply"
}

cmd_install() {
    load_local_src
    if [[ -n "$LOCAL_SRC" && "$LOCAL_KIND" != "repo" ]]; then
        ui_fail "Not a fork checkout" "$(tilde "$LOCAL_SRC") is an ii config dir"
        ui_note "install runs ./setup from the repository root. Point --local at that."
        exit 1
    fi

    ui_banner "ii-p3drovfx" "install"
    ui_note "Installs illogical-impulse first, then this fork's Quickshell config."
    printf '\n'

    local origin url branch fork
    origin="$(local_origin)"
    url="${origin%%|*}"
    local rest="${origin#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"
    if [[ -n "$OPT_FORK" ]]; then
        local pair
        pair="$(resolve_fork "$OPT_FORK")" || exit 1
        url="${pair%|*}"
        branch="${pair#*|}"
        fork="$(fork_id_from_url "$url")"
    fi
    [[ -n "$OPT_BRANCH" ]] && branch="$OPT_BRANCH"

    ui_frame_open "Base install"
    if [[ -n "$LOCAL_SRC" ]]; then
        ui_kv "source" "$(tilde "$LOCAL_SRC")"
    else
        ui_kv "source" "${url#https://}"
        ui_kv "branch" "$branch"
    fi
    ui_kv "runs" "./setup install"
    ui_frame_close

    if [[ "$OPT_ASSUME_YES" != true ]]; then
        ui_confirm "Install the base dotfiles now? This installs system packages." || {
            ui_note "Cancelled."
            return 0
        }
    fi

    # The base installer lives in the repository, not in the ii config dir, so
    # it comes from a fresh clone rather than from a possibly stale mirror —
    # unless a local checkout was named, which is the whole point of --local.
    local base_root
    if [[ -n "$LOCAL_SRC" ]]; then
        base_root="$LOCAL_SRC"
    else
        CLONE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ii-base-XXXXXX")"
        clone_repo "$url" "$branch" "$CLONE_DIR" || return 1
        base_root="$CLONE_DIR"
    fi

    local -a runner=(./setup install)
    if [[ ! -x "$base_root/setup" ]]; then
        if [[ ! -f "$base_root/setup" ]]; then
            if [[ -n "$LOCAL_SRC" ]]; then
                ui_fail "No base installer" "$(tilde "$base_root") has no ./setup"
            else
                ui_fail "No base installer" "$url has no ./setup at $branch"
            fi
            return 1
        fi
        if [[ -n "$LOCAL_SRC" ]]; then
            # Never chmod somebody's working tree just to run their installer.
            runner=(bash ./setup install)
        else
            chmod +x "$base_root/setup"
        fi
    fi

    ui_info "Handing over to ./setup install — its own output follows."
    printf '\n'
    local rc=0
    (cd "$base_root" && "${runner[@]}") || rc=$?
    printf '\n'
    if ((rc != 0)); then
        ui_fail "Base install failed" "./setup install exited $rc"
        return 1
    fi
    ui_ok "Base ready" "illogical-impulse installed"

    if [[ -z "$LOCAL_SRC" ]]; then
        rm -rf "$CLONE_DIR"
        CLONE_DIR=""
    fi

    # Before any config files land, so the shell the user ends up looking at
    # is running the Quickshell this fork was written against.
    ensure_quickshell_git

    OPT_SKIP_BASE_CHECK=true
    apply_config "$url" "$branch" "$fork" "install"
}

cmd_update() {
    require_base
    load_local_src

    # The active config came off somebody's working tree. Re-cloning the fork it
    # happens to sit in would quietly undo their changes, and there is no honest
    # way to tell whether the path is still the one they meant, so say so.
    local prev
    prev="$(read_local_state)"
    if [[ -n "$prev" && -z "$LOCAL_SRC" ]]; then
        ui_fail "Deployed from a local path" "$(tilde "$prev")"
        ui_note "Re-run with the path:  $SCRIPT_SELF update --local $(tilde "$prev")"
        ui_note "Or go back to a remote: $SCRIPT_SELF fork p3drovfx"
        exit 1
    fi

    local state url branch fork
    state="$(read_state)"
    url="${state%%|*}"
    local rest="${state#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"

    if [[ -z "$url" && -z "$LOCAL_SRC" ]]; then
        ui_fail "Nothing to update" "no .active-remote in $(tilde "$TARGET_DIR")"
        ui_note "Pick a fork explicitly:  $SCRIPT_SELF fork p3drovfx"
        exit 1
    fi
    [[ -n "$OPT_BRANCH" ]] && branch="$OPT_BRANCH"

    ui_banner "ii-p3drovfx" "update"
    apply_config "$url" "$branch" "$fork" "update"
}

cmd_switch() {
    require_base
    load_local_src
    if [[ -z "$OPT_FORK" && -z "$OPT_BRANCH" && -z "$LOCAL_SRC" ]]; then
        ui_fail "Nothing to switch" "pass --fork <preset|url>, --branch <name> or --local <path>"
        exit 1
    fi

    local url="" branch="" fork=""
    if [[ -n "$LOCAL_SRC" ]]; then
        : # apply_config reads the checkout itself
    elif [[ -n "$OPT_FORK" ]]; then
        local pair
        pair="$(resolve_fork "$OPT_FORK")" || exit 1
        url="${pair%|*}"
        branch="${pair#*|}"
        fork="$(fork_id_from_url "$url")"
    else
        local state rest
        state="$(read_state)"
        url="${state%%|*}"
        rest="${state#*|}"
        branch="${rest%%|*}"
        fork="${rest##*|}"
        if [[ -z "$url" ]] || [[ -n "$(read_local_state)" ]]; then
            ui_fail "No active fork" "no remote recorded in $(tilde "$TARGET_DIR")"
            ui_note "Pass --fork as well, or run:  $SCRIPT_SELF fork p3drovfx"
            exit 1
        fi
    fi
    [[ -n "$OPT_BRANCH" ]] && branch="$OPT_BRANCH"

    ui_banner "ii-p3drovfx" "switch"
    apply_config "$url" "$branch" "$fork" "switch"
}

cmd_list_forks() {
    ui_banner "ii-p3drovfx" "forks"
    ui_frame_open "Presets"
    local url id aliases
    for url in "${!PRESET_CANONICAL[@]}"; do
        id="${PRESET_CANONICAL[$url]}"
        aliases=""
        local k
        for k in "${!PRESET_URLS[@]}"; do
            [[ "${PRESET_URLS[$k]}" == "$url" && "$k" != "$id" ]] && aliases+="${aliases:+, }$k"
        done
        ui_kv "$id" "${url#https://}${aliases:+  ($aliases)}"
    done
    ui_frame_close
    ui_note "Any https://github.com/USER/REPO also works as a --fork value."
    printf '\n'
}

cmd_list_branches() {
    local url
    if [[ -n "$OPT_FORK" ]]; then
        local pair
        pair="$(resolve_fork "$OPT_FORK")" || exit 1
        url="${pair%|*}"
    else
        url="$(read_state)"
        url="${url%%|*}"
        [[ -z "$url" ]] && url="$(local_origin)" && url="${url%%|*}"
    fi

    ui_banner "ii-p3drovfx" "branches"
    ui_step "Querying"
    local -a branches=()
    local line
    while IFS= read -r line; do branches+=("$line"); done < <(
        git ls-remote --heads "$url" 2>>"$LOG_FILE" | sed 's@^.*refs/heads/@@' | sort
    )
    if ((${#branches[@]} == 0)); then
        ui_fail "No branches" "could not reach $url"
        exit 1
    fi
    ui_ok "Queried" "${#branches[@]} branches"
    printf '\n'

    local state active=""
    state="$(read_state)"
    if [[ "$(normalize_url "${state%%|*}")" == "$(normalize_url "$url")" ]]; then
        local rest="${state#*|}"
        active="${rest%%|*}"
    fi

    ui_frame_open "${url#https://}"
    for line in "${branches[@]}"; do
        if [[ "$line" == "$active" ]]; then
            ui_frame_row "$G_OK $line"
        else
            ui_frame_row "  $line"
        fi
    done
    ui_frame_close
}

cmd_doctor() {
    ui_banner "ii-p3drovfx" "doctor"
    local state url branch fork
    state="$(read_state)"
    url="${state%%|*}"
    local rest="${state#*|}"
    branch="${rest%%|*}"
    fork="${rest##*|}"

    local active_local
    active_local="$(read_local_state)"

    ui_frame_open "Active config"
    ui_kv "fork" "${fork:-unknown}"
    ui_kv "branch" "${branch:-unknown}"
    if [[ -n "$active_local" ]]; then
        ui_kv "local" "$(tilde "$active_local")"
    else
        ui_kv "remote" "${url#https://}"
    fi
    ui_kv "target" "$([[ -d "$TARGET_DIR" ]] && tilde "$TARGET_DIR" || printf 'missing')"
    ui_frame_close

    ui_frame_open "Paths"
    ui_kv "base" "$([[ -d "$BASE_DIR" ]] && tilde "$BASE_DIR" || printf 'missing')"
    ui_kv "mirror" "$([[ -d "$MIRROR_DIR" ]] && tilde "$MIRROR_DIR" || printf 'missing')"
    ui_kv "backups" "$({ find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name 'ii_*' 2>/dev/null || true; } | wc -l) kept"
    ui_kv "log" "$(tilde "$LOG_FILE")"
    ui_frame_close

    ui_frame_open "Tooling"
    local t
    for t in git rsync qs quickshell hyprctl fc-list; do
        ui_kv "$t" "$(command -v "$t" 2>/dev/null || printf 'not found')"
    done
    ui_kv "cli" "$([[ -L "$BIN_DIR/$CLI_NAME" ]] && readlink "$BIN_DIR/$CLI_NAME" || printf 'not linked')"
    ui_frame_close

    ui_frame_open "Renderer"
    ui_kv "glyphs" "$UI_GLYPHS"
    ui_kv "colour" "$UI_COLOR"
    ui_kv "tty" "$UI_TTY"
    ui_kv "width" "$UI_WIDTH"
    ui_frame_close
}

cmd_hypr() {
    local lib="$1"
    shift
    local path=""
    local d
    for d in "$SCRIPT_DIR" "$MIRROR_DIR"; do
        [[ -f "$d/sdata/cli/lib/$lib.sh" ]] && {
            path="$d/sdata/cli/lib/$lib.sh"
            break
        }
    done
    [[ -n "$path" ]] || ui_die "Missing helper" "sdata/cli/lib/$lib.sh not found"
    exec bash "$path" "$@"
}

#══════════════════════════════════════════════════════════════════════════════
# Help
#══════════════════════════════════════════════════════════════════════════════

show_help() {
    local me="$SCRIPT_SELF"
    [[ "$INVOKED_AS" == "$CLI_NAME" ]] && me="$CLI_NAME"

    ui_banner "ii-p3drovfx" "v$SETUP_VERSION"

    ui_rule "Usage"
    printf '  %s [command] [options]\n\n' "$me"

    ui_rule "Commands"
    printf '  %s%-16s%s %s\n' "$C_OK" "apply" "$C_RST" "Apply the Quickshell config (default)"
    printf '  %s%-16s%s %s\n' "$C_OK" "install" "$C_RST" "Install base illogical-impulse, then apply"
    printf '  %s%-16s%s %s\n' "$C_OK" "update" "$C_RST" "Refresh the active fork+branch from GitHub"
    printf '  %s%-16s%s %s\n' "$C_OK" "switch" "$C_RST" "Switch fork and/or branch"
    printf '  %s%-16s%s %s\n' "$C_OK" "fork <x> [br]" "$C_RST" "Shorthand for switch --fork <x> [--branch br]"
    printf '  %s%-16s%s %s\n' "$C_OK" "branch <name>" "$C_RST" "Shorthand for switch --branch <name>"
    printf '  %s%-16s%s %s\n' "$C_OK" "list-forks" "$C_RST" "Show the fork presets"
    printf '  %s%-16s%s %s\n' "$C_OK" "list-branches" "$C_RST" "Show remote branches of a fork"
    printf '  %s%-16s%s %s\n' "$C_OK" "restart" "$C_RST" "Restart Quickshell (alias: run)"
    printf '  %s%-16s%s %s\n' "$C_OK" "doctor" "$C_RST" "Report resolved paths, state and tooling"
    printf '  %s%-16s%s %s\n' "$C_OK" "hyprset" "$C_RST" "Write a Hyprland key/animation"
    printf '  %s%-16s%s %s\n' "$C_OK" "hyprmerge" "$C_RST" "Merge a Hyprland config into the local one"
    printf '  %s%-16s%s Remove the %s symlink\n' "$C_OK" "remove-cli" "$C_RST" "$CLI_NAME"
    printf '  %s%-16s%s %s\n' "$C_OK" "help, version" "$C_RST" "This message / the version"
    printf '  %s%-16s%s %s\n' "$C_OK" "demo" "$C_RST" "Render every UI primitive and exit"
    printf '\n'

    ui_rule "Options"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-f, --fork <preset|url>" "$C_RST" "Target fork"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-b, --branch <name>" "$C_RST" "Target branch"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-l, --local <path>" "$C_RST" "Deploy from a local checkout, not GitHub"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-y, --yes" "$C_RST" "Skip every confirmation"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-v, --verbose" "$C_RST" "Echo command output as it runs"
    printf '  %s%-24s%s %s\n' "$C_STEP" "-q, --quiet" "$C_RST" "Only errors on stdout"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --backup" "$C_RST" "Keep the replaced config (default)"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-backup" "$C_RST" "Discard the previous config instead of keeping it"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --keep-config" "$C_RST" "Never reset ~/.config/illogical-impulse/config.json"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --reset-config" "$C_RST" "Always reset it (a backup is kept)"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-restart" "$C_RST" "Leave Quickshell alone when finished"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --hypr" "$C_RST" "Install the fork's ~/.config/hypr files"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-hypr" "$C_RST" "Never install them, never ask"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --rebuild-quickshell" "$C_RST" "Rebuild Quickshell from source first"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --skip-base-check" "$C_RST" "Do not require illogical-impulse to be present"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --ii-subdir <name>" "$C_RST" "Override ii* auto-detection in the clone"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --log-file <path>" "$C_RST" "Write the run log elsewhere"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-log" "$C_RST" "Do not write a run log"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --ascii" "$C_RST" "ASCII glyphs only"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --no-color" "$C_RST" "Strip ANSI colour"
    printf '  %s%-24s%s %s\n' "$C_STEP" "    --demo" "$C_RST" "Render every UI primitive and exit"
    printf '\n'

    ui_rule "Notes"
    printf '  %s--local takes a fork checkout or an ii config dir; either way nothing%s\n' "$C_SUB" "$C_RST"
    printf '  %sis cloned. update will not guess the path back: it refuses and prints%s\n' "$C_SUB" "$C_RST"
    printf '  %sthe --local line to re-run.%s\n' "$C_SUB" "$C_RST"
    printf '  %sOn Arch, install swaps the base installer'"'"'s pinned quickshell for the%s\n' "$C_SUB" "$C_RST"
    printf '  %sAUR quickshell-git this fork targets, before any config lands.%s\n' "$C_SUB" "$C_RST"
    printf '  %sGiven neither --keep-config nor --reset-config, config.json is kept on%s\n' "$C_SUB" "$C_RST"
    printf '  %supdates and branch hops and reset on fork switches, where the schema%s\n' "$C_SUB" "$C_RST"
    printf '  %schanges.%s\n' "$C_SUB" "$C_RST"
    printf '  %sapply, install, update and switch offer to overlay the fork'"'"'s Hyprland%s\n' "$C_SUB" "$C_RST"
    printf '  %sconfig on ~/.config/hypr, leaving custom/ and anything the repo does%s\n' "$C_SUB" "$C_RST"
    printf '  %snot ship alone. -y answers that question no, not yes; --hypr is the%s\n' "$C_SUB" "$C_RST"
    printf '  %sexplicit yes and --no-hypr the permanent no.%s\n' "$C_SUB" "$C_RST"
    printf '  %sEvery successful apply, install or switch opens Welcome through the shell;%s\n' "$C_SUB" "$C_RST"
    printf '  %supdate is the only deployment that keeps it closed. Hyprland files are%s\n' "$C_SUB" "$C_RST"
    printf '  %soptional: their rule only makes the Welcome window float.%s\n' "$C_SUB" "$C_RST"
    printf '  %sOptions take --flag=value as well as --flag value, and everything after%s\n' "$C_SUB" "$C_RST"
    printf '  %sa bare -- is passed through to hyprset/hyprmerge.%s\n' "$C_SUB" "$C_RST"
    printf '  %sAliases: --no-confirm/--noconfirm (-y), --preserve-config (--keep-config),%s\n' "$C_SUB" "$C_RST"
    printf '  %s--force-install (--skip-base-check), --no-colour (--no-color),%s\n' "$C_SUB" "$C_RST"
    printf '  %s--hypr-config (--hypr), --no-hypr-config (--no-hypr).%s\n' "$C_SUB" "$C_RST"
    printf '\n'

    ui_rule "Examples"
    printf '  %s%s install%s                  %sfirst-time setup on a bare machine%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s update%s                   %spull the latest of what you run now%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s fork end4%s                %sswitch to end-4/dots-hyprland%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s branch dev%s               %shop branches on the active fork%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s switch -f mine -b main%s   %sboth at once%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '  %s%s apply --local .%s          %sdeploy the checkout you stand in%s\n' "$C_ACC" "$me" "$C_RST" "$C_SUB" "$C_RST"
    printf '\n'
    printf '%sLog: %s%s\n' "$C_SUB" "$(tilde "$DEFAULT_LOG_FILE")" "$C_RST"
    printf '%sDocs: %shttps://ii.clsty.link%s\n\n' "$C_SUB" "$C_UL" "$C_RST"
}

#══════════════════════════════════════════════════════════════════════════════
# Argument parsing
#══════════════════════════════════════════════════════════════════════════════

ORIGINAL_ARGS=("$@")

arg_error() {
    ERR_REPORTED=true
    printf '%s%s %s%s\n' "$C_ERR" "$G_ERR" "$1" "$C_RST" >&2
    printf '%s  Run "%s help" for usage.%s\n' "$C_SUB" "$SCRIPT_SELF" "$C_RST" >&2
    exit 2
}

need_value() {
    [[ -n "${2:-}" ]] || arg_error "$1 requires a value"
}

parse_args() {
    local -a positional=()
    while (($# > 0)); do
        local arg="$1" val=""
        # --opt=value
        if [[ "$arg" == --*=* ]]; then
            val="${arg#*=}"
            arg="${arg%%=*}"
            set -- "$arg" "$val" "${@:2}"
        fi
        case "$1" in
            -f | --fork)
                need_value "$1" "${2:-}"
                OPT_FORK="$2"
                shift 2
                ;;
            -b | --branch)
                need_value "$1" "${2:-}"
                OPT_BRANCH="$2"
                shift 2
                ;;
            -l | --local)
                need_value "$1" "${2:-}"
                OPT_LOCAL="$2"
                shift 2
                ;;
            --ii-subdir)
                need_value "$1" "${2:-}"
                OPT_II_SUBDIR="$2"
                shift 2
                ;;
            --log-file)
                need_value "$1" "${2:-}"
                LOG_FILE="$2"
                shift 2
                ;;
            -v | --verbose)
                OPT_VERBOSE=true
                shift
                ;;
            -q | --quiet)
                OPT_QUIET=true
                shift
                ;;
            -y | --yes | --no-confirm | --noconfirm)
                OPT_ASSUME_YES=true
                shift
                ;;
            --no-backup)
                OPT_BACKUP=false
                shift
                ;;
            --backup)
                OPT_BACKUP=true
                shift
                ;;
            --keep-config | --preserve-config)
                OPT_KEEP_CONFIG=true
                shift
                ;;
            --reset-config)
                OPT_KEEP_CONFIG=false
                shift
                ;;
            --rebuild-quickshell)
                OPT_REBUILD_QS=true
                shift
                ;;
            --no-restart)
                OPT_RESTART=false
                shift
                ;;
            --hypr | --hypr-config)
                OPT_HYPR=true
                shift
                ;;
            --no-hypr | --no-hypr-config)
                OPT_HYPR=false
                shift
                ;;
            --skip-base-check | --force-install)
                OPT_SKIP_BASE_CHECK=true
                shift
                ;;
            --no-log)
                OPT_LOG=false
                shift
                ;;
            --ascii)
                OPT_ASCII=true
                shift
                ;;
            --no-color | --no-colour)
                OPT_NO_COLOR=true
                shift
                ;;
            --demo)
                COMMAND="demo"
                shift
                ;;
            -h | --help)
                COMMAND="help"
                shift
                ;;
            -V | --version)
                COMMAND="version"
                shift
                ;;
            # Legacy flag spellings, kept so old callers and muscle memory still work.
            --update)
                COMMAND="${COMMAND:-update}"
                shift
                ;;
            --switch)
                COMMAND="${COMMAND:-switch}"
                shift
                ;;
            --install)
                COMMAND="${COMMAND:-install}"
                shift
                ;;
            --apply)
                COMMAND="${COMMAND:-apply}"
                shift
                ;;
            --list-forks)
                COMMAND="list-forks"
                shift
                ;;
            --list-branches)
                COMMAND="list-branches"
                shift
                ;;
            --)
                shift
                PASSTHRU_ARGS+=("$@")
                break
                ;;
            -*)
                arg_error "Unknown option \"$1\""
                ;;
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    [[ -n "$OPT_LOCAL" && -n "$OPT_FORK" ]] &&
        arg_error "--local and --fork name two different sources; pick one"

    # First positional is the command unless a legacy flag already chose one.
    if ((${#positional[@]} > 0)); then
        local first="${positional[0]}"
        case "$first" in
            apply | install | update | switch | fork | branch | list-forks | list-branches | \
                restart | run | doctor | remove-cli | hyprset | hyprmerge | help | version | demo)
                COMMAND="$first"
                positional=("${positional[@]:1}")
                ;;
        esac
    fi

    # Command-specific positionals.
    case "$COMMAND" in
        fork)
            [[ -n "${positional[0]:-}" ]] && OPT_FORK="${positional[0]}"
            [[ -n "${positional[1]:-}" ]] && OPT_BRANCH="${positional[1]}"
            [[ -n "$OPT_FORK" ]] || arg_error "fork requires <preset|url>"
            COMMAND="switch"
            ;;
        branch)
            [[ -n "${positional[0]:-}" ]] && OPT_BRANCH="${positional[0]}"
            [[ -n "$OPT_BRANCH" ]] || arg_error "branch requires <name>"
            COMMAND="switch"
            ;;
        list-branches)
            [[ -n "${positional[0]:-}" && -z "$OPT_FORK" ]] && OPT_FORK="${positional[0]}"
            ;;
        hyprset | hyprmerge)
            PASSTHRU_ARGS=("${positional[@]}" "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}")
            ;;
        *)
            if ((${#positional[@]} > 0)); then
                arg_error "Unexpected argument \"${positional[0]}\""
            fi
            ;;
    esac
}

#══════════════════════════════════════════════════════════════════════════════
# Main
#══════════════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"

    # Bare `vynx` is a CLI, not an installer: show the surface instead of acting.
    if [[ -z "$COMMAND" && "$INVOKED_AS" == "$CLI_NAME" ]]; then
        COMMAND="help"
    fi
    [[ -z "$COMMAND" ]] && COMMAND="apply"

    if [[ -n "$OPT_LOCAL" ]]; then
        case "$COMMAND" in
            apply | install | update | switch) ;;
            *) arg_error "--local applies to apply, install, update and switch" ;;
        esac
    fi

    ui_init
    [[ "$UI_TTY" == true && "$COMMAND" != "help" ]] && printf '\033[?25l'

    case "$COMMAND" in
        help)
            show_help
            exit 0
            ;;
        version)
            printf '%s %s\n' "$SCRIPT_SELF" "$SETUP_VERSION"
            exit 0
            ;;
        demo)
            ui_demo
            exit 0
            ;;
        hyprset) cmd_hypr hyprset "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}" ;;
        hyprmerge) cmd_hypr hyprmerge "${PASSTHRU_ARGS[@]+"${PASSTHRU_ARGS[@]}"}" ;;
    esac

    open_log

    # Only the mutating commands migrate legacy paths; listing and doctor must
    # never move anything just because you asked them a question.
    case "$COMMAND" in
        apply | install | update | switch | restart | run | remove-cli) migrate_legacy ;;
    esac

    case "$COMMAND" in
        restart | run)
            ui_banner "ii-p3drovfx" "restart"
            OPT_RESTART=true
            restart_quickshell
            ;;
        remove-cli)
            ui_banner "ii-p3drovfx" "remove-cli"
            remove_cli
            ;;
        doctor) cmd_doctor ;;
        list-forks) cmd_list_forks ;;
        list-branches) cmd_list_branches ;;
        apply | install | update | switch)
            if [[ "$OPT_REBUILD_QS" == true ]]; then
                build_quickshell || exit 1
            elif [[ "$COMMAND" != "install" ]] && qt_mismatch; then
                if ui_confirm "Rebuild Quickshell from source to match your Qt?"; then
                    build_quickshell || exit 1
                else
                    ui_note "Skipped. Crashes may persist until the ABI matches."
                fi
            fi
            case "$COMMAND" in
                apply) cmd_apply ;;
                install) cmd_install ;;
                update) cmd_update ;;
                switch) cmd_switch ;;
            esac
            ;;
        *)
            arg_error "Unknown command \"$COMMAND\""
            ;;
    esac
}

main "$@"
