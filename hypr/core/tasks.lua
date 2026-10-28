-- Task groups: 25 workspaces each — the HUD's 5×5, cells 1–25, 21–25 on top, so +5 is up.
-- Group slot k owns workspaces (k-1)*25+1 … k*25. A group's number (SUPER+N) is its place
-- in the list; its slot never changes, so renaming or deleting another group moves no window.
-- Quickshell (services/TaskGroups.qml) owns the list and writes STATE:
--   return { order = { 1, 3 }, last = { [3] = { laptop = 13, external = 14 } } }
-- The keys run here, in the compositor, so they never wait on the shell.
local T = {}

T.CELLS = 25
T.HOME  = 13            -- where a group opens: the centre cell
T.SIDE  = 14            -- the other screen's first cell in a group

local STATE = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
    .. "/hypr/taskgroups.lua"

local function state()
    local ok, s = pcall(dofile, STATE)
    if ok and type(s) == "table" and type(s.order) == "table" and #s.order > 0 then return s end
    return { order = { 1 }, last = {} }
end

function T.slot(id) return math.floor((id - 1) / T.CELLS) + 1 end
function T.cell(id) return (id - 1) % T.CELLS + 1 end
function T.ws(slot, cell) return (slot - 1) * T.CELLS + cell end

-- the laptop panel or the other screen: connector names move (DP-2 ⇄ HDMI-A-1)
local function kind(m) return m.name:match("^eDP") and "laptop" or "external" end

local function active()
    local w = hl.get_active_workspace()
    return (w and w.id and w.id > 0) and w.id or 1
end

-- Put group `slot` on every screen: the focused one at cell 13, each other one where it last
-- was in that group (14 the first time; never two screens on one cell). Focus and the
-- pointer end where they began.
function T.go_slot(slot)
    slot = tonumber(slot)
    if not slot or slot < 1 then return end
    local s = state()
    local last = (s.last or {})[slot] or {}
    local mons = hl.get_monitors()
    local focused
    for _, m in ipairs(mons) do if m.focused then focused = m end end
    local cur = hl.get_cursor_pos()
    local taken = { [T.HOME] = true }
    for _, m in ipairs(mons) do
        if not m.focused then
            local c = tonumber(last[kind(m)]) or T.SIDE
            while taken[c] do c = c % T.CELLS + 1 end
            taken[c] = true
            hl.dispatch(hl.dsp.focus({ monitor = m.name }))
            hl.dispatch(hl.dsp.focus({ workspace = T.ws(slot, c), on_current_monitor = true }))
        end
    end
    if focused then
        if #mons > 1 then hl.dispatch(hl.dsp.focus({ monitor = focused.name })) end
        hl.dispatch(hl.dsp.focus({ workspace = T.ws(slot, T.HOME), on_current_monitor = true }))
        if cur and #mons > 1 then hl.dispatch(hl.dsp.cursor.move({ x = cur.x, y = cur.y })) end
    end
    hl.dispatch(hl.dsp.event("task:go:" .. slot))     -- the HUD says where you are
end

-- SUPER+N: the N-th group in the list
function T.go(n)
    local slot = state().order[n]
    if slot then T.go_slot(slot)
    else hl.dispatch(hl.dsp.event("task:none:" .. n)) end
end

-- SUPER+SHIFT+N: the focused window to cell N of this group (you stay). 0.56's window.move
-- reads `follow`, not `silent` (`silent = true` was ignored: the old binds took you along)
function T.move_to_cell(c)
    hl.dispatch(hl.dsp.window.move({ workspace = T.ws(T.slot(active()), c), follow = false }))
end

-- a step inside the group: ±1 along the cells, ±5 a row; nil at the group's edge
function T.step_target(d)
    local id = active()
    local c = T.cell(id) + d
    if c < 1 or c > T.CELLS then return nil end
    return T.ws(T.slot(id), c)
end

function T.step(d)
    local id = T.step_target(d)
    if id then hl.dispatch(hl.dsp.focus({ workspace = id })) end
end

function T.move_step(d, follow)
    local id = T.step_target(d)
    if id then hl.dispatch(hl.dsp.window.move({ workspace = id, follow = follow })) end
end

-- the scroll wheel: the next / previous cell of this group that has windows
function T.cycle(dir)
    local id = active()
    local slot, here = T.slot(id), T.cell(id)
    local open = {}
    for _, w in ipairs(hl.get_workspaces()) do
        if w.id and w.id > 0 and T.slot(w.id) == slot and (w.windows or 0) > 0 then open[T.cell(w.id)] = true end
    end
    for i = 1, T.CELLS - 1 do
        local c = (here - 1 + dir * i) % T.CELLS + 1
        if open[c] then
            hl.dispatch(hl.dsp.focus({ workspace = T.ws(slot, c) }))
            return
        end
    end
end

-- Leaving the session, whichever way (a logout, Hyprland told to exit): the windows as they
-- are, before they close — quickshell/scripts/session.py, which brings them back at the next
-- login. Its first final save wins, so the one logind's PrepareForShutdown already took
-- isn't overwritten by a desktop half closed.
hl.on("hyprland.shutdown", function()
    os.execute("python3 " .. os.getenv("HOME") .. "/.config/quickshell/scripts/session.py save --final")
end)

return T
