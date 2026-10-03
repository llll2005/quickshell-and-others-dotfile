#!/bin/sh
# sddm-void.sh — the login screen in the Void (dotfiles/system/sddm-void: the same
# composition as the Quickshell lock and power exit).
#   sudo sh sddm-void.sh          install as /usr/share/sddm/themes/void and select it
#   sudo sh sddm-void.sh --undo   back to the theme that was selected before
# The fonts (Josefin Sans, Operator Mono) and the Void's colours come from your own
# ~/.local/share/fonts and quickshell/config/shell.conf [void]; run it again after
# changing either. Try it without logging out:
#   sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/void
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
DEST=/usr/share/sddm/themes/void
HOME_DIR=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)

current() { sed -n 's/^[[:space:]]*Current[[:space:]]*=[[:space:]]*//p' /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null | tail -1; }
select_theme() {   # both places that name the theme; /etc/sddm.conf wins over conf.d
    for f in /etc/sddm.conf /etc/sddm.conf.d/theme.conf; do
        [ -e "$f" ] && grep -q '^[[:space:]]*Current[[:space:]]*=' "$f" && sed -i "s/^\([[:space:]]*Current[[:space:]]*=\).*/\1$1/" "$f"
    done
    grep -qs '^[[:space:]]*Current[[:space:]]*=' /etc/sddm.conf.d/theme.conf || printf '[Theme]\nCurrent=%s\n' "$1" > /etc/sddm.conf.d/theme.conf
}

if [ "$1" = "--undo" ]; then
    prev=$(cat "$DEST/.previous" 2>/dev/null || echo breeze)
    select_theme "$prev"
    echo "SDDM theme: $prev"
    exit 0
fi

prev=$(current)
rm -rf "$DEST"
mkdir -p "$DEST/fonts"
cp "$HERE/sddm-void/Main.qml" "$HERE/sddm-void/metadata.desktop" "$HERE/sddm-void/theme.conf" "$DEST/"
[ -n "$prev" ] && [ "$prev" != void ] && echo "$prev" > "$DEST/.previous"

# the shell's faces (not in the repo: Operator Mono is commercial); the sddm user can't
# read your font folder, so they go next to the theme
f=$(ls "$HOME_DIR"/.local/share/fonts/josefin-sans/*.ttf 2>/dev/null | head -1)
[ -n "$f" ] && cp "$f" "$DEST/fonts/void.ttf"
f="$HOME_DIR/.local/share/fonts/operator-mono/OperatorMono-Book.otf"
[ -e "$f" ] && cp "$f" "$DEST/fonts/mono-Book.otf"

# the Void's ink from shell.conf [void]
conf="$HOME_DIR/.config/quickshell/config/shell.conf"
pick() { awk -v k="$1" '/^\[/{s=$0} s=="[void]" || s ~ /^\[void\][[:space:]]/ { if ($1==k) { sub(/^[^=]*=[[:space:]]*/,""); sub(/[[:space:]].*/,""); print; exit } }' "$conf" 2>/dev/null; }
light=$(pick light); warn=$(pick warn)
[ -n "$light" ] && sed -i "s/^light=.*/light=$light/" "$DEST/theme.conf"
[ -n "$warn" ] && sed -i "s/^warn=.*/warn=$warn/" "$DEST/theme.conf"

chmod -R a+rX "$DEST"
select_theme void
echo "SDDM theme: void (was ${prev:-unset}; --undo goes back)."
echo "Try it without logging out: sddm-greeter-qt6 --test-mode --theme $DEST"
