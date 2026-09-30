import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../theme"

Item {
    id: root

    readonly property int pw: 440
    readonly property int ph: 200
    property real screenW: 1920
    property real screenH: 1080

    property var  shellScreen:     null   // the frame the glass backdrop refracts
    property bool panelOpen:       false
    property bool wipeHideRunning: false
    // Open: map empty → frame captured (_ready) + first frame shown (_gateOk) →
    // reveal. Close: the window unmaps once both the panel and the triangles are gone.
    property bool _ready:     false
    property bool _gateOk:    false
    property bool _panelGone: true
    property bool _bgGone:    true
    property int  curWs:           0

    implicitWidth:  screenW
    implicitHeight: screenH

    // ── Palette (YoRHa Paper · 與 Menu 一致) ─────────────────────────────
    readonly property color paper:     Theme.paper
    readonly property color ink:       Theme.ink
    readonly property color inkStrong: Theme.inkStrong
    readonly property color inkSoft:   Theme.inkSoft
    readonly property color lineSoft:  Theme.alpha(Theme.ink, 0.25)
    readonly property color lineVsoft: Theme.alpha(Theme.ink, 0.12)
    readonly property color accent:    Theme.accent

    // ── Processes ────────────────────────────────────────────────────────
    Process {
        id: getCurWs
        command: ["sh", "-c", "hyprctl activeworkspace -j | jq '.id'"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                var n = parseInt(data.trim())
                if (n > 0) { root.curWs = n; root._doOpen() }
            }
        }
    }

    Process { id: moveProc; running: false }

    Timer {
        id: focusTimer; interval: 50; repeat: true; running: false
        property int attempts: 0
        onTriggered: {
            wsInput.forceActiveFocus()
            attempts++
            if (attempts >= 10) { running = false; attempts = 0 }
        }
    }

    // ── API ───────────────────────────────────────────────────────────────
    function open() {
        if (panelOpen) return
        wsInput.text = ""
        getCurWs.running = true
    }

    function _doOpen() {
        _ready = false; _gateOk = false; _panelGone = false; _bgGone = false
        panelOpen = true
        wipeHide.stop()
        readyFallback.restart()
        // The window is unmapped while closed: show the reveal's start state and
        // wait for the first presented frame so the OutExpo slide isn't clipped.
        panelHost.x       = (root.screenW - root.pw) / 2 + root.pw + 2
        wipeCurtain.x     = 0
        wipeCurtain.width = root.pw
        revealGate.arm()
    }

    MapGate { id: revealGate; onReady: { root._gateOk = true; root._tryReveal() } }
    Timer { id: readyFallback; interval: 350; onTriggered: { root._ready = true; root._tryReveal() } }
    function _tryReveal() {
        if (root.panelOpen && root._gateOk && root._ready && !wipeReveal.running) wipeReveal.start()
    }
    function _maybeFinish() {
        if (!root.panelOpen && root._panelGone && root._bgGone) root.wipeHideRunning = false
    }

    function close() {
        if (!panelOpen) return
        wipeHideRunning = true    // before panelOpen: the window stays mapped (no remap flash)
        panelOpen = false
        if (!_ready) _bgGone = true   // the backdrop never unfolded, so it won't report hidden()
        readyFallback.stop()
        revealGate.disarm()
        wipeReveal.stop()
        wipeHide.start()
    }

    function confirm() {
        var t = parseInt(wsInput.text.trim())
        if (isNaN(t) || t < 1 || t > 20 || t === root.curWs) {
            shakeAnim.restart()
            return
        }
        var script = Qt.resolvedUrl("../scripts/move-ws.sh").toString().replace("file://", "")
        moveProc.running = false
        moveProc.command = ["bash", script, String(root.curWs), String(t)]
        moveProc.running = true
        root.close()
    }

    // ── Backdrop: the shared glass triangles (components/GlassBackdrop.qml) ──
    GlassBackdrop {
        anchors.fill: parent
        z: 0
        screen:    root.shellScreen
        capturing: root.panelOpen || root.wipeHideRunning
        active:    root.panelOpen && root._ready
        originPx:  Qt.point(width, height / 2)    // unfolds from the side the panel slides in from
        onFrameReady: { root._ready = true; readyFallback.stop(); root._tryReveal() }
        onHidden: { root._bgGone = true; root._maybeFinish() }
    }
    MouseArea {
        z: 1; anchors.fill: parent
        enabled: root.panelOpen || root.wipeHideRunning
        onClicked: root.close()
    }

    // ── Panel host (clip + wipe) ──────────────────────────────────────────
    Item {
        id: panelHost
        z: 2
        x: (root.screenW - root.pw) / 2
        y: (root.screenH - root.ph) / 2
        width: root.pw; height: root.ph
        clip:    true
        visible: (root.panelOpen && root._ready) || wipeReveal.running || wipeHide.running

        // Shake animation on invalid input
        SequentialAnimation {
            id: shakeAnim
            NumberAnimation { target:panelHost; property:"x"; to:(root.screenW-root.pw)/2-8; duration:50; easing.type:Easing.OutQuad }
            NumberAnimation { target:panelHost; property:"x"; to:(root.screenW-root.pw)/2+8; duration:60; easing.type:Easing.InOutQuad }
            NumberAnimation { target:panelHost; property:"x"; to:(root.screenW-root.pw)/2-5; duration:50; easing.type:Easing.InOutQuad }
            NumberAnimation { target:panelHost; property:"x"; to:(root.screenW-root.pw)/2;   duration:50; easing.type:Easing.OutBounce }
        }

        // ── Content ──────────────────────────────────────────────────────
        Rectangle {
            id: panelContent
            anchors.fill: parent
            color: root.paper
            border.color: root.ink; border.width: 1

            // Grid
            Repeater {
                model: Math.floor(root.pw / 20) + 1
                Rectangle { x:index*20; y:0; width:1; height:root.ph; color:root.lineVsoft }
            }
            Repeater {
                model: Math.floor(root.ph / 20) + 1
                Rectangle { x:0; y:index*20; width:root.pw; height:1; color:root.lineVsoft }
            }

            // ── HEADER ───────────────────────────────────────────────────
            Item {
                id: hdr; width: parent.width; height: 42

                Row {
                    anchors { left:parent.left; leftMargin:20; verticalCenter:parent.verticalCenter }
                    spacing: 10
                    Text {
                        text: "WORKSPACE RELOCATOR"
                        font.pixelSize:10; font.letterSpacing:3; font.weight:Font.Medium
                        color: root.inkStrong
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle { width:20; height:1; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                    Text {
                        text: "ワークスペース移動"
                        font.pixelSize:9; font.letterSpacing:2; color:root.inkSoft
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors { right:parent.right; rightMargin:20; verticalCenter:parent.verticalCenter }
                    spacing: 6
                    Text { text:"WS"; font.pixelSize:8; font.letterSpacing:2; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                    Text {
                        text: String(root.curWs).padStart(2, "0")
                        font.pixelSize:10; font.letterSpacing:2; color:root.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
            }

            // ── BODY ─────────────────────────────────────────────────────
            Item {
                anchors { top:hdr.bottom; bottom:footer.top; left:parent.left; right:parent.right }

                Column {
                    anchors.centerIn: parent
                    spacing: 14

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "MOVE ALL WINDOWS  ·  WS " + String(root.curWs).padStart(2,"0") + " → ?"
                        font.pixelSize:9; font.letterSpacing:2.5; color:root.inkSoft
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 14

                        Text {
                            text: "TARGET"
                            font.pixelSize:10; font.letterSpacing:3; color:root.inkSoft
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Rectangle {
                            width: 76; height: 42
                            color: "transparent"
                            border.color: wsInput.activeFocus ? root.ink : root.lineSoft
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration:150 } }

                            TextInput {
                                id: wsInput
                                anchors { fill:parent; margins:8 }
                                font.pixelSize:22; font.letterSpacing:4
                                color: root.ink
                                maximumLength: 2
                                inputMethodHints: Qt.ImhDigitsOnly
                                verticalAlignment:   TextInput.AlignVCenter
                                horizontalAlignment: TextInput.AlignHCenter
                                validator: IntValidator { bottom:1; top:20 }
                                Keys.onReturnPressed: root.confirm()
                                Keys.onEnterPressed:  root.confirm()
                                Keys.onEscapePressed: root.close()
                            }
                        }

                        // Accent blink dot
                        Rectangle {
                            width:6; height:6; color:root.accent; radius:3
                            anchors.verticalCenter: parent.verticalCenter
                            opacity: wsInput.activeFocus ? 1.0 : 0.2
                            SequentialAnimation on opacity {
                                running: wsInput.activeFocus; loops: Animation.Infinite
                                NumberAnimation { to:0.15; duration:620 }
                                NumberAnimation { to:1.0;  duration:620 }
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "1 – 20"
                        font.pixelSize:8; font.letterSpacing:3; color:root.inkSoft; opacity:0.45
                    }
                }
            }

            // ── FOOTER ───────────────────────────────────────────────────
            Item {
                id: footer; anchors.bottom:parent.bottom; width:parent.width; height:36
                Rectangle { anchors.top:parent.top; width:parent.width; height:1; color:root.lineSoft }

                Text {
                    anchors { left:parent.left; leftMargin:20; verticalCenter:parent.verticalCenter }
                    text: "YoRHa WORKSPACE CONTROL"
                    font.pixelSize:8; font.letterSpacing:2; color:root.inkSoft; opacity:0.35
                }

                Row {
                    anchors { right:parent.right; rightMargin:20; verticalCenter:parent.verticalCenter }
                    spacing: 14
                    Repeater {
                        model: [["↵","CONFIRM"], ["ESC","CANCEL"]]
                        Row {
                            spacing:5; anchors.verticalCenter:parent.verticalCenter
                            Rectangle {
                                width:kT.implicitWidth+8; height:16; color:"transparent"
                                border.color:root.lineSoft; border.width:1
                                Text { id:kT; anchors.centerIn:parent; text:modelData[0]; font.pixelSize:9; font.letterSpacing:1; color:root.ink }
                            }
                            Text { text:modelData[1]; font.pixelSize:9; font.letterSpacing:2; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                        }
                    }
                }
            }
        }

        // Wipe curtain (horizontal, like Menu)
        Rectangle {
            id: wipeCurtain
            anchors { top:parent.top; bottom:parent.bottom }
            color: root.paper; z:50; width:2; x:root.pw-2
        }
    }

    // ── Animations (horizontal wipe · Menu style) ─────────────────────────
    SequentialAnimation {
        id: wipeReveal
        onStarted: {
            panelHost.x       = (root.screenW - root.pw) / 2 + root.pw + 2
            wipeCurtain.x     = 0
            wipeCurtain.width = root.pw
        }
        NumberAnimation {
            target:panelHost; property:"x"
            to:(root.screenW-root.pw)/2
            duration:380; easing.type:Easing.OutExpo
        }
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     to:root.pw-2; duration:280; easing.type:Easing.OutExpo }
            NumberAnimation { target:wipeCurtain; property:"width"; to:2;         duration:280; easing.type:Easing.OutExpo }
        }
        onFinished: {
            wipeCurtain.width = 0
            focusTimer.attempts = 0
            focusTimer.restart()
        }
    }

    SequentialAnimation {
        id: wipeHide
        onStarted: {
            wipeCurtain.x     = root.pw - 2
            wipeCurtain.width = 2
        }
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     to:0;       duration:160; easing.type:Easing.InOutQuart }
            NumberAnimation { target:wipeCurtain; property:"width"; to:root.pw; duration:160; easing.type:Easing.InOutQuart }
        }
        NumberAnimation {
            target:panelHost; property:"x"
            to:(root.screenW-root.pw)/2+root.pw+2
            duration:280; easing.type:Easing.InExpo
        }
        onFinished: { root._panelGone = true; root._maybeFinish() }
    }
}
