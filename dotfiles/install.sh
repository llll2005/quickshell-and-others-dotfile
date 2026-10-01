#!/usr/bin/env bash
# Install these dotfiles from a clone (e.g. ~/nier-dots):
#   dotfiles/install.sh           check dependencies, link quickshell/ into ~/.config, build the plugin
#   dotfiles/install.sh --hypr    …and link hypr/ as well
# Whatever is already at ~/.config/quickshell (or hypr) is moved to *.bak-<date>, never deleted.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WITH_HYPR=0
for a in "$@"; do
    case "$a" in
        --hypr) WITH_HYPR=1 ;;
        -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

# ── dependencies ──
say "Checking dependencies"
need=(hyprctl qs python3 grim wl-copy magick)
want=(cliphist fd qalc wf-recorder tesseract hyprpicker swappy cava brightnessctl fcitx5 gcalcli kitty yazi zenity)
missing=0
for c in "${need[@]}"; do command -v "$c" >/dev/null || { warn "  required, missing: $c"; missing=1; }; done
for c in "${want[@]}"; do command -v "$c" >/dev/null || echo "  optional, missing: $c"; done
python3 -c 'import gi' 2>/dev/null || warn "  python-gobject is missing (the IME candidate window needs it)"
[ "$missing" = 1 ] && warn "Install the required ones first; continuing anyway."

# ── link the configs ──
link() {   # link <name>: ~/.config/<name> → <repo>/<name>
    local src="$REPO/$1" dst="$CFG/$1"
    if [ "$(readlink -f "$dst" 2>/dev/null)" = "$src" ]; then echo "  $dst already points here"; return; fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then mv "$dst" "$dst.bak-$STAMP"; echo "  moved the old $dst to $dst.bak-$STAMP"; fi
    ln -s "$src" "$dst"; echo "  $dst → $src"
}
say "Linking"
mkdir -p "$CFG"
link quickshell
[ "$WITH_HYPR" = 1 ] && link hypr

# the nierlock submodule (lockscreen)
if [ -d "$REPO/.git" ] && [ ! -e "$REPO/quickshell/nierlock/shell.qml" ]; then
    git -C "$REPO" submodule update --init --recursive || warn "  couldn't fetch the nierlock submodule"
fi

# ── the Hyprland plugin ──
say "Building the Hyprland plugin (imecaret)"
if pkg-config --exists hyprland 2>/dev/null; then
    make -C "$REPO/quickshell/hypr-plugin/imecaret" && echo "  built — load it from your Hyprland autostart (see hypr/core/autostart.lua)"
else
    warn "  Hyprland's headers aren't installed (pkg-config hyprland): no plugin, so no window effects / caret placement"
fi

say "Done"
cat <<EOF
Next:
  • start the shell:  qs     (or log in again if your autostart runs it)
  • options:          $CFG/quickshell/config/shell.conf
  • a theme:          qs ipc call theme set aha
EOF
[ "$WITH_HYPR" = 0 ] && echo "  • your own Hyprland config: see \"Using your own Hyprland config\" in the README"
exit 0
