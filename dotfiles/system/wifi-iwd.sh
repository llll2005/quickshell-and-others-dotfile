#!/bin/sh
# wifi-iwd.sh — one Wi-Fi daemon: NetworkManager on iwd.
#
# What was wrong (2026-10-03): NetworkManager.conf had `wifi.backend=iwd` under [main],
# where NetworkManager ignores it ("unknown key ... in section [main]"), so NM kept using
# wpa_supplicant — while iwd, enabled on its own, kept retrying the phone hotspot every
# ~100 s with a stale WPA2 ("psk") profile for a WPA3 (SAE) network. Two daemons on one
# card: iwd's attempts broke NM's handshakes, NM took that for wrong secrets and asked for
# the password again (the CC said "wrong password", nmtui looped); a few minutes or a
# reboot sometimes let one of them win.
#
#   sudo sh wifi-iwd.sh            NetworkManager on iwd (iwd handles WPA3/SAE natively)
#   sudo sh wifi-iwd.sh --restore  put back the iwd profiles a re-run moved aside, iwd autoconnect on
#   sudo sh wifi-iwd.sh --undo     NetworkManager on wpa_supplicant, iwd off
#
# Either way only one daemon runs. Wi-Fi drops for a few seconds while NM restarts.
# iwd keeps the secrets and does the autoconnecting: it rejoins every network it has joined
# once. Don't hand autoconnect to NetworkManager (wifi.iwd.autoconnect=false): NM's own
# profiles from before iwd hold no secrets, and with no secret agent running they all
# failed with "no-secrets" (2026-10-22).
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
CONF=/etc/NetworkManager/NetworkManager.conf
DROP=/etc/NetworkManager/conf.d/wifi-backend.conf

# the misplaced key, wherever it is
sed -i '/^[[:space:]]*wifi\.backend[[:space:]]*=/d' "$CONF"

# --restore: the profiles iwd had learned, back from their newest .bak-<date> copies
if [ "$1" = "--restore" ]; then
    # only the newest batch (the 10-03 one held the stale hotspot profile)
    last=$(ls -1 /var/lib/iwd/ 2>/dev/null | sed -n 's/.*\.bak-\([0-9]*\)$/\1/p' | sort | tail -1)
    for b in /var/lib/iwd/*.bak-"$last"; do
        [ -e "$b" ] || continue
        f=${b%.bak-*}
        [ -e "$f" ] || { mv "$b" "$f"; echo "restored $(basename "$f")"; }
    done
    printf '# NetworkManager drives iwd (dotfiles/system/wifi-iwd.sh). The key belongs in [device].\n[device]\nwifi.backend=iwd\n' > "$DROP"
    systemctl restart iwd
    systemctl restart NetworkManager
    sleep 4
    nmcli -t -f DEVICE,STATE,CONNECTION dev | grep wlan || true
    exit 0
fi

if [ "$1" = "--undo" ]; then
    rm -f "$DROP"
    systemctl disable --now iwd
    systemctl restart NetworkManager
    echo "NetworkManager on wpa_supplicant; iwd disabled."
    exit 0
fi

# already on iwd? then iwd's profiles are the good ones: leave them
first=1
grep -qs '^wifi.backend=iwd' "$DROP" && first=0
printf '# NetworkManager drives iwd (dotfiles/system/wifi-iwd.sh). The key belongs in [device].\n[device]\nwifi.backend=iwd\n' > "$DROP"
systemctl enable iwd
systemctl stop wpa_supplicant 2>/dev/null || true
# switching from wpa_supplicant: iwd's old profiles go (its stale "psk" one for the WPA3
# hotspot was failing every retry). Only then — a re-run moved the working ones aside
# (2026-10-22), and NetworkManager had no secrets of its own to give iwd instead.
if [ "$first" = 1 ]; then
    for f in /var/lib/iwd/*.psk /var/lib/iwd/*.open /var/lib/iwd/*.8021x; do
        [ -e "$f" ] && mv "$f" "$f.bak-$(date +%Y%m%d)"
    done
fi
systemctl restart iwd
systemctl restart NetworkManager
sleep 3
nmcli -t -f DEVICE,STATE,CONNECTION dev | grep wlan || true
echo "NetworkManager on iwd. If a network asks for its password once, that's iwd learning it."
