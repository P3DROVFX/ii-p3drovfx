#!/bin/sh
# Installs ii-fand system-wide. Run as root (the Settings page runs it through pkexec).
#   install.sh            install / update
#   install.sh --remove   uninstall and hand the fans back to the firmware
set -e
HERE=$(dirname "$(readlink -f "$0")")

if [ "$1" = "--remove" ]; then
    systemctl disable --now ii-fand.service 2>/dev/null || true
    rm -f /usr/local/bin/ii-fand /etc/systemd/system/ii-fand.service \
          /usr/share/polkit-1/actions/org.ii.fand.policy
    systemctl daemon-reload
    echo "ii-fand removed (config kept in /etc/ii-fand)"
    exit 0
fi

install -Dm755 "$HERE/ii-fand" /usr/local/bin/ii-fand
install -Dm644 "$HERE/ii-fand.service" /etc/systemd/system/ii-fand.service
install -Dm644 "$HERE/org.ii.fand.policy" /usr/share/polkit-1/actions/org.ii.fand.policy

# First install: carry over the curve from the old g15-fancurve script, then retire it.
if [ ! -f /etc/ii-fand/config.json ] && [ -f /usr/local/bin/g15-fancurve ]; then
    val() { sed -n "s/^$1 *= *\([0-9.]*\).*/\1/p" /usr/local/bin/g15-fancurve | head -1; }
    mkdir -p /etc/ii-fand
    /usr/local/bin/ii-fand set "{\"curve\":{\"minPct\":$(val MIN_PCT),\"tStart\":$(val T_START),\"tMax\":$(val T_MAX),\"steepness\":$(val STEEPNESS)},\"hysteresis\":$(val HYSTERESIS),\"interval\":$(val INTERVAL)}" >/dev/null
fi
if systemctl list-unit-files g15-fancurve.service >/dev/null 2>&1; then
    systemctl disable --now g15-fancurve.service 2>/dev/null || true
fi

systemctl daemon-reload
systemctl enable ii-fand.service
systemctl restart ii-fand.service
echo "ii-fand installed"
