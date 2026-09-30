#!/usr/bin/env lua5.4
-- Monitor-aware move active window to workspace (silent = no auto-follow)
-- arg[1] = key index (1-10)

local key = tonumber(arg[1]) or 1

local function get_active_monitor()
    local f = io.popen("hyprctl monitors -j 2>/dev/null")
    if not f then return "" end
    local json = f:read("*a")
    f:close()
    local pos = json:find('"focused"%s*:%s*true')
    if not pos then return "" end
    return json:sub(1, pos):match('.*"name"%s*:%s*"([^"]+)"') or ""
end

local monitor = get_active_monitor()
local target = (monitor == "DP-2") and (10 + key) or key

os.execute("hyprctl dispatch 'hl.dsp.window.move({ workspace = " .. target .. ", silent = true })'")
