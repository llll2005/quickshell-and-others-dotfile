import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../services"
import "../settings"

// hyprland.conf: bind = SUPER, grave, exec, qs ipc call bar toggle
ShellRoot {
    id: root

// ── Palette (YoRHa Paper · 與 Menu 一致) ────────────────────────────────
    readonly property color cBg:     "#d6cfb5"   // 底座：溫紙 (Menu.paper)
    readonly property color cSurf:   "#cbc4ab"   // 浮現：略深底紙 (hover)
    readonly property color cBorder: Qt.rgba(70/255,63/255,46/255, 0.25)  // 邊線：柔墨 (Menu.lineSoft)

    // 主題強調色 (元件、進度條、圖示)
    readonly property color cPink:   "#6e2a2a"   // 主強調：深硃紅 (Menu.accent)
    readonly property color cRose:   "#8a3a20"   // 副強調：暗橙褐
    readonly property color cPurple: "#2a3a5a"   // 冷調：深靛藍

    // 文字與層級
    readonly property color cText:   "#463f2e"   // 主文字：深墨褐 (Menu.ink)
    readonly property color cMuted:  "#7a7358"   // 次文字：淡墨 (Menu.inkSoft)
    readonly property color cDim:    Qt.rgba(70/255,63/255,46/255, 0.30)  // 弱提示：淡褐

    // 狀態指示色 (系統負載、電量、網路)
    readonly property color cRed:    "#6e2a2a"   // 警告/過載：深硃 (= cPink)
    readonly property color cGreen:  "#2a5a3a"   // 健康/連線：深翠

    readonly property int   rad:     0           // 方正無圓角 (Menu 風格)
    readonly property int   barH:    44
    // When CornerHud is the chosen status UI, this whole bar produces no windows.
    readonly property bool   barActive: !Settings.cornerHudEnabled
    // ── IPC ───────────────────────────────────────────────────────────────
    property bool   vis:   false
    property string panel: ""

    IpcHandler {
        target: "bar"
        function show():   void { root.vis = true;  root.edgeAutoShown = false }
        function hide():   void { root.vis = false; root.edgeAutoShown = false; root.panel = "" }
        function toggle(): void { root.vis = !root.vis; root.edgeAutoShown = false; if (!root.vis) root.panel = "" }
    }

    // ── State ─────────────────────────────────────────────────────────────
    // CPU/GPU load from the shared Sys service (no duplicate polling).
    // Process lists (cpuProcs/gpuProcs) stay local — fed by cpuTop/gpuTop below.
    readonly property real cpuPct:  Sys.cpuPct
    readonly property real gpuPct:  Sys.gpuPct
    readonly property real gpuMem:  Sys.gpuMem
    readonly property real gpuTemp: Sys.gpuTemp
    property var    cpuProcs: []
    property var    gpuProcs: []
    property bool   wifiOn: false; property string wifiSSID: ""; property int wifiSig: 0; property string wifiIP: ""
    property bool   ethOn:  false; property string ethName:  ""; property string ethIP:  ""
    property bool   btOn: false;   property string btDev: "";    property string btBat: ""
    property real   batPct: 100;   property bool   batChg: false
    // vol/muted come from the shared Audio service (native Pipewire, reactive)
    readonly property real vol:   Audio.volume
    readonly property bool muted: Audio.muted
    property real   bri: 0.8
    property string wxIcon: "⛅";  property string wxTemp: "--°"; property string wxDesc: ""; property var wxFc: []
    property string tStr: "--:--:--"; property string dStr: "--/--"; property string dow: "---"
    property var    gcal: []
    property string todo: ""
    // 全域紀錄當前是否有任何一個 Bar 被游標懸停
    property bool barHovered: false

    // 三秒自動收起計時器
    Timer {
        id: autoHideTimer
        interval: 3000
        onTriggered: {
            // 只有在面板為空、未被懸停、且非手動鎖定工作區視圖時，才執行隱藏
            if (root.panel === "" && !root.barHovered && !root.wspManualMode) {
                root.vis = false
                root.edgeAutoShown = false
            }
        }
    }

    // 當 Topbar 顯示狀態改變時觸發
    onVisChanged: {
        if (vis) {
            // Bar 顯示時：如果滑鼠不在 bar 上且沒有打開面板，啟動 3 秒倒數
            if (root.panel === "" && !root.barHovered) {
                autoHideTimer.restart()
            }
        } else {
            // Bar 隱藏時：停止計時器
            autoHideTimer.stop()
        }
    }

    // ── Workspace state ───────────────────────────────────────────────────
    property var    monitorData: ({})   // { "DP-1": { activeId:5, wsps:[1,3,5] } }
    property var    wspClients:  ({})   // { wspId: [{title,cls}] }
    property bool   wspMode:       false
    property bool   wspManualMode: false   // right-click to lock wsp view open
    property bool   wspAutoShown:  false
    property int    wspPopupWspId: -1
    property real   wspPopupX: 0
    property string wspPopupScreen: ""

    // ── Edge auto-show ─────────────────────────────────────────────────────
    property bool edgeAutoShown: false
    Timer { id: edgeHideTimer; interval:700; onTriggered: { if(root.edgeAutoShown && root.panel===""){ root.vis=false; root.edgeAutoShown=false } } }

    property bool   _popupVis:       false
    property bool   _popupWasWsp:    false
    property string _popupWspScreen: ""
    Timer { id: _popupHideTimer; interval: 420; onTriggered: root._popupVis = false }

    onPanelChanged: {
        if (panel !== "") {
            root._popupVis = true
            root._popupWasWsp = (panel === "wsp")
            root._popupWspScreen = root.wspPopupScreen
            _popupHideTimer.stop()
            autoHideTimer.stop() // 開啟 popup 時，暫停 3 秒自動收起
        } else {
            _popupHideTimer.restart()
            if (root.edgeAutoShown) edgeHideTimer.restart()
            // 關閉面板後，如果 bar 可見且滑鼠不在上面，啟動 3 秒自動收起
            if (root.vis && !root.barHovered) {
                autoHideTimer.restart()
            }
            if (root.vis && !root.barHovered) autoHideTimer.restart() // 關閉 popup 後，重新啟動 3 秒倒數
        }
    }

    property var    sessionStart:    new Date()
    property string claudeResetStr:  "5h 00m"
    property string claudeWeekCost:  "$--.--"
    property string claudeMonthCost: "$--.--"
    property string claudeTodayCost: "$--.--"
    property string claudeWeekTok:   "--"
    property string claudeMonthTok:  "--"
    property string claudeTodayTok:  "--"

    Timer {
        interval: 60000; running: root.barActive; repeat: true; triggeredOnStart: true
        onTriggered: {
            var now = new Date()
            var resetMs = root.sessionStart.getTime() + 5 * 3600 * 1000
            var remaining = Math.max(0, resetMs - now.getTime())
            var h = Math.floor(remaining / 3600000)
            var m = Math.floor((remaining % 3600000) / 60000)
            root.claudeResetStr = h + "h " + String(m).padStart(2, "0") + "m"
        }
    }
    Process {
        id: claudeUsageP; running: false
        command: ["python3", "/home/LnoArch/.config/quickshell/scripts/claude-usage.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim().split("|")
                if (p.length >= 6) {
                    root.claudeWeekCost  = "$" + p[0]
                    root.claudeMonthCost = "$" + p[1]
                    root.claudeTodayCost = "$" + p[2]
                    root.claudeWeekTok   = p[3]
                    root.claudeMonthTok  = p[4]
                    root.claudeTodayTok  = p[5]
                }
            }
        }
    }
    Timer { interval:300000; running:root.barActive; repeat:true; triggeredOnStart:true; onTriggered: claudeUsageP.running=true }

    // ── Polling ───────────────────────────────────────────────────────────
    // Every poll below is gated on barActive: with CornerHud chosen this bar has
    // no windows, so polling would only burn CPU (and a second `nmcli monitor`).
    // cpuPct/gpuPct come from the Sys service now (see properties above); only
    // the per-process top lists are polled locally, on demand when a panel opens.
    Process {
        id: cpuTop; running:false
        command: ["sh","-c","ps aux --sort=-%cpu --no-header|head -10|awk '{printf \"%s|%.1f|%s\\n\",$2,$3,$11}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p=[]
                this.text.trim().split("\n").forEach(function(l){
                    var t=l.split("|")
                    if(t.length>=3 && parseFloat(t[1])>0) p.push({pid:t[0],pct:t[1],name:t[2].split("/").pop()})
                })
                root.cpuProcs=p
            }
        }
    }

    Process {
        id: gpuTop; running:false
        command: ["sh","-c","nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>/dev/null|head -10"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p=[]
                this.text.trim().split("\n").forEach(function(l){
                    var t=l.split(",").map(function(s){return s.trim()})
                    if(t.length>=3 && t[0]) p.push({pid:t[0],name:t[1].split("/").pop(),mem:t[2]+" MiB"})
                })
                root.gpuProcs=p
            }
        }
    }

    // Polls WiFi + Ethernet every 3 s.  Also triggered immediately by nmcli monitor.
    Timer { interval:3000; running:root.barActive; repeat:true; triggeredOnStart:true; onTriggered: netP.running=true }
    Process {
        id: netP; running:false
        command: ["sh","-c",
            // Line 1: WiFi connection name  (TYPE field in 'nmcli dev' is simply "wifi")
            "nmcli -t -f TYPE,CONNECTION dev 2>/dev/null|awk -F: '/^wifi/{print $2;exit}';" +
            // Line 2: WiFi signal quality 0-100
            "nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no 2>/dev/null|awk -F: '/^\\*/{print $2;exit}'||echo 0;" +
            // Line 3: WiFi IP (from the wifi device)
            "ip -br addr show $(nmcli -t -f TYPE,DEVICE dev 2>/dev/null|awk -F: '/^wifi/{print $2;exit}') 2>/dev/null|awk '{print $3}'|cut -d/ -f1;" +
            // Line 4: Ethernet connection name (first non-empty connected ethernet, or blank)
            "nmcli -t -f TYPE,CONNECTION dev 2>/dev/null|awk -F: '/^ethernet/&&$2!=\"\"{print $2;exit}'||echo '';" +
            // Line 5: Ethernet IP (from the connected ethernet device)
            "ip -br addr show $(nmcli -t -f TYPE,DEVICE,STATE dev 2>/dev/null|awk -F: '/^ethernet.*:connected/{print $2;exit}') 2>/dev/null|awk '{print $3}'|cut -d/ -f1"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                var ls = this.text.trim().split("\n")
                root.wifiSSID = ls[0] ? ls[0].trim() : ""
                root.wifiOn   = root.wifiSSID !== ""
                root.wifiSig  = Math.min(100, parseInt(ls[1]) || 0)
                root.wifiIP   = ls[2] ? ls[2].trim() : ""
                root.ethName  = ls[3] ? ls[3].trim() : ""
                root.ethOn    = root.ethName !== ""
                root.ethIP    = ls[4] ? ls[4].trim() : ""
            }
        }
    }

    // Long-running nmcli monitor — fires netP immediately on any network state change.
    Process {
        id: nmcliMonP; running: root.barActive
        command: ["nmcli", "monitor"]
        stdout: SplitParser {
            onRead: data => {
                if (data.trim() !== "") {
                    netP.running = false
                    netP.running = true
                }
            }
        }
        // Auto-restart if nmcli monitor exits unexpectedly
        onExited: { if (root.barActive) { running = false; running = true } }
    }

    Timer { interval:6000; running:root.barActive; repeat:true; triggeredOnStart:true; onTriggered: btP.running=true }
    Process {
        id: btP; running:false
        command: ["sh", Qt.resolvedUrl("../scripts/bt-status.sh").toString().replace("file://","")]
        stdout: StdioCollector {
            onStreamFinished: {
                var t=this.text; root.btOn=t.indexOf("Powered: yes")>=0
                var m=t.match(/Device [0-9A-F:]+ (.+)/); root.btDev=m?m[1].trim():""
                if(root.btDev) btBatP.running=true
            }
        }
    }
    Process {
        id: btBatP; running:false
        command: ["sh","-c","upower -e 2>/dev/null|grep -i bluetooth|while read d;do p=$(upower -i \"$d\" 2>/dev/null|awk '/percentage/{print $2}');[ -n \"$p\" ]&&echo \"$p\"&&break;done"]
        stdout: StdioCollector { onStreamFinished: { root.btBat=this.text.trim() } }
    }

    Timer { interval:15000; running:root.barActive; repeat:true; triggeredOnStart:true; onTriggered: batP.running=true }
    Process {
        id: batP; running:false
        command: ["sh","-c","cat /sys/class/power_supply/BAT*/capacity 2>/dev/null|head -1;cat /sys/class/power_supply/BAT*/status 2>/dev/null|head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ls=this.text.trim().split("\n")
                root.batPct=parseFloat(ls[0])||100; root.batChg=ls[1] && ls[1].indexOf("Charging")>=0
            }
        }
    }

    // Volume/mute via the shared Audio service (native Pipewire — reactive, no
    // wpctl polling, and shared with ControlCenter so the two never desync).
    function setVol(v)  { Audio.setVolume(v) }
    function togMute()  { Audio.toggleMute() }

    Timer { interval:3000; running:root.barActive; repeat:true; triggeredOnStart:true; onTriggered: briP.running=true }
    Process {
        id: briP; running:false
        command: ["sh","-c","brightnessctl g;brightnessctl m"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ls=this.text.trim().split("\n")
                if(ls.length>=2 && parseFloat(ls[1])>0) root.bri=parseFloat(ls[0])/parseFloat(ls[1])
            }
        }
    }
    Process { id: briSet; running:false }
    function setBri(v) {
        var c=Math.max(0.01,Math.min(1,v))
        briSet.command=["sh","-c","brightnessctl s "+Math.round(c*100)+"%"]
        briSet.running=true; root.bri=c
    }

    Timer { interval:600000; running:root.barActive; repeat:true; triggeredOnStart:true; onTriggered: wxP.running=true }
    Process {
        id: wxP; running:false
        command: ["sh","-c","curl -sf --max-time 10 'wttr.in/?format=j1' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j=JSON.parse(this.text), cur=j.current_condition[0]
                    root.wxTemp=cur.temp_C+"°"; root.wxDesc=cur.weatherDesc[0].value
                    root.wxIcon=root.wCode(parseInt(cur.weatherCode))
                    var fc=[]
                    for(var i=0;i<Math.min(3,j.weather.length);i++){
                        var d=j.weather[i]
                        fc.push({date:d.date,max:d.maxtempC+"°",min:d.mintempC+"°",icon:root.wCode(parseInt(d.hourly[4].weatherCode)),desc:d.hourly[4].weatherDesc[0].value})
                    }
                    root.wxFc=fc
                } catch(e) {}
            }
        }
    }
    function wCode(c){
        if(c===113) return "☀"; if(c===116) return "⛅"
        if(c===119||c===122) return "☁"
        if(c>=176&&c<=263) return "🌧"; if(c>=296&&c<=314) return "🌦"
        if(c>=317&&c<=395) return "❄"; return "🌤"
    }

    Timer {
        interval:1000; running:root.barActive; repeat:true; triggeredOnStart:true
        onTriggered: {
            var d=new Date()
            root.tStr=String(d.getHours()).padStart(2,"0")+":"+String(d.getMinutes()).padStart(2,"0")+":"+String(d.getSeconds()).padStart(2,"0")
            root.dStr=String(d.getMonth()+1).padStart(2,"0")+"/"+String(d.getDate()).padStart(2,"0")
            root.dow="周"+["日","一","二","三","四","五","六"][d.getDay()]
        }
    }

    Process {
        id: calP; running:false
        command: ["sh","-c","gcalcli agenda --nocolor --tsv $(date +%Y-%m-%d) $(date -d '+14 days' +%Y-%m-%d) 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var ev=[]
                this.text.trim().split("\n").forEach(function(l){
                    var c=l.split("\t"); if(c.length>=6) ev.push({date:c[0],time:c[1],title:c[5].trim()})
                })
                root.gcal=ev
            }
        }
    }

    Process {
        id: todoR; running:false
        command: ["sh","-c","cat ~/todo-list.md 2>/dev/null||printf '# Todo\\n\\n- [ ] '"]
        stdout: StdioCollector { onStreamFinished: { root.todo=this.text } }
    }
    Process { id: todoW; running:false }
    Timer {
        id: todoT; interval:1500
        onTriggered: {
            var esc=root.todo.replace(/\\/g,"\\\\").replace(/'/g,"'\\''")
            todoW.command=["sh","-c","printf '%s' '"+esc+"' > ~/todo-list.md"]
            todoW.running=true
        }
    }

    Process { id: killP; running:false }
    function doKill(pid) {
        killP.command=["sh","-c","kill -9 "+pid]; killP.running=true
        Qt.callLater(function(){ cpuTop.running=true; gpuTop.running=true })
    }

    // ── Workspace tracking ────────────────────────────────────────────────
    // Native Hyprland event stream (replaces the long-lived scripts/hypr-events.py
    // python helper). Quickshell.Hyprland delivers socket2 events directly; we
    // filter to the workspace/window-layout events and rebuild state via wspQ.
    Connections {
        target: Hyprland
        enabled: root.barActive
        function onRawEvent(event) {
            switch (event.name) {
                case "workspace":        case "workspacev2":
                case "focusedmon":       case "focusedmonv2":
                case "openwindow":       case "closewindow":
                case "movewindow":       case "movewindowv2":
                case "moveworkspace":    case "moveworkspacev2":
                case "createworkspace":  case "createworkspacev2":
                case "destroyworkspace": case "destroyworkspacev2":
                    wspQ.running = true
                    root.wspMode = true
                    if (!root.vis) { root.vis = true; root.wspAutoShown = true }
                    wspAutoHide.restart()
                    break
            }
        }
    }
    Timer {
        id: wspAutoHide; interval:2500
        onTriggered: {
            if(!root.wspManualMode) root.wspMode=false
            if(root.wspAutoShown && !root.wspManualMode){ root.vis=false; root.wspAutoShown=false }
        }
    }
    Process {
        id: wspQ; running:false
        command: ["sh","-c","hyprctl monitors -j 2>/dev/null;echo '===';hyprctl workspaces -j 2>/dev/null;echo '===';hyprctl clients -j 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var parts=this.text.split("===\n")
                    if(parts.length<3) return
                    var monitors=JSON.parse(parts[0].trim()||"[]")
                    var workspaces=JSON.parse(parts[1].trim()||"[]")
                    var clients=JSON.parse(parts[2].trim()||"[]")
                    var md={}
                    monitors.forEach(function(m){ md[m.name]={activeId:m.activeWorkspace.id,wsps:[]} })
                    workspaces.forEach(function(w){
                        if(md[w.monitor] && w.id>0 && md[w.monitor].wsps.indexOf(w.id)<0)
                            md[w.monitor].wsps.push(w.id)
                    })
                    var wc={}
                    clients.forEach(function(c){
                        var wid=c.workspace ? c.workspace.id : -1
                        if(wid>0){
                            if(!wc[wid]) wc[wid]=[]
                            wc[wid].push({title:c.title||"",cls:c.class||c.initialClass||"?"})
                        }
                    })
                    Object.keys(md).forEach(function(mn){
                        var m=md[mn]
                        if(m.wsps.indexOf(m.activeId)<0) m.wsps.push(m.activeId)
                        m.wsps.sort(function(a,b){return a-b})
                    })
                    root.monitorData=md; root.wspClients=wc
                } catch(e) {}
            }
        }
    }
    Process { id: wspSwitchP; running:false }
    Timer { interval:600; running:root.barActive; repeat:false; onTriggered: wspQ.running=true }

    // ── Markdown parser ────────────────────────────────────────────────────
    function md(text) {
        var lines=text.replace(/\r\n/g,"\n").replace(/\r/g,"\n").split("\n"), out=[]
        for(var i=0;i<lines.length;i++){
            var l=lines[i]
            if(/^### /.test(l))           l='<b><font color="#2a3a5a">'+l.slice(4)+'</font></b>'
            else if(/^## /.test(l))       l='<b><font color="#6e2a2a">'+l.slice(3)+'</font></b>'
            else if(/^# /.test(l))        l='<big><b><font color="#6e2a2a">'+l.slice(2)+'</font></b></big>'
            else if(/^- \[x\] /i.test(l)) l='<font color="#2a5a3a">✓</font> <font color="#7a7358"><s>'+l.slice(6)+'</s></font>'
            else if(/^- \[ \] /.test(l))  l='<font color="#8a3a20">○</font> '+l.slice(6)
            else if(/^- /.test(l))        l='<font color="#7a7358">·</font> '+l.slice(2)
            else if(l.trim()==="")        l='<br>'
            l=l.replace(/\*\*(.+?)\*\*/g,'<b>$1</b>').replace(/\*(.+?)\*/g,'<i>$1</i>')
            out.push(l)
        }
        return out.join("<br>")
    }

    // ── Popup sizing ───────────────────────────────────────────────────────
    function pxOf(p, sw) {
        switch(p){
            case "cpu":     return 47;   case "gpu":  return 131
            case "wifi":    return 216;  case "bt":   return 298;  case "bat": return 378
            case "time":    return Math.round(sw/2 - 10)
            case "date":    return Math.round(sw/2 + 108)
            case "weather": return Math.round(sw - 148)
            case "vol":     return Math.round(sw - 240)
            case "bri":     return Math.round(sw - 330)
            case "todo":    return Math.round(sw - 44)
            case "wsp":     return root.wspPopupX
            case "claude":  return Math.round(sw - 174)
            default:        return Math.round(sw/2)
        }
    }
    function pw(p) {
        switch(p){
            case "cpu": case "gpu": return 430
            case "wifi": case "bt": case "bat": return 220
            case "time": return 230;  case "date": return 510
            case "weather": return 272; case "todo": return 460
            case "wsp": return 240
            case "claude": return 240
            default: return 0
        }
    }
    function ph(p) {
        switch(p){
            case "cpu": case "gpu": return 252
            case "wifi": return 192; case "bt": case "bat": return 172
            case "time": return 188; case "date": return 262
            case "weather": return 202; case "todo": return 292
            case "wsp": {
                var cl=root.wspClients[root.wspPopupWspId]
                return cl ? Math.min(280, 36 + cl.length*28) : 60
            }
            case "claude": return 220
            default: return 0
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1 — BAR
    // ══════════════════════════════════════════════════════════════════════
    Variants {
        model: root.barActive ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            property string scrName: modelData.name
            screen: modelData
            anchors.top: true; anchors.left: true; anchors.right: true
            property bool _barWipeRunning: false
            exclusionMode: root.vis ? ExclusionMode.Normal : ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            implicitWidth:  modelData.width
            implicitHeight: (root.vis || _barWipeRunning) ? root.barH : 0

            Rectangle {
                id: barContent
                y: 0             // content sits in place; barCurtain wipes to reveal/hide it
                width: parent.width; height: root.barH
                color: root.cBg
                border.color: root.cText; border.width: 1

                HoverHandler {
                    onHoveredChanged: {
                        root.barHovered = hovered // 將游標狀態同步給全域
                        if (hovered) {
                            edgeHideTimer.stop()
                            autoHideTimer.stop() // 滑鼠移入時，打斷自動收起倒數
                        } else {
                            if (root.edgeAutoShown && root.panel === "") {
                                edgeHideTimer.start()
                            }
                            if (root.vis && root.panel === "") {
                                autoHideTimer.restart() // 滑鼠移出時，重新啟動 3 秒倒數
                            }
                        }
                    }
                }

                // LEFT
                Row {
                    anchors.left: parent.left; anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Pill {
                        pLabel:"CPU"; pVal:root.cpuPct.toFixed(0)+"%"; pFill:root.cpuPct/100
                        pColor: root.cpuPct>80?root.cRed:root.cpuPct>50?root.cRose:root.cPink
                        pOn: root.panel==="cpu"
                        onTap: { cpuTop.running=true; root.panel=root.panel==="cpu"?"":"cpu" }
                    }
                    Pill {
                        pLabel:"GPU"; pVal:root.gpuPct.toFixed(0)+"%"; pFill:root.gpuPct/100
                        pColor: root.gpuPct>80?root.cRed:root.gpuPct>50?root.cRose:root.cPurple
                        pOn: root.panel==="gpu"
                        onTap: { gpuTop.running=true; root.panel=root.panel==="gpu"?"":"gpu" }
                    }
                    Chip {
                        cIcon: root.wifiOn?(root.wifiSig>=70?"▰▰▰":root.wifiSig>=40?"▰▰▱":"▰▱▱"):"✕"
                        cIconColor: root.wifiOn?(root.wifiSig>=60?root.cGreen:root.cRose):root.cRed
                        cLabel: root.wifiSSID||(root.wifiOn?"WiFi":"Off")
                        cOn: root.panel==="wifi"
                        onTap: { root.panel=root.panel==="wifi"?"":"wifi" }
                    }
                    Chip {
                        visible: root.ethOn
                        cIcon: "⬛"
                        cIconColor: root.cGreen
                        cLabel: root.ethName||"ETH"
                        cOn: root.panel==="eth"
                        onTap: { root.panel=root.panel==="eth"?"":"eth" }
                    }
                    Chip {
                        cIcon: "◈"
                        cIconColor: root.btOn?(root.btDev?root.cPink:root.cMuted):root.cDim
                        cLabel: root.btDev||(root.btOn?"BT":"Off")
                        cOn: root.panel==="bt"
                        onTap: { root.panel=root.panel==="bt"?"":"bt" }
                    }
                    Chip {
                        cIcon: root.batChg?"⚡":(root.batPct>=75?"♥♥♥":root.batPct>=50?"♥♥♡":root.batPct>=25?"♥♡♡":"♡♡♡")
                        cIconColor: root.batChg?root.cPurple:(root.batPct>=50?root.cGreen:root.batPct>=20?root.cRose:root.cRed)
                        cLabel: root.batPct.toFixed(0)+"%"
                        cOn: root.panel==="bat"
                        onTap: { root.panel=root.panel==="bat"?"":"bat" }
                    }
                }

                // CENTER — animated time/date ↔ workspace
                Item {
                    anchors.centerIn: parent
                    width: 320
                    height: root.barH
                    clip: true

                    // Time + Date (slides up when wspMode)
                    Row {
                        id: centerTimeRow
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        y: root.wspMode ? -root.barH : Math.round((root.barH - height) / 2)
                        Behavior on y { NumberAnimation { duration:220; easing.type:Easing.OutCubic } }

                        // 獨立的跳轉進程，避免與其他點擊衝突
                        Process { id: timeWspJump; running: false }

                        Ctr {
                            cText: root.tStr; cSize:17; cBold:true; cColor:root.cPink
                            cOn: root.panel==="time"
                            onTap: { root.panel=root.panel==="time"?"":"time" }
                            onScroll: function(d) {
                                var dir = d > 0 ? "e-1" : "e+1"
                                timeWspJump.running = false
                                // 加上 >/dev/null 2>&1 & 強制進程瞬間結束
                                timeWspJump.command = ["sh", "-c", "hyprctl dispatch 'hl.dsp.focus({ workspace = \"" + dir + "\" })' >/dev/null 2>&1 &"]
                                timeWspJump.running = true
                            }
                        }
                        Ctr {
                            cText: root.dStr+"  "+root.dow; cSize:11; cColor:root.cPurple
                            cOn: root.panel==="date"
                            onTap: { calP.running=true; root.panel=root.panel==="date"?"":"date" }
                            onScroll: function(d) {
                                var dir = d > 0 ? "e-1" : "e+1"
                                timeWspJump.running = false
                                // 加上 >/dev/null 2>&1 & 強制進程瞬間結束
                                timeWspJump.command = ["sh", "-c", "hyprctl dispatch 'hl.dsp.focus({ workspace = \"" + dir + "\" })' >/dev/null 2>&1 &"]
                                timeWspJump.running = true
                            }
                        }
                    }

                    // Workspace dots (動態置中滑動車廂)
                    Row {
                        id: wspDotsRow
                        // 移除原本的 anchors.horizontalCenter，改由動態計算的 targetX 接管
                        x: targetX
                        y: root.wspMode ? Math.round((root.barH - height) / 2) : root.barH
                        spacing: 10

                        // 動態計算當前 Active 節點的絕對偏移量，使其恆定保持在寬度 320 的正中央 (160)
                        property real targetX: {
                            var mdata = root.monitorData[scrName]
                            if (!mdata || !mdata.wsps || mdata.wsps.length === 0) return 160
                            var activeId = mdata.activeId
                            var cx = 0
                            var found = false

                            for (var i = 0; i < mdata.wsps.length; i++) {
                                var wid = mdata.wsps[i]
                                var isAct = (wid === activeId)
                                var hasW = root.wspClients[wid] && root.wspClients[wid].length > 0
                                var itemW = isAct ? 28 : (hasW ? 18 : 8)

                                if (isAct) {
                                    cx += itemW / 2
                                    found = true
                                    break
                                } else {
                                    cx += itemW + 10 // 加上 spacing
                                }
                            }
                            return found ? (160 - cx) : 160
                        }

                        // 為 x 軸加上過渡動畫，形成平滑的置中滑動感
                        Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                        Repeater {
                            model: {
                                var mdata = root.monitorData[scrName]
                                return mdata ? mdata.wsps : []
                            }
                            Item {
                                id: dotItem
                                property int wspId: modelData
                                property bool isActive: {
                                    var mdata=root.monitorData[scrName]
                                    return mdata ? mdata.activeId===wspId : false
                                }
                                property bool hasWin: root.wspClients[wspId] && root.wspClients[wspId].length>0

                                width: isActive ? 28 : (hasWin ? 18 : 8)
                                height: root.barH
                                Behavior on width { NumberAnimation { duration:150; easing.type:Easing.OutCubic } }

                                // 每個 dot 擁有獨立的 Process，杜絕元件庫的狀態競爭
                                Process {
                                    id: localWspJump
                                    running: false
                                }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 1
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: isActive ? "✦" : (hasWin ? "✦" : "·")
                                        font.pixelSize: isActive ? 14 : (hasWin ? 9 : 7)
                                        font.family: "Share Tech Mono"
                                        color: isActive ? root.cPink : (hasWin ? root.cRose : root.cBorder)
                                        Behavior on color { ColorAnimation { duration:200 } }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: wspId
                                        font.pixelSize: isActive ? 9 : 7
                                        font.family: "Share Tech Mono"
                                        color: isActive ? root.cPink : root.cMuted
                                        visible: hasWin || isActive
                                        Behavior on color { ColorAnimation { duration:200 } }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        localWspJump.running = false
                                        // 加上脫離機制，並確保數字正確轉換為字串
                                        localWspJump.command = ["sh", "-c", "hyprctl dispatch 'hl.dsp.focus({ workspace = \"" + wspId.toString() + "\" })' >/dev/null 2>&1 &"]
                                        localWspJump.running = true
                                    }
                                    onEntered: {
                                        if(hasWin) {
                                            var pt = dotItem.mapToItem(null, dotItem.width/2, 0)
                                            root.wspPopupX = pt.x
                                            root.wspPopupWspId = wspId
                                            root.wspPopupScreen = scrName
                                            root.panel = "wsp"
                                        }
                                    }
                                    onExited: {
                                        if(root.panel === "wsp") root.panel = ""
                                    }
                                    onWheel: function(w) {
                                        var d = w.angleDelta.y > 0 ? "e-1" : "e+1"
                                        localWspJump.running = false
                                        localWspJump.command = ["sh", "-c", "hyprctl dispatch 'hl.dsp.focus({ workspace = \"" + d + "\" })' >/dev/null 2>&1 &"]
                                        localWspJump.running = true
                                    }
                                }
                            }
                        }
                    }

                    // Right-click = toggle persistent workspace view
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        propagateComposedEvents: true
                        onClicked: function(m) {
                            root.wspManualMode = !root.wspManualMode
                            root.wspMode = root.wspManualMode
                        }
                    }
                }

                // RIGHT
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4; layoutDirection: Qt.RightToLeft

                    Chip {
                        cIcon: "✦"; cIconColor:root.cPink; cLabel:"TODO"
                        cOn: root.panel==="todo"
                        onTap: { todoR.running=true; root.panel=root.panel==="todo"?"":"todo" }
                    }
                    Chip {
                        cIcon: root.wxIcon; cIconColor:root.cText; cLabel:root.wxTemp
                        cOn: root.panel==="weather"
                        onTap: { root.panel=root.panel==="weather"?"":"weather" }
                    }
                    Chip {
                        cIcon: "◈"; cIconColor: root.cPurple; cLabel: root.claudeTodayCost
                        cOn: root.panel==="claude"
                        onTap: { root.panel=root.panel==="claude"?"":"claude" }
                    }
                    Scrl {
                        sIcon: root.muted?"🔇":(root.vol>0.8?"🔊":"🔉")
                        sLabel: root.muted?"mute":Math.round(root.vol/1.5*100)+"%"
                        sFill: root.muted?0:root.vol/1.5; sColor:root.cPurple
                        onIconTap: { root.togMute() }
                        onScroll: function(d){ root.setVol(root.vol+d*0.025) }
                    }
                    Scrl {
                        sIcon: "☀"; sLabel:Math.round(root.bri*100)+"%"; sFill:root.bri; sColor:root.cPink
                        onIconTap: {}
                        onScroll: function(d){ root.setBri(root.bri+d*0.025) }
                    }
                }

                // NieR paper grid
                Repeater {
                    model: Math.ceil(modelData.width / 20) + 1
                    Rectangle { x:index*20; y:0; width:1; height:root.barH; color:Qt.rgba(70/255,63/255,46/255,0.09) }
                }
                Repeater {
                    model: Math.ceil(root.barH / 20) + 1
                    Rectangle { x:0; y:index*20; width:parent.width; height:1; color:Qt.rgba(70/255,63/255,46/255,0.09) }
                }
            } // barContent

            // Wipe curtain — covers the bar then slides away (top → bottom) to
            // reveal it. A thin accent line rides the leading edge (NieR scanline).
            Rectangle {
                id: barCurtain
                anchors.left: parent.left; anchors.right: parent.right
                y: 0; height: 0; color: root.cBg; z: 50
                // accent rides the moving (top) edge of the curtain — NieR scanline
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 2; color: root.cPink
                    opacity: barCurtain.height > 2 ? 0.9 : 0
                }
            }

            // Reveal: curtain covers the bar, then its top edge glides DOWN,
            // wiping the content into view top→bottom. Single smooth OutQuint
            // motion — no redundant hidden slide, no dead pause.
            ParallelAnimation {
                id: barReveal
                onStarted: { _barWipeRunning = true; barContent.y = 0; barCurtain.y = 0; barCurtain.height = root.barH }
                NumberAnimation { target: barCurtain; property: "y";      to: root.barH; duration: 420; easing.type: Easing.OutQuint }
                NumberAnimation { target: barCurtain; property: "height"; to: 0;         duration: 420; easing.type: Easing.OutQuint }
                onFinished: { barCurtain.height = 0; _barWipeRunning = false }
            }

            // Hide: curtain grows UPWARD from the bottom edge, covering the
            // content bottom→top, then the window collapses.
            ParallelAnimation {
                id: barHide
                onStarted: { _barWipeRunning = true; barCurtain.y = root.barH; barCurtain.height = 0 }
                NumberAnimation { target: barCurtain; property: "y";      to: 0;         duration: 300; easing.type: Easing.InQuint }
                NumberAnimation { target: barCurtain; property: "height"; to: root.barH; duration: 300; easing.type: Easing.InQuint }
                onFinished: { _barWipeRunning = false }
            }

            Connections {
                target: root
                function onVisChanged() {
                    if (root.vis) {
                        barHide.stop()
                        barReveal.start()
                    } else {
                        barReveal.stop()
                        barHide.start()
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 1b — EDGE HOTSPOT (3px strip; auto-shows bar on hover)
    // ══════════════════════════════════════════════════════════════════════
    Variants {
        model: root.barActive ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top: true; anchors.left: true; anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Top
            color: "transparent"
            implicitWidth:  modelData.width
            implicitHeight: 3
            visible: !root.vis

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    root.vis = true
                    root.edgeAutoShown = true
                    edgeHideTimer.stop()
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // 2 — POPUP
    // ══════════════════════════════════════════════════════════════════════
    Variants {
        model: root.barActive ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            property string scrName: modelData.name
            screen: modelData
            anchors.top: true; anchors.left: true; anchors.right: true
            margins.top: root.barH
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.panel==="todo"||root.panel==="time") ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            color: "transparent"
            implicitWidth:  modelData.width
            implicitHeight: modelData.height - root.barH
            visible: root._popupVis && root.vis &&
                     (!root._popupWasWsp || scrName === root._popupWspScreen)

            MouseArea { anchors.fill:parent; enabled: root.panel !== ""; onClicked: root.panel="" }

            Item {
                anchors.fill: parent
                clip: true

                Rectangle {
                id: box
                property int bw: root.pw(root.panel)
                property int _lastBw: 0
                onBwChanged: if(bw > 0) _lastBw = bw
                property int animBw: bw > 0 ? bw : _lastBw

                property int bh: root.ph(root.panel)
                property int _lastBh: 0
                onBhChanged: if(bh > 0) _lastBh = bh
                property int animBh: bh > 0 ? bh : _lastBh

                property int cx: root.pxOf(root.panel, modelData.width)
                property int _lastCx: Math.round(modelData.width / 2)
                onCxChanged: if(root.panel !== "") _lastCx = cx
                property int animCx: root.panel !== "" ? cx : _lastCx

                x: Math.max(8, Math.min(modelData.width - animBw - 8, animCx - animBw/2))
                width:  animBw
                height: animBh
                radius: root.rad
                color:  root.cBg
                border.color: root.cText; border.width:1
                clip: true

                Behavior on x      { NumberAnimation { duration:160; easing.type:Easing.OutCubic } }
                Behavior on width  { NumberAnimation { duration:160; easing.type:Easing.OutCubic } }

                // NieR paper grid
                Repeater {
                    model: 30
                    Rectangle { x:index*20; y:0; width:1; height:1000; color:Qt.rgba(70/255,63/255,46/255,0.09) }
                }
                Repeater {
                    model: 20
                    Rectangle { x:0; y:index*20; width:1000; height:1; color:Qt.rgba(70/255,63/255,46/255,0.09) }
                }

                Rectangle {
                    anchors.top: parent.top; width:parent.width; height:2; radius:root.rad
                    color: ["cpu","gpu","bat"].indexOf(root.panel)>=0 ? root.cPink :
                           ["wifi","eth","bt"].indexOf(root.panel)>=0 ? root.cRose :
                           root.panel==="time"||root.panel==="date"  ? root.cPurple : root.cPink
                }

                MouseArea { anchors.fill:parent; acceptedButtons:Qt.AllButtons; onClicked:{} }

                Item {
                    anchors.fill: parent; anchors.topMargin:2
                    opacity: box.height>24 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration:100 } }

                    // CPU
                    ProcPanel {
                        visible: root.panel==="cpu"
                        anchors.fill:parent; anchors.margins:14
                        ppTitle:"CPU  ·  "+root.cpuPct.toFixed(0)+"%"
                        ppColor:root.cPink; ppProcs:root.cpuProcs; ppMem:false
                        onKill: function(pid){ root.doKill(pid) }
                        onRefresh: { cpuTop.running=true }
                    }

                    // GPU
                    ProcPanel {
                        visible: root.panel==="gpu"
                        anchors.fill:parent; anchors.margins:14
                        ppTitle:"GPU  ·  "+root.gpuPct.toFixed(0)+"%  "+root.gpuTemp.toFixed(0)+"°  "+root.gpuMem.toFixed(0)+" MiB"
                        ppColor:root.cPurple; ppProcs:root.gpuProcs; ppMem:true
                        onKill: function(pid){ root.doKill(pid) }
                        onRefresh: { gpuTop.running=true }
                    }

                    // WiFi
                    Item {
                        visible: root.panel==="wifi"; anchors.fill:parent; anchors.margins:16
                        Column {
                            spacing:10
                            PLabel { text:"NETWORK" }
                            IRow { il:"SSID";   iv:root.wifiSSID||"—" }
                            IRow { il:"SIGNAL";  iv:root.wifiSig+"%" }
                            IRow { il:"IP";      iv:root.wifiIP||"—" }
                            IRow { il:"STATUS";  iv:root.wifiOn?"CONNECTED":"OFFLINE"; ivc:root.wifiOn?root.cGreen:root.cRed }
                            Row {
                                spacing:5; topPadding:4
                                Repeater {
                                    model:5
                                    Item {
                                        width:11; height:44
                                        Rectangle {
                                            anchors.bottom:parent.bottom; width:parent.width; height:8+index*8; radius:2
                                            color: index<Math.ceil(root.wifiSig/20)?root.cGreen:root.cDim
                                            Behavior on color { ColorAnimation { duration:300 } }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Ethernet
                    Item {
                        visible: root.panel==="eth"; anchors.fill:parent; anchors.margins:16
                        Column {
                            spacing:10
                            PLabel { text:"ETHERNET" }
                            IRow { il:"NAME";   iv:root.ethName||"—" }
                            IRow { il:"IP";     iv:root.ethIP||"—" }
                            IRow { il:"STATUS"; iv:root.ethOn?"CONNECTED":"OFFLINE"; ivc:root.ethOn?root.cGreen:root.cRed }
                        }
                    }

                    // BT
                    Item {
                        visible: root.panel==="bt"; anchors.fill:parent; anchors.margins:16
                        Column {
                            spacing:10
                            PLabel { text:"BLUETOOTH" }
                            IRow { il:"STATUS"; iv:root.btOn?"ACTIVE":"OFF"; ivc:root.btOn?root.cPink:root.cMuted }
                            IRow { il:"DEVICE"; iv:root.btDev||"—" }
                            IRow { il:"BATTERY";iv:root.btBat||"N/A" }
                            Row {
                                spacing:6; topPadding:6
                                visible: root.btOn && root.btDev!==""
                                Repeater {
                                    model:3
                                    Rectangle {
                                        width:10; height:10; radius:5; color:root.cPink
                                        anchors.verticalCenter:parent.verticalCenter
                                        SequentialAnimation on opacity {
                                            running: root.btOn && root.btDev!==""
                                            loops: Animation.Infinite
                                            PauseAnimation  { duration:index*300 }
                                            NumberAnimation { to:0.15; duration:600; easing.type:Easing.InOutSine }
                                            NumberAnimation { to:1.0;  duration:600; easing.type:Easing.InOutSine }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Battery
                    Item {
                        visible: root.panel==="bat"; anchors.fill:parent; anchors.margins:16
                        Column {
                            spacing:10
                            PLabel { text:"BATTERY" }
                            IRow { il:"LEVEL";  iv:root.batPct.toFixed(0)+"%" }
                            IRow { il:"STATUS"; iv:root.batChg?"CHARGING ⚡":"DISCHARGING"; ivc:root.batChg?root.cPurple:root.cText }
                            Item {
                                width:180; height:26
                                Rectangle {
                                    width:parent.width-8; height:parent.height; radius:root.rad
                                    color:root.cSurf; border.color:root.cBorder; border.width:1
                                    Rectangle {
                                        width: Math.max(0,(parent.width-2)*root.batPct/100)
                                        height:parent.height-2
                                        anchors.verticalCenter:parent.verticalCenter; anchors.left:parent.left; anchors.leftMargin:1
                                        radius:root.rad
                                        color:root.batChg?root.cPurple:(root.batPct>=50?root.cGreen:root.batPct>=20?root.cRose:root.cRed)
                                        Behavior on width { NumberAnimation { duration:600 } }
                                    }
                                    Text { anchors.centerIn:parent; text:root.batPct.toFixed(0)+"%"; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cText }
                                }
                                Rectangle { x:parent.width-7; y:parent.height*0.3; width:5; height:parent.height*0.4; color:root.cBorder; radius:1 }
                            }
                        }
                    }

                    // Stopwatch
                    Item {
                        id: sw; visible:root.panel==="time"; anchors.fill:parent; anchors.margins:16
                        property bool go: false; property int elapsed: 0
                        Timer { interval:1000; running:sw.go; repeat:true; onTriggered: sw.elapsed++ }
                        function fmt(s){ var h=Math.floor(s/3600),m=Math.floor((s%3600)/60),ss=s%60; return(h>0?String(h).padStart(2,"0")+":":"") +String(m).padStart(2,"0")+":"+String(ss).padStart(2,"0") }
                        Column {
                            anchors.centerIn:parent; spacing:14
                            PLabel { text:"STOPWATCH"; anchors.horizontalCenter:parent.horizontalCenter }
                            Text {
                                anchors.horizontalCenter:parent.horizontalCenter
                                text:sw.fmt(sw.elapsed); font.pixelSize:44; font.family:"Share Tech Mono"
                                color:sw.go?root.cPink:root.cText
                                Behavior on color { ColorAnimation { duration:300 } }
                            }
                            Row {
                                anchors.horizontalCenter:parent.horizontalCenter; spacing:8
                                PBtn { bLabel:sw.go?"STOP":"START"; bColor:sw.go?root.cRed:root.cGreen; onBClick:{ sw.go=!sw.go } }
                                PBtn { bLabel:"RESET"; bColor:root.cMuted; onBClick:{ sw.go=false; sw.elapsed=0 } }
                            }
                        }
                    }

                    // Calendar + gcal
                    Item {
                        id: calItem; visible:root.panel==="date"; anchors.fill:parent
                        property int cy: new Date().getFullYear()
                        property int cm: new Date().getMonth()
                        function dim(y,m){ return new Date(y,m+1,0).getDate() }
                        function fdow(y,m){ return new Date(y,m,1).getDay() }
                        Row {
                            anchors.fill:parent; spacing:0
                            Item {
                                width:214; height:parent.height
                                Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:root.cBorder }
                                Column {
                                    anchors.fill:parent; anchors.margins:12; spacing:6
                                    Row {
                                        width:parent.width
                                        Text {
                                            text:"◂"; font.pixelSize:13; color:root.cPurple
                                            MouseArea {
                                                anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                                onClicked: { calItem.cm--; if(calItem.cm<0){ calItem.cm=11; calItem.cy-- } }
                                            }
                                        }
                                        Text {
                                            width:parent.width-28; horizontalAlignment:Text.AlignHCenter
                                            text:calItem.cy+" · "+["一","二","三","四","五","六","七","八","九","十","十一","十二"][calItem.cm]+"月"
                                            font.pixelSize:11; font.family:"Share Tech Mono"; color:root.cText
                                        }
                                        Text {
                                            text:"▸"; font.pixelSize:13; color:root.cPurple
                                            MouseArea {
                                                anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                                onClicked: { calItem.cm++; if(calItem.cm>11){ calItem.cm=0; calItem.cy++ } }
                                            }
                                        }
                                    }
                                    Row {
                                        width:parent.width
                                        Repeater {
                                            model:["日","一","二","三","四","五","六"]
                                            Text {
                                                width:190/7; text:modelData; horizontalAlignment:Text.AlignHCenter
                                                font.pixelSize:9; font.family:"Share Tech Mono"
                                                color:(index===0||index===6)?root.cPink:root.cDim
                                            }
                                        }
                                    }
                                    Rectangle { width:parent.width; height:1; color:root.cBorder }
                                    Grid {
                                        columns:7; width:190
                                        property int _d: calItem.dim(calItem.cy,calItem.cm)
                                        property int _f: calItem.fdow(calItem.cy,calItem.cm)
                                        Repeater {
                                            model: parent._f+parent._d
                                            delegate: Item {
                                                width:190/7; height:22
                                                property int  day:   index-parent._f+1
                                                property bool valid: index>=parent._f
                                                property bool today: {
                                                    var n=new Date()
                                                    return valid&&day===n.getDate()&&calItem.cm===n.getMonth()&&calItem.cy===n.getFullYear()
                                                }
                                                Rectangle { anchors.centerIn:parent; width:18; height:18; radius:root.rad; color:today?root.cPink:"transparent" }
                                                Text { anchors.centerIn:parent; text:valid?day:""; font.pixelSize:10; font.family:"Share Tech Mono"; color:today?root.cBg:(valid?root.cText:root.cDim) }
                                            }
                                        }
                                    }
                                }
                            }
                            Item {
                                width:parent.width-214; height:parent.height
                                Column {
                                    anchors.fill:parent; anchors.margins:12; spacing:4
                                    PLabel { text:"UPCOMING" }
                                    Repeater {
                                        model:Math.min(root.gcal.length,7)
                                        Item {
                                            width:parent?parent.width:0; height:28
                                            Rectangle { anchors.fill:parent; anchors.margins:1; radius:root.rad; color:eHov.containsMouse?root.cSurf:"transparent" }
                                            Row {
                                                anchors.verticalCenter:parent.verticalCenter; anchors.left:parent.left; anchors.leftMargin:6; spacing:8
                                                Rectangle { width:2; height:14; color:root.cPurple; radius:1; anchors.verticalCenter:parent.verticalCenter }
                                                Text { text:root.gcal[index].date.slice(5)+" "+root.gcal[index].time; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cMuted; width:82 }
                                                Text { text:root.gcal[index].title; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cText; elide:Text.ElideRight; width:parent.parent.width-110 }
                                            }
                                            MouseArea { id:eHov; anchors.fill:parent; hoverEnabled:true }
                                        }
                                    }
                                    Text { visible:root.gcal.length===0; text:"no upcoming events"; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cDim }
                                }
                            }
                        }
                    }

                    // Weather
                    Item {
                        visible: root.panel==="weather"; anchors.fill:parent; anchors.margins:16
                        Column {
                            spacing:14
                            PLabel { text:"FORECAST" }
                            Row {
                                spacing:14
                                Text { text:root.wxIcon; font.pixelSize:34 }
                                Column {
                                    anchors.verticalCenter:parent.verticalCenter; spacing:3
                                    Text { text:root.wxTemp; font.pixelSize:22; font.family:"Share Tech Mono"; color:root.cText }
                                    Text { text:root.wxDesc; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cMuted }
                                }
                            }
                            Rectangle { width:150; height:1; color:root.cBorder }
                            Row {
                                spacing:10
                                Repeater {
                                    model:root.wxFc
                                    Rectangle {
                                        width:74; height:72; radius:root.rad; color:root.cSurf; border.color:root.cBorder; border.width:1
                                        Column {
                                            anchors.centerIn:parent; spacing:4
                                            Text { text:modelData.icon; font.pixelSize:20; anchors.horizontalCenter:parent.horizontalCenter }
                                            Text { text:modelData.max+"/"+modelData.min; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cMuted; anchors.horizontalCenter:parent.horizontalCenter }
                                            Text { text:modelData.date.slice(5); font.pixelSize:8; font.family:"Share Tech Mono"; color:root.cDim; anchors.horizontalCenter:parent.horizontalCenter }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Claude usage
                    Item {
                        visible: root.panel==="claude"; anchors.fill:parent; anchors.margins:16
                        Column {
                            spacing:10
                            PLabel { text:"CLAUDE  USAGE" }
                            Row {
                                spacing:0
                                Text { text:"WEEK";  width:60; font.pixelSize:9;  font.family:"Share Tech Mono"; color:root.cMuted }
                                Text { text:root.claudeWeekCost;  font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cText; font.bold:true }
                                Text { text:" · "+root.claudeWeekTok;  font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cDim }
                            }
                            Row {
                                spacing:0
                                Text { text:"MONTH"; width:60; font.pixelSize:9;  font.family:"Share Tech Mono"; color:root.cMuted }
                                Text { text:root.claudeMonthCost; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cText; font.bold:true }
                                Text { text:" · "+root.claudeMonthTok; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cDim }
                            }
                            Row {
                                spacing:0
                                Text { text:"TODAY"; width:60; font.pixelSize:9;  font.family:"Share Tech Mono"; color:root.cMuted }
                                Text { text:root.claudeTodayCost; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cPink; font.bold:true }
                                Text { text:" · "+root.claudeTodayTok; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cDim }
                            }
                            Rectangle { width:200; height:1; color:root.cBorder }
                            IRow { il:"RESET IN"; iv:root.claudeResetStr; ivc:root.cPurple }
                            Text {
                                text:"est. via API pricing · session start "+root.sessionStart.toLocaleTimeString(Qt.locale(),"HH:mm")
                                font.pixelSize:8; font.family:"Share Tech Mono"; color:root.cDim
                                wrapMode:Text.Wrap; width:200
                            }
                        }
                    }

                    // Workspace window list popup
                    Item {
                        visible: root.panel==="wsp"; anchors.fill:parent; anchors.margins:12
                        Column {
                            spacing:6; width:parent.width
                            PLabel { text:"WSP "+root.wspPopupWspId }
                            Repeater {
                                model: root.wspClients[root.wspPopupWspId] || []
                                Item {
                                    width:parent?parent.width:0; height:28
                                    Rectangle { anchors.fill:parent; anchors.margins:1; radius:root.rad; color:root.cSurf }
                                    Row {
                                        anchors.verticalCenter:parent.verticalCenter; anchors.left:parent.left; anchors.leftMargin:8; spacing:8
                                        Rectangle { width:6; height:6; radius:3; color:root.cPink; anchors.verticalCenter:parent.verticalCenter }
                                        Text {
                                            text: modelData.cls; width:60; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cMuted; elide:Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.title; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cText
                                            elide:Text.ElideRight; width:parent.parent.width-90
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Todo
                    Item {
                        id: todoPanel; visible:root.panel==="todo"; anchors.fill:parent
                        property bool editing: false

                        Row {
                            anchors.fill:parent; spacing:0
                            Item {
                                width: todoPanel.editing ? parent.width/2 : parent.width
                                height: parent.height; clip:true
                                Behavior on width { NumberAnimation { duration:160; easing.type:Easing.OutCubic } }
                                Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:root.cBorder; visible:todoPanel.editing }
                                Flickable {
                                    anchors.fill:parent; anchors.margins:14
                                    contentWidth: width
                                    contentHeight: mdOut.implicitHeight+20
                                    clip:true
                                    Text {
                                        id: mdOut; width:parent.width
                                        text: root.md(root.todo)
                                        textFormat:Text.RichText; wrapMode:Text.Wrap
                                        font.pixelSize:11; font.family:"Share Tech Mono"; color:root.cText; lineHeight:1.6
                                    }
                                }
                            }
                            Item {
                                width: todoPanel.editing ? parent.width/2 : 0
                                height: parent.height; visible:todoPanel.editing; clip:true
                                Behavior on width { NumberAnimation { duration:160; easing.type:Easing.OutCubic } }
                                Flickable {
                                    anchors.fill:parent; anchors.margins:14
                                    contentWidth: width
                                    contentHeight: tEdit.implicitHeight+20
                                    clip:true
                                    TextEdit {
                                        id: tEdit; width:parent.width
                                        font.pixelSize:11; font.family:"Share Tech Mono"; color:root.cText
                                        wrapMode:TextEdit.Wrap; selectByMouse:true
                                        selectionColor:Qt.rgba(root.cPurple.r,root.cPurple.g,root.cPurple.b,0.3)
                                        onTextChanged: { root.todo=text; todoT.restart() }
                                    }
                                }
                            }
                        }
                        Row {
                            anchors.right:parent.right; anchors.top:parent.top; anchors.margins:8; spacing:4
                            PBtn {
                                bLabel:todoPanel.editing?"PREVIEW":"EDIT"; bColor:root.cPurple
                                onBClick: {
                                    todoPanel.editing=!todoPanel.editing
                                    if(todoPanel.editing) tEdit.text=root.todo
                                }
                            }
                        }
                    }

                } // fade Item

                Rectangle {
                    id: popupCurtain
                    anchors.left: parent.left; anchors.right: parent.right
                    y: 0; height: 0
                    color: root.cBg
                    z: 50
                }
            } // box Rectangle
            } // clip Item

            SequentialAnimation {
                id: popupReveal
                onStarted: {
                    box.y = -(box.animBh + 10)
                    popupCurtain.y = 0
                    popupCurtain.height = box.animBh
                }
                NumberAnimation { target: box; property: "y"; to: 6; duration: 300; easing.type: Easing.OutExpo }
                ParallelAnimation {
                    NumberAnimation { target: popupCurtain; property: "y";      to: box.animBh - 2; duration: 220; easing.type: Easing.OutExpo }
                    NumberAnimation { target: popupCurtain; property: "height"; to: 2;              duration: 220; easing.type: Easing.OutExpo }
                }
                onFinished: { popupCurtain.height = 0 }
            }

            SequentialAnimation {
                id: popupHide
                onStarted: {
                    popupCurtain.y = box.animBh - 2
                    popupCurtain.height = 2
                }
                ParallelAnimation {
                    NumberAnimation { target: popupCurtain; property: "y";      to: 0;           duration: 140; easing.type: Easing.InOutQuart }
                    NumberAnimation { target: popupCurtain; property: "height"; to: box.animBh;  duration: 140; easing.type: Easing.InOutQuart }
                }
                NumberAnimation { target: box; property: "y"; to: -(box.animBh + 10); duration: 220; easing.type: Easing.InExpo }
            }

            Connections {
                target: root
                function onPanelChanged() {
                    if (root.panel !== "") {
                        if (popupHide.running || box.y < 0) {
                            popupHide.stop()
                            popupReveal.start()
                        }
                    } else {
                        popupReveal.stop()
                        popupHide.start()
                    }
                }
            }
        } // popup PanelWindow
    } // popup Variants

    // ══════════════════════════════════════════════════════════════════════
    // COMPONENTS
    // ══════════════════════════════════════════════════════════════════════

    // 10-segment dot fill bar
    component DotBar: Row {
        property real fill: 0
        property color dotColor: root.cPink
        spacing: 2
        Repeater {
            model: 10
            Rectangle {
                width:5; height:5; radius:1
                color: index < Math.round(fill*10) ? dotColor : root.cDim
                Behavior on color { ColorAnimation { duration:200 } }
            }
        }
    }

    component Pill: Item {
        property string pName: ""
        property string pLabel:""; property string pVal:""; property real pFill:0
        property color  pColor:root.cPink; property bool pOn:false
        signal tap
        property bool _h:false; width:84; height:root.barH
        Rectangle { anchors.fill:parent; anchors.margins:3; radius:root.rad; color:(_h||pOn)?root.cSurf:"transparent"; border.color:pOn?pColor:(_h?root.cBorder:"transparent"); border.width:1 }
        Column {
            anchors.centerIn: parent; spacing: 5
            Row {
                anchors.horizontalCenter: parent.horizontalCenter; spacing: 5
                Text { text:pLabel; font.pixelSize:9;  font.family:"Share Tech Mono"; color:root.cMuted }
                Text { text:pVal;   font.pixelSize:11; font.family:"Share Tech Mono"; color:root.cText; font.bold:true }
            }
            DotBar { fill:Math.min(1,Math.max(0,pFill)); dotColor:pColor; anchors.horizontalCenter:parent.horizontalCenter }
        }
        MouseArea {
            anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
            onEntered: { _h=true;  if(pName!=="") root.togglePanel(pName, false, true) }
            onExited:  { _h=false; if(pName!=="") root.togglePanel(pName, false, false) }
            onClicked: { if(pName!=="") root.togglePanel(pName, true, false); else tap() }
        }
    }

    component Chip: Item {
        property string pName: ""
        property string cIcon:"◈"; property color cIconColor:root.cPink; property string cLabel:""; property bool cOn:false
        signal tap
        property bool _h:false; width:Math.max(62,_r.implicitWidth+18); height:root.barH
        Rectangle { anchors.fill:parent; anchors.margins:3; radius:root.rad; color:(_h||cOn)?root.cSurf:"transparent"; border.color:cOn?root.cPink:(_h?root.cBorder:"transparent"); border.width:1 }
        Row {
            id:_r; anchors.centerIn:parent; spacing:5
            Text { text:cIcon;  font.pixelSize:12; font.family:"Share Tech Mono"; color:cIconColor }
            Text { text:cLabel; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cMuted; elide:Text.ElideRight; width:Math.min(implicitWidth,80) }
        }
        MouseArea {
            anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
            onEntered: { _h=true;  if(pName!=="") root.togglePanel(pName, false, true) }
            onExited:  { _h=false; if(pName!=="") root.togglePanel(pName, false, false) }
            onClicked: { if(pName!=="") root.togglePanel(pName, true, false); else tap() }
        }
    }

    component Ctr: Item {
        property string pName: ""
        property string cText:""; property int cSize:16; property bool cBold:false; property color cColor:root.cPink; property bool cOn:false
        signal tap; signal scroll(real d)
        property bool _h:false; width:_t.implicitWidth+22; height:root.barH
        Rectangle { anchors.fill:parent; anchors.margins:3; radius:root.rad; color:(_h||cOn)?root.cSurf:"transparent"; border.color:cOn?cColor:(_h?root.cBorder:"transparent"); border.width:1 }
        Text { id:_t; anchors.centerIn:parent; text:cText; font.pixelSize:cSize; font.family:"Share Tech Mono"; font.bold:cBold; color:cOn?root.cText:(_h?root.cText:root.cMuted) }
        MouseArea {
            anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
            onEntered: { _h=true;  if(pName!=="") root.togglePanel(pName, false, true) }
            onExited:  { _h=false; if(pName!=="") root.togglePanel(pName, false, false) }
            onClicked: { if(pName!=="") root.togglePanel(pName, true, false); else tap() }
            onWheel: function(w) { scroll(w.angleDelta.y / 120) }
        }
    }

    component Scrl: Item {
        property string sIcon:"☀"; property string sLabel:""; property real sFill:0.5
        property color  sColor:root.cPink
        signal iconTap; signal scroll(real d)
        property bool _h:false
        width:88; height:root.barH

        Rectangle {
            anchors.fill:parent; anchors.margins:3; radius:root.rad
            color:_h?root.cSurf:"transparent"
            border.color:_h?root.cBorder:"transparent"; border.width:1
            Behavior on color { ColorAnimation { duration:100 } }
        }
        Column {
            anchors.centerIn:parent; spacing:5
            Row {
                anchors.horizontalCenter:parent.horizontalCenter; spacing:5
                Text {
                    text:sIcon; font.pixelSize:13; color:root.cText
                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked: iconTap() }
                }
                Text { text:sLabel; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cMuted }
            }
            DotBar { fill:Math.min(1,Math.max(0,sFill)); dotColor:sColor; anchors.horizontalCenter:parent.horizontalCenter }
        }
        MouseArea {
            anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.SizeVerCursor; acceptedButtons:Qt.NoButton
            onEntered: _h=true; onExited: _h=false
            onWheel: function(w){ scroll(w.angleDelta.y/120) }
        }
    }

    component PLabel: Text {
        font.pixelSize:9; font.family:"Share Tech Mono"; font.letterSpacing:3; color:root.cPink
    }
    component IRow: Item {
        property string il:""; property string iv:""; property color ivc:root.cText
        width:300; height:20
        Text { text:il; width:72; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cMuted }
        Text { anchors.left:parent.left; anchors.leftMargin:78; text:iv; font.pixelSize:10; font.family:"Share Tech Mono"; color:ivc }
    }
    component PBtn: Item {
        property string bLabel:""; property color bColor:root.cPink
        signal bClick
        property bool _h:false
        width:bT.implicitWidth+18; height:22

        Rectangle {
            anchors.fill:parent; radius:root.rad
            color:_h?Qt.rgba(bColor.r,bColor.g,bColor.b,0.15):"transparent"
            border.color:bColor; border.width:1
            Behavior on color { ColorAnimation { duration:100 } }
        }
        Text { id:bT; anchors.centerIn:parent; text:bLabel; font.pixelSize:8; font.family:"Share Tech Mono"; font.letterSpacing:2; color:bColor }
        MouseArea {
            anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
            onEntered: _h=true; onExited: _h=false; onClicked: bClick()
        }
    }

    component ProcPanel: Item {
        property string ppTitle:""; property color ppColor:root.cPink
        property var    ppProcs:[]; property bool ppMem:false
        signal kill(string pid); signal refresh

        Column {
            anchors.fill:parent; spacing:8
            Row {
                spacing:8
                Text { text:ppTitle; font.pixelSize:10; font.family:"Share Tech Mono"; font.letterSpacing:2; color:ppColor; anchors.verticalCenter:parent.verticalCenter }
                Item {
                    width:22; height:18; anchors.verticalCenter:parent.verticalCenter
                    Rectangle {
                        anchors.fill:parent; radius:root.rad
                        color:rh.containsMouse?root.cSurf:"transparent"
                        border.color:root.cBorder; border.width:1
                        Text { anchors.centerIn:parent; text:"↻"; font.pixelSize:12; color:root.cMuted }
                    }
                    MouseArea { id:rh; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked: refresh() }
                }
            }
            Row {
                spacing:0
                Text { width:ppMem?200:256; text:"PROCESS"; font.pixelSize:8; font.family:"Share Tech Mono"; font.letterSpacing:2; color:root.cDim }
                Text { width:58; text:ppMem?"VRAM":"CPU%"; font.pixelSize:8; font.family:"Share Tech Mono"; font.letterSpacing:2; color:root.cDim }
                Text { width:40; text:"PID"; font.pixelSize:8; font.family:"Share Tech Mono"; font.letterSpacing:2; color:root.cDim }
            }
            Rectangle { width:parent.width; height:1; color:root.cBorder }
            Repeater {
                model:ppProcs
                Item {
                    width:parent?parent.width:0; height:24
                    property bool _h:false
                    Rectangle { anchors.fill:parent; radius:root.rad; color:_h?root.cSurf:"transparent"; Behavior on color{ColorAnimation{duration:80}} }
                    Row {
                        anchors.verticalCenter:parent.verticalCenter; anchors.left:parent.left; anchors.leftMargin:4; spacing:0
                        Text { width:ppMem?200:256; text:modelData.name; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cText; elide:Text.ElideRight }
                        Text { width:58; text:ppMem?modelData.mem:modelData.pct+"%"; font.pixelSize:10; font.family:"Share Tech Mono"; color:ppMem?root.cMuted:(parseFloat(modelData.pct)>50?root.cRed:root.cMuted) }
                        Text { width:38; text:modelData.pid; font.pixelSize:9; font.family:"Share Tech Mono"; color:root.cDim }
                        Item {
                            width:22; height:16; anchors.verticalCenter:parent.verticalCenter
                            Rectangle {
                                anchors.fill:parent; radius:root.rad
                                color:kh.containsMouse?Qt.rgba(0.8,0.1,0.2,0.15):"transparent"
                                border.color:Qt.rgba(0.8,0.1,0.2,0.5); border.width:1
                                Text { anchors.centerIn:parent; text:"✕"; font.pixelSize:9; color:root.cRed }
                            }
                            MouseArea { id:kh; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked: kill(modelData.pid) }
                        }
                    }
                    MouseArea { anchors.fill:parent; hoverEnabled:true; acceptedButtons:Qt.NoButton; onEntered:_h=true; onExited:_h=false }
                }
            }
            Text { visible:ppProcs.length===0; text:"no processes"; font.pixelSize:10; font.family:"Share Tech Mono"; color:root.cDim }
        }
    }
}
