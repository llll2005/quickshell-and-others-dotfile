#!/bin/sh
# qs-restart.sh [WHY] — restart the shell as a new process, from inside it. A reload keeps
# Quickshell's singletons, and its NetworkManager connection never comes back after
# NetworkManager restarts (an upgrade, dotfiles/system/wifi-iwd.sh): services/Health.qml
# runs this when NetworkManager's bus name changes owner. Started detached by the shell,
# so the new one gets its environment (Hyprland's: QT_SCALE_FACTOR and the rest). Only the
# default config is killed — the lock (lock.qml, its own qs) is left alone.
why=$1
qs kill >/dev/null 2>&1
sleep 0.6
qs -n -d >/dev/null 2>&1
if [ -n "$why" ]; then
    sleep 4    # the notification daemon is the shell: wait for the new one
    notify-send -a Quickshell -u low "SHELL RESTARTED" "$why" 2>/dev/null
fi
