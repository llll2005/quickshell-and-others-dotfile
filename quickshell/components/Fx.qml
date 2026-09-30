pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../settings"

// Global effects layer: the shared diamond burst (HitBurst) and the typing sparks
// (Sparks), anywhere on any screen. One click-through Overlay surface per screen,
// mapped only while an effect is in flight — nothing is drawn (or composited) at idle.
//
//   Fx.burst(gx, gy, strength)          // global layout px (what Hyprland reports)
//   Fx.sparks(gx, gy)
//   Fx.burstOn(monitor, x, y, strength) // monitor-local layout px
//   Fx.sparksOn(monitor, x, y)
//
// Also answers clicks: the imecaret Hyprland plugin (hypr-plugin/imecaret) posts
// `clickfx>>x,y,button` for mouse presses on windows (not on bars / the shell's own
// panels, which answer clicks themselves) → a small burst there
// (Settings.clickFx; skipped while the focused workspace has a fullscreen window).
Singleton {
    id: fx

    function burst(gx, gy, strength)  { _global(0, gx, gy, strength === undefined ? 0.6 : strength) }
    function sparks(gx, gy)           { _global(1, gx, gy, 0) }
    function burstOn(mon, x, y, strength) { _local(0, mon, x, y, strength === undefined ? 0.6 : strength) }
    function sparksOn(mon, x, y)      { _local(1, mon, x, y, 0) }
    function init() {}                // referencing Fx creates it (shell.qml does, for the clicks)

    // kind: 0 burst · 1 sparks; x/y: monitor-local layout px; mw: that monitor's layout width
    signal play(int kind, string mon, real x, real y, real mw, real strength)

    function _monitor(name) {
        var ms = Hyprland.monitors.values
        for (var i = 0; i < ms.length; i++) if (ms[i] && ms[i].name === name) return ms[i]
        return null
    }
    function _local(kind, mon, x, y, s) {
        var m = _monitor(mon)
        if (m) play(kind, mon, x, y, m.width / m.scale, s)
    }
    function _global(kind, gx, gy, s) {
        var ms = Hyprland.monitors.values
        for (var i = 0; i < ms.length; i++) {
            var m = ms[i]
            if (!m) continue
            var w = m.width / m.scale, h = m.height / m.scale
            if (gx >= m.x && gx < m.x + w && gy >= m.y && gy < m.y + h) {
                play(kind, m.name, gx - m.x, gy - m.y, w, s)
                return
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name !== "clickfx" || !Settings.clickFx) return
            if (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.hasFullscreen) return
            var p = e.data.split(",")
            fx.burst(+p[0], +p[1], 0.35)
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: w
            required property var modelData
            screen: modelData
            property bool hold: false
            Timer { id: holdT; interval: 750; onTriggered: w.hold = false }
            visible: hold
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}           // never takes the pointer

            property int _nextBurst: 0
            Connections {
                target: fx
                function onPlay(kind, mon, x, y, mw, s) {
                    if (mon !== w.modelData.name) return
                    // scale by the screen, not the window: a window that has just been
                    // mapped is 0×0 for a moment
                    var k = w.modelData.width / Math.max(1, mw)
                    w.hold = true; holdT.restart()
                    if (kind === 0) {
                        var b = bursts.itemAt(w._nextBurst)
                        w._nextBurst = (w._nextBurst + 1) % bursts.count
                        if (b) b.play(x * k, y * k, s)
                    } else {
                        sparkField.fire(x * k, y * k)
                    }
                }
            }

            // a few bursts so quick clicks don't cut each other off
            Repeater {
                id: bursts
                model: 3
                HitBurst { scale: Settings.burstSize }
            }
            Sparks { id: sparkField; anchors.fill: parent }
        }
    }
}
