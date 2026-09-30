-- Window Management: focus, float, workspaces, mouse
local G    = require("globals")
local anim = require("ui.animations")
local M    = G.mainMod

-- ── Window Actions ───────────────────────────────────────────
hl.bind(M .. " + Q", hl.dsp.window.close())
hl.bind(M .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(M .. " + P", hl.dsp.window.pseudo())

-- ── Focus Movement ───────────────────────────────────────────
hl.bind(M .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(M .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(M .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(M .. " + down",  hl.dsp.focus({ direction = "down" }))

-- ── Workspace Switch & Move (monitor-aware) ──────────────────
-- On DP-2 (MSI): keys 1-0 → workspaces 11-20
-- On eDP-2 (laptop): keys 1-0 → workspaces 1-10
for i = 1, 10 do
    local key = tostring(i % 10)
    local ki  = tostring(i)
    hl.bind(M .. " + " .. key,
        hl.dsp.exec_cmd("lua5.4 ~/.config/hypr/scripts/ws_switch.lua " .. ki))
    hl.bind(M .. " + SHIFT + " .. key,
        hl.dsp.exec_cmd("lua5.4 ~/.config/hypr/scripts/ws_move.lua " .. ki))
end

-- ── Compact workspaces (left-pack current range) ─────────────
hl.bind(M .. " + G", hl.dsp.exec_cmd("lua5.4 ~/.config/hypr/scripts/ws_compact.lua"))

-- ── Vertical workspace slides ────────────────────────────────
-- Runs a dispatcher with a one-off workspace slide style, so ±5 actions slide
-- vertically while everything else keeps "slide". The new workspace enters from
-- the arrow's side (same logic as left/right: Right → enters from right).
-- hl.dispatch is synchronous, so the animation has already captured its
-- direction when the style is restored.
local function with_ws_style(style, dispatcher)
    return function()
        anim.set_workspace_style(style)
        hl.dispatch(dispatcher)
        anim.set_workspace_style("slide")
    end
end

-- ── WIN+SHIFT+Arrow: move window to adjacent/±5 workspace ────
-- 0.56 window.move reads `follow`, not `silent`: these follow the window.
hl.bind(M .. " + SHIFT + left",  hl.dsp.window.move({ workspace = "-1", silent = true }))
hl.bind(M .. " + SHIFT + right", hl.dsp.window.move({ workspace = "+1", silent = true }))
hl.bind(M .. " + SHIFT + up",    with_ws_style("slide top",    hl.dsp.window.move({ workspace = "+5" })))
hl.bind(M .. " + SHIFT + down",  with_ws_style("slide bottom", hl.dsp.window.move({ workspace = "-5" })))

-- ── CTRL+WIN extended controls ───────────────────────────────
-- ±1 relative navigation (unchanged from original)
hl.bind(M .. " + CTRL + left",  hl.dsp.focus({ workspace = "-1" }), { repeating = true })
hl.bind(M .. " + CTRL + right", hl.dsp.focus({ workspace = "+1" }), { repeating = true })
-- ±5 jump (cross monitor boundary)
hl.bind(M .. " + CTRL + up",   with_ws_style("slide top",    hl.dsp.focus({ workspace = "+5" })), { repeating = true })
hl.bind(M .. " + CTRL + down", with_ws_style("slide bottom", hl.dsp.focus({ workspace = "-5" })), { repeating = true })
-- Cycle monitor focus
hl.bind(M .. " + CTRL + C", hl.dsp.focus({ monitor = "+1" }))

-- Scroll wheel through workspaces
hl.bind(M .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(M .. " + mouse_up",   hl.dsp.focus({ workspace = "e+1" }))

-- ── Mouse Window Interaction ─────────────────────────────────
hl.bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
