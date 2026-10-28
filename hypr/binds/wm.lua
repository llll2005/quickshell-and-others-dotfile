-- Window Management: focus, float, workspaces, mouse
local G    = require("globals")
local anim = require("ui.animations")
local T    = require("core.tasks")
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

-- ── Task groups (core/tasks.lua) ─────────────────────────────
-- SUPER+1-0      → task group 1-10, opened at its centre cell (13) on every screen
-- SUPER+SHIFT+1-0 → the focused window to cell 1-10 of this group (you stay)
-- SUPER+G        → the groups menu (Quickshell): ↑↓ pick · → delete · ← rename · + new
for i = 1, 10 do
    local key = tostring(i % 10)
    hl.bind(M .. " + " .. key,             function() T.go(i) end)
    hl.bind(M .. " + SHIFT + " .. key,     function() T.move_to_cell(i) end)
end
hl.bind(M .. " + G", hl.dsp.exec_cmd("qs ipc call tasks menu"))

-- ── Vertical workspace slides ────────────────────────────────
-- Runs a ±5 step with a one-off workspace slide style, so it slides vertically while
-- everything else keeps "slide". The new workspace enters from the arrow's side (same
-- logic as left/right: Right → enters from right). hl.dispatch is synchronous, so the
-- animation has already captured its direction when the style is restored. The step is
-- the group's (core/tasks.lua): nothing happens at its edge, so no step leaves the group.
local function step_with_style(style, d, move, follow)
    return function()
        if not T.step_target(d) then return end
        anim.set_workspace_style(style)
        if move then T.move_step(d, follow) else T.step(d) end
        anim.set_workspace_style("slide")
    end
end

-- ── WIN+SHIFT+Arrow: move window to the adjacent / ±5 cell of this group ────
-- You go with the window, all four ways (0.56's window.move reads `follow`; SUPER+SHIFT+N,
-- which throws a window to a cell, leaves you where you are).
hl.bind(M .. " + SHIFT + left",  function() T.move_step(-1, true) end)
hl.bind(M .. " + SHIFT + right", function() T.move_step(1, true) end)
hl.bind(M .. " + SHIFT + up",    step_with_style("slide top",    5, true, true))
hl.bind(M .. " + SHIFT + down",  step_with_style("slide bottom", -5, true, true))

-- ── CTRL+WIN: walk the group's 5×5 ───────────────────────────
hl.bind(M .. " + CTRL + left",  function() T.step(-1) end, { repeating = true })
hl.bind(M .. " + CTRL + right", function() T.step(1) end, { repeating = true })
hl.bind(M .. " + CTRL + up",   step_with_style("slide top",    5), { repeating = true })
hl.bind(M .. " + CTRL + down", step_with_style("slide bottom", -5), { repeating = true })
-- Cycle monitor focus
hl.bind(M .. " + CTRL + C", hl.dsp.focus({ monitor = "+1" }))

-- Scroll wheel: the group's cells that have windows
hl.bind(M .. " + mouse_down", function() T.cycle(-1) end)
hl.bind(M .. " + mouse_up",   function() T.cycle(1) end)

-- ── Mouse Window Interaction ─────────────────────────────────
hl.bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
