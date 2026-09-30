#!/bin/sh
# Usage: playerctl-ctl.sh play-pause|next|previous
cmd="$1"
player=$(playerctl -a metadata --format "{{playerName}}|{{status}}" 2>/dev/null \
    | awk -F'|' '$2=="Playing"{print $1;exit}')
[ -z "$player" ] && player=$(playerctl -l 2>/dev/null | head -1)
[ -n "$player" ] && playerctl --player="$player" "$cmd"
