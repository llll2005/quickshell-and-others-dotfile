pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Health — keeps the shell's outside helpers running, so every feature is on whenever
// the shell is (scripts/health.sh):
//   plugin   the imecaret Hyprland plugin (window effects, IME caret, click / Enter
//            bursts). Hyprland's autostart loads it too, but that can silently fail
//            at boot; here it is loaded whenever it's missing.
//   clip     the two cliphist watchers (the clipboard panel's history)
//   fcitx, bridge   fcitx5 and the kimpanel bridge (reported; ImePanel restarts the bridge)
//   nm       NetworkManager's bus name. Quickshell's Networking never reconnects after
//            NetworkManager restarts (an upgrade, wifi-iwd.sh) and a reload keeps it, so a
//            changed owner restarts the whole shell (scripts/qs-restart.sh). nmRunning
//            false: NetworkManager is down (the CC says so).
// A repair (`fix`) runs at start and whenever a 30 s check finds the plugin or the
// watchers gone. `rebuild()` recompiles the plugin after a Hyprland update.
Singleton {
    id: root

    property bool known:  false        // the first report has arrived
    property bool plugin: false
    property bool built:  true
    property bool clip:   false
    property bool fcitx:  false
    property bool bridge: false
    property string nm: ""             // NetworkManager's unique name now
    property string nmFirst: ""        // … when the shell first saw it
    readonly property bool nmRunning: !known || nm !== ""
    readonly property bool nmStale: nmFirst !== "" && nm !== "" && nm !== nmFirst
    property bool busy:   false        // a fix / rebuild is running
    readonly property bool allOk: plugin && clip && fcitx && bridge

    function init() {}                 // referencing Health creates it (shell.qml does)
    function check()   { _run("check") }
    function fix()     { _run("fix") }
    function rebuild() { _run("rebuild") }

    property string _queued: ""
    function _run(mode) {
        if (proc.running) { _queued = mode; return }
        busy = mode !== "check"
        proc.command = ["sh", Quickshell.shellDir + "/scripts/health.sh", mode]
        proc.running = true
    }
    Process {
        id: proc
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    var s = JSON.parse(line)
                    root.plugin = s.plugin; root.built = s.built; root.clip = s.clip
                    root.fcitx = s.fcitx; root.bridge = s.bridge; root.known = true
                    root.nm = s.nm || ""
                    if (root.nmFirst === "") root.nmFirst = root.nm
                } catch (e) {}
            }
        }
        onExited: {
            root.busy = false
            if (root._queued !== "") { var q = root._queued; root._queued = ""; root._run(q); return }
            // a check that finds something gone repairs it
            if (root.known && (!root.plugin && root.built || !root.clip)) root._autoFix()
        }
    }
    onNmStaleChanged: if (nmStale) restartT.start()
    Timer {   // NetworkManager settles for a moment after it comes back
        id: restartT; interval: 2500
        onTriggered: Quickshell.execDetached(["sh", Quickshell.shellDir + "/scripts/qs-restart.sh",
                                              "NetworkManager 重新啟動過，shell 重新連上它。"])
    }
    property double _lastFix: 0
    function _autoFix() {
        if (Date.now() - _lastFix < 25000) return     // not in a loop when a fix can't help
        _lastFix = Date.now()
        fix()
    }

    Timer { interval: 1200; running: true; onTriggered: { root._lastFix = Date.now(); root.fix() } }
    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.check() }
}
