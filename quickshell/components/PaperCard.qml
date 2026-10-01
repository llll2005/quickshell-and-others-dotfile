import QtQuick
import "../theme"

// The popups' card: paper, an ink frame, a fine grid, a glass rim along the top
// (its glint drifts with `t`, the popup's rhythm clock) and cut-diamond corners.
// Content goes inside like any Rectangle.
Rectangle {
    id: card
    property real t: 0
    property int  gridStep: 20
    property bool grid: true

    color: Theme.paper
    border.color: Theme.ink; border.width: 1

    Repeater {
        model: card.grid ? Math.floor(card.width / card.gridStep) + 1 : 0
        Rectangle { x: index * card.gridStep; width: 1; height: card.height; color: Theme.alpha(Theme.ink, 0.12) }
    }
    Repeater {
        model: card.grid ? Math.floor(card.height / card.gridStep) + 1 : 0
        Rectangle { y: index * card.gridStep; width: card.width; height: 1; color: Theme.alpha(Theme.ink, 0.12) }
    }
    Rectangle {
        x: 1; y: 1; width: card.width - 2; height: 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.35 + 0.05 * Math.sin(card.t * 0.8); color: Theme.alpha(Theme.light, 0.9) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }
    Repeater {
        model: 4
        Rectangle {
            width: 7; height: 7; rotation: 45; antialiasing: true
            x: (index % 2 === 0 ? 0 : card.width) - 3.5
            y: (index < 2 ? 0 : card.height) - 3.5
            color: Theme.ink
        }
    }
}
