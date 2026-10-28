import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../theme"
import "../settings"
import "../services"

// Welcome — sleep and wake in the Void (quickshell/CLAUDE.md, "Design language").
// The shell holds a logind delay lock on sleep, so the system waits for it:
//   · going down: the Void's dark is drawn (STANDBY) — or, with `[void] lockOnSleep`, the
//     session is locked first (scripts/lock.sh) — then the lock is let go and it sleeps;
//     a lock already up (SUPER+L) needs neither
//   · waking: WELCOME BACK, the time and how long it slept; any key or click, or 2 s, and
//     the words fade and the dark lifts off the desktop. No password: lock with SUPER+L.
// `[void] welcome = false` sleeps and wakes plainly. IPC: `qs ipc call welcome preview`.
Scope {
    id: root
    property string phase: "awake"          // awake · down (dark, asleep) · back (the words) · lifting
    property real dark: 0
    property real words: 0
    property double downAt: 0
    property string slept: ""
    readonly property bool shown: phase !== "awake"

    // ── the delay lock logind waits for (InhibitDelayMaxSec, 5 s by default) ──
    Process {
        id: inhibit
        running: true
        command: ["systemd-inhibit", "--what=sleep", "--who=Quickshell", "--mode=delay",
                  "--why=Draw the Void (or lock) before sleeping", "sleep", "infinity"]
    }
    function letGo() { relT.stop(); inhibit.running = false }
    Timer { id: relT; interval: 380; onTriggered: root.letGo() }     // the dark has had its frame

    Process {
        id: watch
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("PrepareForSleep") < 0) return
                if (line.indexOf("true") >= 0) root.goingDown()
                else root.wokeUp()
            }
        }
    }

    // is the session lock up already? (lock.qml runs as its own qs)
    Process {
        id: lockCheck
        command: ["pgrep", "-f", "lock\\.qml"]
        onExited: (code) => {
            if (code === 0) { root.letGo(); return }            // locked: nothing to draw
            if (Settings.lockOnSleep) { lockUp.running = true; return }
            if (!Settings.welcomeOnWake) { root.letGo(); return }
            root.phase = "down"; root.words = 0
            downIn.restart()
            relT.restart()
        }
    }
    // lock, and let go once the lock is secure (or after 3 s: never hold sleep hostage)
    Process {
        id: lockUp
        command: ["sh", "-c", "r=${XDG_RUNTIME_DIR:-/tmp}/qs-lock; rm -f \"$r.ready\"; setsid -f \"$0\" >/dev/null 2>&1;"
                  + " i=0; while [ ! -e \"$r.ready\" ] && [ $i -lt 30 ]; do sleep 0.1; i=$((i + 1)); done",
                  Quickshell.shellDir + "/scripts/lock.sh"]
        onExited: root.letGo()
    }

    function goingDown() {
        downAt = Date.now()
        lockCheck.running = true
    }
    function wokeUp() {
        inhibit.running = true                      // the next sleep waits for us again
        if (phase !== "down") return
        var m = Math.max(0, Math.round((Date.now() - downAt) / 60000))
        slept = m < 60 ? m + " MIN" : Math.floor(m / 60) + " H " + String(m % 60).padStart(2, "0") + " MIN"
        phase = "back"
        backIn.restart()
    }
    function lift() {
        if (phase !== "back" && phase !== "down") return
        phase = "lifting"
        backIn.stop(); downIn.stop()
        liftOut.restart()
    }
    // asleep that never slept (a failed suspend): don't stay dark
    Timer { running: root.phase === "down"; interval: 45000; onTriggered: root.lift() }

    NumberAnimation { id: downIn; target: root; property: "dark"; to: 1; duration: 160; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: backIn
        NumberAnimation { target: root; property: "dark"; to: 1; duration: 0 }
        NumberAnimation { target: root; property: "words"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
        PauseAnimation { duration: 1600 }
        ScriptAction { script: root.lift() }
    }
    SequentialAnimation {
        id: liftOut
        NumberAnimation { target: root; property: "words"; to: 0; duration: 240; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "dark"; to: 0; duration: 560; easing.type: Easing.OutCubic }
        ScriptAction { script: { root.phase = "awake"; root.words = 0; TaskGroups.showPrompt() } }   // the HUD: which task group
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: root.shown
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // while the words show, the first key is ours (it lifts the dark, it isn't typed)
            WlrLayershell.keyboardFocus: root.phase === "back" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            readonly property real u: Math.max(0.7, (modelData ? modelData.height : 1080) / 1080)
            readonly property real s0: Theme.voidStep(0) * u
            readonly property real s2: Theme.voidStep(2) * u

            Rectangle { anchors.fill: parent; color: Theme.voidBg; opacity: root.dark }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: (e) => { root.lift(); e.accepted = true }
                MouseArea { anchors.fill: parent; onPressed: root.lift() }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.46 - height / 2
                    spacing: 18 * win.u
                    opacity: root.phase === "down" ? root.dark : root.words
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 11 * win.u; height: width; rotation: 45; antialiasing: true
                        color: "transparent"; border.color: Theme.voidLight; border.width: 1
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.phase === "down" ? "STANDBY" : "WELCOME BACK"
                        font.family: Theme.voidFont; font.weight: Theme.voidWeight
                        font.pixelSize: Math.round(win.s2); font.letterSpacing: 0.26 * win.s2
                        color: Theme.voidLight
                    }
                    Rectangle {   // the hairline grows with the words
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 260 * win.u * (root.phase === "down" ? 1 : root.words); height: 1
                        color: Theme.alpha(Theme.voidLight, 0.45)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: root.phase !== "down"
                        text: {
                            var d = new Date(), p = function(n) { return String(n).padStart(2, "0") }
                            var day = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][d.getDay()]
                            return day + " " + p(d.getMonth() + 1) + "." + p(d.getDate()) + "  ·  " + p(d.getHours()) + ":" + p(d.getMinutes())
                                   + (root.slept !== "" ? "  ·  SLEPT " + root.slept : "")
                        }
                        font.family: Theme.mono; font.pixelSize: Math.round(win.s0); font.letterSpacing: 0.12 * win.s0
                        color: Theme.alpha(Theme.voidLight, 0.6)
                    }
                }
                Text {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 48 * win.u }
                    visible: root.phase === "back"
                    opacity: root.words * 0.5
                    text: "ANY KEY"
                    font.family: Theme.voidFont; font.weight: Theme.voidWeight
                    font.pixelSize: Math.round(win.s0); font.letterSpacing: 0.3 * win.s0
                    color: Theme.voidLight
                }
            }
        }
    }

    IpcHandler {
        target: "welcome"
        // the whole thing without sleeping: dark, then the welcome a second later
        function preview(): void {
            if (root.phase !== "awake") return
            root.downAt = Date.now() - 37 * 60000
            root.phase = "down"; root.words = 0; downIn.restart()
            previewT.restart()
        }
        function state(): string { return root.phase }
    }
    Timer { id: previewT; interval: 1100; onTriggered: { root.phase = "down"; root.wokeUp() } }
}
