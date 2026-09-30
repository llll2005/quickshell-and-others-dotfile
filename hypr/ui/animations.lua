-- Animations: Q彈 / 果凍感
--
-- 原則：生成、移動、切換都用 spring 回彈；退場先微微回收再離開，
-- 時長與進場對齊，不再「瞬間消失」。
--
-- Spring 物理（hyprutils advanceSpring，已對照原始碼）：
--   ω₀ = √(stiffness / mass)                  越大越快
--   ζ  = dampening / (2·√(stiffness·mass))    < 1 才會回彈，越小彈越多
--   spring 完全忽略 hl.animation 的 speed，時長只由上面兩個值決定。
-- Bezier：duration = speed × 100ms；控制點 y 可在 -1..2（可做回拉）。

local A = {}

hl.config({ animations = { enabled = true } })

-- ── Springs ──────────────────────────────────────────────────
--                          ω₀    ζ     過衝   落定(1%)
-- jelly       視窗移動     22   0.50   16%   ~0.42s
-- jelly_pop   視窗生成     24   0.54   13%   ~0.35s
-- jelly_layer 面板/Layer   24   0.60    9%   ~0.32s
-- jelly_ws    工作區切換   20   0.73    4%   ~0.32s   整頁位移，過衝要收斂
hl.curve("jelly",       { type = "spring", mass = 1, stiffness = 484, dampening = 22 })
hl.curve("jelly_pop",   { type = "spring", mass = 1, stiffness = 576, dampening = 26 })
hl.curve("jelly_layer", { type = "spring", mass = 1, stiffness = 576, dampening = 29 })
hl.curve("jelly_ws",    { type = "spring", mass = 1, stiffness = 400, dampening = 29 })

-- ── Beziers ──────────────────────────────────────────────────
-- pop  : 快速減速，用於淡入與邊框
-- tuck : 退場先往回收一點再離開（easeInBack）
-- sink : 淡出，前段保持可見、尾段加速（easeInCirc）
hl.curve("pop",  { type = "bezier", points = { {0.22, 1.0}, {0.36, 1.0} } })
hl.curve("tuck", { type = "bezier", points = { {0.36, 0.0}, {0.66, -0.56} } })
hl.curve("sink", { type = "bezier", points = { {0.55, 0.0}, {1.0, 0.45} } })

-- speed 對 spring 無效，但 hl.animation 要求 > 0
local SPRING_SPEED = 1

-- ── Windows ──────────────────────────────────────────────────
hl.animation({ leaf = "windows",     enabled = true, speed = SPRING_SPEED, spring = "jelly" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = SPRING_SPEED, spring = "jelly" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = SPRING_SPEED, spring = "jelly_pop", style = "slide bottom" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 3,            bezier = "tuck",      style = "slide bottom" })

-- ── Fade ─────────────────────────────────────────────────────
-- fadeOut 與 windowsOut 同為 300ms，退場的位移與透明度同步結束
hl.animation({ leaf = "fade",    enabled = true, speed = 2.5, bezier = "pop" })
hl.animation({ leaf = "fadeIn",  enabled = true, speed = 2.5, bezier = "pop" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 3,   bezier = "sink" })

-- ── Border ───────────────────────────────────────────────────
hl.animation({ leaf = "border", enabled = true, speed = 2.5, bezier = "pop" })

-- ── Workspaces ───────────────────────────────────────────────
-- In / Out 必須同一條 spring，否則新舊頁面位移不同步（出現縫隙或重疊）。
-- binds/wm.lua 會在 ±5 跳轉時暫時切成 "slide top" / "slide bottom"
-- （新頁從方向鍵那一側進來，與左右一致）。
function A.set_workspace_style(style)
    for _, leaf in ipairs({ "workspaces", "workspacesIn", "workspacesOut" }) do
        hl.animation({ leaf = leaf, enabled = true, speed = SPRING_SPEED, spring = "jelly_ws", style = style })
    end
end

A.set_workspace_style("slide")

-- ── Layers (quickshell panels, hyprlock) ─────────────────────
hl.animation({ leaf = "layers",        enabled = true, speed = SPRING_SPEED, spring = "jelly_layer" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = SPRING_SPEED, spring = "jelly_layer", style = "slidefade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 2.5,          bezier = "tuck",        style = "slidefade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 2.5,          bezier = "pop" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 2.5,          bezier = "sink" })

return A
