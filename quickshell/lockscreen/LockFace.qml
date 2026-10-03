import QtQuick
import Quickshell
import Quickshell.Io
import "../theme"
import "../settings"
import "../components"

// LockFace — one screen of the session lock, built like the power exit (the Void's
// reference): the desktop shatters into the dark, then a diamond, SYSTEM LOCKED, one
// hairline and a mono line (the time, where the exit shows its command) fade in — and under
// them, the password as a diamond per character. No big clock, no corners, no typing
// effect. Every screen shows the same state (LockState); whichever has the keyboard types.
// Nothing animates at rest but the caret's two-frames-a-second blink.
Item {
    id: face
    required property var st
    property var scr: null

    readonly property real  u:     Math.max(0.7, height / 1080)
    readonly property color fg:    Theme.voidLight
    readonly property color dim:   Theme.alpha(Theme.voidLight, 0.6)
    readonly property color faint: Theme.alpha(Theme.voidLight, 0.22)
    readonly property color warn:  Theme.voidWarn
    readonly property string vfont: Theme.voidFont
    // the Void's type scale (Theme.voidStep: px at 1080 p) at this screen's size
    readonly property real s0: Theme.voidStep(0) * u      // the mono line, the status
    readonly property real s2: Theme.voidStep(2) * u      // the title (as the exit's)
    readonly property int  wt: Theme.voidWeight

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

    // ── the time, for the mono line ──
    property date now: new Date()
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: face.now = new Date() }
    function pad(n) { return String(n).padStart(2, "0") }
    readonly property var days:   ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    readonly property var months: ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    // ── motion ──
    property real inT: 0          // the face fading in
    SequentialAnimation {
        id: introT
        // with the frozen desktop: it shows under the glass, then shatters into the dark (the
        // power exit's move) and the face fades in; without it, the glass unfolds over black
        PauseAnimation { duration: 60 }
        ScriptAction { script: glass.active = true }
        PauseAnimation { duration: face.hasFrame ? 420 : 640 }
        ScriptAction { script: if (face.hasFrame) glass.active = false }
        PauseAnimation { duration: face.hasFrame ? 380 : 0 }
        ParallelAnimation {
            NumberAnimation { target: face; property: "inT"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                ScriptAction { script: glass.active = false }      // (no frame) shatters as the face comes in
            }
        }
    }
    Timer { id: closeT; interval: 350; onTriggered: glass.active = true }   // the glass closes over the face, then the screen opens
    Connections {
        target: face.st
        function onFailedPulse() { inputLine.fail() }
        function onAuthorizedPulse() { inputLine.ok(); closeT.start() }
    }

    // ── the exit's composition: diamond · title · hairline · mono line, then the password ──
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        // the optical centre sits a little above the middle (46 %)
        anchors.verticalCenterOffset: -0.04 * face.height + (1 - face.inT) * 14 * face.u
        spacing: 0
        opacity: face.inT

        Item {   // the diamond, its core pulsing while PAM thinks
            anchors.horizontalCenter: parent.horizontalCenter
            width: 18 * face.u; height: width
            readonly property color c: face.st.phase === "failed" ? face.warn : face.fg
            Rectangle {
                anchors.centerIn: parent; width: 12 * face.u; height: width; rotation: 45
                color: "transparent"; border.color: parent.c; border.width: 1
            }
            Rectangle {
                anchors.centerIn: parent; width: 5 * face.u; height: width; rotation: 45
                color: parent.c
                opacity: face.st.phase === "verifying" ? 0.3 + 0.7 * blink.v : 0.8
            }
        }
        Item { width: 1; height: 16 * face.u }
        Text {      // no typing: phase changes just switch the words
            anchors.horizontalCenter: parent.horizontalCenter
            text: ({ idle: "SYSTEM LOCKED", verifying: "VERIFYING", failed: "ACCESS DENIED",
                     authorized: "UNLOCKED" })[face.st.phase] || ""
            font.family: face.vfont; font.weight: face.wt
            font.pixelSize: Math.round(face.s2); font.letterSpacing: 0.26 * face.s2
            color: face.st.phase === "failed" ? face.warn : face.fg
        }
        Item { width: 1; height: 16 * face.u }
        Rectangle {   // the hairline, opening with the face
            anchors.horizontalCenter: parent.horizontalCenter
            width: 260 * face.u * face.inT; height: 1
            color: face.fg; opacity: 0.45
        }
        Item { width: 1; height: 14 * face.u }
        Text {        // where the exit shows its command: the time
            anchors.horizontalCenter: parent.horizontalCenter
            text: face.pad(face.now.getHours()) + ":" + face.pad(face.now.getMinutes()) + "  ·  "
                + face.days[face.now.getDay()] + " " + face.pad(face.now.getDate()) + " " + face.months[face.now.getMonth()]
            font.family: "Iosevka, monospace"; font.pixelSize: Math.round(face.s0); font.letterSpacing: 0.04 * face.s0
            color: face.dim
        }
        Item { width: 1; height: 44 * face.u }
        // the password: a diamond per character on a hairline (components/VoidField.qml)
        VoidField {
            id: inputLine
            anchors.horizontalCenter: parent.horizontalCenter
            u: face.u
            text: face.st.text
            phase: face.st.phase
            blink: blink.v
            opacity: face.st.text !== "" || face.st.phase !== "idle" ? 1 : 0.55
            Behavior on opacity { NumberAnimation { duration: 220 } }
            Component.onCompleted: burst.backdrop = glass
        }
        Item { width: 1; height: 14 * face.u }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property int wait: Math.max(0, Math.ceil((face.st.holdUntil - face.now.getTime()) / 1000))
            text: face.st.caps ? "CAPS LOCK ON"
                : wait > 0 ? "RETRY IN " + wait + " S"
                : face.st.fails > 0 ? face.st.fails + (face.st.fails === 1 ? " FAILED ATTEMPT" : " FAILED ATTEMPTS") : " "
            font.family: face.vfont; font.weight: face.wt
            font.pixelSize: Math.round(face.s0); font.letterSpacing: 0.3 * face.s0
            color: face.st.caps || wait > 0 ? face.warn : face.dim
        }
    }

    // caret / verifying blink — stepped, not animated: two frames a second while locked
    QtObject {
        id: blink
        property real v: 1
        property var _t: Timer { interval: 530; running: true; repeat: true; onTriggered: blink.v = blink.v > 0.5 ? 0.15 : 1 }
    }

    // ── the glass: unfolds over the black and shatters (lock), closes over the face (unlock) ──
    // the desktop as it was (scripts/lock.sh: $XDG_RUNTIME_DIR/qs-lock-<screen>.ppm), only
    // as the glass's frame: drawn through the panes, gone with them
    readonly property string framePath: scr && scr.name ? (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-lock-" + scr.name + ".ppm" : ""
    readonly property bool hasFrame: frozen.status === Image.Ready
    Image {
        id: frozen
        anchors.fill: parent
        source: face.framePath !== "" ? "file://" + face.framePath : ""
        cache: false
        asynchronous: false
        fillMode: Image.Stretch
    }
    ShaderEffectSource { id: frozenTex; sourceItem: frozen; hideSource: true; visible: false }

    TriField {
        id: glass
        anchors.fill: parent
        sourceTex: face.hasFrame ? frozenTex : null
        hasSource: face.hasFrame
        dimAmount: face.hasFrame ? Settings.backdropDim : 0
        targetOpacity: face.hasFrame ? Settings.backdropOpacity : Math.max(0.5, Settings.backdropOpacity)
        flickerAmount: 0.5
        originPx: Qt.point(width / 2, height / 2)
        glarePx: Qt.point(width / 2, height / 2)
    }
}
