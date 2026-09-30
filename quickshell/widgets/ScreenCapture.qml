import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../components"
import "../settings"
import "../theme"

Item {
    id: root

    // ── Dimensions (match Menu) ───────────────────────────────────────
    readonly property int lw: 780
    readonly property int lh: 540
    property real   screenW:     1920
    property real   screenH:     1080
    property string screenName:  ""     // Wayland output name, e.g. "DP-1" — for monitor-limited grim
    property var    shellScreen: null   // ShellScreen — the frame the glass panes refract
    readonly property real hostX: (screenW - lw) / 2

    // ── Palette (match Menu) ──────────────────────────────────────────
    readonly property color paper:     Theme.paper
    readonly property color ink:       Theme.ink
    readonly property color inkStrong: Theme.inkStrong
    readonly property color inkSoft:   Theme.inkSoft
    readonly property color lineSoft:  Theme.alpha(Theme.ink, 0.25)
    readonly property color lineVsoft: Theme.alpha(Theme.ink, 0.12)
    readonly property color accent:    Theme.accent
    readonly property color light:     Theme.light   // glints / flashes (same as Emblem glow)
    function paperA(a) { return Theme.alpha(Theme.paper, a) }
    function inkA(a)   { return Theme.alpha(Theme.ink, a) }

    // ── State ─────────────────────────────────────────────────────────
    property bool   panelOpen:        false
    property bool   wipeHideRunning:  false
    // shell.qml maps the PanelWindow only while this is true, so a closed panel
    // holds no full-screen buffers.
    readonly property bool mapped: panelOpen || wipeHideRunning || warming
    // Warm-up: shortly after start the window maps once, invisibly and
    // click-through, so shaders and glyph caches exist before the first real open
    // (otherwise that open drops ~3 frames building them).
    property bool   warming: false
    // closed → arming → open → closing → closed.
    // "arming": mapped but fully transparent while the backdrop frame and the
    // freeze frame are captured (~30 ms) — an empty surface adds nothing to them.
    property string phase:            "closed"
    readonly property bool shown:     phase === "open" || phase === "closing" || phase === "selecting"
    readonly property string defaultCat: "copy"   // page selected every time the panel opens
    property string currentCat:       defaultCat
    property int    focusIdx:         0
    property bool   showRecOpts:      false
    property string recMode:          "full"
    property bool   recording:        false
    property bool   recMic:           false
    property bool   recAudio:         true
    property string recFmt:           "mp4"
    property bool   wfAvail:          false
    property string clockStr:         "--:--:--"
    property string _pendingCmd: ""
    property bool   freeze:      Settings.captureFreeze   // F toggles it for this session
    property bool   _freezeOk:   false
    property bool   _freezeDone: false
    property bool   _keepFreeze: false   // a region selection will still read the freeze frame
    property bool   _busy:       false   // confirm flourish playing; ignore input
    readonly property string freezeFile: "/tmp/qs-freeze-" + screenName + ".ppm"

    // ── Region selection ──────────────────────────────────────────────
    // Runs in this same window: the panel steps aside and the glass backdrop
    // becomes the selection layer, so nothing has to start up (phase "selecting").
    property string _selCmd:       ""      // command whose NIER_GEOM / NIER_CROP gets filled in
    property bool   _selFrozen:    false   // crop the freeze frame now (else grab live after closing)
    property bool   _liveBackdrop: false   // live selection: panes over the live screen, not the frame
    property string _runAfterClose: ""
    property bool   selDrag:    false
    property bool   hasSel:     false
    property real   selX1: 0
    property real   selY1: 0
    property real   selX2: 0
    property real   selY2: 0
    property real   curX: -1               // pointer, logical px (-1 = not seen yet)
    property real   curY: -1
    property real   selConfirm: 0          // 0 → 1 confirm flourish
    property string pickHex:    ""         // colour under the pointer, from the freeze frame
    property bool   _probeBusy: false
    property string _probeWant: ""
    readonly property rect selRect: Qt.rect(Math.min(selX1, selX2), Math.min(selY1, selY2),
                                            Math.abs(selX2 - selX1), Math.abs(selY2 - selY1))
    // The selection eased by ~0.16 s: the triangles fold after it, so dragging reads as
    // motion. _foldSnap skips the ease on a new press (no sweep from the old spot).
    property bool _foldSnap: false
    property real foldX: selRect.x
    property real foldY: selRect.y
    property real foldW: selRect.width
    property real foldH: selRect.height
    Behavior on foldX { enabled: !root._foldSnap; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on foldY { enabled: !root._foldSnap; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on foldW { enabled: !root._foldSnap; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on foldH { enabled: !root._foldSnap; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    // logical → physical px of this monitor (QT_SCALE_FACTOR); exact from the captured frame
    readonly property real dpr: backdrop.hasFrame && width > 0 ? backdrop.frameSize.width / width : Screen.devicePixelRatio
    function phys(v) { return Math.round(v * root.dpr) }
    function ratioLabel(w, h) {
        if (w <= 0 || h <= 0) return ""
        var r = w / h
        var common = [[1,1],[4,3],[3,2],[16,10],[16,9],[21,9],[3,4],[2,3],[10,16],[9,16]]
        for (var i = 0; i < common.length; i++)
            if (Math.abs(r - common[i][0] / common[i][1]) / r < 0.01) return common[i][0] + ":" + common[i][1]
        return r >= 1 ? r.toFixed(2) + " : 1" : "1 : " + (1 / r).toFixed(2)
    }
    // point on the selection's perimeter, `u` px clockwise from the top-left corner
    function perim(u, w, h) {
        var P = 2 * (w + h)
        if (P <= 0) return Qt.point(0, 0)
        u = ((u % P) + P) % P
        if (u < w) return Qt.point(u, 0)
        u -= w; if (u < h) return Qt.point(w, u)
        u -= h; if (u < w) return Qt.point(w - u, h)
        u -= w; return Qt.point(0, h - u)
    }

    signal rowsEnter()

    implicitWidth:  screenW
    implicitHeight: screenH

    // ── Rhythm ────────────────────────────────────────────────────────
    // One clock drives the backdrop shader and every idle pulse, so they all
    // land on the same beat. Only runs while the panel is on screen.
    readonly property real bpm: 120
    property real t: 0
    NumberAnimation on t {
        running: root.shown
        from: 0; to: 100000; duration: 100000000; loops: Animation.Infinite
    }
    readonly property real beatPhase: (t * bpm / 60) % 1
    readonly property int  beatIndex: Math.floor(t * bpm / 60)
    readonly property real pulse:     Math.pow(1 - beatPhase, 3)   // sharp hit, soft decay

    property real flashV:    0   // confirm flash
    property real hitT:      0   // confirm hit-stop: the selector pops and holds

    // ── Open / close styles ───────────────────────────────────────────
    // Picked by shell.qml (Settings.captureOpenStyle, `qs ipc call capture style
    // <id>`); S inside the panel replays the next one for comparison.
    property string openStyle: "wipe"
    signal requestStyle(string id)
    readonly property var styles: [
        { id:"wipe",   label:"幕簾" },
        { id:"rise",   label:"浮現" },
        { id:"scan",   label:"掃描" },
        { id:"iris",   label:"鑽石光圈" },
        { id:"blinds", label:"百葉" }
    ]
    readonly property int styleIndex: Math.max(0, styles.findIndex(function(s){ return s.id === root.openStyle }))
    readonly property bool maskStyle: openStyle === "scan" || openStyle === "iris" || openStyle === "blinds"
    property real revealP:   1       // reveal mask progress (scan / iris / blinds)
    property real riseT:     1       // rise: 0 hidden → 1 shown
    property bool _masking:  false   // panel renders through the reveal mask
    property bool _replay:   false   // S: reopen with the next style after closing
    property bool _panelGone: true
    property bool _triGone:   true

    // ── Categories ────────────────────────────────────────────────────
    readonly property var cats: [
        { id:"copy",       label:"複製",   sub:"コピー"   },
        { id:"screenshot", label:"截圖",   sub:"スクショ" },
        { id:"record",     label:"錄影",   sub:"レコード" },
        { id:"ocr",        label:"OCR",    sub:"テキスト" },
        { id:"color",      label:"色彩",   sub:"カラー"   }
    ]
    readonly property int catIndex: Math.max(0, cats.findIndex(function(c){ return c.id === root.currentCat }))
    // Direction of the last category change: +1 = → / next / swipe left, -1 = ← / previous.
    // Every category transition moves this way, so the motion follows the gesture.
    property int    catDir:   1
    // What the action list shows. It trails currentCat by the swap-out, so the old
    // rows can leave (against catDir) before the new ones come in (from catDir).
    property string shownCat: defaultCat
    readonly property int shownIndex: Math.max(0, cats.findIndex(function(c){ return c.id === root.shownCat }))
    property real   listOut:  0      // 0..1 while the old rows leave
    onCurrentCatChanged: {
        if (!root.shown) { swapAnim.stop(); root.listOut = 0; root.shownCat = root.currentCat; return }
        swapAnim.restart()
    }

    // ── Save paths ────────────────────────────────────────────────────
    readonly property string shotDir:  "$HOME/Pictures/Screenshots"
    readonly property string videoDir: "~/Videos"
    readonly property string clipDir:  "/tmp/qs-shot"
    readonly property string ts:       "$(date +%Y%m%d-%H%M%S)"

    // ── Action definitions (key = number-key shortcut) ────────────────
    readonly property var actionMap: ({
        "copy": [
            { id:"region",   icon:"⊡", label:"區域複製",   desc:"拖曳選取範圍 → 剪貼簿",            key:"1" },
            { id:"screen",   icon:"□", label:"目前螢幕",   desc:"這個螢幕 → 剪貼簿",                key:"2" },
            { id:"all",      icon:"◫", label:"所有螢幕",   desc:"所有螢幕拼成一張 → 剪貼簿",        key:"3" },
            { id:"window",   icon:"▣", label:"視窗複製",   desc:"目前焦點視窗 → 剪貼簿",            key:"4" }
        ],
        "screenshot": [
            { id:"screen",   icon:"□", label:"目前螢幕",   desc:"這個螢幕 · 存檔",                  key:"1" },
            { id:"all",      icon:"◫", label:"所有螢幕",   desc:"所有螢幕拼成一張 · 存檔",          key:"2" },
            { id:"region",   icon:"⊡", label:"區域截圖",   desc:"拖曳選取範圍 · 存檔",              key:"3" },
            { id:"window",   icon:"▣", label:"視窗截圖",   desc:"目前焦點視窗 · 存檔",              key:"4" },
            { id:"annotate", icon:"✎", label:"區域標註",   desc:"選取範圍 → swappy 標註 · 關閉時存檔", key:"5" },
            { id:"delay",    icon:"◷", label:"延遲 3秒",   desc:"3 秒後截取所有螢幕 · 存檔",        key:"6" }
        ],
        "record": [
            { id:"full",   icon:"◉", label:"全螢幕錄影", desc:"錄製整個螢幕輸出", key:"1" },
            { id:"region", icon:"⊡", label:"區域錄影",   desc:"拖曳選取錄製範圍", key:"2" }
        ],
        "ocr": [
            { id:"region", icon:"⊡", label:"區域識別",    desc:"選取範圍 → 文字 → 剪貼簿", key:"1" },
            { id:"full",   icon:"□", label:"全螢幕識別",  desc:"全螢幕 → 文字 → 剪貼簿",  key:"2" },
            { id:"file",   icon:"≡", label:"儲存文字檔",  desc:"選取範圍識別結果存為 .txt", key:"3" }
        ],
        "color": [
            { id:"pick",   icon:"◈", label:"取色",     desc:"點選像素取得 HEX 色碼 · 複製", key:"1" },
            { id:"region", icon:"⊡", label:"平均色彩", desc:"選取範圍計算平均色 · 複製",    key:"2" }
        ]
    })

    // ── Commands ──────────────────────────────────────────────────────
    // grim -g argument for the focused window (shared by screenshot + copy)
    readonly property string winGeom: "\"$(hyprctl -j activewindow 2>/dev/null | python3 -c 'import sys,json; w=json.load(sys.stdin); print(\"{},{} {}x{}\".format(w[\"at\"][0],w[\"at\"][1],w[\"size\"][0],w[\"size\"][1]))' 2>/dev/null)\""
    readonly property string notifyScript: "\"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/scripts/shot-notify.sh\""

    // Shell snippet writing a PNG of the chosen area to stdout. A frozen region
    // is cut from the frame taken when the panel opened (NIER_CROP, filled in
    // by the region overlay); a live one is grabbed after the overlay is gone.
    function grab(kind) {
        switch (kind) {
            case "region": return (root.freeze && root._freezeOk)
                                  ? "magick " + root.freezeFile + " -crop NIER_CROP +repage png:-"
                                  : "grim -g \"NIER_GEOM\" -"
            case "screen": return "grim -o \"" + root.screenName + "\" -"
            case "all":    return "grim -"
            case "window": return "grim -g " + winGeom + " -"
        }
        return ""
    }
    // Whole-screen / window grabs wait for the panel to finish fading out.
    function settle(kind) { return kind === "region" ? "" : "sleep 0.3 && " }
    function notify(kind, file, msg) {
        return "setsid -f sh " + notifyScript + " " + kind + " \"" + file + "\" \"" + msg + "\""
    }

    function copyCmd(id) {
        var msg = ({ region:"區域已複製到剪貼簿", screen:"螢幕已複製到剪貼簿",
                     all:"所有螢幕已複製到剪貼簿", window:"視窗已複製到剪貼簿" })[id]
        if (!msg) return ""
        return settle(id) + "mkdir -p " + clipDir + " && c=" + clipDir + "/clip-$(date +%s%N).png && "
             + grab(id) + " > \"$c\" && wl-copy -t image/png < \"$c\" && " + notify("copied", "$c", msg)
    }

    function shotCmd(id) {
        var f = "mkdir -p " + shotDir + " && f=\"" + shotDir + "/cap-" + ts + ".png\" && "
        switch(id) {
            case "screen":
            case "all":
            case "region":
            case "window":
                return settle(id) + f + grab(id) + " > \"$f\" && " + notify("saved", "$f", "已儲存")
            case "annotate":
                // swappy writes the annotated result to $f when it closes
                return f + grab("region") + " | swappy -f - -o \"$f\"; " + notify("saved", "$f", "標註已儲存")
            case "delay":
                return f + "sleep 3 && grim \"$f\" && " + notify("saved", "$f", "已儲存")
        }
        return ""
    }

    function recCmd(mode) {
        var f   = videoDir + "/rec-" + ts + "." + root.recFmt
        var mk  = "mkdir -p " + videoDir + " && "
        var geo = mode === "region" ? "-g \"NIER_GEOM\" " : ""
        var audioFlag = root.recMic
            ? "--audio=$(pactl get-default-source 2>/dev/null) "
            : (root.recAudio ? "--audio " : "")
        return mk + "wf-recorder " + geo + audioFlag + "-f " + f
    }

    function ocrCmd(id) {
        var tmp  = "/tmp/ocr-cap-$$.png"
        var proc = "/tmp/ocr-pre-$$.png"
        // Full-screen: restrict to the active monitor so secondary monitors are excluded
        var grabTo = id === "full"
            ? (root.screenName !== "" ? "grim -o \"" + root.screenName + "\" " + tmp : "grim " + tmp)
            : grab("region") + " > " + tmp
        // Upscale 3× + grayscale + normalise before tesseract — large accuracy boost for screen text
        var pre  = "(magick " + tmp + " -resize 300% -colorspace Gray -normalize -sharpen 0x0.5 " + proc
                 + " 2>/dev/null || convert " + tmp + " -resize 300% -colorspace Gray -normalize -sharpen 0x0.5 " + proc
                 + " 2>/dev/null || cp " + tmp + " " + proc + ")"
        var lang = "$(tesseract --list-langs 2>/dev/null | grep -q chi_tra && echo '-l chi_tra+chi_sim+eng' || echo '')"
        var tess = "tesseract " + proc + " stdout " + lang + " --oem 3 --psm 11 --dpi 300 2>/dev/null"
        var done = "rm -f " + tmp + " " + proc
        if (id === "file") {
            var out = "~/Documents/ocr-" + ts
            return grabTo + " && " + pre + " && tesseract " + proc + " " + out + " " + lang + " --oem 3 --psm 11 --dpi 300 2>/dev/null && notify-send \"OCR\" \"文字已儲存\" -t 2000 ; " + done
        }
        return grabTo + " && " + pre + " && " + tess + " | wl-copy && notify-send \"OCR\" \"文字已複製到剪貼簿\" -t 2000 ; " + done
    }

    function colorCmd(id) {
        if (id === "pick") {
            return "hyprpicker -a && notify-send \"色彩\" \"HEX 已複製到剪貼簿\" -t 2000"
        }
        var tmp = "/tmp/color-avg-$$.png"
        return grab("region") + " > " + tmp +
               " && (convert " + tmp + " -resize 1x1\\! -format '#%[hex:u]' info: 2>/dev/null" +
               " || python3 -c \"from PIL import Image,ImageStat; img=Image.open('" + tmp + "').convert('RGB'); s=ImageStat.Stat(img); print('#{:02X}{:02X}{:02X}'.format(*[int(x) for x in s.mean[:3]]))\" 2>/dev/null" +
               " || echo unknown) | tr -d '\\n' | wl-copy && notify-send \"色彩\" \"平均 HEX 已複製\" -t 2000 && rm -f " + tmp
    }

    // ── Processes ─────────────────────────────────────────────────────
    Process { id: checkWfP; command:["sh","-c","which wf-recorder >/dev/null 2>&1 && echo 1 || echo 0"]; running:false
        stdout: StdioCollector { onStreamFinished: root.wfAvail = this.text.trim()==="1" }
    }
    Process { id: actionP; running:false }
    Process { id: recStopP; command:["sh","-c","pkill -SIGINT wf-recorder 2>/dev/null || true"]; running:false }
    Process {
        id: recCheckP; running:false
        command:["sh","-c","pgrep -x wf-recorder >/dev/null && echo 1 || echo 0"]
        stdout: StdioCollector { onStreamFinished: root.recording = this.text.trim()==="1" }
    }
    // Freeze frame: raw PPM (~30 ms, no PNG encode) of this monitor, taken while
    // the panel surface is still empty.
    Process {
        id: freezeP; running: false
        onExited: (code) => { root._freezeOk = code === 0; root._freezeDone = true; root._tryIntro() }
    }
    Process { id: cleanupP; running: false }

    // Colour under the pointer during region selection: one helper holds the freeze
    // frame in memory and answers "x y" → "#RRGGBB" (Qt's Canvas can't read pixels back).
    Process {
        id: pixelP; running: false; stdinEnabled: true
        command: ["sh", "-c", "exec python3 \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/scripts/pixel-probe.py\" \"$1\"",
                  "pixel-probe", root.freezeFile]
        stdout: SplitParser {
            onRead: (line) => {
                var p = line.split(" ")
                root._probeBusy = false
                if (p.length >= 3 && p[2] !== "-") root.pickHex = p[2]
                if (root._probeWant !== "" && p[0] + " " + p[1] !== root._probeWant) {
                    root._probeBusy = true; pixelP.write(root._probeWant + "\n")
                }
            }
        }
        onRunningChanged: if (!running) root._probeBusy = false
    }
    function _probe() {
        if (!pixelP.running || root.curX < 0) return
        root._probeWant = root.phys(root.curX) + " " + root.phys(root.curY)
        if (!root._probeBusy) { root._probeBusy = true; pixelP.write(root._probeWant + "\n") }
    }

    // Poll recording state every 2s — only while the panel is open, the only place
    // `recording` is shown (the REC dot / stop button). Checks immediately on open.
    Timer { interval:2000; running:root.panelOpen; repeat:true; triggeredOnStart:true; onTriggered: recCheckP.running=true }


    // Open anyway if a capture hangs: no frame → panes over the live screen,
    // no freeze file → region grabs stay live.
    Timer { id: armTimeout; interval: 350; onTriggered: root._startIntro() }

    Timer {
        interval: 2500; running: true
        onTriggered: if (!root.panelOpen) { root.warming = true; root.rowsEnter(); warmEnd.start() }
    }
    Timer { id: warmEnd; interval: 700; onTriggered: root.warming = false }

    function execute(cmd) {
        root._runAfterClose = cmd      // runs from _finishClose, once the window is unmapped
        root.closePanel()
    }

    function executeOrRegion(cmd) {
        if (cmd.indexOf("NIER_GEOM") !== -1 || cmd.indexOf("NIER_CROP") !== -1) {
            root.beginSelect(cmd)
        } else {
            root.execute(cmd)
        }
    }
    function _runPending() {
        if (root._pendingCmd === "") return
        actionP.running = false
        actionP.command = ["sh", "-c", root._pendingCmd]
        actionP.running = true
        root._pendingCmd = ""
    }
    // live region grabs run once the window is gone
    Timer { id: afterCloseT; interval: 120; onTriggered: root._runPending() }

    function startRecording(mode) {
        if (!root.wfAvail) return
        var cmd = "nohup " + root.recCmd(mode) + " >/dev/null 2>&1 &"
        root.executeOrRegion(cmd)
    }

    function stopRecording() {
        recStopP.running = false
        recStopP.running = true
        root.recording = false
    }

    // ── Clock ─────────────────────────────────────────────────────────
    // Only ticks while open.
    Timer {
        interval:1000; running:root.panelOpen; repeat:true; triggeredOnStart:true
        onTriggered: {
            var d=new Date()
            root.clockStr=String(d.getHours()).padStart(2,"0")+":"+String(d.getMinutes()).padStart(2,"0")+":"+String(d.getSeconds()).padStart(2,"0")
        }
    }

    Component.onCompleted: checkWfP.running = true

    // ── Backdrop: the shared glass triangles (components/GlassBackdrop.qml) ──
    GlassBackdrop {
        id: backdrop
        anchors.fill: parent
        z: 0
        screen:    root.shellScreen
        capturing: root.panelOpen || root.wipeHideRunning      // kept through the close cross-fade
        active:    root.phase === "open" || root.phase === "selecting"
        warm:      root.warming
        live:      root._liveBackdrop
        glarePx:   Qt.point(root.screenW / 2, root.screenH / 2)
        selecting: root.hasSel
        selection: root.selRect
        foldRect:  Qt.rect(root.foldX, root.foldY, root.foldW, root.foldH)
        onFrameReady: root._tryIntro()
        onHidden: { root._triGone = true; root._maybeFinishClose() }
    }
    MouseArea { anchors.fill: parent; z: 1; enabled: root.panelOpen && root.phase === "open"; onClicked: root.closePanel() }
    // Confirm impact: rings + shards over the panel, a shock ring through the triangles
    HitBurst { id: burst; z: 3; backdrop: backdrop; spreadX: 1.5; spreadY: 0.7 }

    // ── Panel host ────────────────────────────────────────────────────
    Item {
        id: panelHost
        z: 2
        x: root.hostX; y: (root.screenH - root.lh) / 2
        width: root.lw; height: root.lh; clip: true
        visible: (root.shown && !root._panelGone) || root.warming
        opacity: root.warming && !root.shown ? 0.004 : (root.openStyle === "rise" ? root.riseT : 1)
        transform: [
            Scale {
                origin.x: root.lw / 2; origin.y: root.lh / 2
                xScale: root.openStyle === "rise" ? 0.965 + 0.035 * root.riseT : 1
                yScale: xScale
            },
            Translate { y: root.openStyle === "rise" ? (1 - root.riseT) * 22 : 0 }
        ]
        layer.enabled: root._masking || (root.warming && root.maskStyle)
        layer.effect: ShaderEffect {
            property real  progress: root.revealP
            property real  mode:     root.openStyle === "iris" ? 0 : (root.openStyle === "scan" ? 1 : 2)
            property size  dims:     Qt.size(root.lw, root.lh)
            property color edge:     Theme.alpha(Theme.light, 0.75)
            fragmentShader: "../components/shaders/reveal.frag.qsb?v=2"   // bump ?v= after recompiling (see TriField.qml)
        }

        Rectangle {
            id: panelContent
            anchors.fill: parent; color: root.paper
            border.color: root.ink; border.width: 1

            // Fine grid
            Repeater { model: Math.floor(root.lw/20)+1
                Rectangle { x: index*20; y: 0; width: 1; height: root.lh; color: root.lineVsoft } }
            Repeater { model: Math.floor(root.lh/20)+1
                Rectangle { x: 0; y: index*20; width: root.lw; height: 1; color: root.lineVsoft } }

            // Glass rim: a light edge along the top, and cut-diamond corners
            Rectangle {
                x: 1; y: 1; width: parent.width - 2; height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.35 + 0.05 * Math.sin(root.t * 0.8); color: Theme.alpha(Theme.light, 0.9) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Repeater {
                model: 4
                Rectangle {
                    width: 7; height: 7; rotation: 45
                    x: (index % 2 === 0 ? 0 : root.lw) - 3.5
                    y: (index < 2 ? 0 : root.lh) - 3.5
                    color: root.ink
                }
            }

            // ── Keyboard focus catcher ───────────────────────────────
            TextInput {
                id: keyInput
                width:0; height:0; visible:false; focus:true
                Keys.onEscapePressed: {
                    if (root.showRecOpts) root.showRecOpts=false
                    else root.closePanel()
                }
                Keys.onUpPressed: {
                    if (root._busy) return
                    root.focusIdx=Math.max(0,root.focusIdx-1)
                }
                Keys.onDownPressed: {
                    if (root._busy) return
                    var max=(root.actionMap[root.currentCat]||[]).length-1
                    root.focusIdx=Math.min(max,root.focusIdx+1)
                }
                Keys.onLeftPressed:  root.stepCat(-1)
                Keys.onRightPressed: root.stepCat(1)
                Keys.onReturnPressed: {
                    var acts=root.actionMap[root.currentCat]||[]
                    if(acts[root.focusIdx]) root.fire(root.currentCat,acts[root.focusIdx].id)
                }
                // 1–9 fire that row directly; F toggles the freeze frame.
                Keys.onPressed: (event) => {
                    if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        var acts = root.actionMap[root.currentCat] || []
                        var n = event.key - Qt.Key_1
                        if (acts[n] && !root.showRecOpts) { root.focusIdx = n; root.fire(root.currentCat, acts[n].id) }
                        event.accepted = true
                    } else if (event.key === Qt.Key_F) {
                        root.freeze = !root.freeze
                        event.accepted = true
                    } else if (event.key === Qt.Key_S) {
                        root.replayNextStyle()
                        event.accepted = true
                    }
                }
            }
            Timer {
                id:focusTimer; interval:50; repeat:true; running:false
                property int attempts:0
                onTriggered: {
                    keyInput.forceActiveFocus()
                    attempts++
                    if(attempts>=8){ running=false; attempts=0 }
                }
            }

            // Scan line
            Rectangle {
                id:scanLine; x:0; width:root.lw; height:2; z:20; opacity:0
                gradient: Gradient {
                    orientation:Gradient.Horizontal
                    GradientStop { position:0.0; color:"transparent" }
                    GradientStop { position:0.5; color:root.accent }
                    GradientStop { position:1.0; color:"transparent" }
                }
                NumberAnimation on y {
                    id:scanAnim; from:0; to:root.lh; duration:700; running:false
                    easing.type:Easing.Linear
                    onStarted:  scanLine.opacity=1
                    onFinished: scanLine.opacity=0
                }
            }

            // ── HEADER ───────────────────────────────────────────────
            Item {
                id:header; width:parent.width; height:52
                Row {
                    anchors { left:parent.left; leftMargin:28; verticalCenter:parent.verticalCenter }
                    spacing:14
                    Text { text:"CAPTURE"; font.pixelSize:11; font.letterSpacing:3.5; font.weight:Font.Medium; color:root.inkStrong }
                    Rectangle { width:24; height:1; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                    Text { text:"スクリーン撮影"; font.pixelSize:10; font.letterSpacing:2; color:root.inkSoft }
                }
                Row {
                    anchors { right:parent.right; rightMargin:28; verticalCenter:parent.verticalCenter }
                    spacing:16
                    // Recording indicator
                    Row {
                        spacing:6; visible:root.recording; anchors.verticalCenter:parent.verticalCenter
                        Rectangle {
                            width:8; height:8; radius:4; color:root.accent
                            anchors.verticalCenter:parent.verticalCenter
                            SequentialAnimation on opacity {
                                running:root.recording && root.shown; loops:Animation.Infinite
                                NumberAnimation { to:0.15; duration:500 }
                                NumberAnimation { to:1.0;  duration:500 }
                            }
                        }
                        Text { text:"REC"; font.pixelSize:9; font.letterSpacing:2; color:root.accent; anchors.verticalCenter:parent.verticalCenter }
                    }
                    // Metronome: the beat everything else pulses on
                    Item {
                        width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            anchors.centerIn: parent; width: 7; height: 7; rotation: 45
                            color: root.accent; scale: 1 + 0.45 * root.pulse
                        }
                        Rectangle {
                            anchors.centerIn: parent; width: 7; height: 7; rotation: 45
                            color: "transparent"; border.color: root.accent; border.width: 1
                            scale: 1 + 1.4 * root.beatPhase; opacity: (1 - root.beatPhase) * 0.7
                        }
                    }
                    Text { text:root.clockStr; font.pixelSize:9; font.letterSpacing:1.5; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                }
                Rectangle { anchors.bottom:parent.bottom; width:parent.width; height:1; color:root.lineSoft }
            }

            // ── BODY ─────────────────────────────────────────────────
            Item {
                id:body
                anchors { top:header.bottom; bottom:footer.top }
                width:parent.width

                // Sidebar
                Item {
                    id:sidebar; width:160; height:parent.height
                    Rectangle { anchors.right:parent.right; width:1; height:parent.height; color:root.lineSoft }

                    Column {
                        y: 16; width: 160
                        Repeater {
                            model: root.cats
                            CatTab {
                                label:   modelData.label
                                sub:     modelData.sub
                                active:  root.currentCat === modelData.id
                                dir:     root.catDir
                                animate: root.shown
                                pulse:   root.pulse
                                onClicked: root.setCat(modelData.id)
                            }
                        }
                    }
                }

                // Right panel
                Item {
                    id:rightPanel
                    anchors { left:sidebar.right; right:parent.right; top:parent.top; bottom:parent.bottom }
                    clip:true

                    // Category name as a large watermark; slides in on every switch
                    Text {
                        id: watermark
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 22; bottomMargin: -26 }
                        text: root.cats[root.shownIndex].label
                        font.pixelSize: 132; font.weight: Font.Bold; font.letterSpacing: 6
                        color: root.inkA(0.075)
                        property real slide: 0
                        opacity: 1 - root.listOut
                        transform: Translate { x: watermark.slide - root.listOut * 60 * root.catDir }
                        NumberAnimation {
                            id: wmAnim; target: watermark; property: "slide"
                            from: 90 * root.catDir; to: 0; duration: 620; easing.type: Easing.OutQuart
                        }
                    }

                    // Action list (levels 1+2)
                    Item {
                        id: listArea
                        anchors { fill: parent; topMargin: 14; bottomMargin: 8 }
                        visible: !(root.shownCat==="record" && root.showRecOpts)
                        readonly property int rowH: 58
                        readonly property var acts: root.actionMap[root.shownCat] || []

                        // Afterimages: slower springs trail the selector while it moves
                        Rectangle {
                            width: parent.width; height: listArea.rowH; color: root.ink; opacity: 0.10
                            visible: listArea.acts.length > 0
                            y: selector.targetY
                            Behavior on y { SpringAnimation { spring: 2.2; damping: 0.36; epsilon: 0.3 } }
                        }
                        Rectangle {
                            width: parent.width; height: listArea.rowH; color: root.ink; opacity: 0.22
                            visible: listArea.acts.length > 0
                            y: selector.targetY
                            Behavior on y { SpringAnimation { spring: 3.4; damping: 0.34; epsilon: 0.3 } }
                        }

                        // Shared selector
                        Item {
                            id: selector
                            readonly property real targetY: root.focusIdx * listArea.rowH
                            width: parent.width; height: listArea.rowH
                            visible: listArea.acts.length > 0
                            y: targetY
                            Behavior on y { SpringAnimation { spring: 5.5; damping: 0.30; epsilon: 0.25 } }
                            scale: 1 + 0.05 * root.hitT

                            Rectangle { anchors.fill: parent; color: root.ink }
                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                width: 2 + 4 * root.pulse; color: root.accent
                            }
                            // Light sheen: on every move, and every 8 beats while idle
                            Item {
                                anchors.fill: parent; clip: true
                                Rectangle {
                                    id: sheen
                                    width: 80; height: parent.height * 2; y: -parent.height / 2
                                    rotation: 18; x: -140
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: "transparent" }
                                        GradientStop { position: 0.5; color: Theme.alpha(Theme.light, 0.26) }
                                        GradientStop { position: 1.0; color: "transparent" }
                                    }
                                }
                                NumberAnimation {
                                    id: sheenAnim; target: sheen; property: "x"
                                    from: -140; to: selector.width + 60; duration: 640; easing.type: Easing.OutCubic
                                }
                            }
                            // Confirm flash
                            Rectangle { anchors.fill: parent; color: root.light; opacity: root.flashV * 0.4 }
                        }
                        // where the confirm burst comes from: the focused row's diamond icon
                        // (its target row, not the spring — number keys fire before it lands)
                        Item { id: burstAnchor; x: 34 + 22 + 16 + 15; y: selector.targetY + listArea.rowH / 2 }
                        Connections {
                            target: root
                            function onFocusIdxChanged() { sheenAnim.restart() }
                            function onBeatIndexChanged() { if (root.beatIndex > 0 && root.beatIndex % 8 === 0) sheenAnim.restart() }
                            function onShownCatChanged() { wmAnim.restart() }
                            function onRowsEnter() { wmAnim.restart() }
                        }

                        Column {
                            width: parent.width
                            Repeater {
                                model: listArea.acts
                                delegate: Item {
                                    id: row
                                    required property var modelData
                                    required property int index
                                    readonly property var  act: modelData
                                    readonly property bool focused: index === root.focusIdx
                                    width: listArea.width; height: listArea.rowH
                                    scale: row.focused ? 1 + 0.05 * root.hitT : 1

                                    // Staggered entrance, like a song list sliding in
                                    property real enter: 0
                                    opacity: enter * (1 - root.listOut)
                                    // in from the gesture side, out toward the other
                                    transform: Translate { x: ((1 - row.enter) * 56 - root.listOut * 44) * root.catDir }
                                    SequentialAnimation {
                                        id: enterAnim
                                        PropertyAction { target: row; property: "enter"; value: 0 }
                                        PauseAnimation { duration: 30 + row.index * 45 }
                                        NumberAnimation { target: row; property: "enter"; to: 1; duration: 380; easing.type: Easing.OutCubic }
                                    }
                                    Component.onCompleted: if (root.shown) enterAnim.start()
                                    Connections { target: root; function onRowsEnter() { enterAnim.restart() } }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        visible: row.index < listArea.acts.length - 1
                                        x: 24; width: parent.width - 48; height: 1; color: root.lineSoft; opacity: 0.5
                                    }

                                    Row {
                                        anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                                  leftMargin: row.focused ? 34 : 24 }
                                        spacing: 16
                                        Behavior on anchors.leftMargin { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }

                                        // Number key
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 22; horizontalAlignment: Text.AlignHCenter
                                            text: row.act.key
                                            font.pixelSize: 15; font.weight: Font.Medium
                                            color: row.focused ? root.paperA(0.75) : root.inkSoft
                                            Behavior on color { ColorAnimation { duration: 120 } }
                                        }
                                        // Icon: a square that turns into a diamond when selected
                                        Item {
                                            width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {   // beat ripple
                                                anchors.centerIn: parent; width: 22; height: 22; rotation: 45
                                                color: "transparent"; border.color: root.light; border.width: 1
                                                visible: row.focused
                                                scale: 1 + 0.9 * root.beatPhase
                                                opacity: (1 - root.beatPhase) * 0.55
                                            }
                                            Rectangle {
                                                anchors.centerIn: parent; width: 26; height: 26
                                                rotation: row.focused ? 45 : 0
                                                scale: row.focused ? 0.86 + 0.06 * root.pulse : 1
                                                color: row.focused ? root.paperA(0.08) : "transparent"
                                                border.width: 1
                                                border.color: row.focused ? root.paperA(0.85) : root.ink
                                                Behavior on rotation { NumberAnimation { duration: 340; easing.type: Easing.OutBack } }
                                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                            }
                                            Text {
                                                anchors.centerIn: parent; text: row.act.icon; font.pixelSize: 13
                                                color: row.focused ? root.paperA(0.95) : root.ink
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                            Text {
                                                text: row.act.label; font.pixelSize: 12; font.letterSpacing: 1.2; font.weight: Font.Medium
                                                color: row.focused ? root.paper : root.ink
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                            Text {
                                                text: row.act.desc; font.pixelSize: 9; font.letterSpacing: 0.8
                                                color: row.focused ? root.paperA(0.55) : root.inkSoft
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }
                                    }
                                    Text {
                                        anchors { right: parent.right; rightMargin: 26 - 4 * root.pulse * (row.focused ? 1 : 0)
                                                  verticalCenter: parent.verticalCenter }
                                        text: "▸"; font.pixelSize: 14; color: root.light
                                        opacity: row.focused ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                    }

                                    MouseArea {
                                        anchors.fill: parent; hoverEnabled: true
                                        onEntered: if (!root._busy) root.focusIdx = row.index
                                        onClicked: { root.focusIdx = row.index; root.fire(root.currentCat, row.act.id) }
                                    }
                                }
                            }
                        }

                        // wf-recorder not installed notice
                        Row {
                            visible: root.shownCat==="record" && !root.wfAvail
                            y: listArea.acts.length * listArea.rowH + 14
                            anchors { left: parent.left; leftMargin: 28 }
                            spacing: 10
                            Text { text:"⚠"; font.pixelSize:11; color:root.accent; anchors.verticalCenter:parent.verticalCenter }
                            Text { text:"請安裝 wf-recorder：  sudo pacman -S wf-recorder"
                                font.pixelSize:9; font.letterSpacing:1; color:root.inkSoft; anchors.verticalCenter:parent.verticalCenter }
                        }
                    }

                    // Recording options (level 3) — slides in from right
                    Item {
                        anchors.fill:parent
                        visible:root.currentCat==="record"&&root.showRecOpts
                        opacity: visible?1:0
                        Behavior on opacity { NumberAnimation { duration:160 } }

                        Column {
                            anchors { fill:parent; margins:24 }
                            spacing:0

                            // Back + title
                            Item {
                                width:parent.width; height:40
                                Row {
                                    anchors { left:parent.left; verticalCenter:parent.verticalCenter }
                                    spacing:8
                                    Text { text:"◂"; font.pixelSize:12; color:root.accent; anchors.verticalCenter:parent.verticalCenter }
                                    Text { text:"錄影選項"; font.pixelSize:11; font.letterSpacing:3; color:root.inkStrong; anchors.verticalCenter:parent.verticalCenter }
                                }
                                Text {
                                    anchors { right:parent.right; verticalCenter:parent.verticalCenter }
                                    text:root.recMode==="full"?"FULL SCREEN":"REGION"
                                    font.pixelSize:9; font.letterSpacing:2; color:root.inkSoft
                                }
                                MouseArea { anchors.fill:parent; onClicked:root.showRecOpts=false }
                            }
                            Rectangle { width:parent.width; height:1; color:root.lineSoft }
                            Item { width:1; height:18 }

                            // Mic toggle
                            TogRow {
                                width:parent.width; tLabel:"麥克風 MIC"; tSub:"錄製麥克風輸入"; tOn:root.recMic
                                onTap: root.recMic=!root.recMic
                            }
                            Item { width:1; height:6 }
                            Rectangle { width:parent.width; height:1; color:root.lineVsoft }
                            Item { width:1; height:6 }

                            // System audio toggle
                            TogRow {
                                width:parent.width; tLabel:"系統聲音 AUDIO"; tSub:"錄製系統音訊輸出"; tOn:root.recAudio
                                onTap: root.recAudio=!root.recAudio
                            }
                            Item { width:1; height:16 }
                            Rectangle { width:parent.width; height:1; color:root.lineVsoft }
                            Item { width:1; height:16 }

                            // Format selector
                            Text { text:"FORMAT · フォーマット"; font.pixelSize:9; font.letterSpacing:2.5; color:root.inkSoft }
                            Item { width:1; height:10 }
                            Row {
                                spacing:8
                                Repeater {
                                    model:["mp4","mkv","webm"]
                                    Item {
                                        width:72; height:30
                                        Rectangle {
                                            anchors.fill:parent; color:"transparent"
                                            border.color:root.recFmt===modelData?root.ink:root.lineSoft
                                            border.width:root.recFmt===modelData?2:1
                                            Behavior on border.color { ColorAnimation { duration:150 } }
                                        }
                                        Text {
                                            anchors.centerIn:parent; text:modelData.toUpperCase()
                                            font.pixelSize:10; font.letterSpacing:2
                                            color:root.recFmt===modelData?root.inkStrong:root.inkSoft
                                            Behavior on color { ColorAnimation { duration:150 } }
                                        }
                                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:root.recFmt=modelData }
                                    }
                                }
                            }

                            Item { width:1; height:22 }

                            // Start button
                            Rectangle {
                                width:180; height:40; color:root.ink
                                border.color:startMA.containsMouse?root.accent:root.ink; border.width:1
                                Behavior on border.color { ColorAnimation { duration:120 } }
                                Text {
                                    anchors.centerIn:parent; text:"▸  START  開始錄影"
                                    font.pixelSize:10; font.letterSpacing:2; color:root.paper
                                }
                                MouseArea {
                                    id:startMA; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                    onClicked: root.startRecording(root.recMode)
                                }
                                opacity: root.wfAvail?1:0.35
                            }
                        }
                    }
                }
            }

            // ── FOOTER ───────────────────────────────────────────────
            Item {
                id:footer; anchors.bottom:parent.bottom; width:parent.width; height:44
                Rectangle { anchors.top:parent.top; width:parent.width; height:1; color:root.lineSoft }

                Row {
                    anchors { left:parent.left; leftMargin:28; verticalCenter:parent.verticalCenter }
                    spacing: 14

                    // Stop recording button
                    Item {
                        width:root.recording?stopLbl.implicitWidth+24:0; height:24; clip:true
                        visible: width > 0.5
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on width { NumberAnimation { duration:200; easing.type:Easing.OutQuart } }
                        Rectangle {
                            anchors.fill: parent; color:"transparent"
                            border.color:root.accent; border.width:1
                            Text {
                                id:stopLbl; anchors.centerIn:parent; text:"■  停止錄影"
                                font.pixelSize:9; font.letterSpacing:2; color:root.accent
                            }
                            MouseArea { anchors.fill:parent; onClicked:root.stopRecording() }
                        }
                    }

                    // Freeze toggle (F)
                    Item {
                        width: fzRow.implicitWidth; height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: fzRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Rectangle {
                                width: fzKey.implicitWidth + 8; height: 16; color: "transparent"
                                border.color: root.lineSoft; border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: fzKey; anchors.centerIn: parent; text: "F"; font.pixelSize: 9; font.letterSpacing: 1; color: root.ink }
                            }
                            Rectangle {
                                width: 7; height: 7; rotation: 45; anchors.verticalCenter: parent.verticalCenter
                                color: root.freeze ? root.accent : "transparent"
                                border.color: root.freeze ? root.accent : root.inkSoft; border.width: 1
                                scale: root.freeze ? 1 + 0.3 * root.pulse : 1
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.freeze ? "凍結畫面 · 開" : "凍結畫面 · 關"
                                font.pixelSize: 9; font.letterSpacing: 2
                                color: root.freeze ? root.inkStrong : root.inkSoft
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.freeze = !root.freeze }
                    }

                    // Open/close style (S replays the next one)
                    Item {
                        width: stRow.implicitWidth; height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: stRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 7
                            Rectangle {
                                width: stKey.implicitWidth + 8; height: 16; color: "transparent"
                                border.color: root.lineSoft; border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: stKey; anchors.centerIn: parent; text: "S"; font.pixelSize: 9; font.letterSpacing: 1; color: root.ink }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "開場 · " + root.styles[root.styleIndex].label
                                font.pixelSize: 9; font.letterSpacing: 2; color: root.inkStrong
                            }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.replayNextStyle() }
                    }
                }

                Row {
                    anchors { right:parent.right; rightMargin:28; verticalCenter:parent.verticalCenter }
                    spacing:14
                    Repeater {
                        model:[["1–9","PICK"],["←→","CAT"],["↑↓","NAV"],["↵","EXEC"],["ESC","CLOSE"]]
                        Row {
                            spacing:5; anchors.verticalCenter:parent.verticalCenter
                            Rectangle {
                                width:kbdT.implicitWidth+8; height:16; color:"transparent"
                                border.color:root.lineSoft; border.width:1
                                Text { id:kbdT; anchors.centerIn:parent; text:modelData[0]; font.pixelSize:9; font.letterSpacing:1; color:root.ink }
                            }
                            Text { text:modelData[1]; anchors.verticalCenter:parent.verticalCenter; font.pixelSize:9; font.letterSpacing:2; color:root.inkSoft }
                        }
                    }
                }
            }

            // Two-finger horizontal swipe switches category, animated the same way as
            // ←/→. With natural scrolling, fingers moving left arrive as dx < 0 = next
            // (like →). Wheel only: clicks and hover still reach the rows below.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                property real acc: 0
                onWheel: (wheel) => {
                    var dx = wheel.pixelDelta.x !== 0 ? wheel.pixelDelta.x : wheel.angleDelta.x / 2
                    var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 2
                    if (Math.abs(dx) <= Math.abs(dy)) { wheel.accepted = false; return }
                    swipeIdle.restart()
                    if (swipeCool.running) return          // one swipe = one category
                    acc += dx
                    if (Math.abs(acc) >= 60) { root.stepCat(acc < 0 ? 1 : -1); acc = 0; swipeCool.restart() }
                }
                Timer { id: swipeIdle; interval: 180; onTriggered: parent.acc = 0 }
                Timer { id: swipeCool; interval: 320 }
            }
        }

        // Wipe curtain (identical to Menu)
        Rectangle {
            id:wipeCurtain
            anchors{top:parent.top;bottom:parent.bottom}
            color:Theme.sepia; z:50; width:root.lw; x:0
        }
    }

    // ── Region selection layer ────────────────────────────────────────
    Item {
        id: selLayer
        anchors.fill: parent
        z: 3
        opacity: root.phase === "selecting" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Esc cancels (the panel's key catcher hides with the panel)
        Item { id: selKeys; Keys.onEscapePressed: root.cancelSelect() }

        // hints (on ink plates: the backdrop can be light)
        Rectangle {
            x: 14; y: 14; width: hintTop.implicitWidth + 18; height: hintTop.implicitHeight + 12
            color: root.inkA(0.88); border.color: root.paperA(0.3); border.width: 1
        }
        Rectangle {
            x: 14; y: parent.height - height - 14; width: hintBot.implicitWidth + 18; height: hintBot.implicitHeight + 12
            color: root.inkA(0.88); border.color: root.paperA(0.3); border.width: 1
        }
        Row {
            id: hintTop
            anchors { top: parent.top; left: parent.left; margins: 22 }
            spacing: 12
            Text { text: "REGION SELECT · 區域選取"; font.pixelSize: 10; font.letterSpacing: 3; font.weight: Font.Medium; color: root.paper }
            Rectangle { width: 5; height: 5; rotation: 45; color: root._selFrozen ? root.accent : root.paper; anchors.verticalCenter: parent.verticalCenter }
            Text { text: root._selFrozen ? "凍結畫面" : "即時畫面"; font.pixelSize: 9; font.letterSpacing: 2; color: root.paperA(0.75); anchors.verticalCenter: parent.verticalCenter }
        }
        Row {
            id: hintBot
            anchors { bottom: parent.bottom; left: parent.left; margins: 22 }
            spacing: 18
            Repeater {
                model: [["DRAG", "選取"], ["右鍵 / ESC", "取消"]]
                Row {
                    spacing: 6
                    Rectangle {
                        width: hk.implicitWidth + 8; height: 16; color: "transparent"
                        border.color: root.paperA(0.4); border.width: 1
                        Text { id: hk; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 8; font.letterSpacing: 1; color: root.paper }
                    }
                    Text { text: modelData[1]; font.pixelSize: 9; font.letterSpacing: 2; color: root.paper; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }

        // crosshair
        Rectangle {
            visible: root.curX >= 0 && root.selConfirm === 0
            x: 0; y: Math.round(root.curY); width: parent.width; height: 1
            color: Theme.alpha(Theme.light, 0.45)
        }
        Rectangle {
            visible: root.curX >= 0 && root.selConfirm === 0
            x: Math.round(root.curX); y: 0; width: 1; height: parent.height
            color: Theme.alpha(Theme.light, 0.45)
        }

        // selection frame: hairline pair, travelling lights, corner diamonds
        Item {
            id: selFrame
            visible: root.hasSel
            x: root.selRect.x; y: root.selRect.y
            width: root.selRect.width; height: root.selRect.height
            Rectangle {
                anchors { fill: parent; margins: -1 }
                color: "transparent"; border.color: root.inkA(0.55); border.width: 1
            }
            Rectangle {
                anchors.fill: parent
                color: "transparent"; border.width: 1
                border.color: Theme.alpha(Theme.light, 0.85 + 0.15 * Math.sin(Math.PI * root.selConfirm))
            }
            Repeater {
                model: 2
                Item {
                    readonly property point pt: root.perim(root.t * 240 + index * (selFrame.width + selFrame.height),
                                                           selFrame.width, selFrame.height)
                    x: pt.x; y: pt.y
                    opacity: 1 - root.selConfirm
                    Rectangle { anchors.centerIn: parent; width: 12; height: 12; radius: 6; color: root.light; opacity: 0.3 }
                    Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: root.light }
                }
            }
            Repeater {
                model: 4
                Rectangle {
                    readonly property bool isRight:  index % 2 === 1
                    readonly property bool isBottom: index >= 2
                    width: 9; height: 9
                    x: (isRight ? selFrame.width : 0) - 4.5 + (isRight ? -1 : 1) * 10 * root.selConfirm
                    y: (isBottom ? selFrame.height : 0) - 4.5 + (isBottom ? -1 : 1) * 10 * root.selConfirm
                    rotation: 45 + 90 * root.selConfirm
                    scale: 1 - 0.6 * root.selConfirm
                    opacity: 1 - root.selConfirm * root.selConfirm
                    color: root.paper; border.color: root.ink; border.width: 1
                }
            }
        }

        // size tag: W × H · ratio · position (physical px)
        Rectangle {
            id: sizeTag
            visible: root.hasSel && root.selRect.width >= 1
            opacity: 1 - root.selConfirm
            width: tagRow.implicitWidth + 20; height: 26
            color: root.inkA(0.92); border.color: root.paperA(0.35); border.width: 1
            x: Math.max(8, Math.min(root.selRect.x, selLayer.width - width - 8))
            y: {
                var below = root.selRect.y + root.selRect.height + 10
                if (below + height <= selLayer.height - 8) return below
                var above = root.selRect.y - height - 10
                return above >= 8 ? above : root.selRect.y + 10
            }
            Row {
                id: tagRow
                anchors.centerIn: parent
                spacing: 9
                Rectangle { width: 5; height: 5; rotation: 45; color: root.light; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: root.phys(root.selRect.width) + " × " + root.phys(root.selRect.height)
                    font.pixelSize: 12; font.weight: Font.Medium; font.letterSpacing: 1; color: root.paper
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.ratioLabel(root.selRect.width, root.selRect.height)
                    font.pixelSize: 9; font.letterSpacing: 1; color: root.light
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "X " + root.phys(root.selRect.x) + "  Y " + root.phys(root.selRect.y)
                    font.pixelSize: 9; font.letterSpacing: 1; color: root.paperA(0.6)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // magnifier: 13×13 frozen pixels around the pointer + coordinates + colour
        Item {
            id: loupe
            readonly property int box: 130
            visible: root.curX >= 0 && root.selConfirm === 0 && backdrop.hasFrame
            width: box; height: box + 42
            x: root.curX + 28 + width > selLayer.width - 8 ? root.curX - 28 - width : root.curX + 28
            y: root.curY + 28 + height > selLayer.height - 8 ? root.curY - 28 - height : root.curY + 28
            Rectangle { anchors { fill: parent; margins: -2 } color: root.paperA(0.5) }
            Rectangle { anchors { fill: parent; margins: -1 } color: root.ink }
            ShaderEffect {
                width: loupe.box; height: loupe.box
                property var   source:  backdrop.frameTexture
                property size  texSize: backdrop.frameSize
                property point center:  Qt.point(root.curX * root.dpr, root.curY * root.dpr)
                property real  cells:   13
                property color gridCol: Theme.alpha(Theme.ink, 0.35)
                property color hiCol:   Theme.light
                fragmentShader: "../components/shaders/loupe.frag.qsb?v=1"   // bump ?v= after recompiling
            }
            Rectangle {
                y: loupe.box; width: loupe.box; height: 42; color: root.ink
                Column {
                    anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    Text {
                        text: "X " + root.phys(root.curX) + "   Y " + root.phys(root.curY)
                        font.pixelSize: 10; font.letterSpacing: 1; color: root.paper
                    }
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 10; height: 10; anchors.verticalCenter: parent.verticalCenter
                            color: root.pickHex !== "" ? root.pickHex : "transparent"
                            border.color: root.paperA(0.6); border.width: 1
                        }
                        Text { text: root.pickHex !== "" ? root.pickHex : "—"; font.pixelSize: 10; font.letterSpacing: 1; color: root.paper }
                    }
                }
            }
            Rectangle { x: -4; y: -4; width: 7; height: 7; rotation: 45; color: root.light }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.phase === "selecting" && root.selConfirm === 0
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.CrossCursor
            function clampX(v) { return Math.max(0, Math.min(v, width)) }
            function clampY(v) { return Math.max(0, Math.min(v, height)) }
            onPositionChanged: (m) => {
                root.curX = clampX(m.x); root.curY = clampY(m.y)
                if (root.selDrag) { root.selX2 = root.curX; root.selY2 = root.curY }
                root._probe()
            }
            onPressed: (m) => {
                if (m.button === Qt.RightButton) { root.cancelSelect(); return }
                root.curX = clampX(m.x); root.curY = clampY(m.y)
                root._foldSnap = true
                root.selX1 = root.selX2 = root.curX
                root.selY1 = root.selY2 = root.curY
                root.selDrag = true; root.hasSel = true
                Qt.callLater(function() { root._foldSnap = false })
            }
            onReleased: (m) => {
                if (m.button !== Qt.LeftButton || !root.selDrag) return
                root.selDrag = false
                root.selX2 = clampX(m.x); root.selY2 = clampY(m.y)
                if (root.selRect.width < 4 || root.selRect.height < 4) { root.hasSel = false; return }
                root.commitSel()
            }
        }
    }

    // ── Toggle row component ──────────────────────────────────────────
    component TogRow: Item {
        property string tLabel:""
        property string tSub:""
        property bool   tOn:false
        signal tap
        height:36

        Row {
            anchors { left:parent.left; right:parent.right; verticalCenter:parent.verticalCenter }
            Column {
                anchors.verticalCenter:parent.verticalCenter; spacing:2
                Text { text:tLabel; font.pixelSize:10; font.letterSpacing:1.5; color:root.inkStrong }
                Text { text:tSub;   font.pixelSize:8;  font.letterSpacing:1;   color:root.inkSoft }
            }
            Item { width:parent.width-180; height:1 }
            Item {
                anchors.verticalCenter:parent.verticalCenter; width:44; height:22
                Rectangle {
                    anchors.fill:parent; radius:11
                    color:tOn?root.ink:Theme.alpha(Theme.ink, 0.15)
                    border.color:tOn?root.ink:root.lineSoft; border.width:1
                    Behavior on color { ColorAnimation { duration:150 } }
                    Rectangle {
                        x:tOn?24:2; y:2; width:18; height:18; radius:9
                        color:tOn?root.paper:root.inkSoft
                        Behavior on x     { NumberAnimation { duration:150; easing.type:Easing.OutQuart } }
                        Behavior on color { ColorAnimation { duration:150 } }
                    }
                }
                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:tap() }
            }
        }
    }

    // ── Rise: fade up from slightly below ─────────────────────────────
    SequentialAnimation {
        id: riseIn
        ScriptAction { script: root.riseT = 0 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "riseT"; to: 1; duration: 440; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: 110 }
                ScriptAction { script: root.rowsEnter() }
            }
        }
        ScriptAction { script: scanAnim.start() }
    }
    NumberAnimation {
        id: riseOut; target: root; property: "riseT"; to: 0; duration: 240; easing.type: Easing.InCubic
        onFinished: root._panelClosed()
    }

    // ── Scan / iris / blinds: reveal mask ─────────────────────────────
    SequentialAnimation {
        id: maskIn
        ScriptAction { script: { root.revealP = 0; root._masking = true } }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "revealP"; to: 1
                duration: root.openStyle === "scan" ? 600 : 520
                easing.type: root.openStyle === "scan" ? Easing.InOutCubic : Easing.OutQuart
            }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                ScriptAction { script: root.rowsEnter() }
            }
        }
        ScriptAction { script: { root._masking = false; scanAnim.start() } }
    }
    SequentialAnimation {
        id: maskOut
        ScriptAction { script: root._masking = true }
        NumberAnimation {
            target: root; property: "revealP"; to: 0
            duration: root.openStyle === "scan" ? 380 : 300
            easing.type: root.openStyle === "scan" ? Easing.InOutCubic : Easing.InCubic
        }
        ScriptAction { script: root._panelClosed() }
    }

    // ── Wipe animations (identical to Menu) ──────────────────────────
    SequentialAnimation {
        id:wipeReveal
        ScriptAction { script: {
            panelHost.x = root.hostX + root.lw + 2
            wipeCurtain.x = 0; wipeCurtain.width = root.lw
        } }
        NumberAnimation { target:panelHost; property:"x"
            from:root.hostX+root.lw+2; to:root.hostX
            duration:440; easing.type:Easing.OutExpo }
        ScriptAction { script: root.rowsEnter() }
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     from:0;       to:root.lw-2; duration:340; easing.type:Easing.OutExpo }
            NumberAnimation { target:wipeCurtain; property:"width"; from:root.lw; to:2;         duration:340; easing.type:Easing.OutExpo }
        }
        ScriptAction { script: { wipeCurtain.width = 0; scanAnim.start() } }
    }
    SequentialAnimation {
        id:wipeHide
        ParallelAnimation {
            NumberAnimation { target:wipeCurtain; property:"x";     from:root.lw-2; to:0;       duration:180; easing.type:Easing.InOutQuart }
            NumberAnimation { target:wipeCurtain; property:"width"; from:2;         to:root.lw; duration:180; easing.type:Easing.InOutQuart }
        }
        NumberAnimation { target:panelHost; property:"x"
            from:root.hostX; to:root.hostX+root.lw+2
            duration:340; easing.type:Easing.InExpo }
        onFinished: root._panelClosed()
    }

    // Confirm (as ControlCenter): hit-stop — the selector pops, flashes and holds for
    // a beat while the impact flies (HitBurst + a ring through the triangles) — then
    // the action runs while the burst finishes
    property string _fireCat: ""
    property string _fireId:  ""
    SequentialAnimation {
        id: confirmAnim
        ScriptAction { script: { root.flashV = 1; burst.playAt(burstAnchor, 0, 0, 1) } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "flashV"; to: 0; duration: 420; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 65 }
                ScriptAction { script: root.handleAction(root._fireCat, root._fireId) }
                NumberAnimation { target: root; property: "hitT"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }

    // ── Action handler ────────────────────────────────────────────────
    function fire(cat, id) {
        if (root._busy || root.phase !== "open") return
        if (cat === "record") { root.handleAction(cat, id); return }   // opens its options page
        root._busy = true
        root._fireCat = cat; root._fireId = id
        confirmAnim.restart()
    }

    function handleAction(cat, id) {
        if (cat==="copy") {
            root.executeOrRegion(root.copyCmd(id))
        } else if (cat==="screenshot") {
            root.executeOrRegion(root.shotCmd(id))
        } else if (cat==="record") {
            if (!root.wfAvail) return
            root.recMode=id; root.showRecOpts=true
        } else if (cat==="ocr") {
            root.executeOrRegion(root.ocrCmd(id))
        } else if (cat==="color") {
            root.executeOrRegion(root.colorCmd(id))
        }
    }

    SequentialAnimation {
        id: swapAnim
        NumberAnimation { target: root; property: "listOut"; to: 1; duration: 110; easing.type: Easing.InCubic }
        ScriptAction { script: { root.shownCat = root.currentCat; root.listOut = 0 } }
    }

    function setCat(id) {
        if (root._busy || id === root.currentCat) return
        var ni = root.cats.findIndex(function(c){ return c.id === id })
        root.catDir = ni > root.catIndex ? 1 : -1
        root.currentCat = id; root.focusIdx = 0; root.showRecOpts = false
    }
    function stepCat(d) {
        var i = root.catIndex + d
        if (i >= 0 && i < root.cats.length) root.setCat(root.cats[i].id)
    }

    // ── Region selection ──────────────────────────────────────────────
    function beginSelect(cmd) {
        root._selCmd = cmd
        root._selFrozen = cmd.indexOf("NIER_CROP") !== -1
        root._liveBackdrop = !root._selFrozen
        root.hasSel = false; root.selDrag = false; root.selConfirm = 0
        root.pickHex = ""; root._probeWant = ""
        root.phase = "selecting"
        wipeReveal.stop(); riseIn.stop(); maskIn.stop()
        if (!root._panelGone) {
            if (root.openStyle === "wipe") wipeHide.start()
            else if (root.openStyle === "rise") riseOut.start()
            else maskOut.start()
        }
        selKeys.forceActiveFocus()
        if (root._freezeOk) { pixelP.running = false; pixelP.running = true }
    }
    function commitSel() {
        var r  = root.selRect
        var lx = root.phys(r.x), ly = root.phys(r.y)
        var w  = root.phys(r.x + r.width) - lx, h = root.phys(r.y + r.height) - ly
        var hm = Hyprland.monitorFor(root.shellScreen)
        var sc = hm && hm.scale > 0 ? hm.scale : 1
        // NIER_CROP: inside this monitor's frame (physical px). NIER_GEOM: compositor layout.
        var crop = w + "x" + h + "+" + lx + "+" + ly
        var geom = ((hm ? hm.x : 0) + Math.round(lx / sc)) + "," + ((hm ? hm.y : 0) + Math.round(ly / sc))
                 + " " + Math.round(w / sc) + "x" + Math.round(h / sc)
        var cmd = root._selCmd.replace("NIER_GEOM", geom).replace("NIER_CROP", crop)
        // the impact comes from where the drag was released (else the region's centre)
        burst.play(root.curX >= 0 ? root.curX : r.x + r.width / 2,
                   root.curX >= 0 ? root.curY : r.y + r.height / 2, 0.8)
        if (root._selFrozen) {           // cut from the frame now, while the layer closes
            root._keepFreeze = true
            actionP.running = false
            actionP.command = ["sh", "-c", cmd + "; rm -f " + root.freezeFile]
            actionP.running = true
        } else {
            root._runAfterClose = cmd    // live: after the window is gone
        }
        selConfirmAnim.restart()
    }
    function cancelSelect() {
        root.hasSel = false; root.selDrag = false
        root.closePanel()
    }
    NumberAnimation {
        id: selConfirmAnim; target: root; property: "selConfirm"
        from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic
        onFinished: root.closePanel()
    }

    // ── Open / close ──────────────────────────────────────────────────
    function _tryIntro() {
        if (root.phase === "arming" && root._freezeDone && backdrop.hasFrame) root._startIntro()
    }
    function _startIntro() {
        if (root.phase !== "arming") return
        armTimeout.stop()
        // Triangles unfold from where the panel comes from: the right edge for
        // the wipe (like NierTriBg "right"), the centre for everything else.
        backdrop.originPx = root.openStyle === "wipe"
            ? Qt.point(root.screenW, root.screenH * (0.25 + 0.5 * Math.random()))
            : Qt.point(root.screenW / 2, root.screenH / 2)
        root._panelGone = false; root._triGone = false
        root.phase = "open"
        wipeHide.stop(); riseOut.stop(); maskOut.stop()
        panelHost.x = root.hostX
        if (root.openStyle === "wipe") {
            wipeReveal.start()
        } else {
            wipeCurtain.width = 0
            if (root.openStyle === "rise") riseIn.start()
            else maskIn.start()
        }
        focusTimer.attempts = 0; focusTimer.restart()
    }
    function _panelClosed() { root._panelGone = true; root._maybeFinishClose() }
    function _maybeFinishClose() {
        if (root.phase === "closing" && root._panelGone && root._triGone) root._finishClose()
    }
    function _finishClose() {
        root.wipeHideRunning = false
        root.phase = "closed"
        root._busy = false
        root._masking = false
        root.hasSel = false; root.selDrag = false; root.selConfirm = 0
        root._liveBackdrop = false; root.curX = -1; root.curY = -1
        if (root._runAfterClose !== "") {
            root._pendingCmd = root._runAfterClose
            root._runAfterClose = ""
            afterCloseT.restart()
        }
        if (!root._keepFreeze) { cleanupP.running = false; cleanupP.command = ["rm", "-f", root.freezeFile]; cleanupP.running = true }
        if (root._replay) {
            root._replay = false
            root.requestStyle(root.styles[(root.styleIndex + 1) % root.styles.length].id)
            Qt.callLater(root.openPanel)
        }
    }
    function replayNextStyle() {
        if (root.phase !== "open" || root._busy) return
        root._replay = true
        root.closePanel()
    }

    function openPanel() {
        if (panelOpen) return
        warming = false; warmEnd.stop()
        panelOpen = true
        phase = "arming"
        showRecOpts = false; focusIdx = 0; catDir = 1; currentCat = defaultCat
        _busy = false; _keepFreeze = false
        _freezeOk = false; _freezeDone = false
        hasSel = false; selDrag = false; selConfirm = 0; _liveBackdrop = false; _runAfterClose = ""
        freezeP.running = false
        freezeP.command = ["grim", "-o", root.screenName, "-t", "ppm", root.freezeFile]
        freezeP.running = true
        armTimeout.restart()
    }
    function closePanel() {
        if (!panelOpen) return
        if (phase === "arming") {          // nothing on screen yet
            panelOpen = false
            armTimeout.stop()
            _finishClose()
            return
        }
        // wipeHideRunning first: `mapped` must never read false mid-close, or the
        // window is destroyed and re-created for one frame (a visible flash + stall).
        var fromSel = phase === "selecting"   // the panel is already hidden / hiding
        wipeHideRunning = true
        panelOpen = false
        phase = "closing"
        pixelP.running = false
        selConfirmAnim.stop()
        if (!fromSel) {
            wipeReveal.stop(); riseIn.stop(); maskIn.stop()
            if (openStyle === "wipe") wipeHide.start()
            else if (openStyle === "rise") riseOut.start()
            else maskOut.start()
        }
    }
    function togglePanel() {
        if (panelOpen) closePanel(); else openPanel()
    }
}
