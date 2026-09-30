import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../components"
import "../services"
import "../settings"
import "../theme"

// CornerHud — compact NieR/YoRHa status cluster anchored top-right.
//
// Header (always): clock + focused workspace.
//   · hover the header        → expands DOWN: CPU / GPU / VOL / BAT stat blocks
//   · on workspace switch     → header morphs to WORKSPACE mode for ~2.8s
//   · right-click the header  → pins WORKSPACE mode open (selector)
//
// WORKSPACE mode shows a 5×5 grid (ws 1-25, matching the ±1 / ±5 navigation).
// Clicking a cell switches to it; hovering/active cell lists that ws's windows
// below the grid. Floating (no exclusion zone). All data comes from the shared
// service singletons + native Hyprland — the HUD never polls on its own.
Scope {
    id: root

    // ── NieR ink palette ── the popups' paper/ink family turned over for a resident
    // widget: the ControlCenter nav bar's dark ink, paper text and lines, light
    // #fff6cf for what's active, and a paper block with ink text for what's picked
    // (the popups' ink selector, inverted). The colour "pop" still comes from the
    // month artwork in the calendar — its own dark vignette melts into the ink, and
    // the frame's lower half takes a whisper of that month's hue (calBottom).
    // (all from the theme — config/themes/<theme>.conf, [dark] + [palette])
    readonly property color cBg:     Theme.panel          // ink (panel)
    readonly property color cSurf:   Theme.panelRaised    // lifted ink (tracks)
    readonly property color cText:   Theme.panelText        // paper
    readonly property color cMuted:  Theme.panelMuted   // paper, dimmed
    readonly property color cAccent: Theme.panelActive    // light — active / selected / fills
    readonly property color cGold:   Theme.panelText        // frame lines / ornaments (paper)
    readonly property color cBorder: Theme.alpha(Theme.panelText, 0.28)
    readonly property color cGood:   Theme.good           // sage (semantic "ok")
    readonly property color cWarn:   Theme.warn           // brick — warnings
    readonly property color cInk:    Theme.panelOnFill    // text on a filled block
    readonly property color cRed:    Theme.accent         // accent edge on a paper block
    function paperA(a) { return Theme.alpha(Theme.panelText, a) }
    readonly property string mono:   Theme.mono

    readonly property int frameW: 196

    // ── Shared clock (one timer for all monitors) ──
    property string clock: "--:--"
    property string secs:  "--"
    // today (live, updated by the clock)
    property int    todayYear:  2026
    property int    todayMonth: 0      // 0-11
    property int    todayDay:   1
    // calendar: viewed month + selected day (navigable, independent of "today")
    property int    calYear:   2026
    property int    calMonth:  0       // 0-11
    property int    calSelDay: 1
    property bool   _calInit:  false
    property Timer _clockT: Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            root.clock = String(d.getHours()).padStart(2,"0") + ":" + String(d.getMinutes()).padStart(2,"0")
            root.secs  = String(d.getSeconds()).padStart(2,"0")
            root.todayYear = d.getFullYear(); root.todayMonth = d.getMonth(); root.todayDay = d.getDate()
            // first tick: sync the viewed month to today and fetch its events
            if (!root._calInit) {
                root.calYear = root.todayYear; root.calMonth = root.todayMonth
                root.calSelDay = root.todayDay; root._calInit = true; root.setCalRange()
            }
        }
    }
    function daysInMonth(y, m) { return new Date(y, m+1, 0).getDate() }
    function firstDOW(y, m)    { return new Date(y, m, 1).getDay() }
    function pad2(n)           { return String(n).padStart(2,"0") }
    function dateStr(y, m, d)  { return y + "-" + pad2(m+1) + "-" + pad2(d) }
    // push the viewed month's date range to the Cal service (drives gcalcli fetch)
    function setCalRange() {
        Cal.rangeStart = dateStr(calYear, calMonth, 1)
        Cal.rangeEnd   = dateStr(calYear, calMonth, daysInMonth(calYear, calMonth))
    }
    // snap the calendar back to the live "today" (called whenever the HUD reveals,
    // so opening it always lands on the current date instead of a stale selection)
    function resetCalToday() {
        calYear = todayYear; calMonth = todayMonth; calSelDay = todayDay
        setCalRange()
    }
    // navigate ±months; keep the selection valid; refetch
    function calShift(delta) {
        var m = calMonth + delta, y = calYear
        while (m < 0)  { m += 12; y-- }
        while (m > 11) { m -= 12; y++ }
        calYear = y; calMonth = m
        calSelDay = Math.min(calSelDay, daysInMonth(y, m))
        setCalRange()
    }
    readonly property var monthNames: ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"]
    // Animated month change (‹ › buttons, the moon hotspots, wheel): the artwork and
    // label slide out the way you went (calOut 0→1), the month flips, then slide in
    // from the other side (calOut 1→0, calIn = true)
    property int  calDir: 1
    property real calOut: 0
    property bool calIn: false
    property int  _calPending: 0
    readonly property real calSlide: (calIn ? calDir : -calDir) * 16 * calOut
    function calNav(d) {
        if (_calAnim.running) _calAnim.complete()
        calDir = d; _calPending = d
        _calAnim.restart()
    }
    property SequentialAnimation _calAnim: SequentialAnimation {
        ScriptAction { script: root.calIn = false }
        NumberAnimation { target: root; property: "calOut"; from: 0; to: 1; duration: 110; easing.type: Easing.InQuad }
        ScriptAction { script: { root.calShift(root._calPending); root.calIn = true } }
        NumberAnimation { target: root; property: "calOut"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        ScriptAction { script: root.calIn = false }
    }

    // ── OSD: header briefly shows VOL/BRI while adjusting, then back to clock ──
    property string osdMode: ""   // "" | "vol" | "bri"
    property bool   _osdReady: false   // ignore the initial volume binding at startup
    property Timer _osdT:     Timer { interval: Settings.hudOsdDuration; onTriggered: root.osdMode = "" }
    property Timer _osdInitT: Timer { interval: 1500; running: true; onTriggered: root._osdReady = true }
    function showOsd(m) { osdMode = m; _osdT.restart() }
    // Volume changes (incl. media keys → Pipewire) auto-trigger the VOL osd.
    Connections {
        target: Audio
        function onVolumeChanged() { if (root._osdReady) root.showOsd("vol") }
        function onMutedChanged()  { if (root._osdReady) root.showOsd("vol") }
    }

    // ── Stopwatch (shared state) ──
    property bool swGo: false
    property int  swElapsed: 0
    property Timer _swT: Timer { interval: 1000; running: root.swGo; repeat: true; onTriggered: root.swElapsed++ }
    function swFmt(s) {
        var h = Math.floor(s/3600), m = Math.floor((s%3600)/60), x = s%60
        return (h>0 ? h+":" : "") + String(m).padStart(2,"0") + ":" + String(x).padStart(2,"0")
    }

    // ── Workspace mode (shared across monitors) ──
    property bool wspPinned: false           // right-click / IPC latches the selector open
    property bool wspAuto:   false           // brief auto-show on a workspace switch
    readonly property bool wspMode: wspPinned || wspAuto
    property bool statsPinned: false         // IPC-toggled stat cluster (keyboard)
    property int  statsPage: 0               // stats paging: 0=STATUS 1=INFO 2=TOOLS
    readonly property var statsPageNames: ["STATUS", "INFO", "TOOLS"]
    // pageDir: which way the last flip went (+1 → next) — the tab fill and the page
    // slide follow it; pageIn animates each new page in
    property int  pageDir: 1
    property real pageIn: 1
    property NumberAnimation _pageInAnim: NumberAnimation { target: root; property: "pageIn"; from: 0; to: 1; duration: 300; easing.type: Easing.OutCubic }
    onStatsPageChanged: _pageInAnim.restart()
    function cycleStatsPage(d) { pageDir = d; statsPage = (statsPage + d + statsPageNames.length) % statsPageNames.length }
    function setStatsPage(n) { if (n === statsPage) return; pageDir = n > statsPage ? 1 : -1; statsPage = n }
    property bool hudVisible: true            // whole-HUD show/hide (keyboard)
    property int  evtTick: 0                  // bumped on every ws/layout event so
                                             // per-monitor bindings re-evaluate

    // Toggle: if the selector is showing (pinned OR auto), fully dismiss it;
    // otherwise pin it open. (Setting wspAuto here without arming _wspHide is what
    // previously left it stuck on — "can switch in but not back".)
    function toggleWsp() {
        if (wspMode) { wspPinned = false; wspAuto = false; _wspHide.stop() }
        else         { wspPinned = true }
    }
    function toggleStats() { statsPinned = !statsPinned }

    // ── Hit feel (as the popups): a click squashes the item and springs it back
    // (pop) and throws a small HitBurst out of it (hit) in the window it lives in ──
    signal hitAt(var item, real strength)
    function hit(item, strength) { if (item) { pop(item); hitAt(item, strength === undefined ? 0.5 : strength) } }
    function pop(item) {
        if (!item) return
        _popAnim.stop(); _popAnim.target = item; _popAnim.restart()
    }
    property SequentialAnimation _popAnim: SequentialAnimation {
        property Item target: null
        NumberAnimation { target: root._popAnim.target; property: "scale"; to: 0.86; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root._popAnim.target; property: "scale"; to: 1; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
    }
    // A hovered clickable row takes the sliding paper selector of its page
    signal rowHot(var row, bool on)

    // Launch external GUI tools (pavucontrol, nm-connection-editor, …)
    property Process _launcher: Process { running: false }
    function run(cmd) {
        _launcher.command = ["sh","-c","nohup " + cmd + " >/dev/null 2>&1 &"]
        _launcher.running = false
        _launcher.running = true
    }

    // ── IPC ── (bind keys in hyprland.conf, e.g. qs ipc call hud toggle)
    IpcHandler {
        target: "hud"
        function toggle(): void  { root.toggleWsp() }    // workspace selector
        function workspaces(): void { root.toggleWsp() }
        function stats(): void   { root.toggleStats() }  // CPU/GPU/MEM/VOL/BAT/… cluster
        function page(n: int): void { root.setStatsPage(n); root.statsPinned = true }  // jump to a stats page
        function visible(): void { root.hudVisible = !root.hudVisible }  // whole HUD
        function show(): void    { root.hudVisible = true }
        function hide(): void    { root.hudVisible = false }
        function close(): void   { root.wspPinned = false; root.wspAuto = false; root._wspHide.stop(); root.statsPinned = false }
        // OSD from media/brightness keys: qs ipc call hud osd bri|vol
        function osd(which: string): void {
            if (which === "bri") Backlight.refresh()
            root.showOsd(which === "bri" ? "bri" : "vol")
        }
    }
    property Timer _wspHide: Timer {
        interval: 2800
        onTriggered: if (!root.wspPinned) root.wspAuto = false
    }

    // Native Hyprland event stream → show the selector briefly on layout changes.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            switch (event.name) {
                // Actual workspace switch → briefly auto-show the selector.
                case "workspace":     case "workspacev2":
                    root.wspAuto = true
                    root._wspHide.restart()
                    // falls through to also refresh state below
                case "focusedmon":    case "focusedmonv2":
                case "openwindow":    case "closewindow":
                case "movewindow":    case "movewindowv2":
                case "moveworkspace": case "moveworkspacev2":
                    // Keep the grid data accurate without forcing the page open
                    // (mouse focus / new windows must NOT flip stats → wsp).
                    root.evtTick++
                    Hyprland.refreshMonitors()
                    Hyprland.refreshToplevels()
                    break
            }
        }
    }

    // Populate native models once at startup (kept in sync by events afterwards).
    property Timer _hyprInit: Timer {
        interval: 500; running: true; repeat: false
        onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshMonitors(); Hyprland.refreshToplevels() }
    }

    // ── TODO file (~/todo-list.md), live-watched + editable ──
    property bool todoEditing: false
    FileView {
        id: todoView
        path: Quickshell.env("HOME") + "/todo-list.md"
        watchChanges: true
        property string fullText: ""
        function _parse() {
            todoView.fullText = (typeof text === "function") ? (text() || "") : ""
        }
        onLoaded: _parse()
        // don't clobber the editor while the user is typing
        onFileChanged: if (!root.todoEditing) reload()
    }
    // Write helper — text passed as argv to avoid shell-escaping issues.
    property Process _todoW: Process { running: false }
    function writeTodo(t) {
        _todoW.command = ["sh","-c","printf '%s' \"$1\" > \"$HOME/todo-list.md\"", "sh", t]
        _todoW.running = false
        _todoW.running = true
    }

    // Per-monitor accent colours (open workspaces are tinted by their monitor)
    readonly property var monColors: Theme.monitorColors
    // per-month deep panel tone (sampled from each artwork's calendar-panel area) —
    // the bottom colour the background fades into, matching the calendar's lower edge.
    readonly property var monPanels: ["#7c2f37","#204d8a","#672340","#495136",
                                      "#2e2c6c","#882b4e","#1d3770","#1e4053",
                                      "#644819","#6c281a","#4a2568","#3a306c"]
    // dark, lightly-tinted bottom tone: cBg mixed with ~45% of the month panel
    // colour. Matches the calendar image's DARK lower edge (vignette/footer) so the
    // feathered edge blends naturally, while keeping a whisper of month hue.
    readonly property color calPanel: monPanels[calMonth]
    readonly property color calBottom: Qt.tint(cBg, Qt.rgba(calPanel.r, calPanel.g, calPanel.b, Theme.monthTint))

    // Does workspace `id` currently exist (has a Hyprland workspace object)?
    function wsExists(id) {
        root.evtTick
        var ws = Hyprland.workspaces.values
        for (var i = 0; i < ws.length; i++) if (ws[i] && ws[i].id === id) return true
        return false
    }
    // Monitor index that workspace `id` lives on, or -1 if it isn't open.
    function wsMonIdx(id) {
        root.evtTick
        var ws = Hyprland.workspaces.values
        for (var i = 0; i < ws.length; i++) {
            if (ws[i] && ws[i].id === id && ws[i].monitor) {
                var mons = Hyprland.monitors.values
                for (var j = 0; j < mons.length; j++)
                    if (mons[j] && mons[j].name === ws[i].monitor.name) return j
            }
        }
        return -1
    }
    // Is workspace `id` the active one on its monitor?
    function wsIsActive(id) {
        root.evtTick
        var mons = Hyprland.monitors.values
        for (var j = 0; j < mons.length; j++)
            if (mons[j] && mons[j].activeWorkspace && mons[j].activeWorkspace.id === id) return true
        return false
    }

    // Windows on workspace `id` → [{cls,title}] (from native toplevels).
    function windowsFor(id) {
        root.evtTick   // dependency: re-eval when windows change
        var out = []
        var tl = Hyprland.toplevels.values
        for (var i = 0; i < tl.length; i++) {
            var o = tl[i] ? tl[i].lastIpcObject : null
            if (o && o.workspace && o.workspace.id === id)
                out.push({ cls: o.class || o.initialClass || "?", title: o.title || "" })
        }
        return out
    }

    Variants {
        model: Settings.cornerHudEnabled ? Quickshell.screens : []
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors.top: true; anchors.right: true
            // margins.right MUST be 0 so the surface reaches the true screen edge —
            // that's where the reveal trigger strip lives.
            margins.top: 8; margins.right: 0
            exclusionMode: ExclusionMode.Ignore
            // Keybind / IPC / OSD reveals go to the Overlay layer so they show above
            // fullscreen windows (which cover Top). A plain edge-hover stays on Top,
            // so a fullscreen game or video never gets the HUD popping over it from
            // a stray pointer. The layer drops back only after the slide-out ends.
            readonly property bool wantOverlay: root.statsPinned || root.wspMode
                                                || root.todoEditing || root.osdMode !== ""
            property bool overlayHold: false
            onWantOverlayChanged: {
                if (wantOverlay) { overlayHold = true; overlayDropT.stop() }
                else overlayDropT.restart()
            }
            property Timer overlayDropT: Timer { interval: 450; onTriggered: win.overlayHold = false }
            WlrLayershell.layer: overlayHold ? WlrLayer.Overlay : WlrLayer.Top
            WlrLayershell.keyboardFocus: root.todoEditing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            // Window is a FIXED tall transparent surface; the frame animates its
            // height INSIDE it. This avoids resizing the layer surface every frame
            // during the expand animation (the buffer realloc was the jank). The
            // mask pins the input + visible region to the frame, so the empty area
            // is fully click-through and only the frame is interactive.
            //   +8 right inset (frame rests 8px from the edge) +8 left slack for deco.
            implicitWidth:  frame.width + 16
            implicitHeight: modelData.height - 16

            // ── Auto-hide reveal ──
            // The HUD parks itself off the right edge. A thin trigger strip on the
            // screen edge slides it in; it slides back out a short time after the
            // pointer leaves (unless a panel is pinned / being edited).
            property bool peeked: false
            property Timer peekHideT: Timer {
                interval: Settings.hudHideDelay
                onTriggered: win.peeked = false
            }
            // An active OSD reveals the HUD too: changing volume/brightness (or
            // muting) slides it in to show the level, and `_osdT` clearing osdMode
            // lets it slide straight back out.
            readonly property bool revealed: peeked || statsExpanded
                                            || root.statsPinned || root.wspMode || root.todoEditing
                                            || root.osdMode !== ""
            readonly property bool shown: root.hudVisible && revealed
            // opening the HUD always snaps the calendar to today; each reveal plays
            // the paper sweep across the frame (revealT 0 → 1)
            property real revealT: 1
            NumberAnimation { id: revealAnim; target: win; property: "revealT"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
            onShownChanged: if (shown) { root.resetCalToday(); revealAnim.restart() }

            // Input region: the edge trigger is always live (when the HUD isn't
            // hotkey-hidden); the catcher (which already contains the frame) joins
            // it only while revealed, so the parked HUD never eats clicks over the
            // empty area.
            mask: Region {
                Region { item: root.hudVisible ? trigger : null }
                Region { item: win.shown ? catcher : null }
            }

            // edge trigger strip — touch the right screen edge to reveal.
            // Width must be >= the frame's 8px right inset, otherwise the 2px
            // between the strip and the frame is in neither input region and the
            // reveal drops the moment the pointer crosses it.
            Item {
                id: trigger
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 10
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) { win.peeked = true; win.peekHideT.stop() }
                        else win.peekHideT.restart()
                    }
                }
            }

            // Hold-open catcher — the frame plus a margin, live only while the HUD
            // is out. The trigger runs the full screen height but the frame is a
            // small box at the top, so without this the pointer reveals the HUD at
            // (say) y=600, then loses it on the way up to the frame and it retracts
            // before ever being touched. Sized off the frame so it grows with the
            // expanded stats instead of covering a fixed slab of the corner.
            Item {
                id: catcher
                anchors { right: parent.right; top: parent.top; left: parent.left }
                height: Math.min(frame.height + 28, win.height)
                enabled: win.shown
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) { win.peeked = true; win.peekHideT.stop() }
                        else win.peekHideT.restart()
                    }
                }
            }

            // Focused workspace id for THIS monitor (native Hyprland).
            // root.evtTick forces re-evaluation on every workspace/layout event.
            property int wsId: {
                root.evtTick   // dependency: re-eval on ws events
                var m = Hyprland.monitors.values.find(function(x){ return x && x.name === modelData.name })
                return (m && m.activeWorkspace) ? m.activeWorkspace.id
                                                : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)
            }

            property bool statsExpanded: false
            property int  hoveredWs: -1
            readonly property bool showWsp:   root.wspMode
            readonly property bool showStats: (statsExpanded || root.statsPinned || root.todoEditing) && !root.wspMode
            // which ws the content list describes: hovered cell, else current
            readonly property int  displayWs: hoveredWs > 0 ? hoveredWs : wsId

            // ── Frame ── (anchored to the TOP-RIGHT of the tall window)
            Rectangle {
                id: frame
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.rightMargin: 8        // rest 8px in from the screen edge
                width: root.frameW
                height: col.implicitHeight + 16
                color: root.cBg
                border.color: root.paperA(0.3)
                border.width: 1
                // whole-HUD show/hide: fade + disable input (enabled cascades to
                // every handler/MouseArea inside → a hidden HUD is click-through).
                opacity: root.hudVisible ? 1 : 0
                enabled: win.shown
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // slide in from / out to the right edge (auto-hide reveal)
                transform: Translate {
                    x: win.shown ? 0 : (frame.width + 24)
                    Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
                }

                clip: true   // keep the background wash + corner deco inside the frame

                // background: the original dark base across the top half, fading in
                // the bottom half to the month's deep panel tone. Keeps the header /
                // stats on clean dark, while the lower colour matches the calendar's
                // lower edge so the feathered calendar dissolves into it.
                Rectangle {
                    anchors.fill: parent; anchors.margins: 1
                    gradient: Gradient {
                        GradientStop { position: 0.00; color: root.cBg }
                        GradientStop { position: 0.20; color: root.cBg }
                        GradientStop { position: 1.00; color: root.calBottom }
                    }
                }

                // hover frame → expand stats AND hold the reveal open; leaving the
                // frame collapses stats and arms the auto-hide slide-out.
                HoverHandler {
                    id: frameHover
                    onHoveredChanged: {
                        win.statsExpanded = hovered
                        if (hovered) {
                            win.peekHideT.stop()
                            // showStats is gated on !wspMode, so during the brief
                            // auto-show after a workspace switch the grid would
                            // swallow the hover and the stats wouldn't appear until
                            // it timed out. A deliberate hover outranks the
                            // transient auto-show — but never the pinned one, which
                            // the user asked for explicitly.
                            if (root.wspAuto && !root.wspPinned) {
                                root.wspAuto = false
                                root._wspHide.stop()
                            }
                        }
                        else win.peekHideT.restart()
                    }
                }

                // Glass rim along the top (static — a resident widget doesn't animate
                // at idle) + the sweep that crosses it, and the frame, on every reveal
                Rectangle {
                    x: 1; y: 1; width: parent.width - 2; height: 1; z: 5
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.35; color: Theme.alpha(Theme.light, 0.55) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Item {
                    anchors.fill: parent; z: 6; clip: true
                    visible: win.revealT < 1
                    // a soft paper band wipes across, right → left (the way it slid in)
                    Rectangle {
                        width: 70; height: parent.height
                        x: parent.width - win.revealT * (parent.width + 140) + 20
                        opacity: 0.16 * (1 - win.revealT)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: root.cText }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                    // …and a light glint along the top edge
                    Rectangle {
                        y: 0; width: 46; height: 2
                        x: parent.width - win.revealT * (parent.width + 60)
                        opacity: 1 - win.revealT * win.revealT
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: root.cAccent }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }

                Column {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 12; rightMargin: 12; topMargin: 8 }
                    spacing: 0

                    // ── Header (always visible) — clock ⇄ workspace label ──
                    Item {
                        width: parent.width; height: 22

                        // clock face (hidden during workspace mode OR an OSD)
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            opacity: (win.showWsp || root.osdMode !== "") ? 0 : 1
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            Text { text: root.clock; font.family: root.mono; font.pixelSize: 14
                                   font.letterSpacing: 1; color: root.cText
                                   anchors.verticalCenter: parent.verticalCenter }
                            Text { text: root.secs; font.family: root.mono; font.pixelSize: 9
                                   color: root.cMuted; y: 2 }
                        }
                        // workspace label (morph-in)
                        Text {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: "WORKSPACE"; font.pixelSize: 10; font.weight: Font.Medium
                            font.letterSpacing: 3; color: root.cAccent
                            opacity: win.showWsp ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                        // OSD: VOL / BRI level while adjusting (crossfades with clock)
                        Row {
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            opacity: (root.osdMode !== "" && !win.showWsp) ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                            property real lvl: root.osdMode === "bri" ? Backlight.value
                                             : Audio.muted ? 0 : Audio.volume/1.5
                            Item {
                                width: 16; height: 14; anchors.verticalCenter: parent.verticalCenter
                                SpeakerIcon { anchors.fill: parent; visible: root.osdMode !== "bri"
                                              color: root.cAccent; muted: Audio.muted }
                                SunIcon     { anchors.fill: parent; visible: root.osdMode === "bri"
                                              color: root.cAccent }
                            }
                            Rectangle {   // the ControlCenter volume slider, in small: frame · inner frame · inset fill
                                anchors.verticalCenter: parent.verticalCenter
                                width: 64; height: 10; color: "transparent"
                                border.color: root.paperA(0.55); border.width: 1
                                Rectangle { anchors.fill: parent; anchors.margins: 2; color: "transparent"
                                            border.color: root.paperA(0.2); border.width: 1 }
                                Rectangle {
                                    x: 2; y: 2; height: parent.height - 4
                                    width: (parent.width - 4) * Math.max(0, Math.min(1, parent.parent.lvl))
                                    color: root.cAccent
                                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                }
                            }
                            Text {
                                text: root.osdMode === "vol" && Audio.muted ? "mute"
                                    : Math.round(parent.lvl*100) + "%"
                                font.family: root.mono; font.pixelSize: 12; color: root.cText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // right side: current ws (+ pin dot)
                        Row {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Rectangle { width: 5; height: 5; rotation: 45; antialiasing: true   // pin: ◆ pinned · ◇ not
                                        color: root.wspPinned ? root.cAccent : "transparent"
                                        border.color: root.wspPinned ? root.cAccent : root.cMuted; border.width: 1
                                        anchors.verticalCenter: parent.verticalCenter }
                            Text { text: "ws·" + win.wsId; font.family: root.mono; font.pixelSize: 11
                                   font.letterSpacing: 1; color: root.cText
                                   anchors.verticalCenter: parent.verticalCenter }
                        }

                        // click the header → toggle the workspace selector
                        // (right-click matches the old TopBar; left-click works too)
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleWsp()
                        }
                    }

                    // divider
                    Rectangle { width: parent.width; height: 1; color: root.cBorder
                                opacity: (win.showStats || win.showWsp) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } } }

                    // ── Body — animated height; holds EITHER stats OR wsp view ──
                    Item {
                        width: parent.width
                        clip: true
                        implicitHeight: win.showWsp  ? wspView.implicitHeight + 10
                                      : win.showStats ? statsView.implicitHeight + 8
                                      : 0
                        Behavior on implicitHeight { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }

                        // ── STATS view — paged: STATUS / INFO / TOOLS ──
                        Column {
                            id: statsView
                            width: parent.width; y: 8; spacing: 7
                            visible: win.showStats
                            opacity: win.showStats ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }

                            // page tabs — STATUS · INFO · TOOLS. The picked one fills with
                            // paper along the way you went (as the popups' category tabs);
                            // click a tab, or wheel over the row to flip.
                            Item {
                                id: pager
                                width: parent.width; height: 16
                                Row {
                                    anchors.fill: parent
                                    spacing: 3
                                    Repeater {
                                        model: root.statsPageNames
                                        HudTab {
                                            width: (pager.width - 6) / 3; height: pager.height
                                            label: modelData
                                            active: root.statsPage === index
                                            dir: root.pageDir
                                            onClicked: root.setStatsPage(index)
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent; acceptedButtons: Qt.NoButton; hoverEnabled: true
                                    onWheel: (w) => root.cycleStatsPage(w.angleDelta.y < 0 ? 1 : -1)
                                }
                            }

                            // page body — instant height (outer body animates); holds
                            // the three page Columns, only the active one visible.
                            Item {
                                id: pageBody
                                width: parent.width; clip: true
                                opacity: 0.25 + 0.75 * root.pageIn
                                transform: Translate { x: (1 - root.pageIn) * 30 * root.pageDir }

                                // Sliding paper selector under the hovered clickable row
                                // (springs between rows, two afterimages trailing)
                                Item {
                                    id: rowSel
                                    z: -1
                                    property Item row: null
                                    property real ty: 0
                                    property real th: 14
                                    x: -4; width: parent.width + 8
                                    opacity: row ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 160 } }
                                    Rectangle {
                                        width: parent.width; height: rowSel.th; color: root.cText; opacity: 0.10
                                        y: rowSel.ty
                                        Behavior on y { SpringAnimation { spring: 2.2; damping: 0.36; epsilon: 0.3 } }
                                    }
                                    Rectangle {
                                        width: parent.width; height: rowSel.th; color: root.cText; opacity: 0.22
                                        y: rowSel.ty
                                        Behavior on y { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.3 } }
                                    }
                                    Item {
                                        width: parent.width; height: rowSel.th
                                        y: rowSel.ty
                                        Behavior on y { SpringAnimation { spring: 5.5; damping: 0.30; epsilon: 0.25 } }
                                        Behavior on height { NumberAnimation { duration: 120 } }
                                        Rectangle { anchors.fill: parent; color: root.cText }
                                        Rectangle { width: 2; height: parent.height; color: root.cRed }
                                    }
                                    Connections {
                                        target: root
                                        function onRowHot(row, on) {
                                            if (!row || row.Window.window !== rowSel.Window.window) return
                                            if (on) {
                                                var p = row.mapToItem(pageBody, 0, 0)
                                                rowSel.th = row.height + 4
                                                rowSel.ty = p.y - 2
                                                rowSel.row = row
                                            } else if (rowSel.row === row) rowSel.row = null
                                        }
                                    }
                                }
                                implicitHeight: root.statsPage === 0 ? pgStatus.implicitHeight
                                              : root.statsPage === 1 ? pgInfo.implicitHeight
                                                                     : pgTools.implicitHeight

                                // ── PAGE 0 · STATUS (system / media / network) ──
                                Column {
                                    id: pgStatus
                                    width: parent.width; spacing: 7
                                    visible: root.statsPage === 0

                                    Section { label: "SYSTEM" }
                                    StatRow { sLabel: "CPU"; sVal: Sys.cpuPct + "%"; sFill: Sys.cpuPct/100
                                              sColor: Sys.cpuPct>80 ? root.cWarn : root.cText }
                                    StatRow { visible: Sys.gpuAvailable
                                              sLabel: "GPU"; sVal: Sys.gpuPct.toFixed(0)+"%"; sFill: Sys.gpuPct/100
                                              sColor: Sys.gpuPct>80 ? root.cWarn : root.cText }
                                    StatRow { sLabel: "MEM"; sVal: Sys.memPct + "%"; sFill: Sys.memPct/100
                                              sColor: Sys.memPct>85 ? root.cWarn : root.cText }
                                    InfoRow { visible: Sys.topName !== ""
                                              iLabel: "TOP"; iVal: Sys.topName + "  " + Sys.topPct.toFixed(0)+"%"
                                              iColor: root.cMuted }

                                    // MEDIA / POWER  (scroll VOL/BRI to adjust, click VOL to mute)
                                    Section { label: "MEDIA" }
                                    StatRow { sLabel: "VOL"; interactive: true
                                              sVal: Audio.muted ? "mute" : Math.round(Audio.volume/1.5*100)+"%"
                                              sFill: Audio.muted ? 0 : Audio.volume/1.5
                                              sColor: Audio.muted ? root.cMuted : root.cText
                                              onSetFrac: (f) => Audio.setVolume(f*1.5)
                                              onStep: (d) => Audio.setVolume(Audio.volume + d*0.05*1.5)
                                              onTapped: Audio.toggleMute()
                                              onDoubleTapped: root.run("pavucontrol") }
                                    StatRow { visible: Backlight.available
                                              sLabel: "BRI"; interactive: true
                                              sVal: Math.round(Backlight.value*100)+"%"; sFill: Backlight.value
                                              sColor: root.cText
                                              onSetFrac: (f) => Backlight.set(f)
                                              onStep: (d) => Backlight.set(Backlight.value + d*0.05) }
                                    StatRow { visible: Battery.available
                                              sLabel: "BAT"
                                              sVal: (Battery.charging ? "⚡" : "") + Math.round(Battery.percent)+"%"
                                              sFill: Battery.percent/100
                                              sColor: Battery.percent<20 ? root.cWarn : root.cGood }

                                    // NETWORK  (click a row → nm-connection-editor)
                                    Section { label: "NETWORK ⚙" }
                                    InfoRow { visible: Net.ethOn; clickable: true
                                              iLabel: "ETH"; iVal: Net.ethIP || "connected"; iColor: root.cGood
                                              onClicked: root.run("nm-connection-editor") }
                                    InfoRow { visible: !Net.ethOn; clickable: true
                                              iLabel: Net.wifiOn ? "WIFI" : "NET"
                                              iVal:   Net.wifiOn ? (Net.wifiSSID + "  " + Net.wifiSig + "%") : "offline"
                                              iColor: Net.wifiOn ? root.cGood : root.cMuted
                                              onClicked: root.run("nm-connection-editor") }
                                    InfoRow { visible: !Net.ethOn && Net.wifiOn && Net.wifiIP !== ""; clickable: true
                                              iLabel: "IP"; iVal: Net.wifiIP; iColor: root.cMuted
                                              onClicked: root.run("nm-connection-editor") }
                                    // BT — always shown; click opens the bluetooth GUI.
                                    InfoRow { clickable: true
                                              iLabel: "BT"
                                              iVal: Net.btOn ? (Net.btDev !== ""
                                                        ? Net.btDev + (Net.btBat ? "  " + Net.btBat : "")
                                                        : "on")
                                                    : "off"
                                              iColor: Net.btOn ? root.cText : root.cMuted
                                              onClicked: root.run("blueman-manager || blueberry || overskride") }
                                }

                                // ── PAGE 1 · INFO (weather / calendar / todo) ──
                                Column {
                                    id: pgInfo
                                    width: parent.width; spacing: 7
                                    visible: root.statsPage === 1

                                    Section { label: "WEATHER"; visible: Weather.ready }
                                    InfoRow { visible: Weather.ready
                                              iLabel: Weather.icon; iVal: Weather.temp + "  " + Weather.desc
                                              iColor: root.cText }
                                    Row {
                                        visible: Weather.ready && Weather.forecast.length > 0
                                        width: parent.width; spacing: 0
                                        Repeater {
                                            model: Weather.forecast
                                            Column {
                                                width: pgInfo.width / 3; spacing: 1
                                                Text { text: modelData.date; font.family: root.mono; font.pixelSize: 8
                                                       color: root.cMuted; anchors.horizontalCenter: parent.horizontalCenter }
                                                Text { text: modelData.icon; font.family: root.mono; font.pixelSize: 13
                                                       color: root.cText; anchors.horizontalCenter: parent.horizontalCenter }
                                                Text { text: modelData.max + "/" + modelData.min; font.family: root.mono
                                                       font.pixelSize: 8; color: root.cText
                                                       anchors.horizontalCenter: parent.horizontalCenter }
                                            }
                                        }
                                    }

                                    // CALENDAR — honkai month artwork + LIVE, year-aware
                                    // day numbers overlaid on the template grid. Numbers
                                    // are computed from the date every render (never baked),
                                    // so the calendar self-corrects every year. Click a day
                                    // to view that day's events/tasks below.
                                    // month header: label (slides with the artwork) · ‹ › diamond buttons
                                    Item {
                                        width: parent.width; height: 15
                                        Text {
                                            y: 0
                                            text: root.monthNames[root.calMonth] + " " + root.calYear
                                            font.pixelSize: 8; font.weight: Font.Medium; font.letterSpacing: 2.5
                                            color: root.paperA(0.72)
                                            opacity: 1 - root.calOut
                                            transform: Translate { x: root.calSlide }
                                        }
                                        Rectangle { y: 12; width: 18; height: 1; color: root.paperA(0.45) }
                                        Row {
                                            anchors.right: parent.right; anchors.rightMargin: 2
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 9
                                            Repeater {
                                                model: [-1, 1]
                                                Item {
                                                    id: navBtn
                                                    required property int modelData
                                                    width: 12; height: 12
                                                    Rectangle {
                                                        anchors.centerIn: parent; width: 9; height: 9; rotation: 45; antialiasing: true
                                                        color: navMA.containsMouse ? root.cText : "transparent"
                                                        border.color: navMA.containsMouse ? root.cText : root.paperA(0.55); border.width: 1
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent; anchors.verticalCenterOffset: -1
                                                        text: navBtn.modelData < 0 ? "‹" : "›"
                                                        font.pixelSize: 10; color: navMA.containsMouse ? root.cInk : root.cText
                                                    }
                                                    MouseArea {
                                                        id: navMA
                                                        anchors.fill: parent; anchors.margins: -3
                                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: { root.hit(navBtn, 0.4); root.calNav(navBtn.modelData) }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Item {
                                        id: calImg
                                        // clean template is 1408x3054. calImg is a CLIP VIEWPORT cropped to
                                        // cropFrac of the full image height (drops the footer/COGNOSPHERE
                                        // watermark); the artwork + overlays are laid out at the FULL display
                                        // height (fullH) anchored to the top, and the bottom is clipped away.
                                        readonly property real imgW: 1408
                                        readonly property real imgH: 3054
                                        readonly property real fullH: width * imgH / imgW   // full image height (no crop)
                                        width: parent.width
                                        height: fullH
                                        // positions are fractions of the FULL image (width / fullH)
                                        function colFrac(i) { return 0.16889 + i * 0.11243 }   // Sun..Sat
                                        function rowFrac(w) { return 0.76752 + w * 0.03222 }   // week 0..5
                                        // scroll over the image to change month
                                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; hoverEnabled: true
                                                    onWheel: (w) => root.calNav(w.angleDelta.y < 0 ? 1 : -1) }

                                        // viewport: the artwork + day numbers slide / fade on a month change
                                        Item {
                                            id: calArt
                                            anchors.fill: parent
                                            clip: true
                                            Item {
                                                width: parent.width; height: calImg.fullH
                                                opacity: 1 - root.calOut
                                                transform: Translate { x: root.calSlide }

                                        // calendar artwork at full height (overflows the clip at the bottom),
                                        // top + a small bottom edge feathered so it melts into the background.
                                        Image {
                                            id: calBg
                                            width: parent.width; height: calImg.fullH
                                            anchors.top: parent.top
                                            visible: false; layer.enabled: true
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true; cache: true; smooth: true; mipmap: true
                                            sourceSize.width: Math.round(width * 2)
                                            source: Qt.resolvedUrl("../assets/cal/month" + (root.calMonth + 1) + ".jpg")
                                        }
                                        Rectangle {
                                            id: calMask
                                            width: parent.width; height: calImg.fullH
                                            anchors.top: parent.top
                                            visible: false; layer.enabled: true
                                            // transparent-black edges → opaque-white middle (feathers whether
                                            // MultiEffect samples alpha or luminance). Bottom fade sits just
                                            // below the last week row, right at the crop line.
                                            gradient: Gradient {
                                                GradientStop { position: 0.00; color: "#00000000" }
                                                GradientStop { position: 0.05; color: "#ffffffff" }
                                                GradientStop { position: 0.96; color: "#ffffffff" }
                                                GradientStop { position: 1.00; color: "#00000000" }
                                            }
                                        }
                                        MultiEffect {
                                            width: parent.width; height: calImg.fullH
                                            anchors.top: parent.top
                                            source: calBg
                                            maskEnabled: true
                                            maskSource: calMask
                                        }

                                        // live day-number overlay (positioned on the full-height image)
                                        Repeater {
                                            model: root.daysInMonth(root.calYear, root.calMonth)
                                            Item {
                                                id: dcell
                                                readonly property int  day:  index + 1
                                                readonly property int  idx:  root.firstDOW(root.calYear, root.calMonth) + index
                                                readonly property real cx:   calImg.colFrac(idx % 7) * calImg.width
                                                readonly property real cy:   calImg.rowFrac(Math.floor(idx / 7)) * calImg.fullH
                                                readonly property bool isToday: day === root.todayDay
                                                                                && root.calMonth === root.todayMonth
                                                                                && root.calYear === root.todayYear
                                                readonly property bool isSel: day === root.calSelDay
                                                readonly property bool hasEv: Cal.eventsOn(root.dateStr(root.calYear, root.calMonth, day)).length > 0
                                                width:  0.11243 * calImg.width; height: 0.03222 * calImg.fullH
                                                x: cx - width / 2;  y: cy - height / 2
                                                // selected = filled ◆ · today = light ◇ (both when it's today and picked)
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width:  Math.min(parent.width, parent.height) * 0.95
                                                    height: width; rotation: 45; antialiasing: true
                                                    color: dcell.isSel ? root.cAccent : "transparent"
                                                    border.color: dcell.isToday ? root.cAccent : "transparent"
                                                    border.width: 1.2
                                                    scale: dcell.isSel ? 1 : 0.9
                                                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                                                }
                                                Text {
                                                    anchors.centerIn: parent; text: dcell.day
                                                    font.family: root.mono; font.bold: dcell.isToday || dcell.isSel
                                                    font.pixelSize: Math.max(8, Math.round(parent.height * 0.7))
                                                    color: dcell.isSel ? root.cInk : "#f3ecd8"
                                                }
                                                // event marker: a tiny ◆ under the number
                                                Rectangle {
                                                    visible: dcell.hasEv && !dcell.isSel
                                                    width: 3; height: 3; rotation: 45; antialiasing: true; color: root.cAccent
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 1
                                                }
                                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            onClicked: { root.hit(dcell, 0.4); root.calSelDay = dcell.day } }
                                            }
                                        }

                                            }
                                        }

                                        // paper hairline frame + diamond corners (static while the art slides)
                                        Rectangle {
                                            anchors.fill: parent; color: "transparent"
                                            border.color: root.paperA(0.4); border.width: 1
                                        }
                                        Repeater {
                                            model: 4
                                            Rectangle {
                                                width: 5; height: 5; rotation: 45; antialiasing: true; color: root.cGold
                                                x: (index % 2 === 0 ? 0 : calImg.width) - 2.5
                                                y: (index < 2 ? 0 : calImg.height) - 2.5
                                            }
                                        }

                                        // month nav — invisible hotspots over the crescent-moon
                                        // ornaments on each frame side (left = prev, right = next).
                                        Repeater {
                                            model: [ { f: 0.045, d: -1 }, { f: 0.955, d: 1 } ]
                                            Rectangle {
                                                required property var modelData
                                                width: calImg.width * 0.13; height: calImg.fullH * 0.065
                                                radius: width / 2
                                                x: calImg.width * modelData.f - width / 2
                                                y: calImg.fullH * 0.843 - height / 2
                                                color: moonMa.pressed ? Theme.alpha(Theme.light, 0.18) : "transparent"
                                                MouseArea {
                                                    id: moonMa
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.calNav(parent.modelData.d)
                                                }
                                            }
                                        }
                                    }

                                    // selected-day detail: that day's events + due tasks
                                    Text {
                                        width: pgInfo.width
                                        text: root.monthNames[root.calMonth] + " " + root.calSelDay
                                        font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1.5; color: root.cAccent
                                    }
                                    Repeater {
                                        model: Cal.eventsOn(root.dateStr(root.calYear, root.calMonth, root.calSelDay))
                                        Row {
                                            width: pgInfo.width; spacing: 5
                                            Rectangle { width: 4; height: 4; rotation: 45; antialiasing: true; color: root.cAccent
                                                        anchors.verticalCenter: parent.verticalCenter }
                                            Text { text: modelData.time !== "" ? modelData.time : "all-day"
                                                   font.family: root.mono; font.pixelSize: 8; color: root.cMuted; width: 44 }
                                            Text { text: modelData.title; font.family: root.mono; font.pixelSize: 8
                                                   color: root.cText; elide: Text.ElideRight; width: pgInfo.width - 58 }
                                        }
                                    }
                                    Text {
                                        visible: Cal.eventsOn(root.dateStr(root.calYear, root.calMonth, root.calSelDay)).length === 0
                                        text: "◇ NO EVENTS ◇"; font.pixelSize: 7; font.letterSpacing: 2.5; color: root.cMuted
                                    }
                                    // tasks due on the selected day (Google Tasks)
                                    Repeater {
                                        model: Tasks.tasksOn(root.dateStr(root.calYear, root.calMonth, root.calSelDay))
                                        Row {
                                            width: pgInfo.width; spacing: 5
                                            Item {   // task: ◇ open · ◆ done (sage)
                                                width: 12; height: 10; anchors.verticalCenter: parent.verticalCenter
                                                Rectangle { anchors.centerIn: parent; width: 5; height: 5; rotation: 45; antialiasing: true
                                                            color: modelData.done ? root.cGood : "transparent"
                                                            border.color: modelData.done ? root.cGood : root.cAccent; border.width: 1 }
                                            }
                                            Text { text: modelData.title; font.family: root.mono; font.pixelSize: 8
                                                   color: root.cText; elide: Text.ElideRight; width: pgInfo.width - 18
                                                   font.strikeout: modelData.done }
                                        }
                                    }

                                    // TODO — click header to toggle edit. Read view renders
                                    // basic markdown; edit view is a raw TextEdit saved live.
                                    Section { label: root.todoEditing ? "TODO  ✓ done" : "TODO  ✎ edit"
                                              clickable: true
                                              onClicked: {
                                                  if (root.todoEditing) {           // finishing edit
                                                      root.writeTodo(todoEd.text)
                                                      root.todoEditing = false
                                                  } else {                          // start edit
                                                      root.todoEditing = true
                                                      todoEd.text = todoView.fullText
                                                      todoEd.forceActiveFocus()
                                                  }
                                              } }
                                    // read view (markdown)
                                    Text {
                                        visible: !root.todoEditing
                                        width: pgInfo.width
                                        text: todoView.fullText !== "" ? todoView.fullText : "_(empty)_"
                                        textFormat: Text.MarkdownText
                                        font.family: root.mono; font.pixelSize: 9
                                        color: root.cText; wrapMode: Text.Wrap
                                        onLinkActivated: (l) => root.run("xdg-open '" + l + "'")
                                    }
                                    // edit view (raw markdown)
                                    Rectangle {
                                        visible: root.todoEditing
                                        width: pgInfo.width; height: todoEd.implicitHeight + 10
                                        color: root.paperA(0.07)
                                        border.color: root.cBorder; border.width: 1
                                        TextEdit {
                                            id: todoEd
                                            anchors.fill: parent; anchors.margins: 5
                                            font.family: root.mono; font.pixelSize: 9
                                            color: root.cText; selectionColor: root.cAccent; selectedTextColor: root.cInk
                                            wrapMode: TextEdit.Wrap
                                            textFormat: TextEdit.PlainText
                                            // save shortly after typing stops
                                            onTextChanged: if (root.todoEditing) todoSaveT.restart()
                                            // Esc → save immediately and leave edit mode
                                            Keys.onPressed: (e) => {
                                                if (e.key === Qt.Key_Escape) {
                                                    root.writeTodo(todoEd.text)
                                                    root.todoEditing = false
                                                    e.accepted = true
                                                }
                                            }
                                        }
                                        Timer { id: todoSaveT; interval: 600; onTriggered: root.writeTodo(todoEd.text) }
                                    }
                                }

                                // ── PAGE 2 · TOOLS (stopwatch / claude usage) ──
                                Column {
                                    id: pgTools
                                    width: parent.width; spacing: 7
                                    visible: root.statsPage === 2

                                    Section { label: "STOPWATCH" }
                                    Row {
                                        width: parent.width; spacing: 8
                                        Text {
                                            text: root.swFmt(root.swElapsed); font.family: root.mono; font.pixelSize: 16
                                            color: root.swGo ? root.cAccent : root.cText
                                            anchors.verticalCenter: parent.verticalCenter; width: 78
                                        }
                                        HudBtn { bLabel: root.swGo ? "STOP" : "START"
                                                 bColor: root.swGo ? root.cWarn : root.cText
                                                 onClicked: root.swGo = !root.swGo }
                                        HudBtn { bLabel: "RST"; bColor: root.cMuted
                                                 onClicked: { root.swGo = false; root.swElapsed = 0 } }
                                    }

                                    // CLAUDE usage
                                    Section { label: "CLAUDE"; visible: ClaudeUsage.ready }
                                    InfoRow { visible: ClaudeUsage.ready; iLabel: "today"
                                              iVal: ClaudeUsage.todayCost + "  " + ClaudeUsage.todayTok; iColor: root.cText }
                                    InfoRow { visible: ClaudeUsage.ready; iLabel: "week"
                                              iVal: ClaudeUsage.weekCost + "  " + ClaudeUsage.weekTok; iColor: root.cMuted }
                                    InfoRow { visible: ClaudeUsage.ready; iLabel: "month"
                                              iVal: ClaudeUsage.monthCost + "  " + ClaudeUsage.monthTok; iColor: root.cMuted }
                                }
                            }
                        }

                        // ── WORKSPACE view ──
                        Column {
                            id: wspView
                            width: parent.width; y: 8; spacing: 8
                            visible: win.showWsp
                            opacity: win.showWsp ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 220 } }

                            // 5×5 grid — ws 1..25 (cols = ±1, rows = ±5). Open workspaces are
                            // framed in their monitor's tint, the current one is filled, unopened
                            // ones are a ◇. A light frame springs between cells under the pointer
                            // (two afterimages trailing); a click throws the burst.
                            Item {
                                id: wspBox
                                width: wspGrid.width; height: wspGrid.height
                                anchors.horizontalCenter: parent.horizontalCenter
                                readonly property real cellH: 18
                                function cellPos(id) {
                                    var c = (id - 1) % 5, r = 4 - Math.floor((id - 1) / 5)
                                    return Qt.point(c * (wspGrid.cell + 4), r * (cellH + 4))
                                }
                                readonly property point selAt: cellPos(win.hoveredWs > 0 ? win.hoveredWs : Math.max(1, Math.min(25, win.wsId)))

                            Grid {
                                id: wspGrid
                                columns: 5; rowSpacing: 4; columnSpacing: 4
                                property real cell: (wspView.width - 4*4) / 5
                                Repeater {
                                    model: 25
                                    Rectangle {
                                        id: wsCell
                                        required property int index
                                        // rows reversed: 21-25 on top, 1-5 on bottom
                                        readonly property int wsid: (4 - Math.floor(index/5))*5 + (index%5) + 1
                                        readonly property int  monIdx: root.wsMonIdx(wsid)   // -1 if not open
                                        readonly property bool exists: monIdx >= 0
                                        readonly property bool active: root.wsIsActive(wsid) // active on its monitor
                                        // open workspaces are tinted by which monitor they live on
                                        readonly property color monColor: exists ? root.monColors[monIdx % root.monColors.length]
                                                                                  : root.cMuted
                                        width: wspGrid.cell; height: wspBox.cellH
                                        color: active ? monColor : "transparent"
                                        border.width: 1
                                        border.color: exists ? monColor : root.paperA(0.12)
                                        Behavior on color { ColorAnimation { duration: 160 } }
                                        // open → number (monitor-tinted; ink on the filled current one)
                                        Text {
                                            visible: wsCell.exists
                                            anchors.centerIn: parent
                                            text: wsCell.wsid
                                            font.family: root.mono; font.pixelSize: 9
                                            color: wsCell.active ? root.cInk : wsCell.monColor
                                        }
                                        // unopened → ◇
                                        Rectangle {
                                            visible: !wsCell.exists
                                            anchors.centerIn: parent
                                            width: 5; height: 5; rotation: 45; antialiasing: true
                                            color: "transparent"
                                            border.color: cellMA.containsMouse ? root.cAccent : root.paperA(0.38); border.width: 1
                                        }
                                        MouseArea {
                                            id: cellMA; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: win.hoveredWs = wsCell.wsid
                                            onExited:  if (win.hoveredWs === wsCell.wsid) win.hoveredWs = -1
                                            onClicked: { root.hit(wsCell, 0.55); Hyprland.dispatch('hl.dsp.focus({ workspace = "' + wsCell.wsid + '" })') }   // Lua-config dispatch syntax
                                        }
                                    }
                                }
                            }

                                // the sliding frame (+ afterimages) over the hovered cell
                                Repeater {
                                    model: [ { a: 0.18, k: 2.2, d: 0.36 }, { a: 0.35, k: 3.4, d: 0.34 }, { a: 1.0, k: 5.5, d: 0.30 } ]
                                    Rectangle {
                                        required property var modelData
                                        width: wspGrid.cell + 4; height: wspBox.cellH + 4
                                        x: wspBox.selAt.x - 2; y: wspBox.selAt.y - 2
                                        Behavior on x { SpringAnimation { spring: modelData.k; damping: modelData.d; epsilon: 0.25 } }
                                        Behavior on y { SpringAnimation { spring: modelData.k; damping: modelData.d; epsilon: 0.25 } }
                                        color: "transparent"
                                        border.color: root.cAccent; border.width: modelData.a === 1.0 ? 1.5 : 1
                                        opacity: win.hoveredWs > 0 ? modelData.a : 0
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }
                                }
                            }

                            // content of the hovered / current ws
                            Column {
                                width: parent.width; spacing: 2
                                Rectangle { width: parent.width; height: 1; color: root.cBorder }
                                Text {
                                    text: "ws·" + win.displayWs + "  ·  " + root.windowsFor(win.displayWs).length + " win"
                                    font.family: root.mono; font.pixelSize: 8; font.letterSpacing: 1
                                    color: root.cMuted; topPadding: 2
                                }
                                Repeater {
                                    model: root.windowsFor(win.displayWs).slice(0, 5)
                                    Row {
                                        width: wspView.width; spacing: 6
                                        Rectangle { width: 4; height: 4; rotation: 45; antialiasing: true; color: root.cAccent
                                                    anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: modelData.cls; font.family: root.mono; font.pixelSize: 9
                                               color: root.cText; width: 54; elide: Text.ElideRight
                                               anchors.verticalCenter: parent.verticalCenter }
                                        Text { text: modelData.title; font.family: root.mono; font.pixelSize: 9
                                               color: root.cMuted; elide: Text.ElideRight
                                               width: wspView.width - 70
                                               anchors.verticalCenter: parent.verticalCenter }
                                    }
                                }
                                Text {
                                    visible: root.windowsFor(win.displayWs).length === 0
                                    text: "◇ EMPTY ◇"; font.pixelSize: 8; font.letterSpacing: 2.5
                                    color: root.cMuted
                                }
                            }
                        }
                    }
                }

            }

            // Diamond corners — outside the frame's clip, riding its slide + fade
            Repeater {
                model: 4
                Rectangle {
                    width: 5; height: 5; rotation: 45; antialiasing: true
                    color: root.cGold
                    x: frame.x + (index % 2 === 0 ? 0 : frame.width) - 2.5
                    y: frame.y + (index < 2 ? 0 : frame.height) - 2.5
                    opacity: frame.opacity
                    transform: Translate { x: win.shown ? 0 : (frame.width + 24)
                        Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } } }
                }
            }

            // Confirm burst for clicks (components/HitBurst.qml), shrunk for a small widget
            HitBurst { id: hudBurst; z: 100; scale: 0.62 }
            Connections {
                target: root
                function onHitAt(item, strength) {
                    if (!item || item.Window.window !== hudBurst.Window.window) return
                    hudBurst.playAt(item, item.width / 2, item.height / 2, strength)
                }
            }
        }
    }

    // ── Reusable stat row: label · bar · [− +] · value ──
    // Interactive rows: drag/click the bar to set the level (setFrac), −/+ buttons
    // step it (step), click the label to toggle (tapped), double-click the bar
    // (doubleTapped). WheelHandler was dropped — wheel events never reach this
    // layer surface here, so the −/+ buttons are the reliable fine-adjust.
    component StatRow: Item {
        id: sr
        property string sLabel: ""
        property string sVal:   ""
        property real   sFill:  0
        property color  sColor: Theme.panelText
        property bool   interactive: false
        signal tapped()             // label clicked (e.g. mute)
        signal setFrac(real f)      // bar clicked/dragged → 0..1
        signal step(real dir)       // −/+ buttons (+1 / −1)
        signal doubleTapped()       // double-click bar (e.g. open mixer)
        width: parent ? parent.width : 160
        height: interactive ? 18 : 14
        // hovered (interactive rows): the page's paper selector slides under it
        readonly property bool hot: interactive && srWheel.containsMouse
        onHotChanged: root.rowHot(sr, hot)
        readonly property color ink: root.cInk

        Text {
            id: srLabel
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: sLabel; font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1
            color: sr.hot ? sr.ink : root.cMuted; width: 26
            Behavior on color { ColorAnimation { duration: 120 } }
            MouseArea { enabled: sr.interactive; anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor; onClicked: { root.hit(srLabel, 0.45); sr.tapped() } }
        }
        Text {
            id: srVal
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: sVal; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            color: sr.hot ? sr.ink : sColor; horizontalAlignment: Text.AlignRight; width: 40
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        // the popups' slider in small: frame + inset fill (interactive rows get the inner frame too)
        Rectangle {
            id: srBar
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: srLabel.right; anchors.leftMargin: 4
            anchors.right: srVal.left; anchors.rightMargin: 6
            height: sr.interactive ? 9 : 5
            color: "transparent"
            border.color: sr.hot ? Theme.alpha(Theme.panelRaised, 0.6) : root.paperA(sr.interactive ? 0.45 : 0.22)
            border.width: 1
            Rectangle {
                visible: sr.interactive
                anchors.fill: parent; anchors.margins: 2; color: "transparent"
                border.color: sr.hot ? Theme.alpha(Theme.panelRaised, 0.25) : root.paperA(0.15); border.width: 1
            }
            Rectangle {
                readonly property real m: sr.interactive ? 2 : 1
                x: m; y: m; height: parent.height - 2 * m
                width: (parent.width - 2 * m) * Math.max(0, Math.min(1, sFill))
                color: sr.hot ? sr.ink : sColor
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            }
            // drag/click to set — top-most child of the bar so it gets events
            MouseArea {
                enabled: sr.interactive
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                function apply(mx) { sr.setFrac(Math.max(0, Math.min(1, mx / width))) }
                onPressed: (e) => apply(e.x)
                onPositionChanged: (e) => { if (pressed) apply(e.x) }
                onDoubleClicked: sr.doubleTapped()
            }
        }

        // wheel-to-step over the whole row. THIS is the working scroll mechanism
        // (MouseArea.onWheel — same as TopBar): wheel does reach the layer surface,
        // the earlier WheelHandler just didn't. acceptedButtons: NoButton so it
        // only takes wheel/hover and lets clicks/drags fall through to the rows below.
        MouseArea {
            id: srWheel
            enabled: sr.interactive
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onWheel: (w) => { sr.step(w.angleDelta.y > 0 ? 1 : -1) }
        }
    }


    // ── Section header: letter-spaced label + a short rule under it (the popups'
    // h3), optionally clickable ──
    component Section: Item {
        id: sec
        property string label: ""
        property bool   clickable: false
        signal clicked()
        width: parent ? parent.width : 160
        height: 15
        Text {
            id: secLbl
            y: 0
            text: label; font.pixelSize: 8; font.weight: Font.Medium; font.letterSpacing: 2.5
            color: secMA.containsMouse ? root.cAccent : root.paperA(0.72)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Rectangle { y: 12; width: 18; height: 1; color: root.paperA(0.45) }
        MouseArea {
            id: secMA
            enabled: sec.clickable
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.hit(secLbl, 0.4); sec.clicked() }
        }
    }

    // ── Info row: label · value (no bar), optionally clickable ──
    component InfoRow: Item {
        id: ir
        property string iLabel: ""
        property string iVal:   ""
        property color  iColor: Theme.panelText
        property bool   clickable: false
        signal clicked()
        width: parent ? parent.width : 160
        height: 13
        readonly property bool hot: clickable && irMA.containsMouse
        onHotChanged: root.rowHot(ir, hot)
        Text {
            id: infoL
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: iLabel; font.family: root.mono; font.pixelSize: 9
            color: ir.hot ? root.cInk : root.cMuted
            Behavior on color { ColorAnimation { duration: 120 } }
            width: 34; elide: Text.ElideRight
        }
        Text {
            anchors { left: infoL.right; right: parent.right; verticalCenter: parent.verticalCenter }
            text: iVal; font.family: root.mono; font.pixelSize: 9
            color: ir.hot ? root.cInk : iColor
            Behavior on color { ColorAnimation { duration: 120 } }
            elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
        }
        // top-most so clicks register (same pattern as the working grid cells)
        MouseArea {
            id: irMA
            enabled: ir.clickable
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.hit(infoL, 0.35); ir.clicked() }
        }
    }

    // ── Small button (stopwatch controls) ──
    component HudBtn: Rectangle {
        id: hb
        property string bLabel: ""
        property color  bColor: Theme.panelText
        signal clicked()
        width: btxt.implicitWidth + 16; height: 18
        color: btnMA.containsMouse ? bColor : "transparent"
        border.color: bColor; border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Rectangle {   // accent edge while hovered (the popups' selector edge)
            width: btnMA.containsMouse ? 2 : 0; height: parent.height; color: root.cRed
        }
        Text {
            id: btxt; anchors.centerIn: parent; text: bLabel
            font.family: root.mono; font.pixelSize: 8; font.letterSpacing: 1.5
            color: btnMA.containsMouse ? root.cInk : bColor
        }
        MouseArea { id: btnMA; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: { root.hit(hb, 0.5); hb.clicked() } }
    }

    // ── Page tab (as components/CatTab, in small and on ink): the picked tab fills
    // with paper along `dir` while the one being left drains the same way; the
    // label inverts along the moving edge; the marker turns from a dash into a ◆ ──
    component HudTab: Item {
        id: tab
        property string label: ""
        property bool   active: false
        property int    dir: 1
        signal clicked()
        // fill span as fractions of the width (the tabs are laid out after they're
        // created, so pixel targets taken at that point would be stale)
        property real fL: 0
        property real fR: active ? 1 : 0
        NumberAnimation { id: fillIn;  target: tab; duration: 280; easing.type: Easing.OutCubic }
        NumberAnimation { id: fillOut; target: tab; duration: 220; easing.type: Easing.InOutCubic }
        onActiveChanged: {
            fillIn.stop(); fillOut.stop()
            if (active) {
                if (dir > 0) { fL = 0; fR = 0; fillIn.property = "fR" }
                else         { fL = 1; fR = 1; fillIn.property = "fL" }
                fillIn.to = dir > 0 ? 1 : 0
                fillIn.start()
                tabPick.restart()
            } else {
                fillOut.property = dir > 0 ? "fL" : "fR"
                fillOut.to = dir > 0 ? 1 : 0
                fillOut.start()
            }
        }
        Rectangle {
            anchors.fill: parent; color: tabMA.containsMouse && !tab.active ? root.paperA(0.08) : "transparent"
            border.color: root.cBorder; border.width: 1
        }
        HudTabFace { anchors.fill: parent; label: tab.label; hovered: tabMA.containsMouse }
        Item {   // paper fill + inked label, clipped to fL..fR
            x: tab.fL * tab.width; width: Math.max(0, tab.fR - tab.fL) * tab.width; height: parent.height
            clip: true
            Rectangle { anchors.fill: parent; color: root.cText }
            HudTabFace { x: -tab.fL * tab.width; width: tab.width; height: tab.height; label: tab.label; inked: true }
            Rectangle { x: -tab.fL * tab.width; width: 2; height: parent.height; color: root.cRed }
        }
        Rectangle {   // marker: dash ⇄ diamond
            id: tabGem
            x: 7 - width / 2; anchors.verticalCenter: parent.verticalCenter
            width:  tab.active ? 4 : 4
            height: tab.active ? 4 : 1
            rotation: tab.active ? (tab.dir > 0 ? 225 : -135) : 0
            color: tab.active ? root.cInk : root.cMuted
            antialiasing: true
            Behavior on height   { NumberAnimation { duration: 220; easing.type: Easing.OutQuart } }
            Behavior on rotation { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on color    { ColorAnimation  { duration: 160 } }
        }
        SequentialAnimation {
            id: tabPick
            NumberAnimation { target: tabGem; property: "scale"; from: 0.3; to: 1.6; duration: 150; easing.type: Easing.OutQuad }
            NumberAnimation { target: tabGem; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
        }
        MouseArea { id: tabMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: tab.clicked() }
    }
    component HudTabFace: Item {
        property string label: ""
        property bool   hovered: false
        property bool   inked: false
        Text {
            x: 12; width: parent.width - 14; anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            text: parent.label; font.pixelSize: 7; font.weight: Font.Medium; font.letterSpacing: 1.5
            color: parent.inked ? root.cInk : (parent.hovered ? root.cText : root.cMuted)
        }
    }

    // ── Vector speaker icon (Canvas) — themeable, no emoji ──
    component SpeakerIcon: Canvas {
        property color color: Theme.light
        property bool  muted: false
        implicitWidth: 16; implicitHeight: 14
        onColorChanged: requestPaint()
        onMutedChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            ctx.fillStyle = color; ctx.strokeStyle = color
            ctx.lineWidth = 1.3; ctx.lineCap = "round"
            // cone
            ctx.beginPath()
            ctx.moveTo(1,5); ctx.lineTo(4,5); ctx.lineTo(7,2)
            ctx.lineTo(7,12); ctx.lineTo(4,9); ctx.lineTo(1,9); ctx.closePath(); ctx.fill()
            if (muted) {
                ctx.beginPath(); ctx.moveTo(9.5,4); ctx.lineTo(14,10)
                ctx.moveTo(14,4); ctx.lineTo(9.5,10); ctx.stroke()
            } else {
                ctx.beginPath(); ctx.arc(8,7,3,   -0.85, 0.85); ctx.stroke()
                ctx.beginPath(); ctx.arc(8,7,5.5, -0.8,  0.8 ); ctx.stroke()
            }
        }
    }

    // ── Vector 4-point star (Canvas) — for unopened workspaces ──
    component StarIcon: Canvas {
        property color color: Theme.light
        implicitWidth: 12; implicitHeight: 12
        onColorChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            ctx.fillStyle = color
            var cx = width/2, cy = height/2, R = Math.min(width,height)/2 - 0.5, r = R*0.32
            ctx.beginPath()
            for (var i = 0; i < 8; i++) {
                var a = -Math.PI/2 + i * Math.PI/4
                var rad = (i % 2 === 0) ? R : r
                var x = cx + Math.cos(a)*rad, y = cy + Math.sin(a)*rad
                if (i === 0) ctx.moveTo(x,y); else ctx.lineTo(x,y)
            }
            ctx.closePath(); ctx.fill()
        }
    }

    // ── Vector sun icon (Canvas) ──
    component SunIcon: Canvas {
        property color color: Theme.light
        implicitWidth: 16; implicitHeight: 14
        onColorChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            ctx.strokeStyle = color; ctx.fillStyle = color
            ctx.lineWidth = 1.2; ctx.lineCap = "round"
            var cx = 8, cy = 7
            ctx.beginPath(); ctx.arc(cx, cy, 2.6, 0, 2*Math.PI); ctx.fill()
            for (var i = 0; i < 8; i++) {
                var a = i * Math.PI / 4
                ctx.beginPath()
                ctx.moveTo(cx + Math.cos(a)*4.3, cy + Math.sin(a)*4.3)
                ctx.lineTo(cx + Math.cos(a)*6.2, cy + Math.sin(a)*6.2)
                ctx.stroke()
            }
        }
    }
}
