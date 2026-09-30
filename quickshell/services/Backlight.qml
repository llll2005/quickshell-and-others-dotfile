pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Backlight — screen brightness via brightnessctl. `value` is 0–1. `available`
// is false when there's no backlight device (desktop monitors).
QtObject {
    id: root

    property real value: 0.8
    property bool available: false

    property Timer _t: Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: _p.running = true
    }
    property Process _p: Process {
        running: false
        command: ["sh","-c","brightnessctl g 2>/dev/null;brightnessctl m 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ls = this.text.trim().split("\n")
                if (ls.length >= 2 && parseFloat(ls[1]) > 0) {
                    root.value = parseFloat(ls[0]) / parseFloat(ls[1])
                    root.available = true
                } else {
                    root.available = false
                }
            }
        }
    }
    property Process _set: Process { running: false }

    function set(v) {
        var c = Math.max(0.01, Math.min(1, v))
        root.value = c
        _set.command = ["sh","-c","brightnessctl s " + Math.round(c*100) + "% >/dev/null 2>&1"]
        _set.running = false
        _set.running = true
    }
    // re-read immediately (e.g. after a brightness key press)
    function refresh() { _p.running = false; _p.running = true }
}
