pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Tasks — Google Tasks via scripts/gtasks.py (15-min poll). tasksOn(date) returns
// tasks due on a given "YYYY-MM-DD". Empty until the script is authorized once:
//   /usr/bin/python3 ~/.config/quickshell/scripts/gtasks.py --auth
// Always runs with the SYSTEM python so conda's env can't shadow the google libs.
QtObject {
    id: root
    property var  all: []        // [{title, due, done, notes, list}]
    property bool ready: false

    function tasksOn(dateStr) { return all.filter(function(t){ return t.due === dateStr }) }
    function refresh() { _p.running = false; _p.running = true }

    property Timer _t: Timer {
        interval: 900000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root.refresh()
    }
    property Process _p: Process {
        running: false
        command: ["/usr/bin/python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/gtasks.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.all = JSON.parse(this.text || "[]"); root.ready = true }
                catch (e) { root.all = [] }
            }
        }
    }
}
