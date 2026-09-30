import QtQuick
import Quickshell
import Quickshell.Wayland
import "../settings"

// The NieR glass-triangle backdrop shared by every full-screen popup
// (ScreenCapture, Menu, ControlCenter, WsMover). Change the look here — or in
// TriField.qml / shaders/tri.frag, which hold the grid, palette, contrast,
// refraction, glare, stars, flicker and timings — and every popup follows.
//
// It freezes a frame of `screen` while `capturing` is true and refracts it
// through the panes. A popup should keep its own content hidden until
// frameReady() (or a short fallback), so it never ends up in its own backdrop.
Item {
    id: gb

    // ── inputs ──
    property var   screen:    null      // ShellScreen to freeze
    property bool  capturing: false     // hold a frame while true (the popup is mapped)
    property bool  active:    false     // true: unfold · false: scatter, then hidden()
    property bool  warm:      false     // one invisible render at start (builds the pipeline)
    property bool  live:      false     // ignore the frame: panes over the live screen
    property real  dimAmount: Settings.backdropDim
    property point originPx:  Qt.point(width / 2, height / 2)   // where the triangles unfold from
    property point glarePx:   Qt.point(width / 2, height / 2)   // centre of the circling glare
    // region selection: spotlight + panes that touch it fold away
    property bool  selecting: false
    property rect  selection: Qt.rect(0, 0, 0, 0)
    property rect  foldRect:  selection

    // ── outputs ──
    readonly property bool hasFrame:     scv.hasContent
    readonly property size frameSize:    scv.sourceSize        // physical px of the frozen frame
    readonly property var  frameTexture: scvTex                 // e.g. for a magnifier
    readonly property int  hideDuration: tri.hideDuration
    signal frameReady()
    signal hidden()

    // A shock ring through the triangles around (x, y), in this item's coordinates
    function impact(x, y, strength) { tri.impact(x, y, strength) }

    ScreencopyView {
        id: scv
        anchors.fill: parent
        live: false
        captureSource: gb.capturing ? gb.screen : null
        onHasContentChanged: if (hasContent) gb.frameReady()
    }
    ShaderEffectSource {
        id: scvTex
        sourceItem: scv; hideSource: true; visible: false
        textureSize: scv.hasContent ? scv.sourceSize : Qt.size(0, 0)   // 1:1 physical px
    }
    TriField {
        id: tri
        anchors.fill: parent
        active:    gb.active
        warm:      gb.warm
        dimAmount: gb.dimAmount
        originPx:  gb.originPx
        glarePx:   gb.glarePx
        sourceTex: scvTex
        hasSource: scv.hasContent && !gb.live
        selecting: gb.selecting
        selection: gb.selection
        foldRect:  gb.foldRect
        onHidden:  gb.hidden()
    }
}
