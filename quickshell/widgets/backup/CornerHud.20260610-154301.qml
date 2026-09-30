import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../components"
import "../services"
import "../settings"

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

    // ── YoRHa paper palette (matches TopBar / Menu) ──
    readonly property color cBg:     "#d6cfb5"
    readonly property color cSurf:   "#cbc4ab"
    readonly property color cText:   "#463f2e"
    readonly property color cMuted:  "#7a7358"
    readonly property color cAccent: "#6e2a2a"
    readonly property color cBorder: Qt.rgba(70/255, 63/255, 46/255, 0.25)
    readonly property color cGood:   "#2a5a3a"
    readonly property string mono:   "Share Tech Mono"

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

    // ── OSD: header briefly shows VOL/BRI while adjusting, then back to clock ──
    property string osdMode: ""   // "" | "vol" | "bri"
    property bool   _osdReady: false   // ignore the initial volume binding at startup
    property Timer _osdT:     Timer { interval: 1700; onTriggered: root.osdMode = "" }
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
    function cycleStatsPage(d) { statsPage = (statsPage + d + statsPageNames.length) % statsPageNames.length }
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
    readonly property var monColors: [cAccent, "#2a3a5a", cGood, "#7a4a20"]

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
            margins.top: 8; margins.right: 8
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.todoEditing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            // Window is a FIXED tall transparent surface; the frame animates its
            // height INSIDE it. This avoids resizing the layer surface every frame
            // during the expand animation (the buffer realloc was the jank). The
            // mask pins the input + visible region to the frame, so the empty area
            // is fully click-through and only the frame is interactive.
            implicitWidth:  frame.width + 16
            implicitHeight: modelData.height - 16
            // When hidden, collapse the input region to nothing so the area is
            // fully click-through (enabled:false alone keeps the surface eating
            // clicks). When shown, pin input + visible region to the frame.
            mask: Region { item: root.hudVisible ? frame : null }

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
            readonly property bool showStats: (statsExpanded || root.statsPinned) && !root.wspMode
            // which ws the content list describes: hovered cell, else current
            readonly property int  displayWs: hoveredWs > 0 ? hoveredWs : wsId

            // ── Frame ── (anchored to the TOP of the tall window)
            Rectangle {
                id: frame
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.frameW
                height: col.implicitHeight + 16
                color: root.cBg
                border.color: root.cText
                border.width: 1
                // whole-HUD show/hide: fade + disable input (enabled cascades to
                // every handler/MouseArea inside → a hidden HUD is click-through).
                opacity: root.hudVisible ? 1 : 0
                enabled: root.hudVisible
                Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                // faint vertical grid
                Row {
                    spacing: 15
                    Repeater { model: Math.floor(frame.width/16)+1
                        Rectangle { width:1; height:frame.height; color:Qt.rgba(70/255,63/255,46/255,0.06) } }
                }

                // hover header → stats; right-click header → pin workspace mode
                HoverHandler { id: frameHover; onHoveredChanged: win.statsExpanded = hovered }

                CornerDeco {
                    anchors.fill: parent
                    lineColor: Qt.rgba(70/255,63/255,46/255,0.55); size: 12; z: 5
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
                            text: "◳ WORKSPACE"; font.family: root.mono; font.pixelSize: 11
                            font.letterSpacing: 2; color: root.cAccent
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
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 60; height: 5; color: Qt.rgba(70/255,63/255,46/255,0.18)
                                border.color: root.cBorder; border.width: 1
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, parent.parent.lvl))
                                    height: parent.height; color: root.cAccent
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
                            Rectangle { width: 4; height: 4; radius: root.wspPinned ? 0 : 2
                                        color: root.wspPinned ? root.cAccent : root.cMuted
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

                            // page switcher:  ‹  LABEL  ›            ● ○ ○
                            Item {
                                id: pager
                                width: parent.width; height: 14
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8
                                    Text { text: "‹"; font.family: root.mono; font.pixelSize: 12; color: root.cMuted
                                           MouseArea { anchors.fill: parent; anchors.margins: -6
                                                       onClicked: root.cycleStatsPage(-1) } }
                                    Text { text: root.statsPageNames[root.statsPage]; width: 56
                                           horizontalAlignment: Text.AlignHCenter
                                           font.family: root.mono; font.pixelSize: 9; color: root.cText }
                                    Text { text: "›"; font.family: root.mono; font.pixelSize: 12; color: root.cMuted
                                           MouseArea { anchors.fill: parent; anchors.margins: -6
                                                       onClicked: root.cycleStatsPage(1) } }
                                }
                                Row {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    Repeater {
                                        model: root.statsPageNames.length
                                        Rectangle { width: 4; height: 4; radius: 2
                                                    color: index === root.statsPage ? root.cAccent : root.cMuted }
                                    }
                                }
                                // scroll anywhere on the row to flip pages
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
                                              sColor: Sys.cpuPct>80 ? root.cAccent : root.cText }
                                    StatRow { visible: Sys.gpuAvailable
                                              sLabel: "GPU"; sVal: Sys.gpuPct.toFixed(0)+"%"; sFill: Sys.gpuPct/100
                                              sColor: Sys.gpuPct>80 ? root.cAccent : root.cText }
                                    StatRow { sLabel: "MEM"; sVal: Sys.memPct + "%"; sFill: Sys.memPct/100
                                              sColor: Sys.memPct>85 ? root.cAccent : root.cText }
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
                                              sColor: Battery.percent<20 ? root.cAccent : root.cGood }

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
                                    InfoRow { visible: Net.btOn && Net.btDev !== ""; clickable: true
                                              iLabel: "BT"; iVal: Net.btDev + (Net.btBat ? "  " + Net.btBat : "")
                                              iColor: root.cText
                                              onClicked: root.run("blueman-manager || bluetoothctl") }
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
                                    Section { label: root.monthNames[root.calMonth] + " " + root.calYear }
                                    Item {
                                        id: calImg
                                        // clean template is 1408x3054; grid positions are stored as
                                        // FRACTIONS of width/height so this stays resolution-independent.
                                        readonly property real imgW: 1408
                                        readonly property real imgH: 3054
                                        width: parent.width
                                        height: width * imgH / imgW
                                        function colFrac(i) { return 0.16889 + i * 0.11243 }   // Sun..Sat
                                        function rowFrac(w) { return 0.76752 + w * 0.03222 }   // week 0..5
                                        // scroll over the image to change month
                                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.NoButton; hoverEnabled: true
                                                    onWheel: (w) => root.calShift(w.angleDelta.y < 0 ? 1 : -1) }

                                        Image {
                                            id: calBg
                                            anchors.fill: parent
                                            fillMode: Image.PreserveAspectFit
                                            asynchronous: true; cache: true; smooth: true; mipmap: true
                                            // decode-time downscale (2× display for crispness) instead of
                                            // squashing the full 1408px texture in the scene graph → sharp.
                                            sourceSize.width: Math.round(width * 2)
                                            source: Qt.resolvedUrl("../assets/cal/month" + (root.calMonth + 1) + ".jpg")
                                        }

                                        // live day-number overlay
                                        Repeater {
                                            model: root.daysInMonth(root.calYear, root.calMonth)
                                            Item {
                                                id: dcell
                                                readonly property int  day:  index + 1
                                                readonly property int  idx:  root.firstDOW(root.calYear, root.calMonth) + index
                                                readonly property real cx:   calImg.colFrac(idx % 7) * calImg.width
                                                readonly property real cy:   calImg.rowFrac(Math.floor(idx / 7)) * calImg.height
                                                readonly property bool isToday: day === root.todayDay
                                                                                && root.calMonth === root.todayMonth
                                                                                && root.calYear === root.todayYear
                                                readonly property bool isSel: day === root.calSelDay
                                                readonly property bool hasEv: Cal.eventsOn(root.dateStr(root.calYear, root.calMonth, day)).length > 0
                                                width:  0.11243 * calImg.width; height: 0.03222 * calImg.height
                                                x: cx - width / 2;  y: cy - height / 2
                                                // selection / today ring
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width:  Math.min(parent.width, parent.height) * 0.92
                                                    height: width; radius: width / 2
                                                    color: dcell.isSel ? root.cAccent : "transparent"
                                                    border.color: dcell.isToday ? "#fff6cf" : "transparent"
                                                    border.width: 1.5
                                                }
                                                Text {
                                                    anchors.centerIn: parent; text: dcell.day
                                                    font.family: root.mono; font.bold: dcell.isToday || dcell.isSel
                                                    font.pixelSize: Math.max(8, Math.round(parent.height * 0.7))
                                                    color: dcell.isSel ? "#fff6cf" : "#f3e9d8"
                                                }
                                                // event marker
                                                Rectangle {
                                                    visible: dcell.hasEv && !dcell.isSel
                                                    width: 3; height: 3; radius: 1.5; color: "#fff6cf"
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    anchors.bottom: parent.bottom; anchors.bottomMargin: 4
                                                }
                                                MouseArea { anchors.fill: parent; onClicked: root.calSelDay = dcell.day }
                                            }
                                        }

                                        // month nav — invisible hotspots over the crescent-moon
                                        // ornaments on each frame side (left = prev, right = next).
                                        Repeater {
                                            model: [ { f: 0.045, d: -1 }, { f: 0.955, d: 1 } ]
                                            Rectangle {
                                                required property var modelData
                                                width: calImg.width * 0.13; height: calImg.height * 0.065
                                                radius: width / 2
                                                x: calImg.width * modelData.f - width / 2
                                                y: calImg.height * 0.843 - height / 2
                                                color: moonMa.pressed ? Qt.rgba(1, 0.96, 0.81, 0.18) : "transparent"
                                                MouseArea {
                                                    id: moonMa
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.calShift(parent.modelData.d)
                                                }
                                            }
                                        }
                                    }

                                    // selected-day detail: that day's events + due tasks
                                    Text {
                                        width: pgInfo.width
                                        text: root.monthNames[root.calMonth] + " " + root.calSelDay
                                        font.family: root.mono; font.pixelSize: 9; color: root.cAccent
                                    }
                                    Repeater {
                                        model: Cal.eventsOn(root.dateStr(root.calYear, root.calMonth, root.calSelDay))
                                        Row {
                                            width: pgInfo.width; spacing: 5
                                            Text { text: modelData.time !== "" ? modelData.time : "all-day"
                                                   font.family: root.mono; font.pixelSize: 8; color: root.cMuted; width: 48 }
                                            Text { text: modelData.title; font.family: root.mono; font.pixelSize: 8
                                                   color: root.cText; elide: Text.ElideRight; width: pgInfo.width - 54 }
                                        }
                                    }
                                    Text {
                                        visible: Cal.eventsOn(root.dateStr(root.calYear, root.calMonth, root.calSelDay)).length === 0
                                        text: "— no events —"; font.family: root.mono; font.pixelSize: 8; color: root.cMuted
                                    }
                                    // tasks due on the selected day (Google Tasks)
                                    Repeater {
                                        model: Tasks.tasksOn(root.dateStr(root.calYear, root.calMonth, root.calSelDay))
                                        Row {
                                            width: pgInfo.width; spacing: 5
                                            Text { text: modelData.done ? "✓" : "☐"; font.family: root.mono
                                                   font.pixelSize: 8; color: modelData.done ? root.cGood : root.cAccent; width: 12 }
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
                                                      root.statsPinned = true
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
                                        color: Qt.rgba(70/255,63/255,46/255,0.07)
                                        border.color: root.cBorder; border.width: 1
                                        TextEdit {
                                            id: todoEd
                                            anchors.fill: parent; anchors.margins: 5
                                            font.family: root.mono; font.pixelSize: 9
                                            color: root.cText; selectionColor: root.cAccent
                                            wrapMode: TextEdit.Wrap
                                            textFormat: TextEdit.PlainText
                                            // save shortly after typing stops
                                            onTextChanged: if (root.todoEditing) todoSaveT.restart()
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
                                                 bColor: root.swGo ? root.cAccent : root.cGood
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

                            // 5×5 grid — ws 1..25 (cols = ±1, rows = ±5)
                            Grid {
                                id: wspGrid
                                columns: 5; rowSpacing: 4; columnSpacing: 4
                                anchors.horizontalCenter: parent.horizontalCenter
                                property real cell: (parent.width - 4*4) / 5
                                Repeater {
                                    model: 25
                                    Rectangle {
                                        required property int index
                                        // rows reversed: 21-25 on top, 1-5 on bottom
                                        readonly property int wsid: (4 - Math.floor(index/5))*5 + (index%5) + 1
                                        readonly property int  monIdx: root.wsMonIdx(wsid)   // -1 if not open
                                        readonly property bool exists: monIdx >= 0
                                        readonly property bool active: root.wsIsActive(wsid) // active on its monitor
                                        // open workspaces are tinted by which monitor they live on
                                        readonly property color monColor: exists ? root.monColors[monIdx % root.monColors.length]
                                                                                  : root.cMuted
                                        width: wspGrid.cell; height: 18
                                        color: cellMA.containsMouse ? root.cText
                                              : active ? monColor
                                              : "transparent"
                                        border.width: 1
                                        border.color: cellMA.containsMouse ? root.cText
                                                    : exists ? monColor
                                                    : root.cBorder
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        // open → number (monitor-tinted)
                                        Text {
                                            visible: parent.exists
                                            anchors.centerIn: parent
                                            text: parent.wsid
                                            font.family: root.mono; font.pixelSize: 9
                                            color: cellMA.containsMouse ? root.cBg
                                                 : parent.active ? root.cBg
                                                 : parent.monColor
                                        }
                                        // unopened → emblem star
                                        Emblem {
                                            visible: !parent.exists
                                            anchors.centerIn: parent
                                            width: 16; height: 16
                                            glow: false
                                            color: cellMA.containsMouse ? root.cBg : Qt.rgba(70/255,63/255,46/255,0.42)
                                        }
                                        MouseArea {
                                            id: cellMA; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onEntered: win.hoveredWs = parent.wsid
                                            onExited:  if (win.hoveredWs === parent.wsid) win.hoveredWs = -1
                                            onClicked: Hyprland.dispatch("workspace " + parent.wsid)
                                        }
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
                                        Rectangle { width: 3; height: 3; color: root.cAccent
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
                                    text: "— empty —"; font.family: root.mono; font.pixelSize: 9
                                    color: root.cMuted
                                }
                            }
                        }
                    }
                }

                // scanline accent on the bottom edge
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 2; color: root.cAccent
                    opacity: (win.showStats || win.showWsp) ? 0.85 : 0.35
                    Behavior on opacity { NumberAnimation { duration: 240 } }
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
        property color  sColor: "#463f2e"
        property bool   interactive: false
        signal tapped()             // label clicked (e.g. mute)
        signal setFrac(real f)      // bar clicked/dragged → 0..1
        signal step(real dir)       // −/+ buttons (+1 / −1)
        signal doubleTapped()       // double-click bar (e.g. open mixer)
        width: parent ? parent.width : 160
        height: interactive ? 18 : 14

        Text {
            id: srLabel
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: sLabel; font.family: root.mono; font.pixelSize: 9; font.letterSpacing: 1
            color: root.cMuted; width: 26
            MouseArea { enabled: sr.interactive; anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor; onClicked: sr.tapped() }
        }
        Text {
            id: srVal
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: sVal; font.family: root.mono; font.pixelSize: 10; font.letterSpacing: 1
            color: sColor; horizontalAlignment: Text.AlignRight; width: 40
        }

        Rectangle {
            id: srBar
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: srLabel.right; anchors.leftMargin: 4
            anchors.right: srVal.left; anchors.rightMargin: 6
            height: sr.interactive ? 5 : 3
            color: Qt.rgba(70/255,63/255,46/255,0.15)
            border.color: sr.interactive ? root.cBorder : "transparent"; border.width: 1
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, sFill)); height: parent.height
                color: sColor
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
            enabled: sr.interactive
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onWheel: (w) => { sr.step(w.angleDelta.y > 0 ? 1 : -1) }
        }
    }


    // ── Section header: accent label + rule, optionally clickable ──
    component Section: Item {
        id: sec
        property string label: ""
        property bool   clickable: false
        signal clicked()
        width: parent ? parent.width : 160
        height: 12
        Text {
            id: secLbl
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: label; font.family: root.mono; font.pixelSize: 8; font.letterSpacing: 2
            color: root.cAccent
        }
        Rectangle {
            anchors { left: secLbl.right; leftMargin: 6; right: parent.right
                      verticalCenter: parent.verticalCenter }
            height: 1; color: root.cBorder
        }
        MouseArea {
            enabled: sec.clickable
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sec.clicked()
        }
    }

    // ── Info row: label · value (no bar), optionally clickable ──
    component InfoRow: Item {
        id: ir
        property string iLabel: ""
        property string iVal:   ""
        property color  iColor: "#463f2e"
        property bool   clickable: false
        signal clicked()
        width: parent ? parent.width : 160
        height: 13
        Text {
            id: infoL
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: iLabel; font.family: root.mono; font.pixelSize: 9; color: root.cMuted
            width: 34; elide: Text.ElideRight
        }
        Text {
            anchors { left: infoL.right; right: parent.right; verticalCenter: parent.verticalCenter }
            text: iVal; font.family: root.mono; font.pixelSize: 9; color: iColor
            elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
        }
        // top-most so clicks register (same pattern as the working grid cells)
        MouseArea {
            enabled: ir.clickable
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: ir.clicked()
        }
    }

    // ── Small button (stopwatch controls) ──
    component HudBtn: Rectangle {
        property string bLabel: ""
        property color  bColor: "#463f2e"
        signal clicked()
        width: btxt.implicitWidth + 14; height: 18
        color: btnMA.containsMouse ? bColor : "transparent"
        border.color: bColor; border.width: 1
        Behavior on color { ColorAnimation { duration: 120 } }
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        Text {
            id: btxt; anchors.centerIn: parent; text: bLabel
            font.family: root.mono; font.pixelSize: 8; font.letterSpacing: 1
            color: btnMA.containsMouse ? root.cBg : bColor
        }
        MouseArea { id: btnMA; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    // ── Vector speaker icon (Canvas) — themeable, no emoji ──
    component SpeakerIcon: Canvas {
        property color color: "#6e2a2a"
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
        property color color: "#6e2a2a"
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
        property color color: "#6e2a2a"
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
