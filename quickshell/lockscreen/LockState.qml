import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// LockState — the password, PAM and the lock's phases, shared by every screen's face.
//   idle → (↵) verifying → authorized → unlocked()
//                        ↘ failed → idle (on the next key)
// The text is typed by key events, not a TextInput, so no input method (fcitx5) ever
// sees the password. Retries slow down after the third failure (pam/lock.conf has no
// faillock, so this is the brake).
Scope {
    id: st

    property string text: ""
    property string phase: "idle"
    property int    fails: 0
    property bool   caps: false
    property double holdUntil: 0               // retries wait until then
    readonly property bool busy: phase === "verifying" || phase === "authorized"

    signal unlocked()
    signal failedPulse()
    signal authorizedPulse()

    function type(s) {
        if (busy || s === "") return
        if (phase === "failed") phase = "idle"
        if (text.length < 128) text += s
    }
    function backspace() { if (!busy) { text = text.slice(0, -1); if (phase === "failed") phase = "idle" } }
    function clear()     { if (!busy) { text = ""; phase = "idle" } }
    function submit() {
        if (busy || text === "" || Date.now() < holdUntil) return
        phase = "verifying"
        pam.start()
    }
    function readCaps() { capsProc.running = true }

    PamContext {
        id: pam
        configDirectory: Quickshell.shellDir + "/pam"
        config: "lock.conf"
        onPamMessage: if (responseRequired) respond(st.text)
        onCompleted: (result) => {
            if (result === PamResult.Success) {
                st.phase = "authorized"
                st.authorizedPulse()
                doneT.start()
            } else {
                st.text = ""
                st.fails++
                st.phase = "failed"
                st.holdUntil = st.fails >= 3 ? Date.now() + Math.min(8000, 1000 * (st.fails - 2)) : 0
                st.failedPulse()
            }
        }
    }
    Timer { id: doneT; interval: 950; onTriggered: st.unlocked() }   // the authorized hit, then the screen opens

    // Caps Lock: the keyboard LED (sysfs doesn't notify, so read after each key)
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | sort -r | head -n 1"]
        stdout: StdioCollector { onStreamFinished: st.caps = text.trim() !== "" && text.trim() !== "0" }
    }
    Component.onCompleted: readCaps()
}
