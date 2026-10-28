pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../settings"

// TaskGroups — named groups of 25 workspaces, the HUD's 5×5 (cells 1–25, 21–25 on top).
// Group slot k owns workspaces (k-1)*25+1 … k*25; a group's number (SUPER+N) is its place in
// the list, and its slot never changes, so renaming or deleting one moves no window.
// The keys run in Hyprland (hypr/core/tasks.lua), which reads the mirror this writes
// (~/.local/state/hypr/taskgroups.lua: the order, and where each screen last was in each
// group). The list itself is ~/.local/state/quickshell/taskgroups.json.
// The groups menu is widgets/TaskMenu.qml (SUPER+G); the HUD shows `prompt`.
Singleton {
    id: root

    readonly property int cells: 25
    readonly property int home: 13
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    readonly property string listPath: stateDir + "/quickshell/taskgroups.json"
    readonly property string luaPath:  stateDir + "/hypr/taskgroups.lua"

    property var  groups: []        // [{slot, name}], in order; number = index + 1
    property var  last: ({})        // slot → {laptop: cell, external: cell}
    property bool loaded: false
    property int  tick: 0           // bumps on Hyprland's workspace / window events

    signal prompt(int slot)         // the HUD says which group this is
    signal missing(int n)           // SUPER+N with no group N
    signal menuRequested()
    signal removeDone(int slot, int left)   // left > 0: windows that didn't close

    function slotOf(id) { return Math.floor((id - 1) / cells) + 1 }
    function cellOf(id) { return (id - 1) % cells + 1 }
    function wsOf(slot, cell) { return (slot - 1) * cells + cell }
    function indexOf(slot) {
        for (var i = 0; i < groups.length; i++) if (groups[i].slot === slot) return i
        return -1
    }
    function nameOf(slot) { var i = indexOf(slot); return i < 0 ? "" : groups[i].name }
    function numberOf(slot) { return indexOf(slot) + 1 }
    function label(slot) {
        var n = numberOf(slot)
        return (n > 0 ? (n < 10 ? "0" + n : "" + n) : "--") + "  " + nameOf(slot)
    }

    readonly property int currentSlot: {
        tick
        var w = Hyprland.focusedWorkspace
        return w && w.id > 0 ? slotOf(w.id) : 1
    }
    readonly property int currentCell: {
        tick
        var w = Hyprland.focusedWorkspace
        return w && w.id > 0 ? cellOf(w.id) : home
    }

    // the windows of a group: [{address, cls, title, ws, cell}]
    function windowsIn(slot) {
        tick
        var out = [], tl = Hyprland.toplevels.values
        for (var i = 0; i < tl.length; i++) {
            var o = tl[i] ? tl[i].lastIpcObject : null
            if (!o || !o.workspace || o.workspace.id < 1 || slotOf(o.workspace.id) !== slot) continue
            out.push({ address: o.address, cls: o.class || o.initialClass || "?", title: o.title || "",
                       ws: o.workspace.id, cell: cellOf(o.workspace.id) })
        }
        return out
    }
    // windows per cell (25 counts), for the menu's small map
    function occupancy(slot) {
        var c = [], ws = windowsIn(slot)
        for (var i = 0; i < cells; i++) c.push(0)
        for (var j = 0; j < ws.length; j++) c[ws[j].cell - 1]++
        return c
    }

    // ── changes ──
    function go(slot) {
        if (indexOf(slot) < 0) return
        _eval.command = ["hyprctl", "eval", 'require("core.tasks").go_slot(' + slot + ')']
        _eval.running = true
    }
    // windows (by address) to a cell of a group; you stay where you are
    function moveWindows(addrs, slot, cell) {
        var ws = wsOf(slot, cell)
        for (var i = 0; i < addrs.length; i++)
            Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + ws + '", follow = false, window = "address:' + addrs[i] + '" })')
        return addrs.length
    }
    function goNumber(n) { if (n >= 1 && n <= groups.length) go(groups[n - 1].slot); else missing(n) }

    function add(name) {
        var used = {}
        for (var i = 0; i < groups.length; i++) used[groups[i].slot] = true
        var slot = 1
        while (used[slot]) slot++
        var g = groups.slice()
        g.push({ slot: slot, name: (name || "").trim() || "任務 " + (g.length + 1) })
        groups = g
        _save()
        return slot
    }
    function rename(slot, name) {
        var i = indexOf(slot)
        name = (name || "").trim()
        if (i < 0 || name === "") return
        var g = groups.slice()
        g[i] = { slot: slot, name: name }
        groups = g
        _save()
    }

    // Deleting closes every window of the group (apps with unsaved work may ask first). The
    // group goes once its windows have; any still open after 5 s keep it, and say so.
    property int removing: 0
    function remove(slot) {
        if (indexOf(slot) < 0 || groups.length < 2 || removing) return false
        removing = slot
        var ws = windowsIn(slot)
        for (var i = 0; i < ws.length; i++)
            Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + ws[i].address + '" })')
        _removeT.restart()
        _removeCheck.restart()
        return true
    }
    property Timer _removeCheck: Timer {     // done early once the group is empty
        interval: 250; repeat: true
        onTriggered: { Hyprland.refreshToplevels(); if (root.windowsIn(root.removing).length === 0) root._finishRemove() }
    }
    property Timer _removeT: Timer { interval: 5000; onTriggered: root._finishRemove() }
    function _finishRemove() {
        _removeT.stop(); _removeCheck.stop()
        var slot = removing
        if (!slot) return
        removing = 0
        var left = windowsIn(slot).length
        if (left === 0) {
            var i = indexOf(slot)
            var wasCurrent = slot === currentSlot
            var g = groups.slice()
            g.splice(i, 1)
            groups = g
            var l = Object.assign({}, last); delete l[slot]; last = l
            _save()
            if (wasCurrent) go(g[Math.max(0, i - 1)].slot)
        }
        removeDone(slot, left)
    }

    // ── where each screen last was in each group (the other screen comes back there) ──
    function _track() {
        var mons = Hyprland.monitors.values, l = last, changed = false
        for (var i = 0; i < mons.length; i++) {
            var m = mons[i]
            if (!m || !m.activeWorkspace || m.activeWorkspace.id < 1) continue
            var id = m.activeWorkspace.id, s = slotOf(id), c = cellOf(id)
            var kind = m.name.indexOf("eDP") === 0 ? "laptop" : "external"
            if (!l[s]) l[s] = {}
            if (l[s][kind] !== c) { l[s][kind] = c; changed = true }
        }
        if (changed) { last = l; _saveT.restart() }
        _adopt()
    }
    // a window in a slot no group owns (moved there by hand, or left from before): give it a
    // group. Windows, not workspaces: Quickshell's workspace list can keep a destroyed one
    // whose last state still says it had a window (that re-made a deleted test group).
    function _adopt() {
        if (!loaded) return
        var tl = Hyprland.toplevels.values, owned = {}, extra = []
        for (var i = 0; i < groups.length; i++) owned[groups[i].slot] = true
        for (var j = 0; j < tl.length; j++) {
            var o = tl[j] ? tl[j].lastIpcObject : null
            if (!o || !o.workspace || o.workspace.id < 1) continue
            var s = slotOf(o.workspace.id)
            if (!owned[s]) { owned[s] = true; extra.push(s) }
        }
        if (extra.length === 0) return
        extra.sort(function(a, b) { return a - b })
        var g = groups.slice()
        for (var k = 0; k < extra.length; k++) g.push({ slot: extra[k], name: "任務 " + (g.length + 1) })
        groups = g
        _save()
    }

    // ── files ──
    FileView {
        id: listFile
        path: root.listPath
        blockWrites: true
        printErrors: false
        onLoaded: root._parse(text())
        onLoadFailed: root._parse("")
    }
    function _parse(t) {
        var d = null
        try { d = JSON.parse(t) } catch (e) { d = null }
        var g = []
        if (d && d.groups && d.groups.length) {
            for (var i = 0; i < d.groups.length; i++) {
                var x = d.groups[i]
                if (x && x.slot > 0) g.push({ slot: Math.floor(x.slot), name: String(x.name || "任務 " + (i + 1)) })
            }
        }
        if (g.length === 0) g = [{ slot: 1, name: "主要" }]
        groups = g
        last = (d && d.last) ? d.last : {}
        var first = !loaded
        loaded = true
        _adopt()
        _writeLua()
        if (t === "") _save()
        if (first) _startPromptT.start()     // at login (and a shell restart): where you are
    }
    property Timer _startPromptT: Timer { interval: 2500; onTriggered: root.showPrompt() }
    property Timer _saveT: Timer { interval: 1500; onTriggered: root._save() }
    function _save() {
        _saveT.stop()
        listFile.setText(JSON.stringify({ version: 1, groups: groups, last: last }, null, 1) + "\n")
        _writeLua()
    }
    FileView { id: luaFile; path: root.luaPath; blockWrites: true; printErrors: false }
    function _writeLua() {
        var order = groups.map(function(g) { return g.slot }).join(", ")
        var ls = []
        for (var s in last) {
            var e = last[s], parts = []
            if (e.laptop) parts.push("laptop = " + Math.floor(e.laptop))
            if (e.external) parts.push("external = " + Math.floor(e.external))
            if (parts.length && Number(s) > 0) ls.push("  [" + Math.floor(Number(s)) + "] = { " + parts.join(", ") + " },")
        }
        luaFile.setText("-- written by quickshell services/TaskGroups.qml; read by hypr/core/tasks.lua\n"
                        + "return {\n order = { " + order + " },\n last = {\n" + ls.join("\n") + "\n },\n}\n")
    }
    property Process _eval: Process { running: false }
    property Process _mkdir: Process {
        running: true
        command: ["mkdir", "-p", root.stateDir + "/quickshell", root.stateDir + "/hypr"]
    }

    // ── Hyprland's events ──
    property Timer _trackT: Timer { interval: 120; onTriggered: { root.tick++; root._track() } }
    property Timer _promptT: Timer { interval: 160; onTriggered: root.prompt(root.currentSlot) }
    onCurrentSlotChanged: if (loaded) _promptT.restart()
    function showPrompt() { _promptT.restart() }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
            case "custom":
                var d = String(event.data || "")
                if (d.indexOf("task:go:") === 0) root._promptT.restart()
                else if (d.indexOf("task:none:") === 0) root.missing(Number(d.substring(10)))
                break
            case "workspacev2": case "focusedmonv2": case "moveworkspacev2":
            case "createworkspacev2": case "destroyworkspacev2":
            case "openwindow": case "closewindow": case "movewindowv2":
                Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels()
                root._trackT.restart()
                if (event.name !== "workspacev2" && !root.restoring) root._sessionT.restart()
                break
            case "changefloatingmode":
                if (!root.restoring) root._sessionT.restart()
                break
            }
        }
    }
    Component.onCompleted: { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); _trackT.restart() }

    // ── the session (scripts/session.py): what was open comes back at login ──
    // Restore first (once per login, [session] restore); saving starts only after it, a few
    // seconds after windows change and every two minutes. A shutdown takes the last one: the
    // shell holds logind's delay lock and saves --final on PrepareForShutdown(true), which
    // freezes the snapshot so the windows closing after it can't overwrite it (a logout takes
    // it from Hyprland's own shutdown, hypr/core/tasks.lua).
    readonly property string sessionPy: Qt.resolvedUrl("../scripts/session.py").toString().replace("file://", "")
    property bool restoring: false
    property bool sessionReady: false
    property Process _restoreP: Process {
        running: false
        stdout: StdioCollector { onStreamFinished: console.log("session: restore " + this.text.trim()) }
        onExited: { root.restoring = false; root.sessionReady = true; root.showPrompt() }
    }
    property Timer _restoreT: Timer {      // the screens and the compositor settle first
        interval: 1500
        onTriggered: {
            root.restoring = true
            root._restoreP.command = ["python3", root.sessionPy, "restore"].concat(Settings.sessionRestore ? [] : ["--skip"])
            root._restoreP.running = true
        }
    }
    onLoadedChanged: if (loaded) _restoreT.start()
    property Process _saveP: Process { running: false }
    function saveSession() {
        if (!sessionReady || _saveP.running) return
        _saveP.command = ["python3", sessionPy, "save"]
        _saveP.running = true
    }
    property Timer _sessionT: Timer { interval: 6000; onTriggered: root.saveSession() }
    property Timer _sessionTick: Timer { interval: 120000; repeat: true; running: root.sessionReady; onTriggered: root.saveSession() }
    property Process _shutdownLock: Process {
        running: root.sessionReady
        command: ["systemd-inhibit", "--what=shutdown", "--mode=delay", "--who=Quickshell",
                  "--why=saving the windows of the task groups", "sleep", "infinity"]
    }
    property Process _finalP: Process {
        running: false
        onExited: root._shutdownLock.running = false      // logind may go on
    }
    property Process _logind: Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("PrepareForShutdown") < 0) return
                if (line.indexOf("true") >= 0) {
                    root._finalP.command = ["python3", root.sessionPy, "save", "--final"]
                    root._finalP.running = true
                } else {                                    // called off: carry on saving
                    Quickshell.execDetached(["python3", root.sessionPy, "unfreeze"])
                    root._shutdownLock.running = root.sessionReady
                }
            }
        }
    }

    IpcHandler {
        target: "tasks"
        function menu(): void { root.menuRequested() }
        function go(n: int): void { root.goNumber(n) }
        function prompt(): void { root.showPrompt() }
        function save(): void { root.saveSession() }
        function session(): string { return JSON.stringify({ restoring: root.restoring, ready: root.sessionReady }) }
        function list(): string {
            return JSON.stringify(root.groups.map(function(g, i) {
                return { number: i + 1, slot: g.slot, name: g.name, windows: root.windowsIn(g.slot).length, current: g.slot === root.currentSlot }
            }))
        }
    }
}
