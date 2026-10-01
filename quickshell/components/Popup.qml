import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../settings"

// Popup — the full-screen glass popup every panel is built on (launcher, capture
// panel, Control Center, workspace mover, clipboard). It owns what they all share:
//
//   · one Overlay layer surface, mapped only while needed, moved to the focused
//     screen on every open (not one surface per screen)
//   · the lifecycle  closed → arming → open → closing → closed
//       arming   mapped but empty while the backdrop freezes a frame of the screen
//       open     the frame is in (or armTimeout passed), the surface has shown its
//                first frame (MapGate — a reveal started earlier loses its front-loaded
//                part) and introReady: intro()
//       closing  the triangles scatter while the panel plays its hide; unmapped
//                once both are done (the panel calls panelGone(), or autoPanelGone)
//   · the shared glass backdrop (GlassBackdrop: the frozen frame + TriField)
//   · a warm-up: one invisible, click-through render shortly after start, so the
//     first real open doesn't stall on shader / glyph / icon loading
//   · the rhythm clock the panels pulse to (t, beatPhase, beatIndex, pulse)
//   · a HitBurst above everything: burst.playAt(item, x, y, strength)
//
// Content goes straight inside (`default` → body). Size things from screenW/H:
// the surface itself is 0×0 for a moment after it maps.
PanelWindow {
    id: pop

    // ── configuration ──
    property bool  warmUp:        true
    property int   warmUpDelay:   2500
    property bool  grabKeyboard:  true
    property bool  introReady:    true    // a panel can hold the intro (e.g. its own freeze frame)
    property bool  autoPanelGone: false   // true: no hide of its own — unmap once the triangles are gone
    property bool  clickOutCloses: true   // a click on the backdrop closes
    property real  dimAmount:     Settings.backdropDim
    property int   armTimeout:    350
    property real  bpm:           120
    property bool  collapse:      false   // scatter the triangles while staying open (the CC's power exit)
    property real  underlay:      0       // black under the triangles (they scatter into the dark, not onto the desktop)

    property alias backdrop: glass
    property alias burst:    hit
    default property alias content:   body.data

    // ── state ──
    property string phase: "closed"
    readonly property bool isOpen:  phase === "arming" || phase === "open"
    readonly property bool shown:   phase === "open" || phase === "closing"
    readonly property bool active:  phase === "open"
    property bool warming: false
    readonly property bool mapped:  phase !== "closed" || warming
    readonly property real screenW: screen ? screen.width : 1920
    readonly property real screenH: screen ? screen.height : 1080
    readonly property string screenName: screen ? screen.name : ""

    // ── rhythm ──
    property real t: 0
    NumberAnimation on t {
        running: pop.shown
        from: 0; to: 100000; duration: 100000000; loops: Animation.Infinite
    }
    readonly property real beatPhase: (t * bpm / 60) % 1
    readonly property int  beatIndex: Math.floor(t * bpm / 60)
    readonly property real pulse:     Math.pow(1 - beatPhase, 3)

    // ── lifecycle hooks ──
    signal opening()      // open() was called: reset state (the surface maps empty)
    signal intro()        // the backdrop is ready: play the reveal
    signal outro()        // close() was called: play the hide, then panelGone()
    signal finished()     // fully closed; the surface is unmapped

    function toggle() { if (isOpen) close(); else open() }
    function open(scr) {
        if (isOpen) return
        if (phase === "closing") _finish()          // reopened mid-close: start clean
        warming = false; warmEnd.stop()
        screen = scr || focusedScreen()
        _panelGone = false; _triGone = false; collapse = false; underlay = 0
        phase = "arming"
        _gateOk = false
        gate.arm()
        armT.restart()
        opening()
        _tryIntro()
    }
    function close() {
        if (!isOpen) return
        armT.stop(); gate.disarm()
        if (phase === "arming") { _finish(); return }   // nothing on screen yet
        phase = "closing"
        outro()
        if (autoPanelGone) _panelGone = true
        _maybeFinish()
    }
    function panelGone() { _panelGone = true; _maybeFinish() }

    function focusedScreen() {
        var m = Hyprland.focusedMonitor, ss = Quickshell.screens
        if (m) for (var i = 0; i < ss.length; i++) if (ss[i].name === m.name) return ss[i]
        return ss.length ? ss[0] : null
    }

    property bool _panelGone: true
    property bool _triGone:   true
    property bool _timedOut:  false
    property bool _gateOk:    false
    onIntroReadyChanged: _tryIntro()
    // the triangles unfold again after a collapse: a later close waits for their scatter
    onCollapseChanged: if (!collapse && phase === "open") _triGone = false
    function _tryIntro() {
        if (phase !== "arming" || !introReady || !_gateOk) return
        if (!glass.hasFrame && !_timedOut) return
        armT.stop(); _timedOut = false
        phase = "open"
        intro()
    }
    function _maybeFinish() { if (phase === "closing" && _panelGone && _triGone) _finish() }
    function _finish() {
        phase = "closed"
        _panelGone = true; _triGone = true; _timedOut = false
        finished()
    }
    Timer { id: armT; interval: pop.armTimeout; onTriggered: { pop._timedOut = true; pop._tryIntro() } }

    // warm-up: once, a moment after start, while nothing is open
    Timer {
        interval: pop.warmUpDelay; running: pop.warmUp
        onTriggered: if (pop.phase === "closed") { pop.screen = pop.focusedScreen(); pop.warming = true; warmEnd.start() }
    }
    Timer { id: warmEnd; interval: 700; onTriggered: pop.warming = false }

    // ── the surface ──
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: mapped
    mask: warming ? noInput : null
    Region { id: noInput }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: grabKeyboard && isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: pop.underlay
        visible: opacity > 0
    }
    GlassBackdrop {
        id: glass
        anchors.fill: parent
        screen:    pop.screen
        capturing: pop.phase !== "closed"
        active:    pop.phase === "open" && !pop.collapse
        warm:      pop.warming
        dimAmount: pop.dimAmount
        onFrameReady: pop._tryIntro()
        onHidden: { pop._triGone = true; pop._maybeFinish() }
    }
    MouseArea {
        anchors.fill: parent
        enabled: pop.clickOutCloses && pop.phase === "open"
        onClicked: pop.close()
    }
    Item {
        id: body
        anchors.fill: parent
        // during the warm-up the content renders once, practically invisible
        opacity: pop.warming && !pop.shown ? 0.004 : 1
    }
    HitBurst { id: hit; backdrop: glass }
    MapGate { id: gate; onReady: { pop._gateOk = true; pop._tryIntro() } }
}
