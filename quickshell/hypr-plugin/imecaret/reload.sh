#!/usr/bin/env bash
# Rebuild imecaret and swap it into the running Hyprland without a restart.
# Never rebuild a loaded .so in place: build a new file, unload the old copy (by the
# path it was loaded from — Hyprland tracks plugins by path, recorded in .loaded),
# load the new one, then move it over imecaret.so for the next start.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
NEW="$PWD/imecaret-$(date +%s).so"
g++ -shared -fPIC --no-gnu-unique -O2 -std=c++2b main.cpp -o "$NEW" \
    $(pkg-config --cflags pixman-1 libdrm hyprland pangocairo libinput libudev wayland-server xkbcommon)
for p in $(cat .loaded 2>/dev/null) "$PWD/imecaret.so"; do hyprctl plugin unload "$p" >/dev/null 2>&1 || true; done
hyprctl plugin load "$NEW"
echo "$NEW" > .loaded
cp "$NEW" imecaret.so
find . -maxdepth 1 -name 'imecaret-*.so' ! -path "./$(basename "$NEW")" -delete
hyprctl plugin list | grep -A1 imecaret
