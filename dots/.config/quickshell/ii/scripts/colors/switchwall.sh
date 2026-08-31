#!/usr/bin/env bash

QUICKSHELL_CONFIG_NAME="ii"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_DIR="$XDG_CONFIG_HOME/quickshell/$QUICKSHELL_CONFIG_NAME"
CACHE_DIR="$XDG_CACHE_HOME/quickshell"
STATE_DIR="$XDG_STATE_HOME/quickshell"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
terminalscheme="$SCRIPT_DIR/terminal/scheme-base.json"

# Matugen aborts the whole run - colors.json included - as soon as any template
# in its config points at an input file that does not exist, and it walks the
# templates in random order, so the breakage looks intermittent: some runs write
# the palette, most do not. Name the offending entries instead of leaving the
# shell silently stuck on the previous colors.
report_matugen_failure() {
    local script_name="$1"
    local exit_code="${2:-1}"
    local flag_file="$STATE_DIR/matugen_error_notified"
    local extra_flags=()

    mkdir -p "$STATE_DIR" 2>/dev/null || true

    if [[ -f "$flag_file" ]]; then
        extra_flags+=(-t 0 -h boolean:suppress-sound:true)
    else
        touch "$flag_file" 2>/dev/null || true
    fi

    local cfg="$MATUGEN_DIR/config.toml"
    local missing=()
    local p
    if [[ -f "$cfg" ]]; then
        while read -r p; do
            [[ -z "$p" ]] && continue
            p="${p/#\~/$HOME}"
            [[ -f "$p" ]] || missing+=("$p")
        done < <(grep -oP "input_path\s*=\s*'\K[^']+" "$cfg" 2>/dev/null)
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[$script_name] matugen aborted (exit code $exit_code); missing template inputs: ${missing[*]}" >&2
        notify-send -a "Wallpaper switcher" -c "im.error" "${extra_flags[@]}" \
            "Color generation failed (code $exit_code)" \
            "matugen aborted with error code $exit_code because these templates are missing: ${missing[*]} - fix or remove them in $cfg" 2>/dev/null || true
    else
        echo "[$script_name] matugen failed (exit code $exit_code); keeping the previous palette." >&2
        notify-send -a "Wallpaper switcher" -c "im.error" "${extra_flags[@]}" \
            "Color generation failed (code $exit_code)" \
            "matugen exited with error code $exit_code, so the shell kept its previous palette." 2>/dev/null || true
    fi
}

handle_kde_material_you_colors() {
    # Check if Qt app theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_qt_apps=$(jq -r '.appearance.wallpaperTheming.enableQtApps' "$SHELL_CONFIG_FILE")
        if [ "$enable_qt_apps" == "false" ]; then
            return
        fi
    fi

    # Map $type_flag to allowed scheme variants for kde-material-you-colors-wrapper.sh
    local kde_scheme_variant=""
    case "$type_flag" in
        scheme-content|scheme-expressive|scheme-fidelity|scheme-fruit-salad|scheme-monochrome|scheme-neutral|scheme-rainbow|scheme-tonal-spot|scheme-vibrant)
            kde_scheme_variant="$type_flag"
            ;;
        scheme-intense)
            kde_scheme_variant="scheme-fidelity"
            ;;
        *)
            kde_scheme_variant="scheme-tonal-spot" # default
            ;;
    esac
    "$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant"
}

