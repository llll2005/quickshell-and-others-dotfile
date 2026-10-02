#!/bin/sh
# Can this system hibernate right now? One JSON line, for the Control Center's Hibernate:
#   swap   free disk swap, GiB — zram doesn't count, it lives in the RAM being saved
#   image  the image the kernel will write, GiB: everything in use (page cache too) down to
#          /sys/power/image_size, but never less than what can't be dropped
#   need   the swap that image takes once compressed, with a margin (LZO packed ~2.2x here)
# A hibernation whose image doesn't fit fails at "Image saving failed: -28", and coming
# back from that failure has left the NVIDIA display dead (2026-10-02), so it is refused
# up front instead.
awk -v isz="$(cat /sys/power/image_size 2>/dev/null || echo 0)" '
FILENAME == "/proc/meminfo" { m[$1] = $2 * 1024 }
FILENAME == "/proc/swaps" && FNR > 1 && $1 !~ /zram/ { swap += ($3 - $4) * 1024 }
END {
    used = m["MemTotal:"] - m["MemFree:"]
    hard = m["MemTotal:"] - m["MemAvailable:"]
    img = used < isz ? used : isz
    if (img < hard) img = hard
    need = img * 0.6
    G = 1073741824
    printf "{\"ok\":%s,\"swap\":%.1f,\"image\":%.1f,\"need\":%.1f}\n", (swap >= need && swap > 0 ? "true" : "false"), swap / G, img / G, need / G
}' /proc/meminfo /proc/swaps
