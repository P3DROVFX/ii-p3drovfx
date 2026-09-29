#!/bin/bash
ACTION=$1
ARG2=$2
ARG3=$3

TARGET_DIR="$HOME/.config/illogical-impulse/bluetooth_images/"
mkdir -p "$TARGET_DIR"

if [ "$ACTION" == "pick" ]; then
    # Pick a PNG file using kdialog or zenity
    if command -v kdialog >/dev/null; then
        kdialog --getopenfilename "$HOME" "*.png|Portable Network Graphics (*.png)" 2>/dev/null
    elif command -v zenity >/dev/null; then
        zenity --file-selection --file-filter="*.png" 2>/dev/null
    else
        echo "Error: No file picker found (kdialog or zenity required)" >&2
        exit 1
    fi
elif [ "$ACTION" == "copy" ]; then
    # Copy and rename image based on MAC
    # Usage: copy <source_path> <mac_address>
    SOURCE_PATH=$ARG2
    MAC=$ARG3
    
    if [ ! -f "$SOURCE_PATH" ]; then
        echo "Error: Source file not found" >&2
        exit 1
    fi
    
    SAFE_MAC=$(echo "$MAC" | tr ':' '_')
    FILENAME="device_${SAFE_MAC}.png"
    # Auto-trim transparent borders so the device image isn't surrounded by empty canvas
    python3 -c "
from PIL import Image
import sys
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src)
bbox = im.getbbox()
if bbox:
    w, h = im.size
    pad = int(max(bbox[2] - bbox[0], bbox[3] - bbox[1]) * 0.02)
    box = (max(0, bbox[0] - pad), max(0, bbox[1] - pad), min(w, bbox[2] + pad), min(h, bbox[3] + pad))
    im.crop(box).save(dst)
else:
    im.save(dst)
" "$SOURCE_PATH" "$TARGET_DIR$FILENAME" 2>/dev/null || cp "$SOURCE_PATH" "$TARGET_DIR$FILENAME"
    echo "$FILENAME"
fi
