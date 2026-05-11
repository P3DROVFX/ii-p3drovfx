#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"

STATE_FILE="$HOME/.local/state/quickshell/states.json"
STATE_JSON_PATH=".screenRecord.active"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

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
    pactl get-default-sink | sed 's/$/.monitor/'
}
getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
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
    fi
done

if pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; then
    notify-send "Recording Stopped" "Stopped (OBS) & Closed" -a 'Recorder' &
    updatestate false
    pkill -TERM -x obs 2>/dev/null
    pkill -TERM -f "com.obsproject.Studio" 2>/dev/null
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
if flatpak list 2>/dev/null | grep -q "com.obsproject.Studio"; then
    OBS_CMD="flatpak run com.obsproject.Studio"
elif command -v obs &> /dev/null; then
    OBS_CMD="obs"
fi

# Set loading state immediately to give UI feedback
updateloading true

if [[ -n "$OBS_CMD" ]]; then
    notify-send "Starting OBS..." "OBS starting to record" -a 'Recorder' &
    
    nohup $OBS_CMD --startrecording --minimize-to-tray > /dev/null 2>&1 &
    
    while ! pgrep -x "obs" > /dev/null && ! pgrep -f "com.obsproject.Studio" > /dev/null; do
        sleep 1
    done
    
    sleep 1 # Wait slightly for log file to actually be created
    LOG_FILE=$(ls -1t ~/.var/app/com.obsproject.Studio/config/obs-studio/logs/*.txt ~/.config/obs-studio/logs/*.txt 2>/dev/null | head -1)
    
    if [[ -f "$LOG_FILE" ]]; then
        for i in {1..20}; do
            if grep -q "==== Recording Start" "$LOG_FILE"; then
                break
            fi
            sleep 0.5
        done
    else
        sleep 4
    fi

        updatestate true
    
    while pgrep -x "obs" > /dev/null || pgrep -f "com.obsproject.Studio" > /dev/null; do
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

    updatestate false
    exit 0
else
    FILENAME="recording_$(getdate).mp4"
    notify-send "Starting recording" "$FILENAME" -a 'Recorder' & disown
    
    # Give it a tiny bit more time for the notification to settle
    sleep 0.2
    updatestate true

    REC_OPTS=""
    if [[ -n "$MANUAL_REGION" ]]; then
        REC_OPTS="-g \"$MANUAL_REGION\""
    else
        REC_OPTS="-o \"$(getactivemonitor)\""
    fi

    if [[ $SOUND_FLAG -eq 1 ]]; then
        eval "wf-recorder $REC_OPTS --pixel-format yuv420p -c libx264 -p preset=fast -p tune=zerolatency -p crf=10 -p x264-params=scenecut=0 -f \"$FILENAME\" --audio=\"$(getaudiooutput)\" &"
    else
        eval "wf-recorder $REC_OPTS --pixel-format yuv420p -c libx264 -p preset=fast -p tune=zerolatency -p crf=10 -p x264-params=scenecut=0 -f \"$FILENAME\" &"
    fi
    
    REC_PID=$!
    wait $REC_PID
    updatestate false
fi
