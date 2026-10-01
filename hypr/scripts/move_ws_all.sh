#!/bin/bash

# 1. 取得當前 workspace ID
cur_ws=$(hyprctl activeworkspace -j | jq '.id')
[[ -z "$cur_ws" || "$cur_ws" == "null" ]] && exit 0

# 2. 呼叫 rofi 輸入目標並去除多餘空白
target=$(echo "" | rofi -dmenu -p '全部移至 workspace:' -theme ~/.config/rofi/theme.rasi)
target=$(echo "$target" | tr -d '[:space:]')
[[ -z "$target" || ! "$target" =~ ^[0-9]+$ || "$target" -eq "$cur_ws" ]] && exit 0

# 3. Code Injection 執行區
for addr in $(hyprctl clients -j | jq -r ".[] | select(.workspace.id == $cur_ws) | .address"); do
    # 這裡的寫法非常極端但絕對有效：
    # 我們刻意外包一層單引號，把『"movetoworkspacesilent",』整包傳給系統
    # 這樣底層拼接時就會變成合法的 Lua： return hl.dispatch("movetoworkspacesilent", "7,address:0x...")
    hyprctl dispatch '"movetoworkspacesilent",' "\"$target,address:$addr\""
done

# 4. 同理，注入引號跳轉焦點
hyprctl dispatch '"workspace",' "\"$target\""