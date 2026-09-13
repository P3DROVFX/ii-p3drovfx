#!/usr/bin/env bash
# Usage:
#   soundcore_anc.sh get  <MAC>          -> prints: Normal|Transparency|NoiseCanceling
#   soundcore_anc.sh set  <MAC> <MODE>   -> sets mode, exits 0 on success

CMD=$1
MAC=$2
MODE=$3

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTL="$DIR/soundcore_ctl.py"

if [ -f "$CTL" ]; then
  python3 "$CTL" "$CMD" "$MAC" ${MODE:+"$MODE"}
  exit $?
fi

CLI=$(which openscq30_cli 2>/dev/null || echo "$HOME/.local/bin/openscq30_cli")

case "$CMD" in
  get)
    "$CLI" device -a "$MAC" setting --get ambientSoundMode --json 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['value']['value'])" 2>/dev/null || echo "Normal"
    ;;
  set)
    "$CLI" device -a "$MAC" setting --set "ambientSoundMode=$MODE"
    ;;
  *)
    echo "Usage: $0 {get|set} MAC [MODE]"
    exit 1
    ;;
esac
