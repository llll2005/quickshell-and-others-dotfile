#!/bin/sh
# lock.sh — lock the session. Every lock comes through here: SUPER+L, hypridle (idle and
# before sleep), the Control Center's Lock, the launcher's LOCK.
#
# The shell's lockscreen (lock.qml) runs as its own qs process; hyprlock takes over when
#   · it doesn't report the lock as secure within 4 s (didn't start, the compositor
#     refused, a QML error…), or
#   · it exits without the right password (crashed while locked) — Hyprland keeps the
#     session locked, and misc:allow_session_lock_restore lets hyprlock take it over.
# hyprlock's look comes from theme-sync (~/.config/hypr/hyprlock.conf).
dir=$(readlink -f "$(dirname "$(readlink -f "$0")")/..")
run=${XDG_RUNTIME_DIR:-/tmp}/qs-lock

exec 9>"$run.lock"
flock -n 9 || exit 0                    # a lock is already up (the fd stays with it)
pidof hyprlock >/dev/null && exit 0

fallback() {
    logger -t qs-lock "$1 — hyprlock"
    exec hyprlock
}

rm -f "$run.ready" "$run.unlocked"
qs -p "$dir/lock.qml" >"$run.log" 2>&1 &
pid=$!

i=0
while [ ! -e "$run.ready" ]; do
    kill -0 "$pid" 2>/dev/null || fallback "lockscreen exited before locking"
    [ $i -ge 40 ] && { kill "$pid" 2>/dev/null; fallback "lockscreen not secure after 4 s"; }
    sleep 0.1
    i=$((i + 1))
done

wait "$pid"
[ -e "$run.unlocked" ] && exit 0
fallback "lockscreen exited while locked"
