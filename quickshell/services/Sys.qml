pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Sys — shared CPU/GPU load, polled once and consumed by any widget (TopBar,
// CornerHud, …) so they never double-poll /proc/stat or nvidia-smi.
QtObject {
    id: root

    property int  cpuPct: 0
    property int  memPct: 0       // RAM used %
    property real memUsedGiB: 0
    property real memTotGiB: 0
    property real gpuPct: 0
    property real gpuMem: 0
    property real gpuTemp: 0
    property bool gpuAvailable: false
    property string topName: ""   // top CPU process name
    property real   topPct:  0    // its %CPU

    property Timer _topT: Timer {
        interval: 4000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: _topP.running = true
    }
    property Process _topP: Process {
        running: false
        command: ["sh","-c","ps -eo comm,%cpu --sort=-%cpu --no-header 2>/dev/null|head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim().split(/\s+/)
                if (t.length >= 2) { root.topName = t[0]; root.topPct = parseFloat(t[1]) || 0 }
            }
        }
    }

    // /proc is read in-process via FileView — no sh/awk fork per tick.
    property FileView _meminfo: FileView { path: "/proc/meminfo"; blockLoading: true }
    property Timer _memT: Timer {
        interval: 3000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root._meminfo.reload()
            var s = root._meminfo.text()
            var tm = s.match(/MemTotal:\s+(\d+)/), am = s.match(/MemAvailable:\s+(\d+)/)
            if (!tm || !am) return
            var tot = parseFloat(tm[1]), used = tot - parseFloat(am[1])
            root.memPct = tot > 0 ? Math.round(used / tot * 100) : 0
            root.memTotGiB  = tot / 1048576
            root.memUsedGiB = used / 1048576
        }
    }

    // CPU % = busy/total jiffies delta between ticks (same user+system over
    // user+nice+system+idle formula as before). The first tick primes the
    // baseline and re-samples 300 ms later so a value shows up right away.
    property FileView _stat: FileView { path: "/proc/stat"; blockLoading: true }
    property var _cpuPrev: null
    function _sampleCpu() {
        _stat.reload()
        var f = _stat.text().split("\n", 1)[0].trim().split(/\s+/)
        if (f.length < 5 || f[0] !== "cpu") return
        var u = parseFloat(f[1]) + parseFloat(f[3])
        var t = parseFloat(f[1]) + parseFloat(f[2]) + parseFloat(f[3]) + parseFloat(f[4])
        if (_cpuPrev) {
            var du = u - _cpuPrev[0], dt = t - _cpuPrev[1]
            cpuPct = dt > 0 ? Math.min(100, Math.round(du / dt * 100)) : 0
        } else {
            _cpuPrimeT.start()
        }
        _cpuPrev = [u, t]
    }
    property Timer _cpuT: Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: root._sampleCpu()
    }
    property Timer _cpuPrimeT: Timer { interval: 300; onTriggered: root._sampleCpu() }

    // GPU: one long-lived nvidia-smi in loop mode (-lms) streams a line every
    // 2 s, instead of spawning sh + nvidia-smi (and re-initialising NVML) each
    // tick. `-i 0` keeps the old `head -1` behaviour (first GPU only).
    property Process _gpuP: Process {
        running: true
        command: ["nvidia-smi", "-i", "0",
                  "--query-gpu=utilization.gpu,memory.used,temperature.gpu",
                  "--format=csv,noheader,nounits", "-lms", "2000"]
        stdout: SplitParser {
            onRead: data => {
                var p = data.trim().split(",")
                if (p.length < 3) return
                root.gpuPct  = parseFloat(p[0]) || 0
                root.gpuMem  = parseFloat(p[1]) || 0
                root.gpuTemp = parseFloat(p[2]) || 0
                root.gpuAvailable = true
            }
        }
        // Driver reload / GPU gone: mark unavailable and retry later.
        onExited: { root.gpuAvailable = false; root._gpuRetryT.restart() }
    }
    property Timer _gpuRetryT: Timer { interval: 30000; onTriggered: root._gpuP.running = true }
}
