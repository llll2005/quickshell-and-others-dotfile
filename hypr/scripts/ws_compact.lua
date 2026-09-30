#!/usr/bin/env lua5.4
-- Left-pack workspaces in the active range (1-10 or 11-20).
-- Uses the same dispatch pattern as ws_switch.lua / ws_move.lua.

local function sh(cmd)
    local f = io.popen(cmd)
    if not f then return "" end
    local s = f:read("*a")
    f:close()
    return s
end

local function dispatch(expr)
    os.execute("hyprctl dispatch '" .. expr .. "'")
end

local cur = tonumber(sh("hyprctl activeworkspace -j | jq '.id'")) or 1

local rs, re
if     cur >= 1  and cur <= 10 then rs, re = 1,  10
elseif cur >= 11 and cur <= 20 then rs, re = 11, 20
else os.exit(0)
end

-- Workspace IDs in range, sorted ascending
local ids = {}
for id_s in sh(string.format(
    "hyprctl workspaces -j | jq -r '[.[] | select(.id >= %d and .id <= %d) | .id] | .[]'",
    rs, re)):gmatch("%d+") do
    ids[#ids + 1] = tonumber(id_s)
end
table.sort(ids)

-- Build move list; tgt <= src always (left-pack), so ascending order avoids collisions
local moves, new_cur = {}, cur
for i, src in ipairs(ids) do
    local tgt = rs + i - 1
    if src == cur then new_cur = tgt end
    if src ~= tgt then moves[#moves + 1] = { src = src, tgt = tgt } end
end

if #moves == 0 then os.exit(0) end

for _, mv in ipairs(moves) do
    -- Count windows on source workspace (re-query each iteration, state may have changed)
    local n = tonumber(sh(string.format(
        "hyprctl clients -j | jq '[.[] | select(.workspace.id == %d)] | length'", mv.src
    ))) or 0
    if n > 0 then
        -- Switch to source workspace, then move active window N times.
        -- silent = true keeps focus on source while each window is relocated.
        dispatch(string.format("hl.dsp.focus({ workspace = %d })", mv.src))
        for _ = 1, n do
            dispatch(string.format(
                "hl.dsp.window.move({ workspace = %d, silent = true })", mv.tgt
            ))
        end
    end
end

dispatch(string.format("hl.dsp.focus({ workspace = %d })", new_cur))
