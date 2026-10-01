import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "../settings"
import "../theme"

// Window effects, driven by the imecaret plugin's `winfx>>kind,addr,x,y,w,h[,why]`:
//   open    the window's own pixels rain down into place (shaders/rain.frag) while
//           the plugin keeps the real window invisible; it is shown the moment the
//           last cell lands (`hyprctl winfx release`, at most `holdMs`)
//   close   it melts downward (shaders/melt.frag), cut from a frame of the screen
//           frozen while Hyprland still draws the closing window (needs Hyprland's
//           own close slide off: theme-sync writes `windowFx` into qs_theme.lua)
//   focus   NieR lock-on brackets spring onto the window that took focus (keyboard,
//           click, a window closing — not focus-follows-mouse unless asked)
// One click-through Overlay surface per screen, mapped only while something plays.
// Nothing over fullscreen workspaces. `[effects]` in shell.conf switches each.
Scope {
    id: root

    // the longest the plugin keeps a new window back; the rain releases it sooner
    readonly property int  holdMs: 900
    readonly property bool openOn:    Settings.windowOpenFx
    readonly property bool closeOn:   Settings.windowCloseFx
    readonly property bool reticleOn: Settings.focusReticle

    // how long the plugin holds new windows back (0 = it changes nothing)
    Process { id: holdP; command: ["hyprctl", "winfx", "hold", String(root.openOn ? root.holdMs : 0)] }
    // re-sent now and then: the plugin may load after the shell, or be reloaded
    Timer { id: holdT; interval: 500; running: true; onTriggered: { holdP.running = false; holdP.running = true; interval = 20000; restart() } }
    onOpenOnChanged: holdT.restart()

    signal play(string kind, string addr, string mon, real x, real y, real w, real h, real mw)
    property var _opening: ({})        // addr → time: no lock-on during its own assembly
    property var _focusArgs: null
    Timer {
        id: focusT; interval: 60
        onTriggered: {
            var a = root._focusArgs
            if (!a || (root._opening[a[0]] && Date.now() - root._opening[a[0]] < 1200)) return
            root.play("focus", a[0], a[1], a[2], a[3], a[4], a[5], a[6])
        }
    }

    function monitorAt(gx, gy) {
        var ms = Hyprland.monitors.values
        for (var i = 0; i < ms.length; i++) {
            var m = ms[i]
            if (!m) continue
            var w = m.width / m.scale, h = m.height / m.scale
            if (gx + 1 >= m.x && gx < m.x + w && gy + 1 >= m.y && gy < m.y + h) return m
        }
        return null
    }
    function toplevelFor(addr) {
        var t = Hyprland.toplevels.values
        for (var i = 0; i < t.length; i++) if (t[i] && t[i].address === addr) return t[i].wayland
        return null
    }

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name !== "winfx") return
            var p = e.data.split(",")
            if (p.length < 6) return
            var kind = p[0], addr = p[1], x = +p[2], y = +p[3], w = +p[4], h = +p[5], why = p[6] || ""
            var m = root.monitorAt(x + w / 2, y + h / 2) || root.monitorAt(x, y)
            if (!m || (m.activeWorkspace && m.activeWorkspace.hasFullscreen)) return
            if (kind === "open") {
                if (!root.openOn) return
                var o = Object.assign({}, root._opening); o[addr] = Date.now(); root._opening = o
                Hyprland.refreshToplevels()
            } else if (kind === "close") {
                if (!root.closeOn) return
            } else if (kind === "focus") {
                if (!root.reticleOn || (why === "ffm" && !Settings.focusReticleHover)) return
                // a new window takes focus just before its open event: wait a moment, and
                // leave it to the rain (which locks on when it lands)
                root._focusArgs = [addr, m.name, x - m.x, y - m.y, w, h, m.width / m.scale]
                focusT.restart()
                return
            } else return
            root.play(kind, addr, m.name, x - m.x, y - m.y, w, h, m.width / m.scale)
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}                 // never takes the pointer

            property int running: 0         // effects in flight
            visible: running > 0 || reticle.shown

            Connections {
                target: root
                function onPlay(kind, addr, mon, x, y, w, h, mw) {
                    if (mon !== win.modelData.name) { if (kind === "focus") reticle.leave(); return }
                    var k = win.modelData.width / Math.max(1, mw)
                    var r = { rx: x * k, ry: y * k, rw: w * k, rh: h * k }
                    if (kind === "open") {
                        r.addr = addr
                        assembleComp.createObject(win.contentItem, r)
                    } else if (kind === "close") {
                        reticle.hideNow()            // keep it out of the frozen frame
                        meltComp.createObject(win.contentItem, r)
                    } else if (kind === "focus") {
                        reticle.lockOn(r.rx, r.ry, r.rw, r.rh)
                    }
                }
            }
            // ── open: pixel rain ── The plugin keeps the new window invisible; its
            // own pixels (a live capture — real content usually ~150 ms in) rain down
            // into place, and the moment the last cell has landed the window is shown
            // (`hyprctl winfx release`). No pixels within 300 ms: it rains paper.
            Component {
                id: assembleComp
                Item {
                    id: fx
                    property real rx; property real ry; property real rw; property real rh
                    property string addr
                    readonly property real drop: Math.min(240, rh * 0.4)
                    // the cells fall from above, but only show inside the window: drawn over
                    // the space above, they'd land on whatever window sits there
                    x: rx; y: ry; width: rw; height: rh
                    clip: true
                    property var  tl: null
                    property bool started: false
                    property bool released: false
                    Component.onCompleted: { win.running++; tl = root.toplevelFor(addr); lookT.start() }
                    Component.onDestruction: release()
                    Timer {   // the toplevel's Wayland handle trails the event (~100 ms)
                        id: lookT; interval: 20; repeat: true
                        property int n: 0
                        onTriggered: { n++; if (!fx.tl) fx.tl = root.toplevelFor(fx.addr); if (fx.tl || n > 30) stop() }
                    }
                    Timer { interval: 300; running: !fx.started; onTriggered: fx.go() }
                    function go() { if (started) return; started = true; anim.start() }
                    function release() {
                        if (released) return
                        released = true
                        Quickshell.execDetached(["hyprctl", "winfx", "release", addr])
                    }

                    Item {
                    id: stage
                    y: -fx.drop; width: fx.rw; height: fx.rh + fx.drop
                    ScreencopyView {
                        id: cap
                        x: 0; y: fx.drop; width: fx.rw; height: fx.rh
                        live: true
                        captureSource: fx.tl
                        onHasContentChanged: if (hasContent) fx.go()
                    }
                    ShaderEffectSource { id: capSrc; sourceItem: cap; hideSource: true; live: true; visible: false }
                    ShaderEffect {
                        id: sh
                        anchors.fill: parent
                        visible: fx.started
                        property real  progress: 0
                        property real  cell: Math.max(10, Math.min(20, Math.round(Math.min(fx.rw, fx.rh) / 30)))
                        property real  hasSource: cap.hasContent ? 1 : 0
                        property size  dims: Qt.size(width, height)
                        property real  drop: fx.drop
                        property real  seed: Math.random() * 10
                        property color paper: Theme.paper
                        property color ink: Theme.ink
                        property color light: Theme.light
                        property var   source: capSrc
                        fragmentShader: Qt.resolvedUrl("../components/shaders/rain.frag.qsb")
                    }
                    }
                    SequentialAnimation {
                        id: anim
                        NumberAnimation { target: sh; property: "progress"; from: 0; to: 1; duration: 480 }
                        ScriptAction { script: { fx.release(); if (root.reticleOn) reticle.lockOn(fx.rx, fx.ry, fx.rw, fx.rh) } }
                        PauseAnimation { duration: 40 }          // the window's first frame on screen
                        NumberAnimation { target: fx; property: "opacity"; to: 0; duration: 90 }
                        ScriptAction { script: { win.running = Math.max(0, win.running - 1); fx.destroy() } }
                    }
                }
            }

            // ── close: melt ── Each close freezes its own frame of this screen (a
            // one-shot ScreencopyView, hidden by the cut), while Hyprland still draws the
            // closing window, and melts the window's rect of it.
            Component {
                id: meltComp
                Item {
                    id: mfx
                    property real rx; property real ry; property real rw; property real rh
                    readonly property real drip: Math.min(260, rh * 0.45)
                    width: win.width; height: win.height
                    property bool started: false
                    Component.onCompleted: win.running++
                    function begin() {
                        if (started) return
                        started = true
                        cut.scheduleUpdate()
                        manim.start()
                    }
                    function done() { win.running = Math.max(0, win.running - 1); mfx.destroy() }
                    Timer { interval: 400; running: !mfx.started; onTriggered: mfx.done() }   // no frame: give up

                    ScreencopyView {
                        id: frame
                        anchors.fill: parent
                        live: false
                        captureSource: win.modelData
                        onHasContentChanged: if (hasContent) mfx.begin()
                    }
                    ShaderEffectSource {
                        id: cut
                        sourceItem: frame
                        hideSource: true
                        sourceRect: Qt.rect(mfx.rx, mfx.ry, mfx.rw, mfx.rh)
                        live: false
                        visible: false
                    }
                    ShaderEffect {
                        id: msh
                        x: mfx.rx; y: mfx.ry; width: mfx.rw; height: mfx.rh + mfx.drip
                        visible: mfx.started
                        property real  progress: 0
                        property real  cell: Math.max(8, Math.min(18, Math.round(mfx.rw / 60)))
                        property real  hasSource: 1
                        property size  dims: Qt.size(width, height)
                        property real  winH: mfx.rh
                        property real  seed: Math.random() * 10
                        property color paper: Theme.paper
                        property color ink: Theme.ink
                        property color accent: Theme.accent
                        property var   source: cut
                        fragmentShader: Qt.resolvedUrl("../components/shaders/melt.frag.qsb")
                    }
                    SequentialAnimation {
                        id: manim
                        NumberAnimation { target: msh; property: "progress"; from: 0; to: 1; duration: 720; easing.type: Easing.InOutSine }
                        ScriptAction { script: mfx.done() }
                    }
                }
            }

            // ── focus: lock-on brackets ──
            Item {
                id: reticle
                property bool shown: false
                property real tx; property real ty; property real tw: 100; property real th: 100
                x: tx; y: ty; width: tw; height: th
                visible: shown
                opacity: 0
                Behavior on x      { enabled: reticle.shown; SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.5 } }
                Behavior on y      { enabled: reticle.shown; SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.5 } }
                Behavior on width  { enabled: reticle.shown; SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.5 } }
                Behavior on height { enabled: reticle.shown; SpringAnimation { spring: 6; damping: 0.32; epsilon: 0.5 } }
                property real flash: 0

                function lockOn(x, y, w, h) {
                    var fresh = !shown
                    if (fresh) {           // come in from a little wider and contract onto it
                        shown = false; tx = x - 26; ty = y - 26; tw = w + 52; th = h + 52
                        shown = true
                    }
                    tx = x; ty = y; tw = w; th = h
                    life.restart()
                }
                function leave() { if (shown && !life.running) return; if (shown) { life.stop(); outA.restart() } }
                function hideNow() { life.stop(); outA.stop(); opacity = 0; shown = false }

                SequentialAnimation {
                    id: life
                    ParallelAnimation {
                        NumberAnimation { target: reticle; property: "opacity"; to: 1; duration: 70 }
                        NumberAnimation { target: reticle; property: "flash"; from: 1; to: 0; duration: 420; easing.type: Easing.OutCubic }
                    }
                    PauseAnimation { duration: 380 }
                    ScriptAction { script: outA.restart() }
                }
                SequentialAnimation {
                    id: outA
                    NumberAnimation { target: reticle; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InQuad }
                    ScriptAction { script: reticle.shown = false }
                }

                readonly property real arm: Math.max(14, Math.min(46, Math.min(width, height) * 0.14))
                readonly property color col: Theme.light
                Repeater {
                    model: 4
                    Item {
                        readonly property bool r: index % 2 === 1
                        readonly property bool b: index >= 2
                        x: r ? reticle.width - reticle.arm : 0
                        y: b ? reticle.height - reticle.arm : 0
                        width: reticle.arm; height: reticle.arm
                        // dark under-line keeps the bracket legible on light windows
                        Rectangle { x: parent.r ? parent.width - 4 : -1; y: -1; width: 5; height: parent.height + 2; color: Theme.alpha(Theme.inkStrong, 0.5) }
                        Rectangle { x: -1; y: parent.b ? parent.height - 4 : -1; width: parent.width + 2; height: 5; color: Theme.alpha(Theme.inkStrong, 0.5) }
                        Rectangle { x: parent.r ? parent.width - 3 : 0; width: 3; height: parent.height; color: reticle.col }
                        Rectangle { y: parent.b ? parent.height - 3 : 0; width: parent.width; height: 3; color: reticle.col }
                        Rectangle {   // the cut-diamond corner
                            width: 7; height: 7; rotation: 45; antialiasing: true; color: reticle.col
                            x: (parent.r ? parent.width : 0) - 3.5
                            y: (parent.b ? parent.height : 0) - 3.5
                            scale: 1 + reticle.flash * 0.8
                        }
                    }
                }
                Rectangle {   // the flash: a light frame that thins out as the brackets land
                    anchors.fill: parent
                    color: "transparent"
                    border.color: reticle.col; border.width: 2
                    opacity: reticle.flash * 0.8
                }
            }
        }
    }
}
