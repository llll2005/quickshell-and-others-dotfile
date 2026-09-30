import QtQuick
import "../theme"
import "../settings"

// Normally used through GlassBackdrop.qml (adds the frozen screen frame); the
// defaults below are the shared look for every popup.
// Triangle backdrop — the look of widgets/NierTriBg.qml (which paints a Canvas on
// the CPU at 30 fps) rendered on the GPU, plus idle flicker, a slow glare and
// vertex stars. Given `sourceTex` (a frozen frame of the screen) the panes also
// refract what is behind them and the dim is drawn in the shader; without one
// it draws dim + panes over the transparent surface. Set `active` to unfold it
// from `originPx`; clearing it scatters it away and emits hidden().
ShaderEffect {
    id: tf

    property bool   active:        false
    property bool   warm:          false   // render once, invisibly, to build the pipeline early
    property real   cellSize:      Settings.backdropCell
    property real   gapPx:         3
    property color  triColor:      Theme.triangle
    property color  glintColor:    Theme.triangleGlint
    property color  shadeColor:    Theme.triangleShade
    property real   targetOpacity: Settings.backdropOpacity
    property real   dimAmount:     Settings.backdropDim
    property real   flickerAmount: Settings.backdropFlicker     // 0 = still, 1 = lively
    // tri.frag EXIT scatter + fade tail; callers wait for hidden() (or this)
    readonly property int hideDuration: 700
    property point  originPx:      Qt.point(width, height / 2)
    property point  glarePx:       Qt.point(width / 2, height / 2)
    property var    sourceTex:     null
    property bool   hasSource:     false
    property bool   selecting:     false            // region selection: spotlight `selection`
    property rect   selection:     Qt.rect(0, 0, 0, 0)
    property rect   foldRect:      selection        // pass an eased copy for a softer fold
    signal hidden()

    // ── shader uniforms (names match tri.frag) ──
    property size   res:     Qt.size(width, height)
    property point  origin:  originPx
    property point  glareC:  glarePx
    property real   cellW:   cellSize
    property real   gap:     gapPx
    property real   time:    0
    property real   tIn:     warm && !_on ? 2 : time - _tShow
    property real   tOut:    _hiding ? time - _tHide : -1
    property real   flicker: flickerAmount
    property real   alpha:   targetOpacity
    property real   dim:     dimAmount
    property real   hasSrc:  hasSource && sourceTex ? 1 : 0
    property color  glint:   glintColor
    property color  shade:   shadeColor
    property var    source:  sourceTex ? sourceTex : fallbackTex
    property real   selOn:   selecting ? 1 : 0
    property point  impactPx: Qt.point(-9999, -9999)
    property real   impT:     _impOn ? time - _impStart : -1
    property real   impS:     1
    property bool   _impOn:    false
    property real   _impStart: 0
    // A ring through the panes around (x, y) — local, gone in ~0.7 s (tri.frag IMP_*)
    function impact(x, y, strength) {
        if (!_on) return
        impactPx = Qt.point(x, y); impS = strength === undefined ? 1 : strength
        _impStart = time; _impOn = true
    }
    property rect   selRect: selection

    property real _tShow:  0
    property real _tHide:  0
    property bool _hiding: false
    property bool _on:     false   // own flag: `visible` also reads false while the window is unmapped

    visible: _on || warm
    opacity: warm && !_on ? 0.004 : 1
    // Relative to this file, not the user. The ?v= tag must be bumped after
    // recompiling: Quickshell reuses windows across reloads and Qt caches a
    // window's shaders by URL, so an unchanged URL keeps the old shader.
    fragmentShader: Qt.resolvedUrl("shaders/tri.frag.qsb") + "?v=15"

    // A sampler must always be bound; this 1×1 stands in when there is no frame.
    ShaderEffectSource {
        id: fallbackTex
        sourceItem: Rectangle { width: 1; height: 1; color: "transparent" }
        live: false; hideSource: true; visible: false
    }

    onActiveChanged: active ? _show() : _hide()
    function _show() {
        _hiding = false
        hideT.stop()
        if (!_on) { _on = true; clock.restart(); _tShow = 0 }
        else _tShow = time
    }
    function _hide() {
        if (!_on) { hidden(); return }
        _hiding = true
        _tHide = time
        hideT.restart()
    }

    NumberAnimation {
        id: clock; target: tf; property: "time"
        from: 0; to: 100000; duration: 100000000; loops: Animation.Infinite
    }
    // backdrop fade (0.42 s in tri.frag) + a small tail
    Timer { id: hideT; interval: tf.hideDuration; onTriggered: { tf._on = false; clock.stop(); tf.hidden() } }
}
