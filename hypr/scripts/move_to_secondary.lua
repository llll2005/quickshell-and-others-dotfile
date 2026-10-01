#!/usr/bin/env lua5.4
-- WIN+SHIFT+C: 雙向 — 將 focused 視窗移到另一個螢幕的 active workspace

local function popen(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local out = f:read("*a")
    f:close()
    return out:match("^%s*(.-)%s*$")
end

-- 取得 focused 視窗所在的 monitor ID（整數）
local win_mon_id = popen("hyprctl activewindow -j 2>/dev/null | jq '.monitor'")
if win_mon_id == "" or win_mon_id == "null" then os.exit(0) end

-- 取得「另一個」螢幕的 active workspace ID
local target_ws = popen(string.format(
    "hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.id != %s) | .activeWorkspace.id' | head -1",
    win_mon_id
))

local target = tonumber(target_ws)
if not target then os.exit(0) end

os.execute("hyprctl dispatch 'hl.dsp.window.move({ workspace = " .. target .. ", silent = true })'")
