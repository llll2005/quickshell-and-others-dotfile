import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import "../components"
import "../theme"
import "../settings"

// AuthPrompt — every password the desktop asks for, in the Void: the glass unfolds over
// the screen and collapses into the dark, then "AUTHORIZATION REQUIRED", what is being
// asked for, and the password as diamonds (components/VoidField.qml; typed from key
// events, so no input method sees it). Two sources, one screen, one at a time:
//   · polkit (pkexec, systemctl, GUI apps asking for root) — this is the session's agent
//   · requests over a private socket, $XDG_RUNTIME_DIR/qs-void-ask.sock: voidbox-askpass
//     when it has no terminal (ssh / git / sudo from a GUI app), pinentry-void (gpg).
//     One JSON line in — {kind: secret|text|confirm|info, title, message, detail, error,
//     hint} — and one out, {ok, value}; a requester that hangs up closes its prompt.
//   ↵ authorize / submit · Esc cancel · ←→ identity (polkit) or YES / NO (confirm)
//
// Only one polkit agent can be registered per session: at start the KDE agent (if a
// previous session left it) is stopped so this one registers; if this one still can't
// register, the KDE agent is started again as the fallback. If Quickshell dies, GUI
// requests wait for an agent, but terminal ones (pkexec, systemctl, sudo) still ask in the
// terminal, and voidbox-askpass draws there too.
Popup {
    id: root
    clickOutCloses: false

    // ── the agent ──
    property bool _agentOn: false
    Loader {
        id: agentLoader
        active: root._agentOn
        sourceComponent: PolkitAgent { onAuthenticationRequestStarted: root.begin() }
    }
    readonly property var agent: agentLoader.item
    readonly property var flow: agent ? agent.flow : null
    readonly property bool registered: !!agent && agent.isRegistered

    Process {
        running: true
        // a socket file left by a previous qs would stop the server from listening
        command: ["sh", "-c", "pkill -f /usr/lib/polkit-kde-authentication-agent-1; rm -f \"$1\"; sleep 0.3", "sh", root.askPath]
        onExited: { root._agentOn = true; regCheck.start() }
    }
    Timer {
        id: regCheck; interval: 5000
        onTriggered: if (!root.registered) {
            console.warn("[AuthPrompt] polkit agent not registered — starting the KDE agent instead")
            Quickshell.execDetached(["/usr/lib/polkit-kde-authentication-agent-1"])
        }
    }

    // ── the socket ──
    readonly property string askPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-void-ask.sock"
    SocketServer {
        active: root._agentOn
        path: root.askPath
        handler: Socket {
            id: sock
            parser: SplitParser { onRead: (line) => root.askIn(sock, line) }
            onConnectedChanged: if (!connected) root.askGone(sock)
        }
    }
    property var ask: null              // the socket request on screen
    property var askQueue: []
    property bool polkitWaiting: false
    readonly property bool asking: ask !== null
    readonly property string kind: asking ? ask.kind : "secret"

    function askIn(s, line) {
        var r
        try { r = JSON.parse(line) } catch (e) { return }
        var kinds = ["secret", "text", "confirm", "info"]
        r.kind = kinds.indexOf(r.kind) >= 0 ? r.kind : "secret"
        r.sock = s
        askQueue = askQueue.concat([r])
        pump()
    }
    function askGone(s) {
        askQueue = askQueue.filter(function(r) { return r.sock !== s })
        if (ask && ask.sock === s && authPhase !== "authorized") { ask.sock = null; close() }
    }
    function askReply(ok, value) {
        if (!ask || !ask.sock || !ask.sock.connected) return
        ask.sock.write(JSON.stringify(ok ? { ok: true, value: value } : { ok: false }) + "\n")
        ask.sock.flush()
        ask.sock = null
    }
    // the next request, once the screen is free (polkit first: its caller is blocked on it)
    function pump() {
        if (phase !== "closed") return
        if (polkitWaiting) { polkitWaiting = false; showPolkit(); return }
        if (askQueue.length === 0) return
        ask = askQueue[0]
        askQueue = askQueue.slice(1)
        if (!ask.sock || !ask.sock.connected) { ask = null; pump(); return }
        text = ""; authPhase = "idle"; choice = 1
        message = ask.message || ""
        actionId = ask.detail || ""
        open()
    }
    onFinished: { ask = null; pump() }

    // ── one request ──
    property string text: ""
    property string authPhase: "idle"      // idle · verifying · failed · authorized (Popup owns `phase`)
    property string message: ""
    property string actionId: ""
    property int    choice: 1              // confirm: 0 YES · 1 NO (NO by default)
    property real   inT: 0
    readonly property real u: Math.max(0.7, screenH / 1080)
    // the Void's type scale (Theme.voidStep) at this screen's size
    readonly property real s0: Theme.voidStep(0) * u
    readonly property real s1: Theme.voidStep(1) * u

    function begin() {
        if (phase !== "closed") { polkitWaiting = true; return }
        showPolkit()
    }
    function showPolkit() {
        if (!flow || flow.isCompleted) return
        ask = null
        text = ""; authPhase = "idle"
        message = flow.message
        actionId = flow.actionId
        open()
    }
    function idName(i) { return i ? String(i.displayName || "").toUpperCase() + (i.isGroup ? "  (GROUP)" : "") : "" }
    function cycleIdentity(d) {
        if (asking || !flow || !flow.identities || flow.identities.length < 2) return
        var ids = flow.identities, n = ids.length, k = ids.indexOf(flow.selectedIdentity)
        flow.selectedIdentity = ids[((k < 0 ? 0 : k) + d + n) % n]
        text = ""; authPhase = "idle"
    }
    function submit() {
        if (authPhase === "verifying" || authPhase === "authorized") return
        if (asking) {
            if (kind === "info") return
            if (kind === "confirm") { askReply(choice === 0, choice === 0 ? "yes" : "no"); authPhase = "authorized"; doneT.start(); return }
            if (text === "") return
            askReply(true, text)
            text = ""; authPhase = "authorized"; field.ok(); doneT.start()
            return
        }
        if (!flow || !flow.isResponseRequired || text === "") return
        authPhase = "verifying"
        flow.submit(text)
    }
    function cancel() {
        if (asking) askReply(false, "")
        else if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest()
        close()
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationSucceeded() { if (root.asking) return; root.text = ""; root.authPhase = "authorized"; field.ok(); doneT.start() }
        function onAuthenticationFailed() { if (root.asking) return; root.text = ""; root.authPhase = "failed"; field.fail() }
        function onAuthenticationRequestCancelled() { if (root.polkitWaiting) root.polkitWaiting = false; else if (!root.asking) root.close() }
        function onIsCompletedChanged() {
            if (root.asking) return
            if (root.flow && root.flow.isCompleted && !root.flow.isSuccessful && root.authPhase !== "authorized") giveUpT.start()
        }
    }
    Timer { id: doneT;   interval: 650;  onTriggered: root.close() }
    Timer { id: giveUpT; interval: 1500; onTriggered: if (!root.asking && (!root.flow || root.flow.isCompleted)) root.close() }

    // ── lifecycle: glass over the screen → collapses into the Void → the prompt ──
    onOpening: { inT = 0; underlay = 0; voidOut.stop() }
    onIntro: voidIn.restart()
    SequentialAnimation {
        id: voidIn
        PauseAnimation { duration: 260 }
        ScriptAction { script: root.collapse = true }
        ParallelAnimation {
            NumberAnimation { target: root; property: "underlay"; to: 1; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "inT"; to: 1; duration: 520; easing.type: Easing.OutCubic }
        }
    }
    onOutro: {
        // closed by anything but a reply (Esc, the requester hanging up, a reload): say so
        if (asking && ask.sock) askReply(false, "")
        voidIn.stop(); doneT.stop(); giveUpT.stop(); voidOut.restart()
    }
    SequentialAnimation {
        id: voidOut
        ParallelAnimation {
            NumberAnimation { target: root; property: "inT"; to: 0; duration: 200 }
            NumberAnimation { target: root; property: "underlay"; to: 0; duration: 380; easing.type: Easing.OutCubic }
        }
        ScriptAction { script: root.panelGone() }
    }

    // stepped caret blink
    property real blinkV: 1
    Timer { interval: 530; running: root.shown; repeat: true; onTriggered: root.blinkV = root.blinkV > 0.5 ? 0.15 : 1 }

    readonly property string titleText: {
        var p = authPhase
        if (asking) {
            if (p === "authorized") return kind === "confirm" ? (choice === 0 ? "CONFIRMED" : "DECLINED") : "SENT"
            return ask.title || (kind === "confirm" ? "CONFIRMATION REQUIRED" : kind === "info" ? "NOTICE" : "AUTHORIZATION REQUIRED")
        }
        return ({ idle: "AUTHORIZATION REQUIRED", verifying: "VERIFYING", failed: "FAILED", authorized: "AUTHORIZED" })[p] || ""
    }
    readonly property string noteText: asking ? (ask.error || "")
                                              : (flow && flow.supplementaryMessage ? flow.supplementaryMessage : "")
    readonly property bool noteWarn: asking ? !!ask.error : !!(flow && flow.supplementaryIsError)

    FocusScope {
        anchors.fill: parent
        focus: root.isOpen
        Keys.onPressed: (e) => {
            var k = e.key
            var busy = root.authPhase === "verifying" || root.authPhase === "authorized"
            if (k === Qt.Key_Escape) root.cancel()
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.submit()
            else if (root.asking && root.kind === "confirm") {
                if (busy) {}
                else if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Tab) root.choice = 1 - root.choice
                else if (k === Qt.Key_Y) { root.choice = 0; root.submit() }
                else if (k === Qt.Key_N) { root.choice = 1; root.submit() }
            }
            else if (root.asking && root.kind === "info") {}
            else if (k === Qt.Key_Left) root.cycleIdentity(-1)
            else if (k === Qt.Key_Right) root.cycleIdentity(1)
            else if (k === Qt.Key_Backspace) {
                if (!busy) {
                    root.text = (e.modifiers & Qt.ControlModifier) ? "" : root.text.slice(0, -1)
                    if (root.authPhase === "failed") root.authPhase = "idle"
                }
            }
            else if (e.text !== "" && e.text.charCodeAt(0) >= 32 && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                if (!busy && root.text.length < 256) {
                    root.text += e.text
                    if (root.authPhase === "failed") root.authPhase = "idle"
                }
            }
            e.accepted = true
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: (1 - root.inT) * 14 * root.u
            width: 620 * root.u
            spacing: 0
            opacity: root.inT

            Rectangle {   // the diamond
                anchors.horizontalCenter: parent.horizontalCenter
                width: 11 * root.u; height: width; rotation: 45
                color: "transparent"; border.color: root.authPhase === "failed" ? Theme.voidWarn : Theme.voidLight; border.width: 1
                Rectangle {
                    anchors.centerIn: parent; width: 4 * root.u; height: width
                    color: root.authPhase === "failed" ? Theme.voidWarn : Theme.voidLight
                    opacity: root.authPhase === "verifying" || (root.asking && root.kind === "info") ? 0.35 + 0.65 * root.blinkV : 0.85
                }
            }
            Item { width: 1; height: 22 * root.u }
            Text {      // no typing: phase changes just switch the words
                id: title
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.titleText
                font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: Math.round(root.s1); font.letterSpacing: 0.32 * root.s1
                color: root.authPhase === "failed" ? Theme.voidWarn : Theme.voidLight
            }
            Item { width: 1; height: 18 * root.u }
            Item {   // the rule
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300 * root.u; height: 1
                Rectangle { width: parent.width * root.inT; x: (parent.width - width) / 2; height: 1; color: Theme.alpha(Theme.voidLight, 0.22) }
            }
            Item { width: 1; height: 22 * root.u }
            Text {   // what is being asked for (polkit's message, the program's own prompt)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.message
                wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
                font.family: Theme.cjk; font.pixelSize: Math.round(root.s1 * 0.85)
                lineHeight: 1.25
                color: Theme.alpha(Theme.voidLight, 0.88)
            }
            Item { width: 1; height: 8 * root.u }
            Text {   // polkit's action id, or who asks ($ ssh host · gpg)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.actionId
                elide: Text.ElideMiddle
                font.family: Theme.mono; font.pixelSize: Math.round(root.s0 * 0.9); font.letterSpacing: 0.08 * root.s0
                color: Theme.alpha(Theme.voidLight, 0.35)
            }
            Item { width: 1; height: 30 * root.u }
            Row {    // as whom (polkit; ←→ when there's a choice)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.asking
                spacing: 12 * root.u
                readonly property bool many: !!root.flow && !!root.flow.identities && root.flow.identities.length > 1
                Text { text: "AS"; font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: Math.round(root.s0); font.letterSpacing: 0.3 * root.s0; color: Theme.alpha(Theme.voidLight, 0.45) }
                Text { visible: parent.many; text: "◂"; font.pixelSize: Math.round(root.s0); color: Theme.alpha(Theme.voidLight, 0.6) }
                Text {
                    text: root.flow ? root.idName(root.flow.selectedIdentity) : ""
                    font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: Math.round(root.s0); font.letterSpacing: 0.3 * root.s0
                    color: Theme.voidLight
                }
                Text { visible: parent.many; text: "▸"; font.pixelSize: Math.round(root.s0); color: Theme.alpha(Theme.voidLight, 0.6) }
            }
            Item { width: 1; height: root.asking ? 0 : 16 * root.u }
            VoidField {
                id: field
                visible: !root.asking || root.kind === "secret" || root.kind === "text"
                anchors.horizontalCenter: parent.horizontalCenter
                u: root.u
                text: root.text
                phase: root.authPhase
                echo: root.asking ? root.kind === "text" : (!!root.flow && root.flow.responseVisible)
                blink: root.blinkV
                hint: root.asking ? (root.ask.hint || (root.kind === "text" ? "TYPE" : "PASSWORD"))
                                  : (root.flow && root.flow.inputPrompt ? String(root.flow.inputPrompt).replace(/[:：]\s*$/, "").toUpperCase() : "PASSWORD")
                Component.onCompleted: burst.backdrop = root.backdrop
            }
            Row {    // confirm: YES / NO, the pick on a diamond
                visible: root.asking && root.kind === "confirm"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 64 * root.u
                height: 28 * root.u
                Repeater {
                    model: ["YES", "NO"]
                    Item {
                        readonly property bool on: root.choice === index
                        width: lbl.implicitWidth + 24 * root.u; height: parent.height
                        Rectangle {
                            anchors.right: lbl.left; anchors.rightMargin: 10 * root.u; anchors.verticalCenter: lbl.verticalCenter
                            width: 7 * root.u; height: width; rotation: 45
                            color: parent.on ? Theme.voidLight : "transparent"
                            border.color: Theme.alpha(Theme.voidLight, parent.on ? 1 : 0.35); border.width: 1
                        }
                        Text {
                            id: lbl
                            anchors.centerIn: parent; anchors.horizontalCenterOffset: 6 * root.u
                            text: modelData
                            font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: Math.round(root.s1); font.letterSpacing: 0.3 * root.s1
                            color: Theme.alpha(Theme.voidLight, parent.on ? 1 : 0.4)
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.horizontalCenter: lbl.horizontalCenter
                            width: lbl.implicitWidth * (parent.on ? 1 : 0); height: 1; color: Theme.voidLight
                            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        MouseArea { anchors.fill: parent; onClicked: { root.choice = index; root.submit() } }
                    }
                }
            }
            Item { width: 1; height: 14 * root.u }
            Text {   // notes: polkit's own, or the requester's error (an error in warn)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.noteText || " "
                wrapMode: Text.Wrap; maximumLineCount: 2
                font.family: Theme.cjk; font.pixelSize: Math.round(root.s0)
                color: root.noteWarn ? Theme.voidWarn : Theme.alpha(Theme.voidLight, 0.55)
            }
            Item { width: 1; height: 26 * root.u }
            Row {    // the keys
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18 * root.u
                Repeater {
                    model: root.asking
                        ? (root.kind === "confirm" ? [["←→", "CHOOSE"], ["↵", "CONFIRM"], ["ESC", "CANCEL"]]
                           : root.kind === "info" ? [["ESC", "DISMISS"]]
                           : [["↵", "SUBMIT"], ["ESC", "CANCEL"]])
                        : [["↵", "AUTHORIZE"], ["ESC", "CANCEL"]].concat(
                            root.flow && root.flow.identities && root.flow.identities.length > 1 ? [["←→", "IDENTITY"]] : [])
                    Row {
                        spacing: 6 * root.u
                        Rectangle {
                            width: kk.implicitWidth + root.s0 * 0.7; height: root.s0 * 1.5
                            color: "transparent"; border.color: Theme.alpha(Theme.voidLight, 0.35); border.width: 1
                            Text { id: kk; anchors.centerIn: parent; text: modelData[0]; font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: Math.round(root.s0 * 0.85); color: Theme.voidLight }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: Math.round(root.s0); font.letterSpacing: 0.26 * root.s0
                            color: Theme.alpha(Theme.voidLight, 0.55)
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "auth"
        function cancel(): void { root.cancel() }
        function status(): string {
            return JSON.stringify({ registered: root.registered, active: !!root.agent && root.agent.isActive,
                                    open: root.isOpen, phase: root.authPhase, action: root.actionId,
                                    asking: root.asking, kind: root.kind, queued: root.askQueue.length,
                                    socket: root.askPath })
        }
    }
}
