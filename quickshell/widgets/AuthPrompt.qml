import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import "../components"
import "../theme"
import "../settings"

// AuthPrompt — the polkit authentication agent (pkexec, systemctl, GUI apps asking for
// root), in the Void: the glass unfolds over the screen and collapses into the dark,
// then "AUTHORIZATION REQUIRED", what is being asked for, and the password as diamonds
// (components/VoidField.qml; typed from key events, so no input method sees it).
//   ↵ authorize · Esc cancel · ←→ another identity (when polkit offers several)
//
// Only one agent can be registered per session: at start the KDE agent (if a previous
// session left it) is stopped so this one registers; if this one still can't register,
// the KDE agent is started again as the fallback. If Quickshell dies, GUI requests wait
// for an agent, but terminal ones (pkexec, systemctl, sudo) still ask in the terminal.
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
        command: ["sh", "-c", "pkill -f /usr/lib/polkit-kde-authentication-agent-1; sleep 0.3"]
        onExited: { root._agentOn = true; regCheck.start() }
    }
    Timer {
        id: regCheck; interval: 5000
        onTriggered: if (!root.registered) {
            console.warn("[AuthPrompt] polkit agent not registered — starting the KDE agent instead")
            Quickshell.execDetached(["/usr/lib/polkit-kde-authentication-agent-1"])
        }
    }

    // ── one request ──
    property string text: ""
    property string authPhase: "idle"      // idle · verifying · failed · authorized (Popup owns `phase`)
    property string message: ""
    property string actionId: ""
    property real   inT: 0
    readonly property real u: Math.max(0.7, screenH / 1080)

    function begin() {
        text = ""; authPhase = "idle"
        message = flow ? flow.message : ""
        actionId = flow ? flow.actionId : ""
        open()
    }
    function idName(i) { return i ? String(i.displayName || "").toUpperCase() + (i.isGroup ? "  (GROUP)" : "") : "" }
    function cycleIdentity(d) {
        if (!flow || !flow.identities || flow.identities.length < 2) return
        var ids = flow.identities, n = ids.length, k = ids.indexOf(flow.selectedIdentity)
        flow.selectedIdentity = ids[((k < 0 ? 0 : k) + d + n) % n]
        text = ""; authPhase = "idle"
    }
    function submit() {
        if (!flow || !flow.isResponseRequired || text === "" || authPhase === "verifying" || authPhase === "authorized") return
        authPhase = "verifying"
        flow.submit(text)
    }
    function cancel() {
        if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest()
        close()
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationSucceeded() { root.text = ""; root.authPhase = "authorized"; field.ok(); doneT.start() }
        function onAuthenticationFailed() { root.text = ""; root.authPhase = "failed"; field.fail() }
        function onAuthenticationRequestCancelled() { root.close() }
        function onIsCompletedChanged() {
            if (root.flow && root.flow.isCompleted && !root.flow.isSuccessful && root.authPhase !== "authorized") giveUpT.start()
        }
    }
    Timer { id: doneT;   interval: 650;  onTriggered: root.close() }
    Timer { id: giveUpT; interval: 1500; onTriggered: if (!root.flow || root.flow.isCompleted) root.close() }

    // ── lifecycle: glass over the screen → collapses into the Void → the prompt ──
    onOpening: { inT = 0; underlay = 0; voidOut.stop() }
    onIntro: voidIn.restart()
    SequentialAnimation {
        id: voidIn
        PauseAnimation { duration: 260 }
        ScriptAction { script: { root.collapse = true; title.play() } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "underlay"; to: 1; duration: 300; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "inT"; to: 1; duration: 520; easing.type: Easing.OutCubic }
        }
    }
    onOutro: { voidIn.stop(); doneT.stop(); giveUpT.stop(); voidOut.restart() }
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

    FocusScope {
        anchors.fill: parent
        focus: root.isOpen
        Keys.onPressed: (e) => {
            var k = e.key
            if (k === Qt.Key_Escape) root.cancel()
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.submit()
            else if (k === Qt.Key_Left) root.cycleIdentity(-1)
            else if (k === Qt.Key_Right) root.cycleIdentity(1)
            else if (k === Qt.Key_Backspace) {
                if (root.authPhase !== "verifying" && root.authPhase !== "authorized") {
                    root.text = (e.modifiers & Qt.ControlModifier) ? "" : root.text.slice(0, -1)
                    if (root.authPhase === "failed") root.authPhase = "idle"
                }
            }
            else if (e.text !== "" && e.text.charCodeAt(0) >= 32 && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
                if (root.authPhase !== "verifying" && root.authPhase !== "authorized" && root.text.length < 256) {
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
                color: "transparent"; border.color: root.authPhase === "failed" ? Theme.warn : Theme.light; border.width: 1
                Rectangle {
                    anchors.centerIn: parent; width: 4 * root.u; height: width
                    color: root.authPhase === "failed" ? Theme.warn : Theme.light
                    opacity: root.authPhase === "verifying" ? 0.35 + 0.65 * root.blinkV : 0.85
                }
            }
            Item { width: 1; height: 22 * root.u }
            ScrambleText {
                id: title
                anchors.horizontalCenter: parent.horizontalCenter
                playOnChange: true
                target: ({ idle: "AUTHORIZATION REQUIRED", verifying: "VERIFYING", failed: "FAILED", authorized: "AUTHORIZED" })[root.authPhase] || ""
                duration: 360
                font.family: Theme.mono; font.pixelSize: Math.round(13 * root.u); font.letterSpacing: 6 * root.u
                color: root.authPhase === "failed" ? Theme.warn : Theme.light
            }
            Item { width: 1; height: 18 * root.u }
            Item {   // the rule
                anchors.horizontalCenter: parent.horizontalCenter
                width: 300 * root.u; height: 1
                Rectangle { width: parent.width * root.inT; x: (parent.width - width) / 2; height: 1; color: Theme.alpha(Theme.light, 0.22) }
            }
            Item { width: 1; height: 22 * root.u }
            Text {   // what is being asked for (polkit's message, often in your language)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.message
                wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                font.family: Theme.cjk; font.pixelSize: Math.round(15 * root.u)
                lineHeight: 1.25
                color: Theme.alpha(Theme.light, 0.88)
            }
            Item { width: 1; height: 8 * root.u }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.actionId
                elide: Text.ElideMiddle
                font.family: Theme.mono; font.pixelSize: Math.round(10 * root.u); font.letterSpacing: 1.5 * root.u
                color: Theme.alpha(Theme.light, 0.35)
            }
            Item { width: 1; height: 30 * root.u }
            Row {    // as whom (←→ when there's a choice)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12 * root.u
                readonly property bool many: !!root.flow && !!root.flow.identities && root.flow.identities.length > 1
                Text { text: "AS"; font.family: Theme.mono; font.pixelSize: Math.round(10 * root.u); font.letterSpacing: 3 * root.u; color: Theme.alpha(Theme.light, 0.45) }
                Text { visible: parent.many; text: "◂"; font.pixelSize: Math.round(10 * root.u); color: Theme.alpha(Theme.light, 0.6) }
                Text {
                    text: root.flow ? root.idName(root.flow.selectedIdentity) : ""
                    font.family: Theme.mono; font.pixelSize: Math.round(10 * root.u); font.letterSpacing: 3 * root.u
                    color: Theme.light
                }
                Text { visible: parent.many; text: "▸"; font.pixelSize: Math.round(10 * root.u); color: Theme.alpha(Theme.light, 0.6) }
            }
            Item { width: 1; height: 16 * root.u }
            VoidField {
                id: field
                anchors.horizontalCenter: parent.horizontalCenter
                u: root.u
                text: root.text
                phase: root.authPhase
                echo: !!root.flow && root.flow.responseVisible
                blink: root.blinkV
                hint: root.flow && root.flow.inputPrompt ? String(root.flow.inputPrompt).replace(/[:：]\s*$/, "").toUpperCase() : "PASSWORD"
                Component.onCompleted: burst.backdrop = root.backdrop
            }
            Item { width: 1; height: 14 * root.u }
            Text {   // polkit's own notes (an error in warn)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.flow && root.flow.supplementaryMessage ? root.flow.supplementaryMessage : " "
                font.family: Theme.cjk; font.pixelSize: Math.round(11 * root.u)
                color: root.flow && root.flow.supplementaryIsError ? Theme.warn : Theme.alpha(Theme.light, 0.55)
            }
            Item { width: 1; height: 26 * root.u }
            Row {    // the keys
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18 * root.u
                Repeater {
                    model: [["↵", "AUTHORIZE"], ["ESC", "CANCEL"]].concat(
                        root.flow && root.flow.identities && root.flow.identities.length > 1 ? [["←→", "IDENTITY"]] : [])
                    Row {
                        spacing: 6 * root.u
                        Rectangle {
                            width: kk.implicitWidth + 8 * root.u; height: 15 * root.u
                            color: "transparent"; border.color: Theme.alpha(Theme.light, 0.35); border.width: 1
                            Text { id: kk; anchors.centerIn: parent; text: modelData[0]; font.family: Theme.mono; font.pixelSize: Math.round(8 * root.u); color: Theme.light }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]; font.family: Theme.mono; font.pixelSize: Math.round(9 * root.u); font.letterSpacing: 2 * root.u
                            color: Theme.alpha(Theme.light, 0.55)
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
                                    open: root.isOpen, phase: root.authPhase, action: root.actionId })
        }
    }
}
