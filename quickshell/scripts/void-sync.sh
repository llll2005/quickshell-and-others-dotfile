#!/bin/sh
# void-sync.sh — carry the Void's colours and type (shell.conf [void] bg / light / warn,
# [font] voidWeight / voidBase / voidRatio) to what the shell can't redraw on its own: the
# login screen and the boot chain. The settings panel runs it when it closes after one of
# them changed.
#   void-sync.sh ask   asks in the Void (YES / NO, widgets/AuthPrompt.qml's socket); YES runs
#   void-sync.sh run   pkexec → the polkit prompt (the Void's password) → as root:
#                      dotfiles/system/sddm-void.sh, then boot-void.sh --update
# The log is ~/.local/state/quickshell/void-sync.log; a notification says how it went.
dir=$(readlink -f "$(dirname "$(readlink -f "$0")")/..")
sys=$(readlink -f "$dir/../dotfiles/system")
log=${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/void-sync.log
sock=${XDG_RUNTIME_DIR:-/tmp}/qs-void-ask.sock

note() { notify-send -a "Quickshell" -i preferences-desktop-theme "$1" "$2" 2>/dev/null; }

case "$1" in
ask)
    # one JSON line to the shell's prompt, its answer back: {"ok": true} is YES
    ans=$(python3 - "$sock" <<'PY'
import json, socket, sys
q = {"kind": "confirm", "title": "SYNC THE VOID",
     "message": "虛空的顏色或字改了。要同步到登入畫面與開機畫面嗎？",
     "detail": "sddm-void.sh · boot-void.sh --update",
     "hint": "YES 之後會要系統密碼；重建開機映像約需一兩分鐘"}
try:
    s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
    s.sendall((json.dumps(q, ensure_ascii=False) + "\n").encode())
    line = s.makefile("r", encoding="utf-8").readline()
    print("yes" if json.loads(line or "{}").get("ok") else "no")
except OSError:
    print("unavailable")
PY
)
    case "$ans" in
        yes) exec "$0" run ;;
        unavailable) note "虛空同步" "沒辦法詢問（shell 的提示沒在跑）。之後可以手動跑：$0 run" ;;
    esac
    ;;
run)
    mkdir -p "$(dirname "$log")"
    note "虛空同步中…" "登入畫面與開機畫面（重建開機映像約需一兩分鐘）"
    # pkexec asks through polkit (the shell's AuthPrompt); the scripts read your shell.conf
    # through SUDO_USER, as they do under sudo
    if pkexec /usr/bin/env SUDO_USER="$(id -un)" /bin/sh -c \
        'sh "$1/sddm-void.sh" && sh "$1/boot-void.sh" --update' sh "$sys" >"$log" 2>&1; then
        note "虛空已同步" "登入畫面與開機畫面都換好了"
    else
        code=$?
        [ $code = 126 ] || [ $code = 127 ] && why="取消了授權" || why="失敗（$code）：$(tail -n 1 "$log")"
        note "虛空沒有同步" "$why · 紀錄在 $log"
        exit $code
    fi
    ;;
*)
    echo "usage: $0 ask|run" >&2; exit 2 ;;
esac
