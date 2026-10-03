import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import "../components"
import "../services"
import "../settings"
import "../theme"

// Settings panel (SUPER+ALT+S, `qs ipc call settings toggle`): every feature switch and the
// main options, written back to config/shell.conf by scripts/conf-set.py (comments and
// layout kept; the shell reloads the file live). The first page is the shell's health
// (services/Health.qml): the helpers it depends on, with repair / rebuild.
// It is always part of the shell — no option turns it off — so it can always turn the
// rest back on. ←→ page · ↑↓ row · ↵/Space toggle or run · −/+ (or the wheel) adjust.
// ↵ on a choice or a slider opens it beside the panel (the card slides left, a second one
// slides in, as a game's inventory and its description): a choice lists every option with
// a preview (fonts drawn in themselves, a theme on the whole shell), typing filters; a
// slider takes ←→ (Shift ×5) live. ↵ keeps, Esc puts the old value back.
Popup {
    id: root

    readonly property int  lw: 900
    readonly property int  lh: 560
    readonly property real rowH: 52

    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggle() }
        // open straight onto one option's side panel: `settings edit general.theme`
        function edit(key: string): void { root.editKey(key) }
    }
    property string _editAt: ""
    function editKey(key) {
        for (var c in pages) {
            var rs = pages[c]
            for (var i = 0; i < rs.length; i++) if (rs[i].key === key) {
                _editAt = key
                if (!isOpen) { open(); return }
                _openEdit()
                return
            }
        }
    }
    function _openEdit() {
        var key = _editAt; _editAt = ""
        for (var c in pages) {
            var rs = pages[c]
            for (var i = 0; i < rs.length; i++) if (rs[i].key === key) {
                cat = c; focusIdx = i
                if (rs[i].type === "choice" || rs[i].type === "num") beginEdit(rs[i])
                return
            }
        }
    }
    burst.spreadX: 1.4
    burst.spreadY: 0.7

    FolderListModel { id: themeFiles; folder: "file://" + Config.dir + "/themes"; nameFilters: ["*.conf"]; showDirs: false }
    // font choices — only the installed faces (the current one is kept even when this qs
    // started before it was installed: fonts are read at startup)
    function installedFonts(want, key) {
        var have = Qt.fontFamilies()
        var out = want.filter(function(f) { return have.indexOf(f) >= 0 })
        var cur = Config.str(key, "")
        if (cur !== "" && out.indexOf(cur) < 0) out.unshift(cur)
        return out.length ? out : [Theme.mono]
    }
    readonly property var monoFonts: installedFonts(["Operator Mono", "GoMono Nerd Font Mono", "Maple Mono NF CN",
                                                     "Iosevka", "Fira Code", "Share Tech Mono"], "font.mono")
    readonly property var cjkFonts: installedFonts(["jf金萱那提2.0", "源雲明體丹", "Noto Sans CJK TC", "Noto Serif CJK TC"], "font.cjk")
    // display faces the Void can use
    readonly property var voidFonts: installedFonts(["Josefin Sans", "Jost", "League Spartan", "Raleway", "Outfit", "Urbanist", "Figtree",
                                                     "Novecento sans wide", "Michroma", "Bender", "Rajdhani", "BigNoodleTitling",
                                                     "Barlow Condensed", "D-DIN", "Cinzel", "Norse", Theme.mono], "font.void")
    // every installed face fontconfig counts as monospace / Traditional Chinese / Latin
    property var fontLists: ({ mono: [], cjk: [], void: [] })
    Process {
        id: fontScan
        running: true
        command: ["sh", "-c",
            "{ fc-list -f '%{family[0]}\\n' ':spacing=100'; fc-list -f '%{family[0]}\\n' ':spacing=90'; } | sort -u | sed 's/^/M\t/';" +
            "fc-list -f '%{family[0]}\\n' ':lang=zh-tw' | sort -u | sed 's/^/C\t/';" +
            "fc-list -f '%{family[0]}\\n' ':lang=en' | sort -u | sed 's/^/A\t/'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var have = {}, q = Qt.fontFamilies()
                for (var i = 0; i < q.length; i++) have[q[i]] = true
                var out = { mono: [], cjk: [], void: [] }
                var lines = text.split("\n")
                for (var j = 0; j < lines.length; j++) {
                    var t = lines[j].split("\t")
                    // icon and emoji faces aren't fonts to read in
                    if (t.length < 2 || !have[t[1]] || /Emoji|Symbols|SignWriting|Material|Awesome|Icons|Wingdings|Webdings/i.test(t[1])) continue
                    out[{ M: "mono", C: "cjk", A: "void" }[t[0]]].push(t[1])
                }
                root.fontLists = out
            }
        }
    }
    function optionsFor(row) {
        var l = row.fonts ? (fontLists[row.fonts] || []) : (row.options || [])
        if (row.fonts && l.length === 0) l = row.options || []
        var cur = String(value(row))
        if (row.fonts && cur !== "" && l.indexOf(cur) < 0) l = [cur].concat(l)
        return l
    }
    readonly property var themeNames: {
        var out = []
        for (var i = 0; i < themeFiles.count; i++) out.push(themeFiles.get(i, "fileBaseName"))
        return out.length ? out : ["nier"]
    }

    // ── what the pages hold ──
    readonly property var cats: [
        { id: "status",  label: "STATUS",  sub: "狀態" },
        { id: "effects", label: "EFFECTS", sub: "特效" },
        { id: "look",    label: "LOOK",    sub: "外觀" },
        { id: "hud",     label: "HUD",     sub: "歌詞" },
        { id: "input",   label: "IME",     sub: "輸入法" },
        { id: "misc",    label: "OTHER",   sub: "截圖通知" }
    ]
    readonly property var pages: ({
        status: [
            { type: "status", key: "plugin", label: "imecaret 外掛", desc: "視窗特效、選字框定位、點擊與 Enter 爆發都靠它。開機時 Hyprland 會載入；沒載入時這裡會自動補上。" },
            { type: "status", key: "clip",   label: "剪貼簿監看", desc: "cliphist 的兩個 wl-paste 監看程式，剪貼簿面板的歷史來自它們；沒在跑會自動啟動。" },
            { type: "status", key: "fcitx",  label: "fcitx5", desc: "輸入法本身。" },
            { type: "status", key: "bridge", label: "選字框橋接", desc: "scripts/imepanel.py，Quickshell 選字框需要它；停掉時會自動重啟。" },
            { type: "action", key: "fix",     label: "一鍵修復", desc: "載入外掛、啟動剪貼簿監看。qs 啟動時與每 30 秒檢查時也會自動做。" },
            { type: "action", key: "rebuild", label: "重新編譯外掛", desc: "Hyprland 更新後，舊版外掛會拒絕載入：重新編譯並換上（約 10 秒）。" },
            { type: "action", key: "reload",  label: "重新載入 Quickshell", desc: "重新讀取所有 QML。設定改動本來就即時生效，通常不需要。" }
        ],
        effects: [
            { type: "bool", key: "effects.click",       def: true,  label: "點擊爆發", desc: "點擊視窗時的鑽石爆發。" },
            { type: "num",  key: "effects.burstSize",   def: 0.7,   min: 0.3, max: 1.5, step: 0.05, label: "爆發大小", desc: "點擊、打字、確認時鑽石爆發的大小。" },
            { type: "bool", key: "effects.windowOpen",  def: true,  label: "開窗：像素雨", desc: "新視窗自己的像素由上往下落進位置；落完才顯示真正的視窗（約 0.5 秒）。" },
            { type: "bool", key: "effects.windowClose", def: true,  label: "關窗：向下溶解", desc: "關閉的視窗往下融化。開啟時 Hyprland 自己的關窗滑出會改成不移動。" },
            { type: "bool", key: "effects.focusReticle", def: true, label: "焦點鎖定準星", desc: "用鍵盤、點擊或關窗換焦點時，角框與中心鑽石鎖定新視窗。" },
            { type: "bool", key: "effects.focusReticleHover", def: false, label: "滑鼠移過也鎖定", desc: "焦點跟著滑鼠換時也顯示準星（移動時會一直出現）。" }
        ],
        look: [
            { type: "choice", key: "general.theme", def: "nier", options: root.themeNames, preview: "theme", label: "主題", desc: "整個 shell 的配色；fcitx5、視窗邊框、終端機也會跟著換（見下方）。↵ 打開時，選到哪個主題整個桌面就先換成那樣。" },
            { type: "num", key: "font.size", def: 0, min: -2, max: 6, step: 1, preview: "size", signed: true, label: "全域字級", desc: "虛空以外所有文字的大小，一級 ×1.09（11 px 大約多 1 px）。虛空（鎖屏、授權、關機）有自己的字級。" },
            { type: "num", key: "terminal.fontSize", def: 13, min: 8, max: 24, step: 0.5, unit: "pt", preview: "kitty", label: "kitty 字級", desc: "kitty 自己的字級，不跟全域字級連動。開著的終端機會即時重排；Ctrl+Backspace 回到這個大小。" },
            { type: "choice", key: "font.mono", def: "Operator Mono", options: root.monoFonts, fonts: "mono", preview: "font", label: "系統字型", desc: "標籤、數字與內文的等寬字（只列已安裝的）；kitty 用同一套時要另外改 kitty.conf。" },
            { type: "choice", key: "font.cjk", def: "jf金萱那提2.0", options: root.cjkFonts, fonts: "cjk", preview: "font", label: "中文字型", desc: "中文說明與通知的字；任何字缺的中文都會落到這裡（fontconfig 規則只認金萱，換別的要改 60-quickshell.conf）。" },
            { type: "choice", key: "font.void", def: "", options: root.voidFonts, fonts: "void", preview: "void", label: "虛空字型", desc: "鎖屏、授權、關機過場的字（只列已安裝的）。新裝的字要重啟 qs 才看得到。" },
            { type: "choice", key: "font.voidWeight", def: "400", options: ["300", "400"], label: "虛空字重", desc: "300 Light · 400 Regular。" },
            { type: "choice", key: "font.voidRatio", def: "1.618", options: ["1.25", "1.333", "1.5", "1.618"], label: "虛空字級比例", desc: "每一級是上一級的幾倍：1.618 黃金比例落差最大，1.25 最平緩。" },
            { type: "num",  key: "font.voidBase", def: 12, min: 10, max: 18, step: 1, unit: "px", label: "虛空基準字級", desc: "最小一級（標籤）在 1080p 的大小；提示、標題、時鐘都由它乘上比例算出。" },
            { type: "choice", key: "void.light", def: "#ffffff", preview: "color", options: ["#ffffff", "#d6ecf0", "#f2ecde", "#fff6cf"], label: "虛空文字色", desc: "固定、不跟主題：#ffffff 白 · #d6ecf0 月白 · #f2ecde 米白 · #fff6cf 象牙。" },
            { type: "choice", key: "void.warn", def: "#b8403c", preview: "color", options: ["#b8403c", "#c3272b", "#9d2933", "#d6ecf0"], label: "虛空警示色", desc: "FAILED 等警示：#b8403c 暗紅 · #c3272b 朱 · #9d2933 胭脂 · 或同文字色。" },
            { type: "choice", key: "font.voidClockStep", def: "5", options: ["4", "5"], label: "鎖屏時鐘級數", desc: "時鐘用第 4 級（小一號）或第 5 級。" },
            { type: "num",  key: "backdrop.opacity",  def: 0.42, min: 0.1, max: 0.9, step: 0.02, label: "玻璃三角形不透明度", desc: "彈窗背景三角形的濃淡，越小越透。" },
            { type: "num",  key: "backdrop.dim",      def: 0.28, min: 0, max: 0.8, step: 0.02, label: "背景變暗", desc: "彈窗打開時，背後畫面變暗的程度。" },
            { type: "num",  key: "backdrop.flicker",  def: 0.6,  min: 0, max: 1, step: 0.1, label: "閃動強度", desc: "三角形隨機閃動的強度，0 = 靜止。" },
            { type: "num",  key: "backdrop.cellSize", def: 180,  min: 100, max: 320, step: 10, unit: "px", label: "三角形大小", desc: "背景三角形的邊長。" },
            { type: "bool", key: "sync.fcitx5",   def: true, label: "fcitx5 跟著主題", desc: "fcitx5 自己的選字框用主題配色；關掉回到固定的 nier 主題。" },
            { type: "bool", key: "sync.hyprland", def: true, label: "視窗邊框跟著主題", desc: "Hyprland 的邊框與光暈用主題配色；關掉回到原本的全息配色。" },
            { type: "bool", key: "sync.terminal", def: true, label: "終端機跟著主題", desc: "kitty 的配色、zsh 提示符與 fzf / bat / delta / atuin 跟著主題；關掉時 kitty 回到 kitty.conf 自己的配色。" }
        ],
        hud: [
            { type: "bool", key: "hud.enabled",     def: true, label: "顯示 HUD", desc: "右上角的 HUD（狀態、月曆、工作區、OSD）。" },
            { type: "num",  key: "hud.hideDelay",   def: 1400, min: 400, max: 5000, step: 100, unit: "ms", label: "收回延遲", desc: "游標離開後多久收回。" },
            { type: "num",  key: "hud.osdDuration", def: 1700, min: 600, max: 5000, step: 100, unit: "ms", label: "OSD 停留", desc: "音量、亮度、麥克風等提示停留多久。" },
            { type: "bool", key: "hud.trackToast",  def: true, label: "換歌顯示曲名", desc: "Spotify、YouTube、bilibili 等換歌時 HUD 彈出曲名卡片。" },
            { type: "bool", key: "lyrics.enabled",  def: true, label: "同步歌詞", desc: "播放時在 HUD 顯示歌詞（找不到時不顯示）。也可以按 SUPER+SHIFT+L 或點一下歌詞切換。" },
            { type: "num",  key: "lyrics.offset",   def: 0, min: -3, max: 3, step: 0.1, unit: "s", label: "歌詞時間校正", desc: "歌詞比歌聲慢就調正數。" }
        ],
        input: [
            { type: "bool", key: "ime.panel",  def: true, label: "Quickshell 選字框", desc: "用 shell 畫的選字框；關掉改用 fcitx5 原生選字框。" },
            { type: "bool", key: "ime.sparks", def: true, label: "打字粒子", desc: "打字時游標旁的菱形粒子。" }
        ],
        misc: [
            { type: "bool",   key: "capture.freeze", def: true, label: "截圖凍結畫面", desc: "區域選取時凍結畫面。" },
            { type: "choice", key: "capture.style",  def: "iris", options: ["wipe", "rise", "scan", "iris", "blinds"], label: "截圖面板動畫", desc: "截圖面板的開關動畫。" },
            { type: "num",  key: "notifications.timeout",         def: 5000,  min: 1000, max: 20000, step: 500,  unit: "ms", label: "通知停留", desc: "一般通知的彈窗停留多久（之後仍在歷史裡）。" },
            { type: "num",  key: "notifications.criticalTimeout", def: 10000, min: 2000, max: 30000, step: 1000, unit: "ms", label: "緊急通知停留", desc: "緊急通知的彈窗停留多久。" },
            { type: "num",  key: "notifications.history",         def: 50,    min: 10, max: 200, step: 10, label: "通知歷史則數", desc: "Control Center 保留的通知數量。" },
            { type: "bool", key: "companions.enabled", def: false, label: "角落小人", desc: "右下角的動畫小人（需要自己放 gif，見 README）。" }
        ]
    })

    property string cat: "status"
    property int    catDir: 1
    property int    focusIdx: 0
    readonly property var rows: pages[cat] || []
    readonly property var cur: rows.length ? rows[Math.min(focusIdx, rows.length - 1)] : null
    readonly property int catIndex: cats.findIndex(function(c) { return c.id === root.cat })

    // ── values: shell.conf through Config, with this panel's writes shown at once ──
    property var _pending: ({})
    // a value stays "pending" until the reloaded file shows it
    Connections {
        target: Config
        function onShellChanged() {
            var p = {}
            for (var k in root._pending) if (String(Config.shell[k]) !== String(root._pending[k])) p[k] = root._pending[k]
            root._pending = p
        }
    }
    function value(row) {
        if (row.type === "status") return Health[row.key]
        if (row.key in _pending) return _pending[row.key]
        var v = Config.shell[row.key]
        if (v === undefined || v === "") return row.def
        if (row.type === "bool") return v === true
        if (row.type === "num") return typeof v === "number" ? v : row.def
        return String(v)
    }
    // writes go one at a time (quick presses are batched into the next one), so two
    // writers never race on shell.conf
    property var _queue: []
    function setValue(row, v) {
        var p = Object.assign({}, _pending); p[row.key] = v; _pending = p
        var dot = row.key.indexOf(".")
        _queue = _queue.concat([row.key.substring(0, dot), row.key.substring(dot + 1), String(v)])
        if (!writer.running) _flush()
    }
    function _flush() {
        if (_queue.length === 0) return
        writer.command = ["python3", Quickshell.shellDir + "/scripts/conf-set.py"].concat(_queue)
        _queue = []
        writer.running = true
    }
    Process { id: writer; onExited: root._flush() }
    function decimals(row) { var s = String(row.step); return s.indexOf(".") < 0 ? 0 : s.length - s.indexOf(".") - 1 }
    function textOf(row) {
        var v = value(row)
        if (row.type === "bool") return v ? "ON" : "OFF"
        if (row.type === "num") return (row.signed && Number(v) > 0 ? "+" : "") + Number(v).toFixed(decimals(row)) + (row.unit ? " " + row.unit : "")
        if (row.type === "status") return v ? "✓  OK" : "✗  未執行"
        if (row.type === "action") return Health.busy && (row.key === "fix" || row.key === "rebuild") ? "…" : "▸  執行"
        return String(v)
    }

    // ── actions ──
    function activate(row) {
        if (!row || phase !== "open") return
        if (row.type === "bool") setValue(row, !value(row))
        else if (row.type === "choice" || row.type === "num") { beginEdit(row); return }
        else if (row.type === "status") { if (!value(row)) Health.fix(); else Health.check() }
        else if (row.key === "fix") Health.fix()
        else if (row.key === "rebuild") Health.rebuild()
        else if (row.key === "reload") { Quickshell.reload(false); return }
        hit()
    }
    function step(row, d) {
        if (!row) return
        if (row.type === "num") {
            var v = Math.max(row.min, Math.min(row.max, Number(value(row)) + d * row.step))
            setValue(row, Number(v.toFixed(decimals(row))))
            nudge(d)
        } else if (row.type === "choice") {
            var o = optionsFor(row), i = o.indexOf(String(value(row)))
            setValue(row, o[((i < 0 ? 0 : i) + d + o.length) % o.length])
            nudge(d)
        }
    }
    // ── the side panel: one choice or slider, opened with ↵ ──
    readonly property int paneW: 380
    readonly property int paneGap: 16
    property bool   editing: false
    property var    editRow: null
    property var    editOrig: null          // the value when it opened (Esc puts it back)
    property int    pickIdx: 0
    property string filter: ""
    property real   editT: 0
    Behavior on editT { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
    readonly property var pickAll: editRow && editRow.type === "choice" ? optionsFor(editRow) : []
    readonly property var pickOptions: {
        if (filter === "") return pickAll
        var f = filter.toLowerCase()
        return pickAll.filter(function(o) { return String(o).toLowerCase().indexOf(f) >= 0 })
    }
    readonly property string picked: pickOptions.length ? String(pickOptions[Math.min(pickIdx, pickOptions.length - 1)]) : ""
    function beginEdit(row) {
        editRow = row; editOrig = value(row); filter = ""
        var i = row.type === "choice" ? optionsFor(row).indexOf(String(editOrig)) : 0
        pickIdx = Math.max(0, i)
        editing = true; editT = 1
        Qt.callLater(function() { pickList.positionViewAtIndex(root.pickIdx, ListView.Center) })
        hit()
    }
    function endEdit(keep) {
        if (!editing) return
        var row = editRow
        if (row.type === "choice") {
            if (row.preview === "theme") Config.themeOverride = ""
            if (keep && picked !== "" && picked !== String(value(row))) setValue(row, picked)
        } else if (!keep && String(value(row)) !== String(editOrig)) setValue(row, editOrig)
        editing = false; editT = 0
        if (keep) hit()
    }
    // a theme previews on the whole shell while it's picked
    onPickedChanged: if (editing && editRow && editRow.preview === "theme" && picked !== "") Config.themeOverride = picked
    function movePick(d) {
        var n = pickOptions.length
        if (n === 0) return
        var i = pickIdx + d
        if (i < 0 || i >= n) { bumpAnim.restart(); return }
        pickIdx = i
    }
    onFilterChanged: pickIdx = 0
    function setCat(k) {
        if (k === cat) return
        var a = catIndex, b = cats.findIndex(function(c) { return c.id === k })
        catDir = b > a ? 1 : -1
        cat = k; focusIdx = 0
        rowsIn.restart()
    }
    function stepCat(d) {
        var i = catIndex + d
        if (i >= 0 && i < cats.length) setCat(cats[i].id)
    }

    // the launcher's hit feel: the selector pops and flashes, a burst from the control
    property real hitT: 0
    property real flashV: 0
    SequentialAnimation {
        id: hitAnim
        ScriptAction { script: { root.flashV = 1; root.burst.playAt(burstAnchor, 0, 0, 0.7) } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "flashV"; to: 0; duration: 380; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
                NumberAnimation { target: root; property: "hitT"; to: 0; duration: 240; easing.type: Easing.OutCubic }
            }
        }
    }
    function hit() { hitAnim.restart() }
    // −/+ shove the value a little that way
    property real shove: 0
    SequentialAnimation {
        id: shoveAnim
        NumberAnimation { id: shoveOut; target: root; property: "shove"; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "shove"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }
    function nudge(d) { shoveAnim.stop(); shoveOut.to = d; shoveAnim.start() }
    property real bump: 0
    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: root; property: "bump"; from: 0; to: 1; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bump"; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }
    property real rowsEnter: 1
    NumberAnimation { id: rowsIn; target: root; property: "rowsEnter"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }

    // ── lifecycle (components/Popup.qml) ──
    onOpening: { cat = "status"; focusIdx = 0; _pending = ({}); editing = false; editT = 0; Health.check(); fontScan.running = true }
    onIntro:    { host.reveal(); keys.forceActiveFocus(); if (_editAt !== "") editT0.start() }
    Timer { id: editT0; interval: 380; onTriggered: root._openEdit() }
    onOutro:    { if (editing) endEdit(false); host.conceal() }
    onFinished: host.reset()

    // ═══════════════════════════════════
    IrisHost {
        id: host
        // the side panel takes room on the right: the pair stays centred
        x: (root.screenW - root.lw) / 2 - root.editT * (root.paneW + root.paneGap) / 2
        y: (root.screenH - root.lh) / 2
        width: root.lw; height: root.lh
        visible: root.shown || root.warming
        forceLayer: root.warming
        onMidReveal: rowsIn.restart()
        onConcealed: root.panelGone()

        FocusScope {
            id: keys
            anchors.fill: parent
            focus: root.isOpen
            Keys.onPressed: (e) => {
                var k = e.key
                if (root.editing) {
                    var r = root.editRow, big = (e.modifiers & Qt.ShiftModifier) ? 5 : 1
                    if (k === Qt.Key_Escape) root.endEdit(false)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.endEdit(true)
                    else if (r.type === "num" && (k === Qt.Key_Left || k === Qt.Key_Minus)) root.step(r, -big)
                    else if (r.type === "num" && (k === Qt.Key_Right || k === Qt.Key_Plus || k === Qt.Key_Equal)) root.step(r, big)
                    else if (r.type === "choice" && k === Qt.Key_Up) root.movePick(-big)
                    else if (r.type === "choice" && k === Qt.Key_Down) root.movePick(big)
                    else if (r.type === "choice" && k === Qt.Key_PageUp) root.movePick(-8)
                    else if (r.type === "choice" && k === Qt.Key_PageDown) root.movePick(8)
                    else if (r.type === "choice" && k === Qt.Key_Backspace) root.filter = root.filter.slice(0, -1)
                    else if (r.type === "choice" && e.text !== "" && e.text.charCodeAt(0) > 32 && !(e.modifiers & Qt.ControlModifier)) root.filter += e.text
                    else if (r.type === "choice" && k === Qt.Key_Space && root.filter !== "") root.filter += " "
                    e.accepted = true
                    return
                }
                if (k === Qt.Key_Escape) root.close()
                else if (k === Qt.Key_Left)  root.stepCat(-1)
                else if (k === Qt.Key_Right || k === Qt.Key_Tab) root.stepCat(k === Qt.Key_Tab && root.catIndex === root.cats.length - 1 ? -root.catIndex : 1)
                else if (k === Qt.Key_Up)   { if (root.focusIdx > 0) root.focusIdx--; else bumpAnim.restart() }
                else if (k === Qt.Key_Down) { if (root.focusIdx < root.rows.length - 1) root.focusIdx++; else bumpAnim.restart() }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.activate(root.cur)
                else if (k === Qt.Key_Minus || k === Qt.Key_Underscore || k === Qt.Key_BracketLeft) root.step(root.cur, -1)
                else if (k === Qt.Key_Plus || k === Qt.Key_Equal || k === Qt.Key_BracketRight) root.step(root.cur, 1)
                else if (k >= Qt.Key_1 && k <= Qt.Key_9) {      // a row's number is its key (Alt too)
                    var n = k - Qt.Key_1
                    if (n < root.rows.length) { root.focusIdx = n; root.activate(root.rows[n]) }
                }
                else return
                e.accepted = true
            }

            PaperCard {
                anchors.fill: parent
                t: root.t
                Rectangle {   // the keys are next door: this card steps back
                    anchors.fill: parent; z: 50
                    color: Theme.paper; opacity: 0.35 * root.editT
                    visible: opacity > 0.01
                    MouseArea { anchors.fill: parent; enabled: root.editing; onClicked: root.endEdit(true) }
                }

                // ── header: title + the helpers at a glance ──
                Item {
                    id: header
                    width: parent.width; height: 52
                    Row {
                        anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Text { text: "SETTINGS"; font.pixelSize: Theme.fs(11); font.letterSpacing: 3.5; font.weight: Font.Medium; color: Theme.inkStrong }
                        Rectangle { width: 24; height: 1; color: Theme.inkSoft; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "設定"; font.pixelSize: Theme.fs(11); font.letterSpacing: 2; color: Theme.inkSoft; font.family: Theme.cjk }
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Repeater {
                            model: [["PLUGIN", "plugin"], ["CLIP", "clip"], ["IME", "bridge"]]
                            Row {
                                spacing: 5; anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: 7; height: 7; rotation: 45; antialiasing: true; anchors.verticalCenter: parent.verticalCenter
                                    readonly property bool ok: Health[modelData[1]]
                                    color: ok ? Theme.ink : "transparent"
                                    border.color: ok ? Theme.ink : Theme.warn; border.width: 1
                                }
                                Text { text: modelData[0]; font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Health[modelData[1]] ? Theme.inkSoft : Theme.warn }
                            }
                        }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                }

                // ── body ──
                Item {
                    anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right }

                    Column {
                        id: side
                        width: 150; anchors { top: parent.top; topMargin: 16 }
                        Repeater {
                            model: root.cats
                            CatTab {
                                width: 150
                                label: modelData.label
                                sub: modelData.sub
                                active: root.cat === modelData.id
                                dir: root.catDir
                                animate: root.shown
                                pulse: root.pulse
                                onClicked: { root.setCat(modelData.id); keys.forceActiveFocus() }
                            }
                        }
                    }
                    Rectangle { x: side.width; width: 1; height: parent.height; color: Theme.alpha(Theme.ink, 0.25) }

                    // rows
                    Item {
                        id: mid
                        anchors { left: side.right; leftMargin: 1; top: parent.top; bottom: parent.bottom }
                        width: 480
                        ListView {
                            id: list
                            anchors.fill: parent
                            anchors.topMargin: 8
                            clip: true
                            model: root.rows
                            keyNavigationEnabled: false
                            interactive: false
                            currentIndex: root.focusIdx

                            SpringSelector {
                                id: sel
                                parent: list.contentItem
                                width: list.width; rowH: root.rowH
                                targetY: root.focusIdx * root.rowH + root.bump * 6
                                hitT: root.hitT; flashV: root.flashV; pulse: root.pulse
                                visible: root.rows.length > 0
                            }
                            Item { id: burstAnchor; parent: list.contentItem; x: list.width - 70; y: sel.targetY + root.rowH / 2 }
                            Connections { target: root; function onFocusIdxChanged() { sel.sheen() } }

                            delegate: Item {
                                id: row
                                width: list.width; height: root.rowH
                                readonly property bool focused: index === root.focusIdx
                                readonly property var r: modelData
                                readonly property color fg: focused ? Theme.paper : Theme.ink
                                readonly property color fgSoft: focused ? Theme.alpha(Theme.paper, 0.55) : Theme.inkSoft
                                opacity: Math.min(1, root.rowsEnter * 1.6 - Math.min(index, 8) * 0.08)
                                transform: Translate { x: (1 - root.rowsEnter) * 40 * root.catDir }
                                scale: focused ? 1 + 0.03 * root.hitT : 1

                                Rectangle { anchors.bottom: parent.bottom; x: 22; width: parent.width - 44; height: 1; color: Theme.alpha(Theme.ink, 0.12) }
                                Text {
                                    x: 14; anchors.verticalCenter: parent.verticalCenter; width: 22
                                    text: String(index + 1).padStart(2, "0"); font.pixelSize: Theme.fs(9); font.letterSpacing: 1.5; color: row.fgSoft
                                }
                                Column {
                                    x: 44; width: parent.width - 44 - ctl.width - 24; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { width: parent.width; elide: Text.ElideRight; text: row.r.label; font.family: Theme.cjk; font.pixelSize: Theme.fs(13); color: row.fg }
                                    Text { width: parent.width; elide: Text.ElideRight; text: row.r.desc; font.family: Theme.cjk; font.pixelSize: Theme.fs(10); color: row.fgSoft }
                                }

                                // the control on the right
                                Item {
                                    id: ctl
                                    anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                                    width: 150; height: 26
                                    transform: Translate { x: row.focused ? root.shove * 5 : 0 }

                                    // bool: a switch whose diamond slides across
                                    Rectangle {
                                        visible: row.r.type === "bool"
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        width: 58; height: 18
                                        readonly property bool on: row.r.type === "bool" && root.value(row.r) === true
                                        color: on ? (row.focused ? Theme.paper : Theme.ink) : "transparent"
                                        border.color: row.fg; border.width: 1
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: parent.on ? 8 : parent.width - width - 8
                                            text: parent.on ? "ON" : "OFF"; font.pixelSize: Theme.fs(8); font.letterSpacing: 2
                                            color: parent.on ? (row.focused ? Theme.ink : Theme.paper) : row.fgSoft
                                        }
                                        Rectangle {
                                            width: 9; height: 9; rotation: 45; antialiasing: true
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: parent.on ? parent.width - 15 : 6
                                            color: parent.on ? (row.focused ? Theme.ink : Theme.paper) : row.fg
                                            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                        }
                                    }
                                    // num / choice: ‹ value › with − + targets
                                    Row {
                                        visible: row.r.type === "num" || row.r.type === "choice"
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        spacing: 6
                                        Text {
                                            text: "‹"; font.pixelSize: Theme.fs(15); color: row.fgSoft; anchors.verticalCenter: parent.verticalCenter
                                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { root.focusIdx = index; root.step(row.r, -1) } }
                                        }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: root.textOf(row.r); font.pixelSize: Theme.fs(11); font.letterSpacing: 1; color: row.fg
                                            }
                                            Rectangle {   // where the value sits in its range
                                                visible: row.r.type === "num"
                                                width: 84; height: 2; color: Theme.alpha(row.fg, 0.2)
                                                Rectangle {
                                                    height: parent.height; color: row.focused ? Theme.paper : Theme.accent
                                                    width: row.r.type === "num" ? parent.width * (Number(root.value(row.r)) - row.r.min) / (row.r.max - row.r.min) : 0
                                                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                                }
                                            }
                                        }
                                        Text {
                                            text: "›"; font.pixelSize: Theme.fs(15); color: row.fgSoft; anchors.verticalCenter: parent.verticalCenter
                                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { root.focusIdx = index; root.step(row.r, 1) } }
                                        }
                                    }
                                    // status / action
                                    Rectangle {
                                        visible: row.r.type === "status" || row.r.type === "action"
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        width: stT.implicitWidth + 18; height: 20
                                        readonly property bool bad: row.r.type === "status" && !root.value(row.r)
                                        color: bad ? Theme.alpha(Theme.warn, 0.18) : "transparent"
                                        border.color: bad ? Theme.warn : row.fg; border.width: 1
                                        Text {
                                            id: stT; anchors.centerIn: parent
                                            text: root.textOf(row.r); font.pixelSize: Theme.fs(9); font.letterSpacing: 1.5
                                            font.family: Theme.cjk
                                            color: parent.bad ? Theme.warn : row.fg
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent; z: -1; hoverEnabled: true
                                    onEntered: root.focusIdx = index
                                    onClicked: { root.focusIdx = index; root.activate(row.r); keys.forceActiveFocus() }
                                    onWheel: (w) => { root.focusIdx = index; root.step(row.r, w.angleDelta.y > 0 ? 1 : -1) }
                                }
                            }
                        }
                    }
                    Rectangle { x: mid.x + mid.width; width: 1; height: parent.height; color: Theme.alpha(Theme.ink, 0.25) }

                    // detail
                    Item {
                        anchors { left: mid.right; leftMargin: 1; right: parent.right; top: parent.top; bottom: parent.bottom }
                        Column {
                            anchors { fill: parent; margins: 20 }
                            spacing: 10
                            Text {
                                text: root.cur ? (root.cur.type === "status" || root.cur.type === "action" ? "HEALTH" : "[" + root.cur.key.replace(".", "] ")) : ""
                                font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Theme.accent
                            }
                            Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: root.cur ? root.cur.label : ""; font.family: Theme.cjk; font.pixelSize: Theme.fs(16); color: Theme.inkStrong
                            }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.3
                                text: root.cur ? root.cur.desc : ""; font.family: Theme.cjk; font.pixelSize: Theme.fs(11); color: Theme.ink
                            }
                            Text {
                                visible: root.cur !== null && root.cur.type !== "action"
                                text: root.cur ? root.textOf(root.cur) : ""
                                font.pixelSize: Theme.fs(22); font.letterSpacing: 2; color: Theme.inkStrong
                                transform: Translate { x: root.shove * 6 }
                            }
                            Text {
                                visible: root.cur !== null && root.cur.type === "num"
                                text: root.cur && root.cur.type === "num" ? (root.cur.min + " … " + root.cur.max + "  ·  預設 " + root.cur.def) : ""
                                font.pixelSize: Theme.fs(9); font.letterSpacing: 1; color: Theme.inkSoft
                            }
                        }
                    }
                }

                // ── footer ──
                Item {
                    id: footer
                    anchors.bottom: parent.bottom; width: parent.width; height: 44
                    Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                    Text {
                        anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                        text: "寫入 config/shell.conf · 即時生效"; font.family: Theme.cjk; font.pixelSize: Theme.fs(9); color: Theme.inkSoft
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Repeater {
                            model: [["1–9", "RUN"], ["←→", "PAGE"], ["↑↓", "SELECT"], ["↵", "OPEN"], ["−/+", "ADJUST"], ["ESC", "CLOSE"]]
                            Row {
                                spacing: 5; anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: kt.implicitWidth + 8; height: 16; color: "transparent"
                                    border.color: Theme.alpha(Theme.ink, 0.25); border.width: 1
                                    Text { id: kt; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: Theme.fs(9); color: Theme.ink }
                                }
                                Text { text: modelData[1]; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Theme.inkSoft }
                            }
                        }
                    }
                }
            }
        }
    }

    // ═══ the side panel: one choice (every option, a preview) or one slider ═══
    Item {
        id: pane
        visible: root.editT > 0.01 && (root.shown || root.warming)
        x: host.x + root.lw + root.paneGap + (1 - root.editT) * 40
        y: host.y
        width: root.paneW; height: root.lh
        opacity: root.editT
        readonly property var r: root.editRow || ({ type: "", key: "", label: "", desc: "" })
        readonly property bool isChoice: r.type === "choice"
        readonly property string kind: r.preview || ""

        PaperCard {
            anchors.fill: parent
            t: root.t

            Column {
                id: paneHead
                x: 22; y: 18; width: parent.width - 44; spacing: 6
                Text { text: "[" + pane.r.key.replace(".", "] "); font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Theme.accent }
                Text { width: parent.width; elide: Text.ElideRight; text: pane.r.label; font.family: Theme.cjk; font.pixelSize: Theme.fs(16); color: Theme.inkStrong }
                Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
            }

            // ── a choice: the filter, the options, the preview ──
            Item {
                visible: pane.isChoice
                anchors { top: paneHead.bottom; topMargin: 8; left: parent.left; right: parent.right; bottom: paneFoot.top }

                Row {   // typing filters
                    id: filterRow
                    x: 22; height: visible ? 22 : 0
                    visible: root.filter !== "" || root.pickAll.length > 10
                    spacing: 8
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "▸"; font.pixelSize: Theme.fs(11); color: Theme.accent }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filter !== "" ? root.filter : "TYPE TO FILTER  ·  " + root.pickAll.length
                        font.family: root.filter !== "" ? Theme.mono : Theme.mono
                        font.pixelSize: Theme.fs(root.filter !== "" ? 12 : 9); font.letterSpacing: root.filter !== "" ? 0.5 : 2
                        color: root.filter !== "" ? Theme.ink : Theme.inkSoft
                    }
                    Text {
                        visible: root.filter !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pickOptions.length + " / " + root.pickAll.length
                        font.pixelSize: Theme.fs(9); color: Theme.inkSoft
                    }
                }

                ListView {
                    id: pickList
                    anchors { top: filterRow.bottom; topMargin: 4; left: parent.left; right: parent.right; bottom: preview.top; bottomMargin: 10 }
                    clip: true; interactive: true
                    model: root.pickOptions
                    currentIndex: root.pickIdx
                    highlightFollowsCurrentItem: false
                    readonly property real rowH: Math.round(Theme.fs(13) * 2.3)
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    SpringSelector {
                        parent: pickList.contentItem
                        width: pickList.width; rowH: pickList.rowH
                        targetY: root.pickIdx * pickList.rowH
                        hitT: root.hitT; flashV: root.flashV; pulse: root.pulse
                        visible: root.pickOptions.length > 0
                    }
                    delegate: Item {
                        width: pickList.width; height: pickList.rowH
                        readonly property bool on: index === root.pickIdx
                        readonly property bool isCur: pane.r.key !== "" && String(modelData) === String(root.value(pane.r))
                        Rectangle {   // the value now: a diamond
                            x: 22; anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; rotation: 45; antialiasing: true
                            visible: parent.isCur
                            color: parent.on ? Theme.paper : Theme.ink
                        }
                        Rectangle {   // a colour option shows itself
                            visible: pane.kind === "color"
                            x: 40; anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; color: String(modelData)
                            border.color: parent.on ? Theme.paper : Theme.ink; border.width: 1
                        }
                        Text {
                            x: pane.kind === "color" ? 64 : 40; width: parent.width - x - 18
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: String(modelData) === "" ? "（主題的 mono）" : String(modelData)
                            // a face is shown in itself
                            font.family: pane.kind === "font" || pane.kind === "void" ? (String(modelData) || Theme.mono) : Theme.mono
                            font.pixelSize: Theme.fs(13)
                            color: parent.on ? Theme.paper : Theme.ink
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { if (root.pickIdx === index) root.endEdit(true); else root.pickIdx = index }
                        }
                    }
                }

                // the preview of what's picked
                Rectangle {
                    id: preview
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
                    height: pane.kind === "" ? 64 : 150
                    color: pane.kind === "void" ? "#010101" : Theme.alpha(Theme.ink, 0.06)
                    border.color: Theme.alpha(Theme.ink, 0.25); border.width: 1
                    Text {
                        x: 10; y: 8; text: "PREVIEW"; font.pixelSize: Theme.fs(8); font.letterSpacing: 2
                        color: pane.kind === "void" ? Theme.alpha(Theme.voidLight, 0.4) : Theme.inkSoft
                    }
                    // a face: the shell's lines in it
                    Column {
                        visible: pane.kind === "font"
                        anchors.centerIn: parent; spacing: 8; width: parent.width - 28
                        Text { width: parent.width; elide: Text.ElideRight; text: pane.r.fonts === "cjk" ? "中文說明文字 · 通知與選字框" : "SYSTEM  0123456789"; font.family: root.picked; font.pixelSize: Theme.fs(18); color: Theme.inkStrong }
                        Text { width: parent.width; elide: Text.ElideRight; text: pane.r.fonts === "cjk" ? "繁體　設定面板的說明會是這樣" : "ALT 1–9 RUN · ↑↓ SELECT · ◆ 0O1lI"; font.family: root.picked; font.pixelSize: Theme.fs(12); color: Theme.ink }
                        Text { width: parent.width; elide: Text.ElideRight; text: pane.r.fonts === "cjk" ? "Latin falls back here too 0123" : "The quick brown fox · 中文落到金萱"; font.family: root.picked; font.pixelSize: Theme.fs(11); color: Theme.inkSoft }
                    }
                    // the Void's face: on black, tracked caps
                    Column {
                        visible: pane.kind === "void"
                        anchors.centerIn: parent; spacing: 12
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "SYSTEM LOCKED"; font.family: root.picked || Theme.mono; font.weight: Theme.voidWeight
                            font.pixelSize: 26; font.letterSpacing: 0.26 * 26; color: Theme.voidLight
                        }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 140; height: 1; color: Theme.alpha(Theme.voidLight, 0.45) }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "AUTHORIZATION REQUIRED"; font.family: root.picked || Theme.mono; font.weight: Theme.voidWeight
                            font.pixelSize: 12; font.letterSpacing: 0.3 * 12; color: Theme.alpha(Theme.voidLight, 0.6)
                        }
                    }
                    // a colour: the swatch on the Void's black
                    Row {
                        visible: pane.kind === "color"
                        anchors.centerIn: parent; spacing: 16
                        Rectangle { width: 64; height: 64; color: root.picked !== "" ? root.picked : "transparent"; border.color: Theme.ink; border.width: 1 }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter; spacing: 6
                            Text { text: root.picked; font.family: Theme.mono; font.pixelSize: Theme.fs(14); color: Theme.inkStrong }
                            Rectangle {
                                width: 150; height: 30; color: "#010101"
                                Text { anchors.centerIn: parent; text: "ACCESS DENIED"; font.family: Theme.voidFont; font.weight: Theme.voidWeight; font.pixelSize: 11; font.letterSpacing: 3; color: root.picked !== "" ? root.picked : "white" }
                            }
                        }
                    }
                    // a theme: the whole shell already shows it; these are its inks
                    Column {
                        visible: pane.kind === "theme"
                        anchors.centerIn: parent; spacing: 10
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.picked.toUpperCase(); font.pixelSize: Theme.fs(14); font.letterSpacing: 3; color: Theme.inkStrong }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                            Repeater {
                                model: [Theme.paper, Theme.ink, Theme.accent, Theme.light, Theme.panel, Theme.panelText, Theme.warn, Theme.good]
                                Rectangle { width: 30; height: 30; rotation: 45; antialiasing: true; color: modelData; border.color: Theme.alpha(Theme.ink, 0.5); border.width: 1 }
                            }
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "整個桌面正在預覽這個主題 · ↵ 套用 · ESC 還原"; font.family: Theme.cjk; font.pixelSize: Theme.fs(10); color: Theme.inkSoft }
                    }
                    Text {
                        visible: pane.kind === ""
                        anchors.centerIn: parent
                        text: root.picked; font.family: Theme.mono; font.pixelSize: Theme.fs(20); font.letterSpacing: 2; color: Theme.inkStrong
                    }
                }
            }

            // ── a slider: the value, the rail, the range ──
            Item {
                visible: !pane.isChoice
                anchors { top: paneHead.bottom; left: parent.left; right: parent.right; bottom: paneFoot.top }
                readonly property real v: pane.r.type === "num" ? Number(root.value(pane.r)) : 0
                readonly property real k: pane.r.type === "num" ? (v - pane.r.min) / (pane.r.max - pane.r.min) : 0
                Column {
                    x: 22; y: 18; width: parent.width - 44; spacing: 18
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pane.r.type === "num" ? root.textOf(pane.r) : ""
                        font.pixelSize: Theme.fs(34); font.letterSpacing: 2; color: Theme.inkStrong
                        transform: Translate { x: root.shove * 8 }
                    }
                    Item {   // the rail: a tick per step (up to 20), the knob a diamond
                        width: parent.width; height: 28
                        readonly property int steps: pane.r.type === "num" ? Math.round((pane.r.max - pane.r.min) / pane.r.step) : 0
                        Rectangle { y: 13; width: parent.width; height: 2; color: Theme.alpha(Theme.ink, 0.18) }
                        Rectangle { y: 13; width: parent.width * parent.parent.parent.k; height: 2; color: Theme.accent
                                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
                        Repeater {
                            model: parent.steps <= 20 ? parent.steps + 1 : 0
                            Rectangle { x: index * (parent.width / parent.steps) - 0.5; y: 9; width: 1; height: 10; color: Theme.alpha(Theme.ink, 0.35) }
                        }
                        Rectangle {
                            width: 14; height: 14; rotation: 45; antialiasing: true
                            x: parent.width * parent.parent.parent.k - 7; y: 7
                            color: Theme.ink; border.color: Theme.paper; border.width: 1
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            function setAt(mx) {
                                var r = pane.r, f = Math.max(0, Math.min(1, mx / width))
                                var v = r.min + Math.round(f * (r.max - r.min) / r.step) * r.step
                                root.setValue(r, Number(v.toFixed(root.decimals(r))))
                            }
                            onPressed: (m) => setAt(m.x)
                            onPositionChanged: (m) => { if (pressed) setAt(m.x) }
                            onWheel: (w) => root.step(pane.r, w.angleDelta.y > 0 ? 1 : -1)
                        }
                    }
                    Row {
                        width: parent.width
                        Text { width: parent.width / 2; text: pane.r.type === "num" ? String(pane.r.min) : ""; font.pixelSize: Theme.fs(9); color: Theme.inkSoft }
                        Text { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: pane.r.type === "num" ? String(pane.r.max) : ""; font.pixelSize: Theme.fs(9); color: Theme.inkSoft }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.3
                        text: pane.r.desc || ""; font.family: Theme.cjk; font.pixelSize: Theme.fs(11); color: Theme.ink
                    }
                    Text {
                        text: pane.r.type === "num" ? "預設 " + pane.r.def + (String(root.editOrig) !== String(root.value(pane.r)) ? "   ·   打開時 " + root.editOrig : "") : ""
                        font.family: Theme.cjk; font.pixelSize: Theme.fs(10); color: Theme.inkSoft
                    }
                    // kitty's size: a terminal's lines at it (pt → px at 96 dpi, as kitty sets it)
                    Rectangle {
                        visible: pane.kind === "kitty"
                        width: parent.width; height: kittyCol.implicitHeight + 24
                        color: Theme.panel; border.color: Theme.alpha(Theme.ink, 0.35); border.width: 1
                        clip: true
                        readonly property real px: (pane.r.type === "num" ? Number(root.value(pane.r)) : 13) * 96 / 72
                        Column {
                            id: kittyCol
                            x: 12; y: 12; width: parent.width - 24; spacing: 2
                            Text { text: "╭─◆ ~/.config ── main ─╮"; font.family: Theme.mono; font.pixelSize: parent.parent.px; color: Theme.panelText }
                            Text { text: "╰─▸ ls -la  0O1lI"; font.family: Theme.mono; font.pixelSize: parent.parent.px; color: Theme.light }
                            Text { text: "中文落到金萱 · 13:52"; font.family: Theme.mono; font.pixelSize: parent.parent.px; color: Theme.panelMuted }
                        }
                    }
                    // the global text size: the shell's lines at that size
                    Rectangle {
                        visible: pane.kind === "size"
                        width: parent.width; height: sizeCol.implicitHeight + 24
                        color: Theme.alpha(Theme.ink, 0.06); border.color: Theme.alpha(Theme.ink, 0.25); border.width: 1
                        Column {
                            id: sizeCol
                            x: 12; y: 12; width: parent.width - 24; spacing: 6
                            Text { text: "SYSTEM  ·  CPU 42%  ·  16:52"; font.pixelSize: Theme.fs(11); font.letterSpacing: 1.5; color: Theme.inkStrong }
                            Text { text: "通知內文：今晚 9 點開會，記得帶 slides"; font.family: Theme.cjk; font.pixelSize: Theme.fs(12); color: Theme.ink }
                            Text { text: "ALT 1–9 RUN · ↑↓ SELECT · ESC CLOSE"; font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Theme.inkSoft }
                        }
                    }
                }
            }

            // ── the keys ──
            Item {
                id: paneFoot
                anchors.bottom: parent.bottom; width: parent.width; height: 44
                Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                Row {
                    anchors.centerIn: parent
                    spacing: 12
                    Repeater {
                        model: pane.isChoice ? [["↑↓", "PICK"], ["A–Z", "FILTER"], ["↵", "KEEP"], ["ESC", "UNDO"]]
                                             : [["←→", "ADJUST"], ["⇧", "×5"], ["↵", "KEEP"], ["ESC", "UNDO"]]
                        Row {
                            spacing: 5; anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: pk.implicitWidth + 8; height: 16; color: "transparent"
                                border.color: Theme.alpha(Theme.ink, 0.25); border.width: 1
                                Text { id: pk; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: Theme.fs(9); color: Theme.ink }
                            }
                            Text { text: modelData[1]; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Theme.inkSoft }
                        }
                    }
                }
            }
        }
    }
}
