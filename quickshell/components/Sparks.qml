import QtQuick
import "../theme"

// Small diamond sparks that pop up from a point and fall back as they fade —
// the typing sparks. A fixed pool reused round-robin; fill the area they may fly in.
//
//   sparks.fire(x, y)        // a handful, in this item's coordinates
Item {
    id: sp
    property int   count: 4                 // per fire()
    property color light: Theme.light
    property color paper: Theme.paper
    property color brick: Theme.warn
    property color rim:   Theme.inkStrong         // ink rim: they read on light and dark alike

    property int _next: 0
    function fire(x, y) {
        for (var n = 0; n < count; n++) {
            var s = pool.itemAt(_next)
            _next = (_next + 1) % pool.count
            if (s) s.go(x, y)
        }
    }

    Repeater {
        id: pool
        model: 24
        Rectangle {
            id: d
            width: index % 4 === 0 ? 7 : 5; height: width; rotation: 45; antialiasing: true
            visible: t > 0 && t < 1
            property real t: 0
            property real ox: 0
            property real oy: 0
            property real vx: 0
            property real vy: 0
            x: ox + vx * t - 2
            y: oy + vy * t + 26 * t * t - 2     // a little gravity pulls them back
            opacity: 1 - t * t
            scale: 1 - 0.6 * t
            color: index % 3 === 0 ? sp.light : (index % 3 === 1 ? sp.paper : sp.brick)
            border.color: sp.rim; border.width: 1
            function go(x, y) {
                ox = x + (Math.random() - 0.5) * 6
                oy = y + (Math.random() - 0.5) * 6
                var a = -Math.PI / 2 + (Math.random() - 0.5) * 1.6
                var v = 26 + Math.random() * 30
                vx = Math.cos(a) * v; vy = Math.sin(a) * v
                anim.restart()
            }
            NumberAnimation { id: anim; target: d; property: "t"; from: 0; to: 1; duration: 520; easing.type: Easing.OutCubic }
        }
    }
}
