#!/bin/sh
# firefox-live.sh — let Firefox follow the shell's theme while it runs (no restart):
# Firefox's autoconfig loads quickshell/firefox/live.js at startup, which registers the
# profile's userChrome / userContent itself and swaps them whenever theme-sync rewrites them.
#
#   sudo sh firefox-live.sh          install (two small files in /usr/lib/firefox)
#   sudo sh firefox-live.sh --undo   remove them: back to toolkit's loader (restart to apply)
#
# The files survive Firefox updates (pacman doesn't own them). The .cfg only loads
# ~/.config/quickshell/firefox/live.js, so changing that needs no sudo. Afterwards restart
# Firefox once; theme-sync turns toolkit's own userChrome loader off so nothing loads twice.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../../quickshell/firefox"
FF=/usr/lib/firefox
[ -d "$FF" ] || { echo "$FF not found"; exit 1; }

if [ "$1" = "--undo" ]; then
    rm -f "$FF/defaults/pref/qs-autoconfig.js" "$FF/qs-firefox.cfg"
    echo "◆ removed; Firefox uses toolkit's userChrome loader again from its next start"
else
    install -Dm 644 "$SRC/qs-autoconfig.js" "$FF/defaults/pref/qs-autoconfig.js"
    install -m 644 "$SRC/qs-firefox.cfg" "$FF/qs-firefox.cfg"
    echo "◆ installed: restart Firefox once, then theme changes reach it within a second"
fi
# rewrite the profiles' user.js for the new loader
U=${SUDO_USER:-$USER}
su "$U" -c "python3 ~/.config/quickshell/scripts/theme-sync.py" >/dev/null 2>&1 || true
