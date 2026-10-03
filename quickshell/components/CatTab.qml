import QtQuick
import "../theme"

// A category tab for the NieR panels' sidebars (ScreenCapture, Menu).
// When picked, its ink fill wipes in the direction of the gesture (`dir`: +1 = →
// fills from the left edge, -1 = ← from the right) while the tab being left
// drains the same way, like a baton handed along; the label inverts exactly
// along the moving edge. The marker spins from a dash into a diamond (turning
// with the gesture) and throws off a light ring.
Item {
    id: tab
    width: 160; height: 34

    property string label:   ""
    property string sub:     ""      // small right-aligned text (reading, count…)
    property bool   active:  false
    property int    dir:     1
    property bool   animate: true    // false while the panel is hidden: snap, don't play
    property real   pulse:   0       // beat pulse (0..1) for the accent edge
    signal clicked()

    readonly property color paper:   Theme.paper
    readonly property color ink:     Theme.ink
    readonly property color inkStrong: Theme.inkStrong
    readonly property color inkSoft: Theme.inkSoft
    readonly property color accent:  Theme.accent
    readonly property color light:   Theme.light

    // Ink fill spans fL..fR
    property real fL: 0
    property real fR: 0
    Component.onCompleted: fR = active ? width : 0
    NumberAnimation { id: fillIn;  target: tab; duration: 300; easing.type: Easing.OutCubic }
    NumberAnimation { id: fillOut; target: tab; duration: 240; easing.type: Easing.InOutCubic }
    onActiveChanged: {
        fillIn.stop(); fillOut.stop()
        if (!animate) { fL = 0; fR = active ? width : 0; return }
        if (active) {
            if (dir > 0) { fL = 0;     fR = 0;     fillIn.property = "fR" }
            else         { fL = width; fR = width; fillIn.property = "fL" }
            fillIn.to = dir > 0 ? width : 0
            fillIn.start()
            pick.restart()
        } else {
            fillOut.property = dir > 0 ? "fL" : "fR"
            fillOut.to = dir > 0 ? width : 0
            fillOut.start()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: !tab.active && ma.containsMouse ? Theme.alpha(Theme.ink, 0.07) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // Label in ink…
    Face { anchors.fill: parent; hovered: ma.containsMouse }
    // …and in paper, only inside the fill
    Item {
        x: tab.fL; width: Math.max(0, tab.fR - tab.fL); height: parent.height
        clip: true
        Rectangle { anchors.fill: parent; color: tab.ink }
        Face { x: -tab.fL; width: tab.width; height: tab.height; inked: true }
        Rectangle { x: -tab.fL; width: 2 + 3 * tab.pulse; height: parent.height; color: tab.accent }
    }

    // Marker: dash ⇄ diamond
    Item {
        x: 20; width: 10; height: 10; anchors.verticalCenter: parent.verticalCenter
        Rectangle {
            id: ring
            anchors.centerIn: parent; width: 6; height: 6; rotation: 45
            color: "transparent"; border.color: tab.light; border.width: 1
            opacity: 0
        }
        Rectangle {
            id: gem
            anchors.centerIn: parent
            width:  tab.active ? 6 : (ma.containsMouse ? 8 : 4)
            height: tab.active ? 6 : 1
            rotation: tab.active ? (tab.dir > 0 ? 225 : -135) : 0
            color: tab.active ? tab.paper : tab.inkSoft
            Behavior on width    { NumberAnimation { duration: 240; easing.type: Easing.OutQuart } }
            Behavior on height   { NumberAnimation { duration: 240; easing.type: Easing.OutQuart } }
            Behavior on rotation { NumberAnimation { duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on color    { ColorAnimation  { duration: 180 } }
        }
        ParallelAnimation {
            id: pick
            NumberAnimation { target: ring; property: "scale";   from: 1;   to: 3.4; duration: 520; easing.type: Easing.OutCubic }
            NumberAnimation { target: ring; property: "opacity"; from: 0.9; to: 0;   duration: 520; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: gem; property: "scale"; from: 0.3; to: 1.5; duration: 170; easing.type: Easing.OutQuad }
                NumberAnimation { target: gem; property: "scale"; to: 1; duration: 300; easing.type: Easing.OutBack }
            }
        }
    }

    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: tab.clicked() }

    component Face: Item {
        property bool hovered: false
        property bool inked:   false
        Text {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            text: tab.label; font.pixelSize: Theme.fs(10); font.letterSpacing: 2
            color: inked ? tab.paper : (hovered ? tab.inkStrong : tab.inkSoft)
        }
        Text {
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: tab.sub; font.pixelSize: Theme.fs(8); font.letterSpacing: 1
            color: inked ? Theme.alpha(Theme.paper, 0.6) : Theme.alpha(Theme.inkSoft, 0.5)
        }
    }
}
