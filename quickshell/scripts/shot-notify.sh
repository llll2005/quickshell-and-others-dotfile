#!/bin/sh
# Screenshot notification with a thumbnail and action buttons.
#   shot-notify.sh saved  FILE [MESSAGE]   → 開啟 / 複製 / 資料夾
#   shot-notify.sh copied FILE [MESSAGE]   → 存檔 / 開啟   (FILE = temp copy of the clipboard image)
# notify-send --action blocks until the notification closes, so ScreenCapture
# launches this with `setsid -f` to keep its own Process free.
kind=$1 f=$2 msg=$3
[ -s "$f" ] || exit 0
shots="$HOME/Pictures/Screenshots"

case $kind in
    saved)
        act=$(notify-send -a "截圖" -i "$f" -t 6000 \
            -A open=開啟 -A copy=複製 -A folder=資料夾 \
            "截圖" "${msg:-已儲存} · $(basename "$f")") ;;
    copied)
        act=$(notify-send -a "截圖" -i "$f" -t 5000 \
            -A save=存檔 -A open=開啟 \
            "截圖" "${msg:-已複製到剪貼簿}") ;;
esac

case $act in
    open)   xdg-open "$f" ;;
    copy)   wl-copy -t image/png < "$f" ;;
    folder) xdg-open "$(dirname "$f")" ;;
    save)
        mkdir -p "$shots"
        g="$shots/cap-$(date +%Y%m%d-%H%M%S).png"
        cp "$f" "$g" && exec "$0" saved "$g" ;;
esac

# Temp clipboard copies are only needed for the thumbnail / 存檔; keep the last hour.
find /tmp/qs-shot -name 'clip-*.png' -mmin +60 -delete 2>/dev/null
exit 0
