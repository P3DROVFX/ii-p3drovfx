#!/usr/bin/env bash

PRESETS_DIR="$HOME/.config/illogical-impulse/presets"
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/ii/preset-backups"
BACKUP_KEEP=10
# Which preset the running config came from. Nothing else records this, and
# an update is only worth applying on the spot when it is the one in use.
ACTIVE_FILE="$PRESETS_DIR/.active"
mkdir -p "$PRESETS_DIR"

notify_export() {
    local urgency="$1"
    local title="$2"
    local body="$3"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "II Presets" -u "$urgency" "$title" "$body" >/dev/null 2>&1 &
    fi
}

fail_export() {
    local message="$1"
    printf '[presets.sh] Export failed: %s\n' "$message" >&2
    notify_export critical "Preset export failed" "$message"
    exit 1
}

# Snapshot config.json before anything rewrites it. Applying a preset is the
# one action here the user cannot undo by hand, so every apply leaves a way
# back.
backup_config() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    mkdir -p "$BACKUP_DIR" || return 1
    local stamp
    # Nanoseconds, not seconds: two applies in the same second would otherwise
    # write the same filename and the older config would be lost.
    stamp=$(date +%Y%m%d-%H%M%S%N)
    cp -- "$CONFIG_FILE" "$BACKUP_DIR/$stamp-config.json" || return 1
    local old_backup
    while IFS= read -r old_backup; do
        [[ -n "$old_backup" ]] && rm -f -- "$old_backup"
    done < <(newest_backups | tail -n +$((BACKUP_KEEP + 1)))
}

