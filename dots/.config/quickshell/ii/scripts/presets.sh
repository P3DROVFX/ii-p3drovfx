#!/usr/bin/env bash

PRESETS_DIR="$HOME/.config/illogical-impulse/presets"
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

action=$1
name=$2

case $action in
    save)
        if [[ -z "$name" ]]; then exit 1; fi
        cp "$CONFIG_FILE" "$PRESETS_DIR/$name.json"
        
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
        cp "$CONFIG_FILE" "$PRESETS_DIR/$name.json"

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
        if [[ -f "$PRESETS_DIR/$name.json" ]]; then
            # Use python helper to expand paths and fallbacks
            python3 "$SCRIPTS_DIR/presets_helper.py" expand "$PRESETS_DIR/$name.json" "$CONFIG_FILE" "$PRESETS_DIR" "$name"
            
            # Read colorEngine from the newly expanded config.json to run the correct script
            color_engine=$(jq -r '.appearance.colorEngine // "vynx"' "$CONFIG_FILE" 2>/dev/null)
            switch_script="switchwall.sh"
            if [[ "$color_engine" == "fork" ]]; then
                switch_script="switchwall_vynx.sh"
            fi
            
            # Apply wallpaper and colors from the newly loaded config
            env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH" "$SCRIPTS_DIR/colors/$switch_script" --noswitch > /tmp/presets_switchwall.log 2>&1 &
        fi
        ;;
    delete)
        if [[ -z "$name" ]]; then exit 1; fi
        rm -f "$PRESETS_DIR/$name.json"
        # Delete any associated asset files
        for file in "$PRESETS_DIR/$name".* "$PRESETS_DIR/${name}_profile".* "$PRESETS_DIR/${name}_banner".*; do
            if [[ -f "$file" && "${file##*.}" != "json" ]]; then
                rm -f "$file"
            fi
        done
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

            # 2. Find and copy profile picture if it exists
            for file in "$PRESETS_DIR/${name}_profile".*; do
                if [[ -f "$file" ]]; then
                    ext="${file##*.}"
                    if [[ "$ext" != "json" && "$ext" != "zip" ]]; then
                        cp "$file" "$TMP_DIR/profile.$ext"
                        break
                    fi
                fi
            done
            # Fallback if profile is not in PRESETS_DIR but local path exists
            if ! ls "$TMP_DIR"/profile.* >/dev/null 2>&1; then
                profile_path=$(jq -r '.userProfile.imagePath // .sidebar.dashboardHeader.profileImagePath // ""' "$PRESETS_DIR/$name.json" 2>/dev/null)
                profile_path="${profile_path#file://}"
                profile_path="${profile_path%%\?*}"
                if [[ -f "$profile_path" ]]; then
                    ext="${profile_path##*.}"
                    cp "$profile_path" "$TMP_DIR/profile.$ext"
                fi
            fi

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
