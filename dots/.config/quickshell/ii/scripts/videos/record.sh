#!/usr/bin/env bash

# Clear AppImage library overrides to avoid breaking system commands like flatpak/obs
unset LD_LIBRARY_PATH
unset LD_PRELOAD

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"
SERVICE_PATH=".screenRecord.service"

STATE_FILE="$HOME/.local/state/quickshell/states.json"
STATE_JSON_PATH=".screenRecord.active"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)
REC_SERVICE=$(jq -r "$SERVICE_PATH" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_SERVICE" || "$REC_SERVICE" == "null" ]]; then
    REC_SERVICE="obs"
fi

REC_USE_GPU=$(jq -r ".screenRecord.useGpu" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_USE_GPU" || "$REC_USE_GPU" == "null" ]]; then
    REC_USE_GPU="true"
fi

REC_CODEC=$(jq -r ".screenRecord.codec" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_CODEC" || "$REC_CODEC" == "null" ]]; then
    REC_CODEC="auto"
fi

REC_BITRATE=$(jq -r ".screenRecord.bitrate" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_BITRATE" || "$REC_BITRATE" == "null" ]]; then
    REC_BITRATE="8"
fi

REC_FRAMERATE=$(jq -r ".screenRecord.framerate" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_FRAMERATE" || "$REC_FRAMERATE" == "null" ]]; then
    REC_FRAMERATE="60"
fi

REC_SHOW_NOTIFICATIONS=$(jq -r ".screenRecord.showNotifications" "$CONFIG_FILE" 2>/dev/null)
if [[ -z "$REC_SHOW_NOTIFICATIONS" || "$REC_SHOW_NOTIFICATIONS" == "null" ]]; then
    REC_SHOW_NOTIFICATIONS="true"
fi

RECORDING_DIR=""

TIMER_PID=""  
SECONDS_ELAPSED=-1

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos"
fi

start_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
    fi

    ( 
        while true; do
            IS_PAUSED=$(jq -r ".screenRecord.paused" "$STATE_FILE" 2>/dev/null)
            if [[ "$IS_PAUSED" != "true" ]]; then
                SECONDS_ELAPSED=$((SECONDS_ELAPSED + 1))
                jq ".screenRecord.seconds = $SECONDS_ELAPSED" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
            fi
            sleep 1
        done
    ) &
    TIMER_PID=$!
}
stop_timer() {
    if [[ -n "$TIMER_PID" ]]; then
        kill "$TIMER_PID" 2>/dev/null
        wait "$TIMER_PID" 2>/dev/null
        TIMER_PID=""
        jq ".screenRecord.seconds = 0" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

trap stop_timer EXIT

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getaudiooutput() {
    local monitor=$(pactl list sources 2>/dev/null | grep 'Name' | grep 'monitor' | cut -d ' ' -f2 | head -n1)
    if [[ -z "$monitor" ]]; then
        pactl get-default-sink 2>/dev/null | sed 's/$/.monitor/'
    else
        echo "$monitor"
    fi
}
getactivemonitor() {
    local active=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null)
    if [[ -z "$active" || "$active" == "null" ]]; then
        # Fallback to the first monitor
        active=$(hyprctl monitors -j | jq -r '.[0].name' 2>/dev/null)
    fi
    if [[ -z "$active" || "$active" == "null" ]]; then
        # Second fallback
        active=$(hyprctl activeworkspace -j | jq -r '.monitor' 2>/dev/null)
    fi
    echo "$active"
}

get_best_codec() {
    # If the user explicitly chose a CPU codec:
    if [[ "$REC_CODEC" == "libx264" || "$REC_CODEC" == "libx265" ]]; then
        echo "$REC_CODEC"
        return
    fi

    # If the user disabled GPU acceleration:
    if [[ "$REC_USE_GPU" != "true" ]]; then
        if [[ "$REC_CODEC" == "hevc_"* || "$REC_CODEC" == "libx265" ]]; then
            echo "libx265"
        else
            echo "libx264"
        fi
        return
    fi

    # If the user explicitly chose a GPU codec:
    if [[ "$REC_CODEC" != "auto" ]]; then
        # Check if the chosen encoder is compiled in ffmpeg
        if ffmpeg -encoders 2>/dev/null | grep -q "$REC_CODEC"; then
            echo "$REC_CODEC"
            return
        fi
    fi

    # If "auto" or the chosen GPU codec is not available, auto-detect:
    if ffmpeg -encoders 2>/dev/null | grep -q "h264_nvenc"; then
        echo "h264_nvenc"
    elif ffmpeg -encoders 2>/dev/null | grep -q "h264_vaapi" && [ -e /dev/dri/renderD128 ]; then
        echo "h264_vaapi"
    elif ffmpeg -encoders 2>/dev/null | grep -q "h264_amf"; then
        echo "h264_amf"
    else
        echo "libx264"
    fi
}

notify-send() {
    if [[ "$REC_SHOW_NOTIFICATIONS" == "true" ]]; then
        command notify-send "$@"
    fi
}

updateloading() {
    local state_value=$1
    jq ".screenRecord.loading = $state_value" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

updatestate() {
    local state_value=$1
    if [[ "$state_value" == "true" ]]; then
        jq "$STATE_JSON_PATH = true | .screenRecord.loading = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        start_timer
    else
        jq "$STATE_JSON_PATH = false | .screenRecord.loading = false | .screenRecord.paused = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        stop_timer
    fi
}

toggle_pause() {
    local current_paused=$(jq -r ".screenRecord.paused" "$STATE_FILE" 2>/dev/null)
    
    if [[ "$current_paused" == "true" ]]; then
        jq ".screenRecord.paused = false" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        notify-send "Recording Resumed" -a 'Recorder' &
    else
        jq ".screenRecord.paused = true" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        notify-send "Recording Paused" -a 'Recorder' &
    fi

    if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
        # Try to toggle pause via our new python script
        python3 "$(dirname "$0")/obs_pause.py" 2>/dev/null
    elif pgrep wf-recorder > /dev/null; then
        pkill -USR1 wf-recorder
    fi
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

ARGS=("$@")

if [[ "${ARGS[0]}" == "--pause" ]]; then
    toggle_pause
    exit 0
fi

MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
REGION_FLAG=0
OBS_FLAG=0

for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        REGION_FLAG=1
        if (( i+1 < ${#ARGS[@]} )) && [[ ! "${ARGS[i+1]}" =~ ^-- ]]; then
            MANUAL_REGION="${ARGS[i+1]}"
            i=$((i+1))
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--obs" ]]; then
        OBS_FLAG=1
    fi
done
IS_OBS_RECORDING=0
if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
    STATUS=$(python3 "/home/pedro/.config/quickshell/ii/scripts/videos/obs_control.py" status 2>/dev/null)
    if [[ "$STATUS" == "active" ]]; then
        IS_OBS_RECORDING=1
    fi
fi

if [[ $IS_OBS_RECORDING -eq 1 ]]; then
    notify-send "Stopping OBS Recording..." "Saving file..." -a 'Recorder' &
    python3 "/home/pedro/.config/quickshell/ii/scripts/videos/obs_control.py" stop
    sleep 1.5
    pkill -x "obs" || pkill -f "com.obsproject.Studio"
    exit 0
fi

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    updatestate false
    pkill wf-recorder &
    exit 0
fi

if [[ $REGION_FLAG -eq 1 && -z "$MANUAL_REGION" ]]; then
    # Interactive region selection
    MANUAL_REGION=$(slurp)
    if [[ -z "$MANUAL_REGION" ]]; then
        # notify-send "Recording cancelled" "No region selected" -a 'Recorder' & disown
        exit 0
    fi
fi
OBS_CMD=""
if [[ "$REC_SERVICE" == "obs" ]]; then
    if [[ -d "/var/lib/flatpak/app/com.obsproject.Studio" || -d "$HOME/.local/share/flatpak/app/com.obsproject.Studio" ]]; then
        OBS_CMD="flatpak run com.obsproject.Studio"
    elif command -v obs &> /dev/null; then
        OBS_CMD="obs"
    elif flatpak list 2>/dev/null | grep -q "com.obsproject.Studio"; then
        OBS_CMD="flatpak run com.obsproject.Studio"
    fi
fi

# Set loading state immediately to give UI feedback
updateloading true

if [[ -n "$OBS_CMD" ]]; then
    OBS_WAS_RUNNING=0
    if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
        OBS_WAS_RUNNING=1
    fi

    if [[ $OBS_WAS_RUNNING -eq 0 ]]; then
        notify-send "Starting OBS..." "OBS starting, please wait..." -a 'Recorder' &
        # Do NOT pass --startrecording here: OBS would open the xdg-desktop-portal
        # screen-picker dialog. Instead, open OBS minimized with its saved scenes,
        # then trigger recording via WebSocket so it uses the pre-configured sources.
        nohup $OBS_CMD --minimize-to-tray > /dev/null 2>&1 &

        # Wait for OBS process to appear
        for i in {1..30}; do
            if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
                break
            fi
            sleep 1
        done
    fi

    # Wait for WebSocket server to become available (OBS needs a few seconds after
    # process launch before the WebSocket server is ready to accept requests).
    # obs_control.py now returns "error" when the connection itself fails, so we
    # can keep waiting instead of mistaking the failure for an idle recording state.
    WEBSOCKET_READY=0
    for i in {1..30}; do
        STATUS=$(python3 "/home/pedro/.config/quickshell/ii/scripts/videos/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" == "inactive" || "$STATUS" == "active" ]]; then
            WEBSOCKET_READY=1
            break
        fi
        sleep 1
    done

    if [[ $WEBSOCKET_READY -eq 0 ]]; then
        notify-send "OBS Error" "Could not reach OBS WebSocket server. Check OBS -> Tools -> WebSocket Server Settings." -a 'Recorder' &
        pkill -x "obs" 2>/dev/null || pkill -f "com.obsproject.Studio" 2>/dev/null
        updatestate false
        exit 1
    fi

    notify-send "Starting OBS Recording..." "Triggering via WebSocket" -a 'Recorder' &
    python3 "/home/pedro/.config/quickshell/ii/scripts/videos/obs_control.py" start

    # Wait for the recording to actually become active before entering the watchdog
    # loop. This is critical: a Wayland pipewire-screen-cast source may pop up the
    # xdg-desktop-portal screen picker when start_record() is issued, and the user
    # needs time to choose a monitor. Until they do, status stays "inactive" and the
    # previous watchdog would have killed OBS immediately (the original bug).
    RECORDING_ACTIVE=0
    for i in {1..60}; do
        if ! pgrep -x "obs" > /dev/null && ! pgrep -f "com.obsproject.Studio" > /dev/null; then
            break
        fi
        STATUS=$(python3 "/home/pedro/.config/quickshell/ii/scripts/videos/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" == "active" ]]; then
            RECORDING_ACTIVE=1
            break
        fi
        if [[ "$STATUS" == "error" ]]; then
            break
        fi
        sleep 1
    done

    if [[ $RECORDING_ACTIVE -eq 0 ]]; then
        notify-send "Recording Failed" "OBS did not start recording. Make sure your scene has a screen capture source and accept the Wayland portal dialog if it appears." -a 'Recorder' &
        sleep 2
        pkill -x "obs" 2>/dev/null || pkill -f "com.obsproject.Studio" 2>/dev/null
        updatestate false
        exit 1
    fi

    updatestate true

    # Now that we have confirmed the recording is "active", watch for it to become
    # "inactive" (which means the user stopped it via a second record.sh call) or
    # for OBS to be killed externally.
    while true; do
        if ! pgrep -x "obs" > /dev/null && ! pgrep -f "com.obsproject.Studio" > /dev/null; then
            break
        fi
        STATUS=$(python3 "/home/pedro/.config/quickshell/ii/scripts/videos/obs_control.py" status 2>/dev/null)
        if [[ "$STATUS" != "active" ]]; then
            # Recording stopped. Give OBS a moment to flush the file, then close it.
            sleep 1
            pkill -x "obs" 2>/dev/null || pkill -f "com.obsproject.Studio" 2>/dev/null
            break
        fi
        sleep 1
    done
    
    if [[ -n "$MANUAL_REGION" ]]; then
        notify-send "Processing Region..." "Cropping video, please wait..." -a 'Recorder' &
        LATEST_FILE=$(ls -1t | grep -E '\.(mp4|mkv|flv|mov)$' | head -1)
        if [[ -n "$LATEST_FILE" ]]; then
             # MANUAL_REGION is in format "X,Y WxH" (slurp)
             # ffmpeg crop filter: crop=w:h:x:y
             W=$(echo "$MANUAL_REGION" | cut -d' ' -f2 | cut -d'x' -f1)
             H=$(echo "$MANUAL_REGION" | cut -d' ' -f2 | cut -d'x' -f2)
             X=$(echo "$MANUAL_REGION" | cut -d' ' -f1 | cut -d',' -f1)
             Y=$(echo "$MANUAL_REGION" | cut -d' ' -f1 | cut -d',' -f2)
             
             ffmpeg -i "$LATEST_FILE" -filter:v "crop=$W:$H:$X:$Y" "cropped_$LATEST_FILE" -y && mv "cropped_$LATEST_FILE" "$LATEST_FILE"
             notify-send "Region Recording Finished" "Saved to $LATEST_FILE" -a 'Recorder' &
        fi
    fi

    LATEST_FILE=$(ls -1t | grep -E '\.(mp4|mkv|flv|mov)$' | head -1)
    if [[ -n "$LATEST_FILE" ]]; then
        qs -c ii ipc call launchVideoEditor handle "$PWD/$LATEST_FILE"
    fi

    updatestate false
    exit 0
else
    FILENAME="recording_$(getdate).mp4"
    
    CODEC=$(get_best_codec)
    CODEC_OPTS=("-c" "$CODEC" "-r" "$REC_FRAMERATE" "-p" "b=${REC_BITRATE}M")
    
    if [[ "$CODEC" == "h264_vaapi" || "$CODEC" == "hevc_vaapi" ]]; then
        CODEC_OPTS+=("-d" "/dev/dri/renderD128" "--pixel-format" "nv12")
    elif [[ "$CODEC" == "h264_amf" || "$CODEC" == "hevc_amf" ]]; then
        CODEC_OPTS+=("--pixel-format" "nv12")
    elif [[ "$CODEC" == "h264_nvenc" || "$CODEC" == "hevc_nvenc" ]]; then
        CODEC_OPTS+=("--pixel-format" "yuv420p")
    else
        CODEC_OPTS+=("--pixel-format" "yuv420p")
    fi

    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" "$FILENAME" -a 'Recorder' & disown
        updatestate true
        if [[ $SOUND_FLAG -eq 1 ]]; then
            wf-recorder -o "$(getactivemonitor)" "${CODEC_OPTS[@]}" -f "$FILENAME" --audio="$(getaudiooutput)"
        else
            wf-recorder -o "$(getactivemonitor)" "${CODEC_OPTS[@]}" -f "$FILENAME" 
        fi
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                updatestate false
                exit 1
            fi
        fi

        pos="${region%% *}"      # x,y
        size="${region##* }"     # WxH
        x="${pos%,*}"
        y="${pos#*,}"
        geometry="${x},${y} ${size}"

        notify-send "Starting recording" "$FILENAME" -a 'Recorder' & disown
        updatestate true
        if [[ $SOUND_FLAG -eq 1 ]]; then
            wf-recorder -o "$(getactivemonitor)" "${CODEC_OPTS[@]}" -f "$FILENAME"  --geometry "$geometry" --audio="$(getaudiooutput)"
        else
            wf-recorder -o "$(getactivemonitor)" "${CODEC_OPTS[@]}" -f "$FILENAME"  --geometry "$geometry"
        fi
    fi

    # Post recording action (launch video editor)
    if [[ -f "$FILENAME" ]]; then
        qs -c ii ipc call launchVideoEditor handle "$PWD/$FILENAME"
    fi
    updatestate false
fi