# Newest first. Sorted by name rather than mtime because the name is the
# timestamp, which survives copying, restoring and touching the files.
newest_backups() {
    ls -1 "$BACKUP_DIR"/*-config.json 2>/dev/null | sort -r
}

# Re-run the colour pipeline against whatever config.json now says.
apply_colors() {
    local color_engine switch_script
    color_engine=$(jq -r '.appearance.colorEngine // "vynx"' "$CONFIG_FILE" 2>/dev/null)
    switch_script="switchwall.sh"
    if [[ "$color_engine" == "fork" ]]; then
        switch_script="switchwall_vynx.sh"
    fi
    env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" \
        "$SCRIPTS_DIR/colors/$switch_script" --noswitch > /tmp/presets_switchwall.log 2>&1 &
}

action=$1
name=$2

case $action in
    save)
        if [[ -z "$name" ]]; then exit 1; fi
        # Sanitize on the way in, not just on export: a preset that never holds
        # a token or a MAC address cannot leak one later.
        python3 "$SCRIPTS_DIR/presets_helper.py" sanitize "$CONFIG_FILE" "$PRESETS_DIR/$name.json" || exit 1
        
        # Also copy the wallpaper if configured
        wall_path=$(jq -r '.background.wallpaperPath // ""' "$CONFIG_FILE" 2>/dev/null)
        wall_path="${wall_path#file://}"
        wall_path="${wall_path%%\?*}"
        if [[ -f "$wall_path" ]]; then
            ext="${wall_path##*.}"
            cp "$wall_path" "$PRESETS_DIR/$name.$ext"
        fi

        # Also copy the profile picture if configured
        profile_path=$(jq -r '.userProfile.imagePath // .sidebar.dashboardHeader.profileImagePath // ""' "$CONFIG_FILE" 2>/dev/null)
        profile_path="${profile_path#file://}"
        profile_path="${profile_path%%\?*}"
        if [[ -f "$profile_path" ]]; then
            ext="${profile_path##*.}"
            cp "$profile_path" "$PRESETS_DIR/${name}_profile.$ext"
        fi

        # Also copy the sidebar dashboard banner image if configured
        banner_path=$(jq -r '.sidebar.bannerImage // ""' "$CONFIG_FILE" 2>/dev/null)
        banner_path="${banner_path#file://}"
        banner_path="${banner_path%%\?*}"
        if [[ -f "$banner_path" ]]; then
            ext="${banner_path##*.}"
            cp "$banner_path" "$PRESETS_DIR/${name}_banner.$ext"
        fi
        ;;
    update)
        if [[ -z "$name" ]]; then exit 1; fi
        if [[ ! -f "$PRESETS_DIR/$name.json" ]]; then exit 1; fi
        # Remove stale asset files for this preset before overwriting
        for file in "$PRESETS_DIR/$name".* "$PRESETS_DIR/${name}_profile".* "$PRESETS_DIR/${name}_banner".*; do
            if [[ -f "$file" && "${file##*.}" != "json" ]]; then
                rm -f "$file"
            fi
        done
        python3 "$SCRIPTS_DIR/presets_helper.py" sanitize "$CONFIG_FILE" "$PRESETS_DIR/$name.json" || exit 1

        wall_path=$(jq -r '.background.wallpaperPath // ""' "$CONFIG_FILE" 2>/dev/null)
        wall_path="${wall_path#file://}"
        wall_path="${wall_path%%\?*}"
        if [[ -f "$wall_path" ]]; then
            ext="${wall_path##*.}"
            cp "$wall_path" "$PRESETS_DIR/$name.$ext"
        fi

        profile_path=$(jq -r '.userProfile.imagePath // .sidebar.dashboardHeader.profileImagePath // ""' "$CONFIG_FILE" 2>/dev/null)
        profile_path="${profile_path#file://}"
        profile_path="${profile_path%%\?*}"
        if [[ -f "$profile_path" ]]; then
            ext="${profile_path##*.}"
            cp "$profile_path" "$PRESETS_DIR/${name}_profile.$ext"
        fi

        banner_path=$(jq -r '.sidebar.bannerImage // ""' "$CONFIG_FILE" 2>/dev/null)
        banner_path="${banner_path#file://}"
        banner_path="${banner_path%%\?*}"
        if [[ -f "$banner_path" ]]; then
            ext="${banner_path##*.}"
            cp "$banner_path" "$PRESETS_DIR/${name}_banner.$ext"
        fi
        ;;
    load)
        if [[ -z "$name" ]]; then exit 1; fi
        if [[ ! -f "$PRESETS_DIR/$name.json" ]]; then exit 1; fi
        # Migrate up, block newer. An older preset is carried forward by the
        # shell's own migrations; a newer one names settings this build has
        # never heard of, and merging it in would mangle them silently.
        compat=$(python3 "$SCRIPTS_DIR/presets_helper.py" compat "$PRESETS_DIR/$name.json" 2>/dev/null)
        if [[ -n "$compat" ]] && [[ "$(jq -r '.ok' <<<"$compat" 2>/dev/null)" == "false" ]]; then
            notify_export critical "Preset not applied" \
                "$(jq -r '.reason // "This preset is not compatible with this version of the shell."' <<<"$compat")"
            printf '[presets.sh] %s\n' "$(jq -r '.reason // "incompatible preset"' <<<"$compat")" >&2
            exit 1
        fi
        if ! backup_config; then
            notify_export critical "Preset not applied" "Could not back up the current config."
            exit 1
        fi
        # Layer the preset over the current config instead of replacing it, so
        # API keys, search aliases and dock pins the preset does not carry are
        # left alone rather than erased.
        if ! python3 "$SCRIPTS_DIR/presets_helper.py" merge "$PRESETS_DIR/$name.json" "$CONFIG_FILE" "$CONFIG_FILE" "$PRESETS_DIR" "$name"; then
            notify_export critical "Preset not applied" "Could not merge preset: $name"
            exit 1
        fi
        printf '%s\n' "$name" > "$ACTIVE_FILE"
        apply_colors
        ;;
    revert)
        # Pops the newest snapshot, so pressing revert twice steps back twice.
        latest=$(newest_backups | head -n1)
        if [[ -z "$latest" || ! -f "$latest" ]]; then
            notify_export normal "Nothing to revert" "No preset has been applied yet."
            exit 1
        fi
        if ! cp -- "$latest" "$CONFIG_FILE"; then
            notify_export critical "Revert failed" "Could not restore: $latest"
            exit 1
        fi
        rm -f -- "$latest"
        rm -f -- "$ACTIVE_FILE"
        apply_colors
        notify_export normal "Settings restored" "Reverted to the config from before the last preset."
        ;;
    delete)
        if [[ -z "$name" ]]; then exit 1; fi
        rm -f "$PRESETS_DIR/$name.json"
        if [[ -f "$ACTIVE_FILE" && "$(cat "$ACTIVE_FILE" 2>/dev/null)" == "$name" ]]; then
            rm -f -- "$ACTIVE_FILE"
        fi
        # Delete any associated asset files
        for file in "$PRESETS_DIR/$name".* "$PRESETS_DIR/${name}_profile".* "$PRESETS_DIR/${name}_banner".*; do
            if [[ -f "$file" && "${file##*.}" != "json" ]]; then
                rm -f "$file"
            fi
        done
        ;;
    scan)
        # One JSON line describing what applying this preset would let run.
        # Always prints something the caller can show, even on failure.
        if [[ -z "$name" ]]; then
            echo '{"ok": false, "error": "No preset name was provided."}'
            exit 1
        fi
        if [[ ! -f "$PRESETS_DIR/$name.json" ]]; then
            echo '{"ok": false, "error": "That preset no longer exists."}'
            exit 1
        fi
        python3 "$SCRIPTS_DIR/presets_helper.py" scan "$PRESETS_DIR/$name.json" "$CONFIG_FILE"
        ;;
    list)
        python3 "$SCRIPTS_DIR/presets_helper.py" list "$PRESETS_DIR"
        ;;
    export)
        if [[ -z "$name" ]]; then
            fail_export "No preset name was provided."
        fi
        if [[ ! -f "$PRESETS_DIR/$name.json" ]]; then
            fail_export "Preset not found: $name"
        fi

        if ! command -v zip >/dev/null 2>&1; then
            fail_export "The 'zip' utility is not installed."
        fi
        
        if command -v zenity >/dev/null; then
            DEST_ZIP=$(zenity --file-selection --save --confirm-overwrite --filename="$HOME/${name}.zip" --file-filter="ZIP | *.zip" 2>/dev/null)
        else
            DEST_ZIP=$(kdialog --getsavefilename "$HOME/${name}.zip" "*.zip" 2>/dev/null)
        fi
        
        if [[ -n "$DEST_ZIP" ]]; then
            # If the user selected .zip but extension wasn't appended automatically:
            if [[ "$DEST_ZIP" != *.zip ]]; then
                DEST_ZIP="${DEST_ZIP}.zip"
            fi

            DEST_DIR=$(dirname -- "$DEST_ZIP")
            if [[ ! -d "$DEST_DIR" ]]; then
                fail_export "Destination directory does not exist: $DEST_DIR"
            fi
            if [[ ! -w "$DEST_DIR" ]]; then
                fail_export "Destination directory is not writable: $DEST_DIR"
            fi
            
            if ! TMP_DIR=$(mktemp -d /tmp/preset_export_XXXXXX); then
                fail_export "Could not create a temporary export directory."
            fi
            
            # Copy and sanitize JSON config
            if ! cp "$PRESETS_DIR/$name.json" "$TMP_DIR/config.json"; then
                rm -rf "$TMP_DIR"
                fail_export "Could not copy the preset configuration."
            fi
            if ! python3 "$SCRIPTS_DIR/presets_helper.py" sanitize "$TMP_DIR/config.json" "$TMP_DIR/config.json"; then
                rm -rf "$TMP_DIR"
                fail_export "Could not sanitize the preset configuration."
            fi
            
            # 1. Find and copy wallpaper if it exists
            for file in "$PRESETS_DIR/$name".*; do
                if [[ -f "$file" ]]; then
                    base=$(basename "$file")
                    ext="${file##*.}"
                    if [[ "$ext" != "json" && "$ext" != "zip" && "$base" != "${name}_profile."* && "$base" != "${name}_banner."* ]]; then
                        cp "$file" "$TMP_DIR/wallpaper.$ext"
                        break
                    fi
                fi
            done
            # Fallback if wallpaper is not in PRESETS_DIR but local path exists
            if ! ls "$TMP_DIR"/wallpaper.* >/dev/null 2>&1; then
                wall_path=$(jq -r '.background.wallpaperPath // ""' "$PRESETS_DIR/$name.json" 2>/dev/null)
                wall_path="${wall_path#file://}"
                wall_path="${wall_path%%\?*}"
                if [[ -f "$wall_path" ]]; then
                    ext="${wall_path##*.}"
                    cp "$wall_path" "$TMP_DIR/wallpaper.$ext"
                fi
            fi

            # 2. The profile picture is deliberately not exported. It is the
            #    user's own avatar, it says nothing about the theme, and an
            #    exported preset is meant to be handed to other people.

            # 3. Find and copy sidebar dashboard banner image if it exists
            for file in "$PRESETS_DIR/${name}_banner".*; do
                if [[ -f "$file" ]]; then
                    ext="${file##*.}"
                    if [[ "$ext" != "json" && "$ext" != "zip" ]]; then
                        cp "$file" "$TMP_DIR/banner.$ext"
                        break
                    fi
                fi
            done
            # Fallback if banner is not in PRESETS_DIR but local path exists
            if ! ls "$TMP_DIR"/banner.* >/dev/null 2>&1; then
                banner_path=$(jq -r '.sidebar.bannerImage // ""' "$PRESETS_DIR/$name.json" 2>/dev/null)
                banner_path="${banner_path#file://}"
                banner_path="${banner_path%%\?*}"
                if [[ -f "$banner_path" ]]; then
                    ext="${banner_path##*.}"
                    cp "$banner_path" "$TMP_DIR/banner.$ext"
                fi
            fi
            
            # Zip everything
            if ! (cd "$TMP_DIR" && zip -r "$DEST_ZIP" .); then
                rm -rf "$TMP_DIR"
                fail_export "Could not write the archive to: $DEST_ZIP"
            fi

            if [[ ! -s "$DEST_ZIP" ]]; then
                rm -rf "$TMP_DIR"
                fail_export "The archive was not created: $DEST_ZIP"
            fi
            
            # Cleanup
            rm -rf "$TMP_DIR"
            printf '[presets.sh] Exported preset to: %s\n' "$DEST_ZIP"
            notify_export normal "Preset exported" "Saved to: $DEST_ZIP"
        else
            printf '[presets.sh] Export cancelled.\n' >&2
            notify_export low "Preset export cancelled" "No destination was selected."
        fi
        ;;
    import)
        if command -v zenity >/dev/null; then
            FILE=$(zenity --file-selection --file-filter="Presets (*.zip *.json) | *.zip *.json" 2>/dev/null)
        else
            FILE=$(kdialog --getopenfilename "$HOME" "*.zip *.json" 2>/dev/null)
        fi
        
        if [[ -n "$FILE" && -f "$FILE" ]]; then
            preset_name=$(basename "$FILE" | sed 's/\.[^.]*$//')
            ext="${FILE##*.}"
            ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$ext" == "json" ]]; then
                # Clean/sanitize paths even on raw JSON import to be safe
                mkdir -p "$PRESETS_DIR"
                python3 "$SCRIPTS_DIR/presets_helper.py" sanitize "$FILE" "$PRESETS_DIR/$preset_name.json"
                echo 'success'
            elif [[ "$ext" == "zip" ]]; then
                TMP_DIR=$(mktemp -d /tmp/preset_import_XXXXXX)
                unzip -o "$FILE" -d "$TMP_DIR" >/dev/null
                
                # Check for config file
                config_json=""
                if [[ -f "$TMP_DIR/config.json" ]]; then
                    config_json="$TMP_DIR/config.json"
                else
                    # Fallback to any json in zip
                    for f in "$TMP_DIR"/*.json; do
                        if [[ -f "$f" ]]; then
                            config_json="$f"
                            break
                        fi
                    done
                fi
                
                if [[ -n "$config_json" ]]; then
                    mkdir -p "$PRESETS_DIR"
                    # Sanitize paths when importing config
                    python3 "$SCRIPTS_DIR/presets_helper.py" sanitize "$config_json" "$PRESETS_DIR/$preset_name.json"
                    
                    # Find and unpack assets (wallpaper, profile, banner)
                    for f in "$TMP_DIR"/*; do
                        if [[ -f "$f" ]]; then
                            fname=$(basename "$f")
                            f_ext="${fname##*.}"
                            f_ext=$(echo "$f_ext" | tr '[:upper:]' '[:lower:]')
                            if [[ "$f_ext" != "json" && "$f_ext" != "zip" ]]; then
                                fname_lower=$(echo "$fname" | tr '[:upper:]' '[:lower:]')
                                if [[ "$fname_lower" == profile.* || "$fname_lower" == *profile*.* ]]; then
                                    cp "$f" "$PRESETS_DIR/${preset_name}_profile.$f_ext"
                                elif [[ "$fname_lower" == banner.* || "$fname_lower" == *banner*.* ]]; then
                                    cp "$f" "$PRESETS_DIR/${preset_name}_banner.$f_ext"
                                elif [[ "$fname_lower" == wallpaper.* || "$fname_lower" == *wallpaper*.* || "$fname_lower" == "$preset_name".* ]]; then
                                    cp "$f" "$PRESETS_DIR/$preset_name.$f_ext"
                                else
                                    # Fallback to main preset wallpaper if no specific match
                                    if [[ ! -f "$PRESETS_DIR/$preset_name.$f_ext" ]]; then
                                        cp "$f" "$PRESETS_DIR/$preset_name.$f_ext"
                                    fi
                                fi
                            fi
                        fi
                    done
                    echo 'success'
                fi
                rm -rf "$TMP_DIR"
            fi
        fi
        ;;
esac
