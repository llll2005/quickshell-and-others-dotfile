import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../settings"
import "../components"
import "../services"

// LockFace — one screen of the session lock, in the Void: black, light type, a diamond,
// words that scramble in. Every screen shows the same state (LockState); whichever one
// has the keyboard takes the typing.
//
// The glass is only for the moments: on lock it unfolds over the black and shatters away
// as the face scrambles in; on the right password it unfolds again over the face and the
// screen opens. In between nothing animates but the caret and the seconds, so a locked
// machine idles.
Item {
    id: face
    required property var st
    property var scr: null

    readonly property real  u:     Math.max(0.7, height / 1080)
    readonly property color fg:    Theme.light
    readonly property color dim:   Theme.alpha(Theme.light, 0.55)
    readonly property color faint: Theme.alpha(Theme.light, 0.22)
    readonly property color warn:  Theme.warn
    readonly property string mono: Theme.mono

    focus: true
    Component.onCompleted: forceActiveFocus()
    // the surface gets its size a moment after it maps: start once it has one
    property bool _started: false
    onWidthChanged: if (width > 0 && !_started) { _started = true; introT.start() }

    Keys.onPressed: (e) => {
        var k = e.key
        if (k === Qt.Key_Return || k === Qt.Key_Enter) face.st.submit()
        else if (k === Qt.Key_Backspace) {
            if (e.modifiers & Qt.ControlModifier) face.st.clear(); else face.st.backspace()
        }
        else if (k === Qt.Key_Escape || (k === Qt.Key_U && (e.modifiers & Qt.ControlModifier))) face.st.clear()
        else if (e.text !== "" && e.text.charCodeAt(0) >= 32 && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) face.st.type(e.text)
        face.st.readCaps()
        e.accepted = true
    }

    // ── clock ──
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: face.now = new Date() }
    function pad(n) { return String(n).padStart(2, "0") }
    readonly property var days:   ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    readonly property var months: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    property string host: ""
    FileView { path: "/etc/hostname"; onLoaded: face.host = text().trim() }
    readonly property string user: Quickshell.env("USER") || ""

    // ── motion ──
    property real inT: 0          // the face scrambling in
    property real shake: 0        // a failed password
    property real okT: 0          // the authorized hit
    SequentialAnimation {
        id: introT
        PauseAnimation { duration: 60 }
        ScriptAction { script: glass.active = true }
        PauseAnimation { duration: 640 }
        ScriptAction { script: { prompt.play(); clock.play() } }
        ParallelAnimation {
            NumberAnimation { target: face; property: "inT"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                ScriptAction { script: glass.active = false }      // shatters as the face comes in
            }
        }
    }
    NumberAnimation { id: shakeAnim; target: face; property: "shake"; from: 0; to: 1; duration: 460 }
    SequentialAnimation {
        id: okAnim
        NumberAnimation { target: face; property: "okT"; from: 0; to: 1; duration: 90; easing.type: Easing.OutQuad }
        PauseAnimation { duration: 260 }
        ScriptAction { script: glass.active = true }      // the glass closes over the face, then the screen opens
    }
    Connections {
        target: face.st
        function onFailedPulse() { shakeAnim.restart(); burst.playAt(inputLine, inputLine.width / 2, 0, 0.45) }
        function onAuthorizedPulse() { okAnim.restart(); burst.playAt(inputLine, inputLine.width / 2, 0, 1.2) }
    }

    // ── corner brackets ──
    Repeater {
        model: 4
        Item {
            readonly property bool r: index % 2 === 1
            readonly property bool b: index >= 2
            x: r ? face.width - 36 * face.u - width : 36 * face.u
            y: b ? face.height - 36 * face.u - height : 36 * face.u
            width: 22 * face.u; height: 22 * face.u
            opacity: face.inT
            Rectangle { x: parent.r ? parent.width - 1 : 0; width: 1; height: parent.height; color: face.faint }
            Rectangle { y: parent.b ? parent.height - 1 : 0; width: parent.width; height: 1; color: face.faint }
        }
    }

    // ── top: what this is ──
    Text {
        x: 72 * face.u; y: 48 * face.u
        text: "SYSTEM LOCKED"
        font.family: face.mono; font.pixelSize: Math.round(11 * face.u); font.letterSpacing: 4 * face.u
        color: face.dim; opacity: face.inT
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 72 * face.u; y: 48 * face.u
        text: face.now.getFullYear() + "." + face.pad(face.now.getMonth() + 1) + "." + face.pad(face.now.getDate())
        font.family: face.mono; font.pixelSize: Math.round(11 * face.u); font.letterSpacing: 4 * face.u
        color: face.dim; opacity: face.inT
    }

    // ── centre ──
    Column {
        id: centre
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -30 * face.u + (1 - face.inT) * 14 * face.u
        spacing: 0
        opacity: face.inT

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10 * face.u
            ScrambleText {
                id: clock
                playOnChange: false
                target: face.pad(face.now.getHours()) + ":" + face.pad(face.now.getMinutes())
                font.family: face.mono; font.pixelSize: Math.round(118 * face.u); font.letterSpacing: 4 * face.u
                color: face.fg
            }
            Text {
                y: 22 * face.u
                text: face.pad(face.now.getSeconds())
                font.family: face.mono; font.pixelSize: Math.round(22 * face.u)
                color: face.dim
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: face.days[face.now.getDay()] + "  ·  " + face.pad(face.now.getDate()) + " " + face.months[face.now.getMonth()] + " " + face.now.getFullYear()
            font.family: face.mono; font.pixelSize: Math.round(13 * face.u); font.letterSpacing: 4 * face.u
            color: face.dim
        }

        Item { width: 1; height: 44 * face.u }

        Item {   // the rule, a diamond at its middle
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300 * face.u; height: 9 * face.u
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * face.inT; x: (parent.width - width) / 2; height: 1; color: face.faint }
            Rectangle {
                anchors.centerIn: parent; width: 7 * face.u; height: width; rotation: 45
                color: "black"; border.color: face.st.phase === "failed" ? face.warn : face.fg; border.width: 1
                Rectangle {
                    anchors.centerIn: parent; width: 3 * face.u; height: width
                    color: face.st.phase === "failed" ? face.warn : face.fg
                    opacity: face.st.phase === "verifying" ? 0.35 + 0.65 * blink.v : 0.85
                }
            }
        }

        Item { width: 1; height: 26 * face.u }

        ScrambleText {
            id: prompt
            anchors.horizontalCenter: parent.horizontalCenter
            target: ({ idle: "AUTHORIZATION REQUIRED", verifying: "VERIFYING", failed: "FAILED",
                       authorized: "AUTHORIZED" })[face.st.phase] || ""
            duration: 360
            font.family: face.mono; font.pixelSize: Math.round(12 * face.u); font.letterSpacing: 6 * face.u
            color: face.st.phase === "failed" ? face.warn : face.fg
        }

        Item { width: 1; height: 22 * face.u }

        // the password: a diamond per character on a hairline, the caret a hollow one
        Item {
            id: inputLine
            anchors.horizontalCenter: parent.horizontalCenter
            width: 360 * face.u; height: 26 * face.u
            transform: Translate { x: 12 * face.u * Math.sin(face.shake * Math.PI * 5) * (1 - face.shake) }
            Row {
                id: dots
                anchors.centerIn: parent
                spacing: 11 * face.u
                Repeater {
                    model: Math.min(face.st.text.length, 24)
                    Rectangle {
                        width: 7 * face.u; height: width; rotation: 45
                        anchors.verticalCenter: parent.verticalCenter
                        color: face.fg
                        opacity: face.st.phase === "verifying" ? 0.45 : 1
                        scale: 1 + 0.35 * face.okT
                    }
                }
                Rectangle {   // caret
                    visible: !face.st.busy
                    width: 7 * face.u; height: width; rotation: 45
                    anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"; border.color: face.fg; border.width: 1
                    opacity: blink.v
                }
                Text {        // what to do, after the caret while nothing is typed
                    visible: face.st.text === "" && face.st.phase === "idle"
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TYPE TO UNLOCK"
                    font.family: face.mono; font.pixelSize: Math.round(10 * face.u); font.letterSpacing: 3 * face.u
                    color: face.faint
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom; width: parent.width; height: 1
                color: face.st.phase === "failed" ? face.warn : Theme.alpha(Theme.light, 0.4)
            }
            Rectangle { anchors.fill: parent; color: face.fg; opacity: 0.25 * face.okT * (1 - face.okT * 0.5) }
        }

        Item { width: 1; height: 16 * face.u }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property int wait: Math.max(0, Math.ceil((face.st.holdUntil - face.now.getTime()) / 1000))
            text: face.st.caps ? "CAPS LOCK ON"
                : wait > 0 ? "RETRY IN " + wait + " S"
                : face.st.fails > 0 ? face.st.fails + (face.st.fails === 1 ? " FAILED ATTEMPT" : " FAILED ATTEMPTS") : " "
            font.family: face.mono; font.pixelSize: Math.round(10 * face.u); font.letterSpacing: 3 * face.u
            color: face.st.caps || wait > 0 ? face.warn : face.dim
        }
    }

    // ── bottom: who, and the power left ──
    Text {
        x: 72 * face.u; anchors.bottom: parent.bottom; anchors.bottomMargin: 48 * face.u
        text: "USER " + face.user.toUpperCase() + (face.host ? "   ·   HOST " + face.host.toUpperCase() : "")
        font.family: face.mono; font.pixelSize: Math.round(10 * face.u); font.letterSpacing: 3 * face.u
        color: face.dim; opacity: face.inT
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 72 * face.u
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48 * face.u
        visible: Battery.available
        text: "BAT " + Battery.percent + "%" + (Battery.charging ? "  ·  CHARGING" : "")
        font.family: face.mono; font.pixelSize: Math.round(10 * face.u); font.letterSpacing: 3 * face.u
        color: Battery.percent <= 15 && !Battery.charging ? face.warn : face.dim
        opacity: face.inT
    }

    // caret / verifying blink — stepped, not animated: two frames a second while locked
    QtObject {
        id: blink
        property real v: 1
        property var _t: Timer { interval: 530; running: true; repeat: true; onTriggered: blink.v = blink.v > 0.5 ? 0.15 : 1 }
    }

    // ── the glass: unfolds over the black and shatters (lock), closes over the face (unlock) ──
    TriField {
        id: glass
        anchors.fill: parent
        dimAmount: 0
        targetOpacity: Math.max(0.5, Settings.backdropOpacity)
        flickerAmount: 0.5
        originPx: Qt.point(width / 2, height / 2)
        glarePx: Qt.point(width / 2, height / 2)
    }
    HitBurst { id: burst; backdrop: glass }
}
