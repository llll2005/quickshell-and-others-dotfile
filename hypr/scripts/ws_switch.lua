#!/usr/bin/env lua5.4
-- Monitor-aware workspace switch
-- arg[1] = key index (1-9 from SUPER+1~9, 10 from SUPER+0)
-- On the MSI (HDMI or DP): 1→11, 2→12, ..., 10→20
-- On the laptop panel (eDP-*): 1→1, ..., 10→10

local key = tonumber(arg[1]) or 1

local function get_active_monitor()
    local f = io.popen("hyprctl monitors -j 2>/dev/null")
    if not f then return "" end
    local json = f:read("*a")
    f:close()
    local pos = json:find('"focused"%s*:%s*true')
    if not pos then return "" end
    -- "name" always appears before "focused" in each monitor block
    return json:sub(1, pos):match('.*"name"%s*:%s*"([^"]+)"') or ""
end

local monitor = get_active_monitor()
-- the MSI on any connector (HDMI-A-1, DP-2…): anything but the laptop panel (eDP-*)
local target = (monitor ~= "" and not monitor:match("^eDP")) and (10 + key) or key

os.execute("hyprctl dispatch 'hl.dsp.focus({ workspace = " .. target .. " })'")
