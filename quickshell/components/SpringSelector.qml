import QtQuick
import "../theme"

// The ink selector the popups' lists share: it springs to `targetY`, two fainter
// afterimages trail it on slower springs, a light sheen sweeps it on sheen(), it
// pops with `hitT` (a confirm's hit-stop) and flashes with `flashV`; its accent
// edge beats with `pulse`.
//
// In a ListView set `parent: list.contentItem` — a ListView doesn't move declared
// children into its content, so the selector would stay put while the rows scroll.
Item {
    id: sel
    property real targetY: 0
    property real rowH: 46
    property real hitT: 0
    property real flashV: 0
    property real pulse: 0
    property color fill: Theme.ink
    property color edge: Theme.accent
    function sheen() { sheenAnim.restart() }

    height: 0     // the parts place themselves at targetY
    z: -1

    Rectangle {
        width: sel.width; height: sel.rowH; color: sel.fill; opacity: 0.10
        y: sel.targetY
        Behavior on y { SpringAnimation { spring: 2.2; damping: 0.36; epsilon: 0.3 } }
    }
    Rectangle {
        width: sel.width; height: sel.rowH; color: sel.fill; opacity: 0.22
        y: sel.targetY
        Behavior on y { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.3 } }
    }
    Item {
        id: main
        width: sel.width; height: sel.rowH
        y: sel.targetY
        Behavior on y { SpringAnimation { spring: 5.5; damping: 0.30; epsilon: 0.25 } }
        scale: 1 + 0.05 * sel.hitT
        Rectangle { anchors.fill: parent; color: sel.fill }
        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 2 + 4 * sel.pulse; color: sel.edge
        }
        Item {
            anchors.fill: parent; clip: true
            Rectangle {
                id: glint
                width: 80; height: parent.height * 2; y: -parent.height / 2
                rotation: 18; x: -140
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Theme.alpha(Theme.light, 0.26) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            NumberAnimation {
                id: sheenAnim; target: glint; property: "x"
                from: -140; to: main.width + 60; duration: 640; easing.type: Easing.OutCubic
            }
        }
        Rectangle { anchors.fill: parent; color: Theme.light; opacity: sel.flashV * 0.4 }
    }
}
