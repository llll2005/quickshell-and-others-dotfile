import QtQuick
import "../theme"

// The confirm impact shared by the NieR popups (ControlCenter, ScreenCapture, Menu):
// two diamond rings and a spray of shards out of a point, plus — when `backdrop`
// is set — a shock ring through that GlassBackdrop's triangles at the same spot.
// Put it above the panel, outside any clipped or masked item, so the shards can
// fly past the panel's edge.
//
//   burst.playAt(markerItem, 3, 3, 1.0)   // from a point of any item
//   burst.play(x, y, 0.6)                 // or in this item's parent's coordinates
Item {
    id: hb
    width: 0; height: 0

    property var   backdrop: null       // GlassBackdrop to send the shock ring through
    property real  spreadX:  1          // shard spread, e.g. 1.5 × 0.7 along a wide row
    property real  spreadY:  1
    property color light:  Theme.light
    property color ink:    Theme.ink
    property color paper:  Theme.paper
    property color accent: Theme.accent

    property real t: 1        // travel (eased out: fast, then drifting)
    property real life: 1     // linear age, for the fade
    property real s: 1        // strength 0..1
    visible: life < 1

    function play(px, py, strength) {
        x = px; y = py; s = strength === undefined ? 1 : strength
        hbAnim.restart()
        if (backdrop) {
            var p = parent ? parent.mapToItem(backdrop, px, py) : Qt.point(px, py)
            backdrop.impact(p.x, p.y, s)
        }
    }
    function playAt(item, ix, iy, strength) {
        var p = item.mapToItem(hb.parent, ix, iy)
        play(p.x, p.y, strength)
    }

    ParallelAnimation {
        id: hbAnim
        NumberAnimation { target: hb; property: "t";    from: 0; to: 1; duration: 620; easing.type: Easing.OutQuart }
        NumberAnimation { target: hb; property: "life"; from: 0; to: 1; duration: 620 }
    }

    Rectangle {   // light ring
        width: 14; height: 14; x: -7; y: -7; rotation: 45
        color: "transparent"; border.color: hb.light; border.width: 2
        scale: 1 + 5.5 * hb.t * (0.6 + 0.4 * hb.s)
        opacity: 1 - hb.life
    }
    Rectangle {   // ink ring, a step behind
        width: 14; height: 14; x: -7; y: -7; rotation: 45
        color: "transparent"; border.color: hb.ink; border.width: 1
        scale: 1 + 3.4 * Math.max(0, hb.t - 0.08) * (0.6 + 0.4 * hb.s)
        opacity: 0.8 * (1 - hb.life)
    }
    Repeater {
        model: 12
        Rectangle {
            readonly property real ang:  index / 12 * Math.PI * 2 + (index % 3) * 0.23
            readonly property real dist: (index % 3 === 0 ? 150 : index % 3 === 1 ? 104 : 72) * (0.55 + 0.45 * hb.s) * hb.t
            readonly property bool sliver: index % 2 === 1
            readonly property real dx: Math.cos(ang) * hb.spreadX
            readonly property real dy: Math.sin(ang) * hb.spreadY
            width:  sliver ? 16 : 9
            height: sliver ? 2  : 9
            x: dx * dist - width / 2
            y: dy * dist - height / 2
            rotation: sliver ? Math.atan2(dy, dx) * 180 / Math.PI : 45 + hb.t * 180
            color: sliver ? hb.light : (index % 4 === 0 ? hb.accent : hb.paper)
            border.color: sliver ? "transparent" : hb.ink; border.width: sliver ? 0 : 1
            opacity: 1 - hb.life * hb.life
            scale: 1 - 0.55 * hb.life
        }
    }
}
