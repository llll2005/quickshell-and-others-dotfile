import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "lockscreen"
import "theme"

// The session lock (ext-session-lock + PAM), in its own qs process so it holds whatever
// the shell does: scripts/lock.sh starts it, and falls back to hyprlock if it doesn't
// report the lock as secure in time, or dies before unlocking.
//   $XDG_RUNTIME_DIR/qs-lock.ready     the compositor confirmed the lock (secure)
//   $XDG_RUNTIME_DIR/qs-lock.unlocked  the right password — exiting on purpose
//
// QS_LOCK_PREVIEW=1 qs -p lock.qml   shows the face on an overlay instead of locking (no
// keyboard grab; `qs -p lock.qml ipc call lockpreview type|submit|clear|quit`), to
// work on the look without locking yourself out.
ShellRoot {
    id: shell
    readonly property string run: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-lock"
    readonly property bool preview: Quickshell.env("QS_LOCK_PREVIEW") === "1"

    // Waking from sleep with the lock up: the outputs come back and Hyprland may hand the
    // keyboard to no surface (2026-10-08: the face animated, no key reached it). After
    // logind's PrepareForSleep(false), put the pointer on the focused monitor's centre, so
    // the compositor re-picks the lock surface under it (LockFace takes the focus back too).
    Process {
        running: !shell.preview
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("PrepareForSleep") >= 0 && line.indexOf("false") >= 0) {
                    console.log("lock: woke from sleep — re-picking the keyboard surface")
                    refocusT.restart()
                }
            }
        }
    }
    Timer { id: refocusT; interval: 400; onTriggered: refocusProc.running = true }
    Process {
        id: refocusProc
        command: ["sh", "-c", "hyprctl monitors -j | python3 -c 'import json,sys; m=[m for m in json.load(sys.stdin) if m[\"focused\"]] or [None]; m=m[0]; " +
                  "print(\"\" if m is None else \"hl.dsp.cursor.move({x=%d, y=%d})\" % (m[\"x\"] + m[\"width\"] / m[\"scale\"] / 2, m[\"y\"] + m[\"height\"] / m[\"scale\"] / 2))' | " +
                  "{ read -r d; [ -n \"$d\" ] && hyprctl dispatch \"$d\"; }"]
    }

    FileView { id: readyFile; path: shell.run + ".ready";    blockWrites: true; printErrors: false }
    FileView { id: doneFile;  path: shell.run + ".unlocked"; blockWrites: true; printErrors: false }

    LockState {
        id: lockState     // not "st": LockFace's own property is st, and Qt 6.12 resolves
                          // `st: st` to that property itself (undefined) — every key was lost
        onUnlocked: {
            if (shell.preview) { console.log("lock preview: authorized"); return }
            doneFile.setText(String(Date.now()))
            lock.locked = false
            Qt.quit()
        }
    }

    WlSessionLock {
        id: lock
        locked: !shell.preview
        onSecureChanged: if (secure) readyFile.setText(String(Date.now()))

        WlSessionLockSurface {
            id: surf
            color: Theme.voidBg
            LockFace { anchors.fill: parent; st: lockState; scr: surf.screen }
        }
    }

    // ── preview (see the header) ──
    PanelWindow {
        id: previewWin
        visible: shell.preview
        screen: Quickshell.screens.find(function(x) { return Hyprland.focusedMonitor && x.name === Hyprland.focusedMonitor.name }) || null
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: Theme.voidBg
        LockFace { anchors.fill: parent; st: lockState; scr: previewWin.screen }
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }   // a click closes the preview
    }
    IpcHandler {
        target: "lockpreview"
        enabled: shell.preview
        function type(s: string): void { lockState.type(s) }
        function submit(): void { lockState.submit() }
        function clear(): void { lockState.clear() }
        function state(): string { return JSON.stringify({ phase: lockState.phase, len: lockState.text.length, fails: lockState.fails, caps: lockState.caps }) }
        function quit(): void { Qt.quit() }
    }
}
