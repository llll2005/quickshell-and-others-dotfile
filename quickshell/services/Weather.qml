pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Weather — wttr.in current conditions, polled every 20 min. Shared so any
// widget can show it without its own curl.
QtObject {
    id: root

    property string temp: "--°"
    property string desc: ""
    property string icon: "⛅"
    property bool   ready: false
    property var    forecast: []   // [{date, icon, max, min, desc}] up to 3 days

    // WWO weather codes (wttr.in) — explicit, since the ranges overlap rain/snow.
    function _wcode(c) {
        if (c === 113) return "☀"
        if (c === 116) return "⛅"
        if (c === 119 || c === 122) return "☁"
        if ([143,248,260].indexOf(c) >= 0) return "🌫"
        if ([200,386,389,392,395].indexOf(c) >= 0) return "⛈"
        var snow = [179,182,185,227,230,317,320,323,326,329,332,335,338,350,368,371,374,377]
        if (snow.indexOf(c) >= 0) return "❄"
        var rain = [176,263,266,281,284,293,296,299,302,305,308,311,314,353,356,359,362,365]
        if (rain.indexOf(c) >= 0) return "🌧"
        return "☁"
    }

    property Timer _t: Timer {
        interval: 1200000; running: true; repeat: true; triggeredOnStart: true   // 20 min
        onTriggered: _p.running = true
    }
    property Process _p: Process {
        running: false
        command: ["sh","-c","curl -sf --max-time 10 'wttr.in/?format=j1' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text), cur = j.current_condition[0]
                    root.temp  = cur.temp_C + "°"
                    root.desc  = cur.weatherDesc[0].value
                    root.icon  = root._wcode(parseInt(cur.weatherCode))
                    var fc = []
                    for (var i = 0; i < Math.min(3, j.weather.length); i++) {
                        var d = j.weather[i]
                        fc.push({
                            date: d.date.slice(5),
                            icon: root._wcode(parseInt(d.hourly[4].weatherCode)),
                            max:  d.maxtempC + "°",
                            min:  d.mintempC + "°",
                            desc: d.hourly[4].weatherDesc[0].value
                        })
                    }
                    root.forecast = fc
                    root.ready = true
                } catch (e) {}
            }
        }
    }
}
