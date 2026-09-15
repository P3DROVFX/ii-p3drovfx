#!/bin/bash

STATE_FILE="$HOME/.local/state/quickshell/user/generated/screenshare/apps.txt"
mkdir -p "$(dirname "$STATE_FILE")"

LAST_STATE=""

while true; do

    apps=$(pw-dump 2>/dev/null | jq -r '.[] | select((.info.props."media.class" == "Stream/Input/Video" or .info.props."media.role" == "Screen") and .info.state == "running") | (.info.props["application.name"] // .info.props["node.description"] // .info.props["node.name"]) | select(. != null and . != "")' | sort -u | paste -sd ", " -)
    
    CURRENT_STATE="${apps:-NONE}"
    if [ -z "$CURRENT_STATE" ]; then
        CURRENT_STATE="NONE"
    fi

    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        echo "$CURRENT_STATE" > "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
        
        LAST_STATE="$CURRENT_STATE"
    fi

    sleep 1.5
done