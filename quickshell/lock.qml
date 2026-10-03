import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "lockscreen"

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

    FileView { id: readyFile; path: shell.run + ".ready";    blockWrites: true; printErrors: false }
    FileView { id: doneFile;  path: shell.run + ".unlocked"; blockWrites: true; printErrors: false }

    LockState {
        id: st
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
            color: "black"
            LockFace { anchors.fill: parent; st: st; scr: surf.screen }
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
        color: "black"
        LockFace { anchors.fill: parent; st: st; scr: previewWin.screen }
        MouseArea { anchors.fill: parent; onClicked: Qt.quit() }   // a click closes the preview
    }
    IpcHandler {
        target: "lockpreview"
        enabled: shell.preview
        function type(s: string): void { st.type(s) }
        function submit(): void { st.submit() }
        function clear(): void { st.clear() }
        function state(): string { return JSON.stringify({ phase: st.phase, len: st.text.length, fails: st.fails, caps: st.caps }) }
        function quit(): void { Qt.quit() }
    }
}
