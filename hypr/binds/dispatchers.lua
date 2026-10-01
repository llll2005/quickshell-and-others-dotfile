-- Dispatchers: App launches, system commands, media keys
local G = require("globals")
local M = G.mainMod

-- ── Application Launchers ────────────────────────────────────
-- Terminal opens on key release to avoid ghost triggers from other SUPER combos
hl.bind(M .. " + W", hl.dsp.exec_cmd(G.terminal),    { on_release = true })
hl.bind(M .. " + E", hl.dsp.exec_cmd(G.browser))
hl.bind(M .. " + F", hl.dsp.exec_cmd(G.fileManager))
hl.bind(M .. " + R", hl.dsp.exec_cmd("qs ipc call menu toggle"))
hl.bind(M .. " + S", hl.dsp.exec_cmd("spotify-launcher"))
hl.bind(M .. " + B", hl.dsp.exec_cmd("bilibili"))

-- ── Window Migration ────────────────────────────────────────
-- Move focused window to DP-2's current active workspace
hl.bind(M .. " + SHIFT + C", hl.dsp.exec_cmd("lua5.4 ~/.config/hypr/scripts/move_to_secondary.lua"))
-- Prompt for a number, then move ALL windows in current workspace there
hl.bind(M .. " + SHIFT + X", hl.dsp.exec_cmd("lua5.4 ~/.config/hypr/scripts/move_ws_all.lua"))
-- hl.bind(M .. " + SHIFT + X", hl.dsp.exec_cmd("bash ~/.config/hypr/scripts/move_ws_all.sh"))
-- ── Quickshell ───────────────────────────────────────────────
-- ControlCenter (NieR radial menu)
-- Clipboard history (cliphist; SUPER+V is float toggle)
hl.bind(M .. " + SHIFT + V", hl.dsp.exec_cmd("qs ipc call clip toggle"))
hl.bind(M .. " + M",       hl.dsp.exec_cmd("qs ipc call ctrl toggle"))
hl.bind(M .. " + ALT + C", hl.dsp.exec_cmd("qs ipc call ctrl toggle"))
-- Status UI:
--   SUPER+`        → CornerHud workspace selector (or TopBar toggle in bar mode)
--   SUPER+SHIFT+`  → CornerHud stat cluster (CPU/GPU/VOL/BAT)
hl.bind(M .. " + grave",         hl.dsp.exec_cmd("qs ipc call hud toggle"))
hl.bind(M .. " + SHIFT + grave", hl.dsp.exec_cmd("qs ipc call hud stats"))
hl.bind(M .. " + CTRL + grave",  hl.dsp.exec_cmd("qs ipc call hud visible"))  -- show/hide whole HUD
-- Media Player widget (native qs IPC — replaces /tmp/qs-toggle file poll)
hl.bind(M .. " + P", hl.dsp.exec_cmd("qs ipc call player toggle"))
-- Launch quickshell (首次啟動 / 若未在執行)
hl.bind(M .. " + SHIFT + Q", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/shell.qml"))
-- Restart shell.qml (kill 後重啟，即使未在執行也能成功)
hl.bind(M .. " + ALT + K", hl.dsp.exec_cmd("sh -c 'pkill -x qs; sleep 0.3 && qs -p ~/.config/quickshell/shell.qml'"))

-- ── System ──────────────────────────────────────────────────
hl.bind(M .. " + L",   hl.dsp.exec_cmd("hyprlock"))
-- hl.bind(M .. " + SPACE", hl.dsp.exec_cmd("ags request overview:toggle"))  -- AGS removed
hl.bind("F4",          hl.dsp.exec_cmd("quickshell -p ~/.config/quickshell/nierlock/shell.qml"))
hl.bind("XF86PowerOff",hl.dsp.exec_cmd("wlogout -b 2"), { locked = true })
hl.bind("Print",       hl.dsp.exec_cmd("qs ipc call capture toggle"))
hl.bind(M.. "+ Print",       hl.dsp.exec_cmd("qs ipc call capture stop"))
-- ── Audio Sinks ─────────────────────────────────────────────
hl.bind(M .. " + F1", hl.dsp.exec_cmd("wpctl set-default " .. G.sink_main))
hl.bind(M .. " + F2", hl.dsp.exec_cmd("wpctl set-default " .. G.sink_sec))

-- ── Volume ──────────────────────────────────────────────────
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.5%+"),
    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.5%-"),
    { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    { locked = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
    { locked = true })

-- ── Media Playback ───────────────────────────────────────────
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"),       { locked = true })

-- ── Brightness ──────────────────────────────────────────────
-- also flashes the CornerHud BRI osd (volume osd is automatic via Pipewire)
-- Caps Lock → the HUD's CAPS osd (non-consuming: the key still toggles Caps Lock)
hl.bind("Caps_Lock", hl.dsp.exec_cmd("qs ipc call hud osd caps"), { non_consuming = true, on_release = true, locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("sh -c 'brightnessctl s 5%+; qs ipc call hud osd bri'"),
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("sh -c 'brightnessctl s 5%-; qs ipc call hud osd bri'"),
    { locked = true, repeating = true })
