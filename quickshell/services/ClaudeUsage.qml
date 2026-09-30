pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ClaudeUsage — cost/token usage via scripts/claude-usage.py, polled every 5 min.
QtObject {
    id: root
    property string todayCost: "-"; property string weekCost: "-"; property string monthCost: "-"
    property string todayTok:  "-"; property string weekTok:  "-"; property string monthTok:  "-"
    property bool   ready: false

    property Timer _t: Timer {
        interval: 300000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: _p.running = true
    }
    property Process _p: Process {
        running: false
        command: ["python3", Qt.resolvedUrl("../scripts/claude-usage.py").toString().replace("file://","")]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim().split("|")
                if (p.length >= 6) {
                    root.weekCost = "$"+p[0]; root.monthCost = "$"+p[1]; root.todayCost = "$"+p[2]
                    root.weekTok  = p[3];     root.monthTok  = p[4];     root.todayTok  = p[5]
                    root.ready = true
                }
            }
        }
    }
}