pre_process() {
    local mode_flag="$1"
    # Set GNOME color-scheme if mode_flag is dark or light
    if [[ "$mode_flag" == "dark" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
    elif [[ "$mode_flag" == "light" ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3'
    fi

    if [ ! -d "$CACHE_DIR"/user/generated ]; then
        mkdir -p "$CACHE_DIR"/user/generated
    fi
}

post_process() {
    local screen_width="$1"
    local screen_height="$2"
    local wallpaper_path="$3"

    handle_kde_material_you_colors &
    "$SCRIPT_DIR/code/material-code-set-color.sh" &
    
    # Generate YouTube Music theme via matugen native template
    "$SCRIPT_DIR/../ytmusic/generate-ytmusic-theme.sh" > /dev/null 2>&1 &
}

check_and_prompt_upscale() {
    local img="$1"
    min_width_desired="$(hyprctl monitors -j | jq '([.[].width] | max)' | xargs)" # max monitor width
    min_height_desired="$(hyprctl monitors -j | jq '([.[].height] | max)' | xargs)" # max monitor height

    if command -v identify &>/dev/null && [ -f "$img" ]; then
        local img_width img_height
        if is_video "$img"; then # Not check resolution for videos, just let em pass
            img_width=$min_width_desired
            img_height=$min_height_desired
        else
            img_width=$(identify -format "%w" "$img" 2>/dev/null)
            img_height=$(identify -format "%h" "$img" 2>/dev/null)
        fi
        if [[ "$img_width" -lt "$min_width_desired" || "$img_height" -lt "$min_height_desired" ]]; then
            action=$(notify-send "Upscale?" \
                "Image resolution (${img_width}x${img_height}) is lower than screen resolution (${min_width_desired}x${min_height_desired})" \
                -A "open_upscayl=Open Upscayl"\
                -a "Wallpaper switcher")
            if [[ "$action" == "open_upscayl" ]]; then
                if command -v upscayl &>/dev/null; then
                    nohup upscayl > /dev/null 2>&1 &
                else
                    action2=$(notify-send \
                        -a "Wallpaper switcher" \
                        -c "im.error" \
                        -A "install_upscayl=Install Upscayl (Arch)" \
                        "Install Upscayl?" \
                        "yay -S upscayl-bin")
                    if [[ "$action2" == "install_upscayl" ]]; then
                        kitty -1 yay -S upscayl-bin
                        if command -v upscayl &>/dev/null; then
                            nohup upscayl > /dev/null 2>&1 &
                        fi
                    fi
                fi
            fi
        fi
    fi
}

CUSTOM_DIR="$XDG_CONFIG_HOME/hypr/custom"
RESTORE_SCRIPT_DIR="$CUSTOM_DIR/scripts"
RESTORE_SCRIPT="$RESTORE_SCRIPT_DIR/__restore_video_wallpaper.sh"
THUMBNAIL_DIR="$RESTORE_SCRIPT_DIR/mpvpaper_thumbnails"
VIDEO_OPTS="no-audio loop hwdec=nvdec scale=bilinear interpolation=no video-sync=display-resample panscan=1.0 video-zoom=0.08 load-scripts=no"

is_video() {
    local extension="${1##*.}"
    [[ "$extension" == "mp4" || "$extension" == "webm" || "$extension" == "mkv" || "$extension" == "avi" || "$extension" == "mov" ]] && return 0 || return 1
}

# mpvpaper paints the *desktop* background layer. The lockscreen and the
# light-mode variant are only ever stored paths — they never own that layer. So
# picking a video for one of them must not take the live desktop over, and
# picking a static image for one of them must not kill a video the desktop is
# already playing. Both used to happen.
is_desktop_target() {
    [[ -z "$lockscreen_flag" && -z "$lightmode_flag" ]]
}

kill_existing_mpvpaper() {
    pkill -f -9 mpvpaper || true
}

kill_existing_wpe() {
    pkill -f linux-wallpaperengine || true
}

disable_wpe_config() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --indent 4 '.background.useWallpaperEngine = false' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

enable_wpe_config() {
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --indent 4 '.background.useWallpaperEngine = true' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

create_restore_script_wpe() {
    local wpe_id=$1
    local wpe_args_str=$2
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: \$(date)

pkill -f linux-wallpaperengine
pkill -f -9 mpvpaper

$wpe_args_str
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

create_restore_script() {
    local video_path=$1
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# Generated by switchwall.sh - Don't modify it by yourself.
# Time: $(date)

pkill -f -9 mpvpaper

for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    mpvpaper -o "$VIDEO_OPTS input-ipc-server=/tmp/mpvpaper-\$monitor.sock" "\$monitor" "$video_path" &
    sleep 0.1
done
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
    chmod +x "$RESTORE_SCRIPT"
}

remove_restore() {
    cat > "$RESTORE_SCRIPT.tmp" << EOF
#!/bin/bash
# The content of this script will be generated by switchwall.sh - Don't modify it by yourself.
EOF
    mv "$RESTORE_SCRIPT.tmp" "$RESTORE_SCRIPT"
}

set_wallpaper_path() {
    local path="$1"
    local target="$2"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        if [[ "$target" == "lightmode" ]]; then
            jq --indent 4 --arg path "$path" '.background.lightModeWallpaperPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        elif [[ "$target" == "lockscreen" ]]; then
            jq --indent 4 --arg path "$path" '.background.lockscreenWallpaperPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        else
            jq --indent 4 --arg path "$path" '.background.wallpaperPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
        fi
    fi
}

set_thumbnail_path() {
    local path="$1"
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        jq --indent 4 --arg path "$path" '.background.thumbnailPath = $path' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    fi
}

categorize_wallpaper() {
    img_cat=$("$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$1")
    # notify-send "Wallpaper category" "$img_cat"
    echo "$img_cat" > "$STATE_DIR/user/generated/wallpaper/category.txt"
}

switch() {
    imgpath="$1"
    mode_flag="$2"
    type_flag="$3"
    color_flag="$4"
    color="$5"
    theme_file="$6"

    # Guard against rapid wallpaper switches racing each other: the all-previews
    # generation below takes over a second, so a second switch launched before it
    # finishes must not have its result overwritten by the older, slower run.
    # request_seq_flag (--request-seq) comes from the QML caller and is strictly
    # increasing in click order, since QML dispatch is single-threaded. Direct
    # callers without a sequence receive the next token under the same lock, so
    # they cannot be rejected just because an older QML token uses timestamps.
    request_token_file="$STATE_DIR/user/generated/.preview_request_token"
    mkdir -p "$(dirname "$request_token_file")"
    if [[ -n "$request_seq_flag" ]]; then
        my_request_token="$request_seq_flag"
        (
            flock -x 201
            current_seq=$(cat "$request_token_file" 2>/dev/null)
            if [[ -z "$current_seq" ]] || ! [[ "$current_seq" =~ ^[0-9]+$ ]] || (( my_request_token > current_seq )); then
                printf '%s' "$my_request_token" > "$request_token_file"
            fi
        ) 201>"$request_token_file.lock"
    else
        my_request_token=$(
            (
                flock -x 201
                current_seq=$(cat "$request_token_file" 2>/dev/null)
                if [[ "$current_seq" =~ ^[0-9]+$ ]]; then
                    next_seq=$((current_seq + 1))
                else
                    next_seq=$(date +%s%3N)
                fi
                printf '%s' "$next_seq" > "$request_token_file"
                printf '%s' "$next_seq"
            ) 201>"$request_token_file.lock"
        )
    fi

    # Start Gemini auto-categorization if enabled
    aiStylingEnabled=$(jq -r '.background.widgets.clock.cookie.aiStyling' "$SHELL_CONFIG_FILE")
    aiStylingModel=$(jq -r '.background.widgets.clock.cookie.aiStylingModel' "$SHELL_CONFIG_FILE")
    if [[ "$aiStylingEnabled" == "true" ]]; then
        if [[ "$aiStylingModel" == "gemini" ]]; then  
            "$SCRIPT_DIR/../ai/gemini-categorize-wallpaper.sh" "$imgpath" > "$STATE_DIR/user/generated/wallpaper/category.txt" &
        fi
        if [[ "$aiStylingModel" == "openrouter" ]]; then  
            "$SCRIPT_DIR/../ai/openrouter-categorize-wallpaper.sh" "$imgpath" > "$STATE_DIR/user/generated/wallpaper/category.txt" &
        fi
    fi

    read scale screenx screeny screensizey < <(hyprctl monitors -j | jq '.[] | select(.focused) | .scale, .x, .y, .height' | xargs)
    cursorposx=$(hyprctl cursorpos -j | jq '.x' 2>/dev/null) || cursorposx=960
    cursorposx=$(bc <<< "scale=0; ($cursorposx - $screenx) * $scale / 1")
    cursorposy=$(hyprctl cursorpos -j | jq '.y' 2>/dev/null) || cursorposy=540
    cursorposy=$(bc <<< "scale=0; ($cursorposy - $screeny) * $scale / 1")
    cursorposy_inverted=$((screensizey - cursorposy))

    matugen_args=(--source-color-index 0)

    if [[ "$color_flag" == "1" ]]; then
        matugen_args+=(color hex "$color")
        generate_colors_material_args=(--color "$color")
    else
        if [[ -z "$imgpath" ]]; then
            echo 'Aborted'
            exit 0
        fi

        check_and_prompt_upscale "$imgpath" &
        
        if [[ "$noswitch_flag" != "1" ]]; then
            kill_existing_mpvpaper
            kill_existing_wpe
        fi

        # Load Wallpaper Engine settings from config.json
        use_wpe=$(jq -r '.background.useWallpaperEngine' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
        wpe_assets=$(jq -r '.background.wallpaperEngineAssetsPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")

        is_wpe=0
        if [[ "$use_wpe" == "true" ]]; then
            is_wpe=1
        fi

        if [[ $is_wpe -eq 1 ]]; then
            # Auto-detect wpe_assets if empty or invalid
            if [[ -z "$wpe_assets" || ! -d "$wpe_assets" ]]; then
                for candidate_assets in \
                    "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/common/wallpaper_engine/assets" \
                    "$HOME/.local/share/Steam/steamapps/common/wallpaper_engine/assets" \
                    "$HOME/.steam/steam/steamapps/common/wallpaper_engine/assets" \
                    "$HOME/.steam/root/steamapps/common/wallpaper_engine/assets"; do
                    if [[ -d "$candidate_assets" ]]; then
                        wpe_assets="$candidate_assets"
                        break
                    fi
                done
            fi

            # Try to resolve workshop directory from assets directory or candidate paths if it's a numeric ID
            if [[ "$imgpath" =~ ^[0-9]+$ ]]; then
                local wpe_candidates=()
                if [[ -n "$wpe_assets" ]]; then
                    wpe_candidates+=("${wpe_assets/common\/wallpaper_engine\/assets/workshop\/content\/431960}")
                    wpe_candidates+=("${wpe_assets/common\/wallpaper_engine/workshop\/content\/431960}")
                fi
                wpe_candidates+=(
                    "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960"
                    "$HOME/.local/share/Steam/steamapps/workshop/content/431960"
                    "$HOME/.steam/steam/steamapps/workshop/content/431960"
                    "$HOME/.steam/root/steamapps/workshop/content/431960"
                )
                for cand in "${wpe_candidates[@]}"; do
                    if [[ -d "$cand/$imgpath" ]]; then
                        imgpath="$cand/$imgpath"
                        break
                    fi
                done
            fi
            enable_wpe_config

            local wpe_screenshot="/tmp/wpe_screenshot.png"

            if [[ "$noswitch_flag" == "1" ]]; then
                if [ -f "$wpe_screenshot" ]; then
                    matugen_args+=(image "$wpe_screenshot")
                    generate_colors_material_args=(--path "$wpe_screenshot")
                else
                    # Fallback to preview or static
                    local fallback_img=""
                    if [[ -d "$imgpath" ]]; then
                        if [[ -f "$imgpath/preview.jpg" ]]; then
                            fallback_img="$imgpath/preview.jpg"
                        elif [[ -f "$imgpath/preview.gif" ]]; then
                            ffmpeg -y -i "$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                            fallback_img="/tmp/wpe_fallback.png"
                        fi
                    fi
                    if [[ -n "$fallback_img" && -f "$fallback_img" ]]; then
                        matugen_args+=(image "$fallback_img")
                        generate_colors_material_args=(--path "$fallback_img")
                    else
                        local default_wall="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                        matugen_args+=(image "$default_wall")
                        generate_colors_material_args=(--path "$default_wall")
                    fi
                fi
            else
                # Verify dependencies
                if ! command -v linux-wallpaperengine &> /dev/null; then
                    notify-send -a "Wallpaper switcher" -c "im.error" "Wallpaper Engine Error" "linux-wallpaperengine command not found. Please install/check dependencies."
                    exit 1
                fi

                # Load additional settings
                wpe_silent=$(jq -r '.background.wpeSilent' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "true")
                wpe_volume=$(jq -r '.background.wpeVolume' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "50")
                wpe_noautomute=$(jq -r '.background.wpeNoAutoMute' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_noaudioprocess=$(jq -r '.background.wpeNoAudioProcessing' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_fps=$(jq -r '.background.wpeFps' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "30")
                wpe_screenspan=$(jq -r '.background.wpeScreenSpan' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                wpe_scaling=$(jq -r '.background.wpeScaling' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "default")
                wpe_disablemouse=$(jq -r '.background.wpeDisableMouse' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_disableparallax=$(jq -r '.background.wpeDisableParallax' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                wpe_nofullscreenpause=$(jq -r '.background.wpeNoFullscreenPause' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")

                # Determine assets directory and build restore options array
                local wpe_restore_opts=(--layer background)
                if [[ -n "$wpe_assets" && -d "$wpe_assets" ]]; then
                    wpe_restore_opts+=(--assets-dir "$wpe_assets")
                fi

                if [[ "$wpe_silent" == "true" ]]; then
                    wpe_restore_opts+=(--silent)
                else
                    wpe_restore_opts+=(--volume "$wpe_volume")
                fi

                if [[ "$wpe_noautomute" == "true" ]]; then
                    wpe_restore_opts+=(--noautomute)
                fi

                if [[ "$wpe_noaudioprocess" == "true" ]]; then
                    wpe_restore_opts+=(--no-audio-processing)
                fi

                if [[ -n "$wpe_fps" && "$wpe_fps" -gt 0 ]]; then
                    wpe_restore_opts+=(--fps "$wpe_fps")
                fi

                if [[ "$wpe_scaling" != "default" && -n "$wpe_scaling" ]]; then
                    wpe_restore_opts+=(--scaling "$wpe_scaling")
                fi

                if [[ "$wpe_disablemouse" == "true" ]]; then
                    wpe_restore_opts+=(--disable-mouse)
                fi

                if [[ "$wpe_disableparallax" == "true" ]]; then
                    wpe_restore_opts+=(--disable-parallax)
                fi

                if [[ "$wpe_nofullscreenpause" == "true" ]]; then
                    wpe_restore_opts+=(--no-fullscreen-pause)
                fi

                # Build options for current execution (including screenshot)
                local wpe_opts=("${wpe_restore_opts[@]}")
                rm -f "$wpe_screenshot"
                wpe_opts+=(--screenshot "$wpe_screenshot")

                # Launch linux-wallpaperengine
                local wpe_args_str=""
                if [[ -n "$wpe_screenspan" ]]; then
                    nohup setsid linux-wallpaperengine "${wpe_opts[@]}" --screen-span "$wpe_screenspan" "$imgpath" >/tmp/wpe_run.log 2>&1 &
                    wpe_args_str="setsid linux-wallpaperengine ${wpe_restore_opts[*]} --screen-span \"$wpe_screenspan\" \"$imgpath\" &"
                else
                    monitors=$(hyprctl monitors -j | jq -r '.[] | .name')
                    for monitor in $monitors; do
                        nohup setsid linux-wallpaperengine "${wpe_opts[@]}" --screen-root "$monitor" "$imgpath" >/tmp/wpe_run.log 2>&1 &
                        sleep 0.1
                    done
                    wpe_args_str="for monitor in \$(hyprctl monitors -j | jq -r '.[] | .name'); do
    setsid linux-wallpaperengine ${wpe_restore_opts[*]} --screen-root \"\$monitor\" \"$imgpath\" &
    sleep 0.1
done"
                fi

                # Create restore script
                create_restore_script_wpe "$imgpath" "$wpe_args_str"

                # Wait up to 2 seconds for screenshot to be written
                for i in {1..20}; do
                    if [ -f "$wpe_screenshot" ]; then
                        break
                    fi
                    sleep 0.1
                done

                if [ -f "$wpe_screenshot" ]; then
                    matugen_args+=(image "$wpe_screenshot")
                    generate_colors_material_args=(--path "$wpe_screenshot")
                else
                    echo "Cannot create image to colorgen from Wallpaper Engine screenshot, trying fallbacks" >&2
                    local fallback_img=""
                    if [[ -d "$imgpath" ]]; then
                        if [[ -f "$imgpath/preview.jpg" ]]; then
                            fallback_img="$imgpath/preview.jpg"
                        elif [[ -f "$imgpath/preview.gif" ]]; then
                            ffmpeg -y -i "$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                            fallback_img="/tmp/wpe_fallback.png"
                        fi
                    elif [[ "$imgpath" =~ ^[0-9]+$ && -f "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960/$imgpath/preview.gif" ]]; then
                        ffmpeg -y -i "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960/$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                        fallback_img="/tmp/wpe_fallback.png"
                    fi

                    if [[ -n "$fallback_img" && -f "$fallback_img" ]]; then
                        matugen_args+=(image "$fallback_img")
                        generate_colors_material_args=(--path "$fallback_img")
                    else
                        exit 1
                    fi
                fi
            fi
        else
            # If not using Wallpaper Engine, make sure it is disabled in config
            disable_wpe_config

            # Resolve directories or numeric IDs to valid image files
            if [[ -d "$imgpath" ]]; then
                if [[ -f "$imgpath/preview.jpg" ]]; then
                    imgpath="$imgpath/preview.jpg"
                elif [[ -f "$imgpath/preview.gif" ]]; then
                    ffmpeg -y -i "$imgpath/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                    imgpath="/tmp/wpe_fallback.png"
                else
                    imgpath="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                fi
            elif [[ "$imgpath" =~ ^[0-9]+$ ]]; then
                local resolved_dir=""
                if [[ -n "$wpe_assets" ]]; then
                    wpe_workshop="${wpe_assets/common\/wallpaper_engine\/assets/workshop\/content\/431960}"
                    if [[ ! -d "$wpe_workshop" ]]; then
                        wpe_workshop="${wpe_assets/common\/wallpaper_engine/workshop\/content\/431960}"
                    fi
                    if [[ -d "$wpe_workshop/$imgpath" ]]; then
                        resolved_dir="$wpe_workshop/$imgpath"
                    fi
                fi
                if [[ -n "$resolved_dir" ]]; then
                    if [[ -f "$resolved_dir/preview.jpg" ]]; then
                        imgpath="$resolved_dir/preview.jpg"
                    elif [[ -f "$resolved_dir/preview.gif" ]]; then
                        ffmpeg -y -i "$resolved_dir/preview.gif" -vframes 1 /tmp/wpe_fallback.png 2>/dev/null
                        imgpath="/tmp/wpe_fallback.png"
                    else
                        imgpath="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                    fi
                else
                    imgpath="$HOME/.config/quickshell/ii/assets/images/default_wallpaper.png"
                fi
            fi

            if is_video "$imgpath"; then
            mkdir -p "$THUMBNAIL_DIR"

            missing_deps=()
            if ! command -v mpvpaper &> /dev/null; then
                missing_deps+=("mpvpaper")
            fi
            if ! command -v ffmpeg &> /dev/null; then
                missing_deps+=("ffmpeg")
            fi
            if [ ${#missing_deps[@]} -gt 0 ]; then
                echo "Missing deps: ${missing_deps[*]}"
                echo "Arch: sudo pacman -S ${missing_deps[*]}"
                action=$(notify-send \
                    -a "Wallpaper switcher" \
                    -c "im.error" \
                    -A "install_arch=Install (Arch)" \
                    "Can't switch to video wallpaper" \
                    "Missing dependencies: ${missing_deps[*]}")
                if [[ "$action" == "install_arch" ]]; then
                    kitty -1 sudo pacman -S "${missing_deps[*]}"
                    if command -v mpvpaper &>/dev/null && command -v ffmpeg &>/dev/null; then
                        notify-send 'Wallpaper switcher' 'Alright, try again!' -a "Wallpaper switcher"
                    fi
                fi
                exit 0
            fi

            # Set wallpaper path
            if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
                if [[ -n "$lightmode_flag" ]]; then
                    set_wallpaper_path "$imgpath" "lightmode"
                elif [[ -n "$lockscreen_flag" ]]; then
                    set_wallpaper_path "$imgpath" "lockscreen"
                else
                    set_wallpaper_path "$imgpath" "desktop"
                fi
            fi

            # Set video wallpaper
            local video_path="$imgpath"
            if [[ -f "${imgpath%.*}_1080p.mp4" ]]; then
                video_path="${imgpath%.*}_1080p.mp4"
            fi
            if is_desktop_target; then
                monitors=$(hyprctl monitors -j | jq -r '.[] | .name')
                for monitor in $monitors; do
                    nohup setsid mpvpaper -o "$VIDEO_OPTS input-ipc-server=/tmp/mpvpaper-$monitor.sock" "$monitor" "$video_path" >/dev/null 2>&1 &
                    sleep 0.1
                done
            fi

            # Extract first frame for color generation
            thumbnail="$THUMBNAIL_DIR/$(basename "$imgpath").jpg"
            ffmpeg -y -i "$imgpath" -vframes 1 "$thumbnail" 2>/dev/null

            # Set thumbnail path. Global, so it belongs to the desktop wallpaper —
            # a lockscreen or light-mode pick must not repaint the desktop preview.
            if is_desktop_target; then
                set_thumbnail_path "$thumbnail"
            fi

            if [ -f "$thumbnail" ]; then
                matugen_args+=(image "$thumbnail")
                generate_colors_material_args=(--path "$thumbnail")
                if is_desktop_target; then
                    create_restore_script "$video_path"
                fi
            else
                echo "Cannot create image to colorgen"
                remove_restore
                exit 1
            fi
        else
            if is_desktop_target; then
                kill_existing_mpvpaper
            fi
            matugen_args+=(image "$imgpath")
            generate_colors_material_args=(--path "$imgpath")
            # Update wallpaper path in config
            if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
                set_wallpaper_path "$imgpath" "${lockscreen_flag:+lockscreen}"
            fi
            if is_desktop_target; then
                remove_restore
            fi
        fi
    fi
    fi

    # Determine mode if not set
    if [[ -z "$mode_flag" ]]; then
        current_mode=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")
        if [[ "$current_mode" == "prefer-dark" ]]; then
            mode_flag="dark"
        else
            mode_flag="light"
        fi
    fi

    # enforce dark mode for terminal
    if [[ -n "$mode_flag" ]]; then
        matugen_args+=(--mode "$mode_flag")
        if [[ $(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.forceDarkMode' "$SHELL_CONFIG_FILE") == "true" ]]; then
            generate_colors_material_args+=(--mode "dark")
        else
            generate_colors_material_args+=(--mode "$mode_flag")
        fi
    fi
    if [[ "$type_flag" == "scheme-intense" ]]; then
        matugen_args+=(--type "scheme-fidelity")
    elif [[ -n "$type_flag" ]]; then
        matugen_args+=(--type "$type_flag")
    fi
    matugen_args+=(--source-color-index 0)
    generate_colors_material_args+=(--scheme "$type_flag")
    generate_colors_material_args+=(--termscheme "$terminalscheme" --blend_bg_fg)
    generate_colors_material_args+=(--cache "$STATE_DIR/user/generated/color.txt")

    pre_process "$mode_flag"

    # Check if app and shell theming is enabled in config
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        enable_apps_shell=$(jq -r '.appearance.wallpaperTheming.enableAppsAndShell' "$SHELL_CONFIG_FILE")
        if [ "$enable_apps_shell" == "false" ]; then
            echo "App and shell theming disabled, skipping matugen and color generation"
            return
        fi
    fi

    # Set harmony and related properties
    if [ -f "$SHELL_CONFIG_FILE" ]; then
        harmony=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmony' "$SHELL_CONFIG_FILE")
        harmonize_threshold=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.harmonizeThreshold' "$SHELL_CONFIG_FILE")
        term_fg_boost=$(jq -r '.appearance.wallpaperTheming.terminalGenerationProps.termFgBoost' "$SHELL_CONFIG_FILE")
        [[ "$harmony" != "null" && -n "$harmony" ]] && generate_colors_material_args+=(--harmony "$harmony")
        [[ "$harmonize_threshold" != "null" && -n "$harmonize_threshold" ]] && generate_colors_material_args+=(--harmonize_threshold "$harmonize_threshold")
        [[ "$term_fg_boost" != "null" && -n "$term_fg_boost" ]] && generate_colors_material_args+=(--term_fg_boost "$term_fg_boost")
    fi

    if [[ -n "$theme_file" ]]; then
        mkdir -p "$(dirname "$STATE_DIR/user/generated/colors.json")"
        cp "$theme_file" "$STATE_DIR/user/generated/colors.json"
        rm -f "$STATE_DIR/matugen_error_notified"
        echo "[switchwall.sh] Applied theme: $type_flag"
        if [[ "$(jq -r '.appearance.icons.enableThemed' "$SHELL_CONFIG_FILE" 2>/dev/null)" == "true" ]]; then python3 "$HOME/.config/quickshell/ii/scripts/colors/recolor_icons.py"; fi
        "$SCRIPT_DIR"/applycolor.sh
    else
        matugen_exit_code=0
        if ! matugen "${matugen_args[@]}"; then
            matugen_exit_code=$?
            report_matugen_failure "switchwall.sh" "$matugen_exit_code"
        else
            rm -f "$STATE_DIR/matugen_error_notified"
        fi
        if [[ "$type_flag" == "scheme-intense" ]]; then
            echo "[switchwall.sh] Applying intense surface boost to colors.json (mode: $mode_flag)" >&2
            python3 "$SCRIPT_DIR/boost_surface_chroma.py" "$STATE_DIR/user/generated/colors.json" --mode "$mode_flag"
        fi
        if [[ "$(jq -r '.appearance.icons.enableThemed' "$SHELL_CONFIG_FILE" 2>/dev/null)" == "true" ]]; then python3 "$HOME/.config/quickshell/ii/scripts/colors/recolor_icons.py"; fi
        source "$(eval echo $ILLOGICAL_IMPULSE_VIRTUAL_ENV)/bin/activate"
        if python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
            --all-previews "$STATE_DIR/user/generated/wallpaper_preview_colors.json" \
            --request-token "$request_token_file" --request-value "$my_request_token" \
            > "$STATE_DIR"/user/generated/material_colors.scss.tmp; then
            mv "$STATE_DIR"/user/generated/material_colors.scss.tmp "$STATE_DIR"/user/generated/material_colors.scss
        else
            rm -f "$STATE_DIR"/user/generated/material_colors.scss.tmp
            echo "[switchwall.sh] Color generation skipped; preserving the previous terminal palette." >&2
        fi
        deactivate
        "$SCRIPT_DIR"/applycolor.sh
    fi


    # Generate dynamic Material You icon theme
    # Using gowall and python helper to recolor a base SVG theme
    #echo "Generating dynamic icons..."
    #python3 "$HOME/.config/quickshell/ii/scripts/colors/recolor_icons.py"
    #local _venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$XDG_STATE_HOME/quickshell/.venv}"
    #source "$(eval echo $_venv)/bin/activate"
    #python3 "$SCRIPT_DIR/generate_colors_material.py" "${generate_colors_material_args[@]}" \
    #    > "$STATE_DIR"/user/generated/material_colors.scss.tmp && \
    #mv "$STATE_DIR"/user/generated/material_colors.scss.tmp "$STATE_DIR"/user/generated/material_colors.scss
    #"$SCRIPT_DIR"/applycolor.sh
    #deactivate

    # Pass screen width, height, and wallpaper path to post_process
    max_width_desired="$(hyprctl monitors -j | jq '([.[].width] | min)' | xargs)"
    max_height_desired="$(hyprctl monitors -j | jq '([.[].height] | min)' | xargs)"
    post_process "$max_width_desired" "$max_height_desired" "$imgpath"
}

main() {
    imgpath=""
    mode_flag=""
    type_flag=""
    color_flag=""
    color=""
    noswitch_flag=""

    get_type_from_config() {
        jq -r '.appearance.palette.type' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "auto"
    }
    get_accent_color_from_config() {
        jq -r '.appearance.palette.accentColor' "$SHELL_CONFIG_FILE" 2>/dev/null || echo ""
    }
    set_accent_color() {
        local color="$1"
        jq --indent 4 --arg color "$color" '.appearance.palette.accentColor = $color' "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    }

    detect_scheme_type_from_image() {
        local img="$1"
        local _venv="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$XDG_STATE_HOME/quickshell/.venv}"
        source "$(eval echo $_venv)/bin/activate"
        "$SCRIPT_DIR"/scheme_for_image.py "$img" 2>/dev/null | tr -d '\n'
        deactivate
    }

    lockscreen_flag=""
    colors_only_flag=""
    lightmode_flag=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                mode_flag="$2"
                shift 2
                ;;
            --type)
                type_flag="$2"
                shift 2
                ;;
            --lockscreen)
                lockscreen_flag="1"
                shift
                ;;
            --lightmode)
                lightmode_flag="1"
                shift
                ;;
            --colors-only)
                colors_only_flag="1"
                shift
                ;;
            --color)
                if [[ "$2" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
                    set_accent_color "$2"
                    shift 2
                elif [[ "$2" == "clear" ]]; then
                    set_accent_color ""
                    shift 2
                else
                    set_accent_color $(hyprpicker --no-fancy)
                    shift
                fi
                ;;
            --image)
                imgpath="$2"
                shift 2
                ;;
            --request-seq)
                request_seq_flag="$2"
                shift 2
                ;;
            --noswitch)
                noswitch_flag="1"
                if [[ -z "$imgpath" ]]; then
                    use_wpe=$(jq -r '.background.useWallpaperEngine' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "false")
                    if [[ "$use_wpe" == "true" ]]; then
                        imgpath=$(jq -r '.background.wallpaperEngineId' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                    else
                        imgpath=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
                    fi
                fi
                shift
                ;;
            *)
                if [[ -z "$imgpath" ]]; then
                    imgpath="$1"
                fi
                shift
                ;;
        esac
    done

    # If accentColor is set in config, use it
    config_color="$(get_accent_color_from_config)"
    if [[ "$config_color" =~ ^#?[A-Fa-f0-9]{6}$ ]]; then
        color_flag="1"
        color="$config_color"
    fi

    # If type_flag is not set, get it from config
    if [[ -z "$type_flag" ]]; then
        type_flag="$(get_type_from_config)"
    fi

    # Validate type_flag (allow 'auto' and 'scheme-auto' as well)
    allowed_types=(scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot scheme-vibrant scheme-intense auto scheme-auto)
    valid_type=0
    for t in "${allowed_types[@]}"; do
        if [[ "$type_flag" == "$t" ]]; then
            valid_type=1
            break
        fi
    done
    
    theme_file=""
    if [[ $valid_type -eq 0 ]]; then
        # Check if it's a custom or default theme
        if [[ -f "$XDG_CONFIG_HOME/illogical-impulse/themes/$type_flag.json" ]]; then
            theme_file="$XDG_CONFIG_HOME/illogical-impulse/themes/$type_flag.json"
            valid_type=1
        elif [[ -f "$CONFIG_DIR/defaults/themes/$type_flag.json" ]]; then
            theme_file="$CONFIG_DIR/defaults/themes/$type_flag.json"
            valid_type=1
        fi
    fi

    if [[ $valid_type -eq 0 ]]; then
        echo "[switchwall.sh] Warning: Invalid type '$type_flag', defaulting to 'auto'" >&2
        type_flag="auto"
    fi
    # Normalize scheme-auto → auto for detection
    [[ "$type_flag" == "scheme-auto" ]] && type_flag="auto"

    # Only prompt for wallpaper if not using --color and not using --noswitch and no imgpath set
    if [[ -z "$imgpath" && -z "$color_flag" && -z "$noswitch_flag" ]]; then
        cd "$(xdg-user-dir PICTURES)/Wallpapers/showcase" 2>/dev/null || cd "$(xdg-user-dir PICTURES)/Wallpapers" 2>/dev/null || cd "$(xdg-user-dir PICTURES)" || return 1
        if command -v zenity >/dev/null; then
            imgpath="$(zenity --file-selection --title="Choose wallpaper" 2>/dev/null)"
        else
            imgpath="$(kdialog --getopenfilename . --title 'Choose wallpaper')"
        fi
        if [[ -z "$imgpath" ]]; then
            echo "Wallpaper selection cancelled."
            exit 0
        fi
    fi

    # Fallback to default wallpaper if empty
    if [[ -z "$imgpath" || "$imgpath" == "null" ]]; then
        imgpath="$CONFIG_DIR/assets/images/default_wallpaper.png"
    fi

    # If --lightmode is passed and --noswitch is passed:
    # Only save to config without running matugen or changing theme colors
    if [[ -n "$lightmode_flag" && -n "$noswitch_flag" ]]; then
        set_wallpaper_path "$imgpath" "lightmode"
        echo "[switchwall.sh] Saved light mode wallpaper path."
        exit 0
    fi

    # Update config wallpaper path unless colors_only_flag or noswitch_flag is set
    if [[ -z "$colors_only_flag" && -z "$noswitch_flag" ]]; then
        if [[ -n "$lightmode_flag" ]]; then
            set_wallpaper_path "$imgpath" "lightmode"
        elif [[ -n "$lockscreen_flag" ]]; then
            set_wallpaper_path "$imgpath" "lockscreen"
        else
            set_wallpaper_path "$imgpath" "desktop"
        fi
    fi

    # Only clear accent color if a NEW image is provided and noswitch is NOT set
    current_wallpaper=$(jq -r '.background.wallpaperPath' "$SHELL_CONFIG_FILE" 2>/dev/null || echo "")
    if [[ -n "$imgpath" && -z "$noswitch_flag" && "$imgpath" != "$current_wallpaper" ]]; then
        set_accent_color ""
        color_flag=""
        color=""
    fi

    # If type_flag is 'auto', detect scheme type from image (after imgpath is set)
    if [[ "$type_flag" == "auto" ]]; then
        if [[ -n "$imgpath" && -f "$imgpath" ]]; then
            detected_type="$(detect_scheme_type_from_image "$imgpath")"
            # Only use detected_type if it's valid
            valid_detected=0
            for t in "${allowed_types[@]}"; do
                if [[ "$detected_type" == "$t" && "$detected_type" != "auto" ]]; then
                    valid_detected=1
                    break
                fi
            done
            if [[ $valid_detected -eq 1 ]]; then
                type_flag="$detected_type"
            else
                echo "[switchwall] Warning: Could not auto-detect a valid scheme, defaulting to 'scheme-tonal-spot'" >&2
                type_flag="scheme-tonal-spot"
            fi
        else
            echo "[switchwall] Warning: No image to auto-detect scheme from, defaulting to 'scheme-tonal-spot'" >&2
            type_flag="scheme-tonal-spot"
        fi
    fi

    # Resolve light theme variant when mode is light
    if [[ -n "$theme_file" && "$mode_flag" == "light" ]]; then
        local light_theme_file="${theme_file%.json}_light.json"
        if [[ -f "$light_theme_file" ]]; then
            theme_file="$light_theme_file"
            echo "[switchwall.sh] Using light theme variant: $type_flag"
        else
            echo "[switchwall.sh] No light variant for '$type_flag', falling back to matugen generation"
            theme_file=""
            # Must be a valid matugen scheme (not "auto" — matugen rejects it)
            type_flag="scheme-tonal-spot"
        fi
    fi

    switch "$imgpath" "$mode_flag" "$type_flag" "$color_flag" "$color" "$theme_file"
}

main "$@"
