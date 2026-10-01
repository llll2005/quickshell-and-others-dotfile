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
Popup {
    id: root

    readonly property int  lw: 900
    readonly property int  lh: 560
    readonly property real rowH: 52

    IpcHandler {
        target: "settings"
        function toggle(): void { root.toggle() }
    }
    burst.spreadX: 1.4
    burst.spreadY: 0.7

    FolderListModel { id: themeFiles; folder: "file://" + Config.dir + "/themes"; nameFilters: ["*.conf"]; showDirs: false }
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
            { type: "choice", key: "general.theme", def: "nier", options: root.themeNames, label: "主題", desc: "整個 shell 的配色；fcitx5 與視窗邊框也會跟著換（見下方兩項）。" },
            { type: "num",  key: "backdrop.opacity",  def: 0.42, min: 0.1, max: 0.9, step: 0.02, label: "玻璃三角形不透明度", desc: "彈窗背景三角形的濃淡，越小越透。" },
            { type: "num",  key: "backdrop.dim",      def: 0.28, min: 0, max: 0.8, step: 0.02, label: "背景變暗", desc: "彈窗打開時，背後畫面變暗的程度。" },
            { type: "num",  key: "backdrop.flicker",  def: 0.6,  min: 0, max: 1, step: 0.1, label: "閃動強度", desc: "三角形隨機閃動的強度，0 = 靜止。" },
            { type: "num",  key: "backdrop.cellSize", def: 180,  min: 100, max: 320, step: 10, unit: "px", label: "三角形大小", desc: "背景三角形的邊長。" },
            { type: "bool", key: "sync.fcitx5",   def: true, label: "fcitx5 跟著主題", desc: "fcitx5 自己的選字框用主題配色；關掉回到固定的 nier 主題。" },
            { type: "bool", key: "sync.hyprland", def: true, label: "視窗邊框跟著主題", desc: "Hyprland 的邊框與光暈用主題配色；關掉回到原本的全息配色。" }
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
    Connections { target: Config; function onShellChanged() { root._pending = ({}) } }
    function value(row) {
        if (row.type === "status") return Health[row.key]
        if (row.key in _pending) return _pending[row.key]
        var v = Config.shell[row.key]
        if (v === undefined || v === "") return row.def
        if (row.type === "bool") return v === true
        if (row.type === "num") return typeof v === "number" ? v : row.def
        return String(v)
    }
    function setValue(row, v) {
        var p = Object.assign({}, _pending); p[row.key] = v; _pending = p
        var dot = row.key.indexOf(".")
        Quickshell.execDetached(["python3", Quickshell.shellDir + "/scripts/conf-set.py",
                                 row.key.substring(0, dot), row.key.substring(dot + 1), String(v)])
    }
    function decimals(row) { var s = String(row.step); return s.indexOf(".") < 0 ? 0 : s.length - s.indexOf(".") - 1 }
    function textOf(row) {
        var v = value(row)
        if (row.type === "bool") return v ? "ON" : "OFF"
        if (row.type === "num") return Number(v).toFixed(decimals(row)) + (row.unit ? " " + row.unit : "")
        if (row.type === "status") return v ? "✓  OK" : "✗  未執行"
        if (row.type === "action") return Health.busy && (row.key === "fix" || row.key === "rebuild") ? "…" : "▸  執行"
        return String(v)
    }

    // ── actions ──
    function activate(row) {
        if (!row || phase !== "open") return
        if (row.type === "bool") setValue(row, !value(row))
        else if (row.type === "choice") step(row, 1)
        else if (row.type === "num") return
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
            var o = row.options, i = o.indexOf(String(value(row)))
            setValue(row, o[((i < 0 ? 0 : i) + d + o.length) % o.length])
            nudge(d)
        }
    }
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
    onOpening: { cat = "status"; focusIdx = 0; _pending = ({}); Health.check() }
    onIntro:    { host.reveal(); keys.forceActiveFocus() }
    onOutro:    host.conceal()
    onFinished: host.reset()

    // ═══════════════════════════════════
    IrisHost {
        id: host
        x: (root.screenW - root.lw) / 2
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
                if (k === Qt.Key_Escape) root.close()
                else if (k === Qt.Key_Left)  root.stepCat(-1)
                else if (k === Qt.Key_Right || k === Qt.Key_Tab) root.stepCat(k === Qt.Key_Tab && root.catIndex === root.cats.length - 1 ? -root.catIndex : 1)
                else if (k === Qt.Key_Up)   { if (root.focusIdx > 0) root.focusIdx--; else bumpAnim.restart() }
                else if (k === Qt.Key_Down) { if (root.focusIdx < root.rows.length - 1) root.focusIdx++; else bumpAnim.restart() }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.activate(root.cur)
                else if (k === Qt.Key_Minus || k === Qt.Key_Underscore || k === Qt.Key_BracketLeft) root.step(root.cur, -1)
                else if (k === Qt.Key_Plus || k === Qt.Key_Equal || k === Qt.Key_BracketRight) root.step(root.cur, 1)
                else return
                e.accepted = true
            }

            PaperCard {
                anchors.fill: parent
                t: root.t

                // ── header: title + the helpers at a glance ──
                Item {
                    id: header
                    width: parent.width; height: 52
                    Row {
                        anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Text { text: "SETTINGS"; font.pixelSize: 11; font.letterSpacing: 3.5; font.weight: Font.Medium; color: Theme.inkStrong }
                        Rectangle { width: 24; height: 1; color: Theme.inkSoft; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "設定"; font.pixelSize: 11; font.letterSpacing: 2; color: Theme.inkSoft; font.family: Theme.cjk }
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
                                Text { text: modelData[0]; font.pixelSize: 9; font.letterSpacing: 2; color: Health[modelData[1]] ? Theme.inkSoft : Theme.warn }
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
                                    text: String(index + 1).padStart(2, "0"); font.pixelSize: 9; font.letterSpacing: 1.5; color: row.fgSoft
                                }
                                Column {
                                    x: 44; width: parent.width - 44 - ctl.width - 24; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                    Text { width: parent.width; elide: Text.ElideRight; text: row.r.label; font.family: Theme.cjk; font.pixelSize: 13; color: row.fg }
                                    Text { width: parent.width; elide: Text.ElideRight; text: row.r.desc; font.family: Theme.cjk; font.pixelSize: 10; color: row.fgSoft }
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
                                            text: parent.on ? "ON" : "OFF"; font.pixelSize: 8; font.letterSpacing: 2
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
                                            text: "‹"; font.pixelSize: 15; color: row.fgSoft; anchors.verticalCenter: parent.verticalCenter
                                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: { root.focusIdx = index; root.step(row.r, -1) } }
                                        }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                text: root.textOf(row.r); font.pixelSize: 11; font.letterSpacing: 1; color: row.fg
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
                                            text: "›"; font.pixelSize: 15; color: row.fgSoft; anchors.verticalCenter: parent.verticalCenter
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
                                            text: root.textOf(row.r); font.pixelSize: 9; font.letterSpacing: 1.5
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
                                font.pixelSize: 9; font.letterSpacing: 2; color: Theme.accent
                            }
                            Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap
                                text: root.cur ? root.cur.label : ""; font.family: Theme.cjk; font.pixelSize: 16; color: Theme.inkStrong
                            }
                            Text {
                                width: parent.width; wrapMode: Text.Wrap; lineHeight: 1.3
                                text: root.cur ? root.cur.desc : ""; font.family: Theme.cjk; font.pixelSize: 11; color: Theme.ink
                            }
                            Text {
                                visible: root.cur !== null && root.cur.type !== "action"
                                text: root.cur ? root.textOf(root.cur) : ""
                                font.pixelSize: 22; font.letterSpacing: 2; color: Theme.inkStrong
                                transform: Translate { x: root.shove * 6 }
                            }
                            Text {
                                visible: root.cur !== null && root.cur.type === "num"
                                text: root.cur && root.cur.type === "num" ? (root.cur.min + " … " + root.cur.max + "  ·  預設 " + root.cur.def) : ""
                                font.pixelSize: 9; font.letterSpacing: 1; color: Theme.inkSoft
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
                        text: "寫入 config/shell.conf · 即時生效"; font.family: Theme.cjk; font.pixelSize: 9; color: Theme.inkSoft
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                        spacing: 14
                        Repeater {
                            model: [["←→", "PAGE"], ["↑↓", "SELECT"], ["↵", "TOGGLE"], ["−/+", "ADJUST"], ["ESC", "CLOSE"]]
                            Row {
                                spacing: 5; anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    width: kt.implicitWidth + 8; height: 16; color: "transparent"
                                    border.color: Theme.alpha(Theme.ink, 0.25); border.width: 1
                                    Text { id: kt; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: 9; color: Theme.ink }
                                }
                                Text { text: modelData[1]; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 9; font.letterSpacing: 2; color: Theme.inkSoft }
                            }
                        }
                    }
                }
            }
        }
    }
}
