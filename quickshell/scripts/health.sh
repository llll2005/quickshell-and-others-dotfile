#!/bin/sh
# The shell's helpers, checked (and with `fix`, started) — one JSON line out:
#   health.sh check | fix | rebuild
#   plugin   the imecaret Hyprland plugin is loaded (window effects, caret, click bursts)
#   built    imecaret.so exists       clip    both cliphist watchers run
#   fcitx    fcitx5 runs              bridge  the kimpanel bridge (scripts/imepanel.py) runs
# `fix` loads the plugin and starts the cliphist watchers when they're missing;
# `rebuild` rebuilds the plugin for this Hyprland and swaps it in (after an update the
# old build refuses to load). Run by services/Health.qml at start and every 30 s.
HERE="$(dirname "$(readlink -f "$0")")"
PLUGIN_DIR="$HERE/../hypr-plugin/imecaret"
PLUGIN="$PLUGIN_DIR/imecaret.so"

plugin_loaded() { hyprctl winfx 2>/dev/null | grep -q '"hold"'; }
clip_text()  { pgrep -f 'wl-paste --type text +--watch cliphist' >/dev/null; }
clip_image() { pgrep -f 'wl-paste --type image +--watch cliphist' >/dev/null; }

case "$1" in
    fix)
        if ! plugin_loaded && [ -f "$PLUGIN" ]; then hyprctl plugin load "$(readlink -f "$PLUGIN")" >/dev/null 2>&1; fi
        clip_text  || setsid -f wl-paste --type text  --watch cliphist store >/dev/null 2>&1
        clip_image || setsid -f wl-paste --type image --watch cliphist store >/dev/null 2>&1
        sleep 0.3 ;;
    rebuild)
        make -C "$PLUGIN_DIR" reload >/dev/null 2>&1 ;;
esac

b() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }
printf '{"plugin":%s,"built":%s,"clip":%s,"fcitx":%s,"bridge":%s}\n' \
    "$(b plugin_loaded)" "$(b test -f "$PLUGIN")" "$(b sh -c 'pgrep -f "wl-paste --type text +--watch cliphist" >/dev/null && pgrep -f "wl-paste --type image +--watch cliphist" >/dev/null')" \
    "$(b pgrep -x fcitx5)" "$(b pgrep -f 'scripts/imepanel.py')"
