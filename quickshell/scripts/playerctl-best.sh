#!/bin/sh
# Output: title|artist|artUrl|status|position|length
# Picks "Playing" player first, falls back to "Paused", then any.
# Input format from playerctl: status|title|artist|artUrl|position|length
playerctl -a metadata \
    --format "{{status}}|{{title}}|{{artist}}|{{mpris:artUrl}}|{{position}}|{{mpris:length}}" \
    2>/dev/null | awk -F'|' '
BEGIN { best = ""; bstat = ""; found = 0 }
$1 == "Playing" {
    # Reorder: title|artist|artUrl|status|position|length
    print $2"|"$3"|"$4"|"$1"|"$5"|"$6
    found = 1; exit
}
$1 == "Paused" && best == "" {
    best = $2"|"$3"|"$4"|"$1"|"$5"|"$6
}
END { if (!found && best != "") print best }
'
