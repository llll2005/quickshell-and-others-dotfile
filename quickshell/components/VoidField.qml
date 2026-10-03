import QtQuick
import "../theme"

// VoidField — a secret typed in the Void (the lock, the polkit prompt): a diamond per
// character on a hairline, a hollow diamond for the caret, a hint while it's empty.
// It only draws; the owner keeps the text (typed from key events, never a TextInput, so
// no input method sees it) and calls fail() / ok() for the shake and the hit.
//   echo     show the characters instead (polkit's responseVisible)
//   phase    idle · verifying · failed · authorized
Item {
    id: vf
    property string text: ""
    property bool   echo: false
    property string phase: "idle"
    property string hint: "TYPE TO UNLOCK"
    property real   u: 1
    property string mono: Theme.mono
    property real   blink: 1           // the owner's stepped blink (0.15 · 1)

    readonly property bool  busy: phase === "verifying" || phase === "authorized"
    readonly property color fg:   Theme.light

    width: 360 * u; height: 26 * u

    property real shake: 0
    property real okT: 0
    function fail() { shakeAnim.restart(); burst.playAt(vf, width / 2, height, 0.45) }
    function ok()   { okAnim.restart();    burst.playAt(vf, width / 2, height, 1.2) }
    NumberAnimation { id: shakeAnim; target: vf; property: "shake"; from: 0; to: 1; duration: 460 }
    NumberAnimation { id: okAnim; target: vf; property: "okT"; from: 0; to: 1; duration: 90; easing.type: Easing.OutQuad }

    Item {
        anchors.fill: parent
        transform: Translate { x: 12 * vf.u * Math.sin(vf.shake * Math.PI * 5) * (1 - vf.shake) }
        Row {
            anchors.centerIn: parent
            spacing: 11 * vf.u
            Repeater {
                model: vf.echo ? 0 : Math.min(vf.text.length, 24)
                Rectangle {
                    width: 7 * vf.u; height: width; rotation: 45
                    anchors.verticalCenter: parent.verticalCenter
                    color: vf.fg
                    opacity: vf.phase === "verifying" ? 0.45 : 1
                    scale: 1 + 0.35 * vf.okT
                }
            }
            Text {       // echo: the characters themselves
                visible: vf.echo && vf.text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: vf.text
                font.family: vf.mono; font.pixelSize: Math.round(13 * vf.u); font.letterSpacing: 2 * vf.u
                color: vf.fg
            }
            Rectangle {  // caret
                visible: !vf.busy
                width: 7 * vf.u; height: width; rotation: 45
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"; border.color: vf.fg; border.width: 1
                opacity: vf.blink
            }
            Text {       // what to do, after the caret while nothing is typed
                visible: vf.text === "" && vf.phase === "idle"
                anchors.verticalCenter: parent.verticalCenter
                text: vf.hint
                font.family: vf.mono; font.pixelSize: Math.round(10 * vf.u); font.letterSpacing: 3 * vf.u
                color: Theme.alpha(Theme.light, 0.22)
            }
        }
        Rectangle {
            anchors.bottom: parent.bottom; width: parent.width; height: 1
            color: vf.phase === "failed" ? Theme.warn : Theme.alpha(Theme.light, 0.4)
        }
        Rectangle { anchors.fill: parent; color: vf.fg; opacity: 0.25 * vf.okT * (1 - vf.okT * 0.5) }
    }
    property alias burst: burst
    HitBurst { id: burst }
}
