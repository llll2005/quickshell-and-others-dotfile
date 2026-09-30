#!/bin/bash
# Move all windows from workspace $1 to workspace $2 using hl.dsp socat API.
cur_ws=$1
target=$2
[[ -z "$cur_ws" || -z "$target" || "$cur_ws" == "$target" ]] && exit 0

# Collect addresses of all windows on cur_ws
addresses=$(hyprctl clients -j | jq -r ".[] | select(.workspace.id == $cur_ws) | .address")
[[ -z "$addresses" ]] && exit 0

# Build [[BATCH]] payload using hl.dsp Lua API syntax
payload="[[BATCH]]"
while IFS= read -r addr; do
    [[ -z "$addr" ]] && continue
    payload="${payload}dispatch hl.dsp.window.move({ workspace = $target, window = \"address:$addr\", silent = true });"
done <<< "$addresses"
payload="${payload}dispatch hl.dsp.focus({ workspace = $target });"

# Resolve socket path (env vars may be absent when spawned from QML)
xdg="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
sig="${HYPRLAND_INSTANCE_SIGNATURE}"
[[ -z "$sig" ]] && sig=$(ls -1t "$xdg/hypr" 2>/dev/null | head -n 1)
[[ -z "$sig" ]] && exit 1

printf '%s' "$payload" | socat - "UNIX-CONNECT:$xdg/hypr/$sig/.socket.sock"
