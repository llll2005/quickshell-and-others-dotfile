pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Cal — Google Calendar events for a date range via gcalcli, grouped per day.
// CornerHud sets rangeStart/rangeEnd to the viewed month; eventsOn(date) returns
// that day's events (incl. multi-day spans). Empty if gcalcli isn't configured.
//
// gcalcli 4.x `agenda --tsv` columns: start_date, start_time, end_date, end_time,
// title  (5 cols; older code expected 6 → silently dropped everything).
QtObject {
    id: root
    property string rangeStart: ""   // "YYYY-MM-DD" inclusive
    property string rangeEnd:   ""    // "YYYY-MM-DD" inclusive
    property var    events: []        // [{start, time, end, title}]  (end exclusive)

    function _addDays(s, n) {
        var d = new Date(s + "T00:00:00"); d.setDate(d.getDate() + n)
        return d.getFullYear() + "-" + String(d.getMonth()+1).padStart(2,"0")
                               + "-" + String(d.getDate()).padStart(2,"0")
    }
    // events covering `dateStr` — single-day (start==end) or multi-day [start,end)
    function eventsOn(dateStr) {
        return events.filter(function(e) {
            if (e.end && e.end > e.start) return dateStr >= e.start && dateStr < e.end
            return dateStr === e.start
        })
    }

    onRangeStartChanged: _refresh()
    onRangeEndChanged:   _refresh()
    function _refresh() { if (rangeStart && rangeEnd) { _p.running = false; _p.running = true } }

    // periodic refresh of the current range
    property Timer _t: Timer {
        interval: 600000; running: true; repeat: true
        onTriggered: root._refresh()
    }
    property Process _p: Process {
        running: false
        // gcalcli end is exclusive → +1 day to include rangeEnd itself
        command: ["sh","-c",
                  "gcalcli agenda --nocolor --tsv " + root.rangeStart
                  + " " + root._addDays(root.rangeEnd, 1) + " 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ev = []
                this.text.trim().split("\n").forEach(function(l) {
                    var c = l.split("\t")
                    if (c.length < 5) return
                    if (!/^\d{4}-\d{2}-\d{2}$/.test(c[0])) return   // skip header
                    ev.push({ start: c[0], time: c[1], end: c[2], title: c[4].trim() })
                })
                root.events = ev
            }
        }
    }
}
