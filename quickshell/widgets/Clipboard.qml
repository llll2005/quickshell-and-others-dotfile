import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../theme"

// Clipboard history (cliphist): type to filter, ←→ switch type, ↑↓ pick, ↵ copies
// the entry back (with the launcher's hit-stop), Del deletes it. Images get
// thumbnails, decoded on demand into /tmp/qs-clip. Built from the shared popup
// pieces (Popup, PaperCard, IrisHost, SpringSelector, CatTab), so it follows the
// theme like the launcher.
//   qs ipc call clip toggle
// cliphist records through `wl-paste --watch cliphist store` (Hyprland autostart).
Popup {
    id: root

    readonly property int  lw: 880
    readonly property int  lh: 540
    readonly property real rowH: 50
    readonly property string thumbDir: "/tmp/qs-clip"

    IpcHandler {
        target: "clip"
        function toggle(): void { root.toggle() }
    }
    burst.spreadX: 1.4
    burst.spreadY: 0.7

    // ── data ──
    property var    entries: []        // {id, text, kind: text | link | image, meta}
    property string query: ""
    property string cat: "all"
    property int    catDir: 1
    property int    focusIdx: 0
    readonly property var cats: [
        { id: "all",   label: "ALL" },
        { id: "text",  label: "TEXT" },
        { id: "link",  label: "LINK" },
        { id: "image", label: "IMAGE" }
    ]
    readonly property var results: {
        var q = query.toLowerCase().trim(), out = []
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i]
            if (cat !== "all" && e.kind !== cat) continue
            if (q && e.text.toLowerCase().indexOf(q) < 0) continue
            out.push(e)
            if (out.length >= 300) break
        }
        return out
    }
    readonly property var cur: results.length ? results[Math.min(focusIdx, results.length - 1)] : null
    function countOf(k) {
        if (k === "all") return entries.length
        var n = 0
        for (var i = 0; i < entries.length; i++) if (entries[i].kind === k) n++
        return n
    }

    Process {
        id: listP
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = [], lines = this.text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var t = lines[i].indexOf("\t")
                    if (t <= 0) continue
                    var id = lines[i].substring(0, t), txt = lines[i].substring(t + 1)
                    var img = txt.match(/^\[\[ binary data (.+?) \]\]$/)
                    if (img) { out.push({ id: id, text: img[1], kind: "image", meta: img[1].toUpperCase() }); continue }
                    var link = /^(https?:\/\/|www\.)\S+$/i.test(txt.trim())
                    out.push({ id: id, text: txt, kind: link ? "link" : "text",
                               meta: link ? txt.replace(/^https?:\/\//i, "").split("/")[0] : txt.length + " CHARS" })
                }
                root.entries = out
            }
        }
    }

    // full text of the focused entry (the list only has a 100-char preview)
    property string fullText: ""
    onCurChanged: {
        fullText = ""
        if (cur && cur.kind !== "image") { textT.restart() }
        if (cur && cur.kind === "image") root.wantThumb(cur.id)
    }
    Timer { id: textT; interval: 90; onTriggered: { if (!root.cur) return; textP.running = false; textP.command = ["cliphist", "decode", root.cur.id]; textP.running = true } }
    Process {
        id: textP
        stdout: StdioCollector { onStreamFinished: root.fullText = this.text.length > 6000 ? this.text.substring(0, 6000) + "…" : this.text }
    }

    // image thumbnails: one decode at a time, newest wishes first
    property var thumbs: ({})          // id → file url
    property var _thumbQueue: []
    function wantThumb(id) {
        if (thumbs[id] || _thumbQueue.indexOf(id) >= 0) return
        _thumbQueue.unshift(id)
        if (!thumbP.running) _nextThumb()
    }
    function _nextThumb() {
        if (_thumbQueue.length === 0) return
        var id = _thumbQueue.shift()
        thumbP.thumbId = id
        thumbP.command = ["sh", "-c", 'mkdir -p "$1" && f="$1/$2.png" && { [ -s "$f" ] || cliphist decode "$2" > "$f"; }', "clip", root.thumbDir, id]
        thumbP.running = true
    }
    Process {
        id: thumbP
        property string thumbId: ""
        onExited: (code) => {
            if (code === 0) { var t = Object.assign({}, root.thumbs); t[thumbP.thumbId] = "file://" + root.thumbDir + "/" + thumbP.thumbId + ".png"; root.thumbs = t }
            root._nextThumb()
        }
    }

    // ── actions ──
    property real hitT: 0
    property real flashV: 0
    property bool _busy: false
    property var  _pick: null
    SequentialAnimation {
        id: copyConfirm
        ScriptAction { script: { root.flashV = 1; root.burst.playAt(burstAnchor, 0, 0, 1) } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "flashV"; to: 0; duration: 420; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 65 }
                ScriptAction { script: {
                    Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy', "clip", root._pick.id])
                    root.close()
                } }
                NumberAnimation { target: root; property: "hitT"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
    }
    function copyCurrent() {
        if (!cur || _busy || phase !== "open") return
        _busy = true; _pick = cur
        copyConfirm.restart()
    }
    function deleteCurrent() {
        if (!cur || _busy) return
        var id = cur.id
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\t\\n" "$1" | cliphist delete', "clip", id])
        root.entries = entries.filter(function(e) { return e.id !== id })
        focusIdx = Math.min(focusIdx, Math.max(0, results.length - 1))
        bumpAnim.restart()
    }
    function setCat(k) {
        if (k === cat || _busy) return
        var a = cats.findIndex(function(c) { return c.id === cat }), b = cats.findIndex(function(c) { return c.id === k })
        catDir = b > a ? 1 : -1
        cat = k; focusIdx = 0
        list.positionViewAtBeginning()
        rowsIn.restart()
    }
    function stepCat(d) {
        var i = cats.findIndex(function(c) { return c.id === cat }) + d
        if (i >= 0 && i < cats.length) setCat(cats[i].id)
    }
    property real bump: 0
    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: root; property: "bump"; from: 0; to: 1; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bump"; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }
    property real rowsEnter: 1
    NumberAnimation { id: rowsIn; target: root; property: "rowsEnter"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }

    // ── lifecycle (components/Popup.qml) ──
    onOpening: {
        query = ""; search.text = ""; cat = "all"; focusIdx = 0; _busy = false
        listP.running = false; listP.running = true
    }
    onIntro:    { host.reveal(); search.forceActiveFocus() }
    onOutro:    host.conceal()
    onFinished: { host.reset(); _busy = false; fullText = "" }

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

        PaperCard {
            anchors.fill: parent
            t: root.t

            // ── header ──
            Item {
                id: header
                width: parent.width; height: 52
                Row {
                    anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    Text { text: "CLIPBOARD"; font.pixelSize: Theme.fs(11); font.letterSpacing: 3.5; font.weight: Font.Medium; color: Theme.inkStrong }
                    Rectangle { width: 24; height: 1; color: Theme.inkSoft; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "クリップボード"; font.pixelSize: Theme.fs(10); font.letterSpacing: 2; color: Theme.inkSoft }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Text { text: root.results.length + " / " + root.entries.length + " ENTRIES"; font.pixelSize: Theme.fs(9); font.letterSpacing: 2; color: Theme.inkSoft; anchors.verticalCenter: parent.verticalCenter }
                    Item {
                        width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { anchors.centerIn: parent; width: 7; height: 7; rotation: 45; color: Theme.accent; scale: 1 + 0.45 * root.pulse }
                        Rectangle {
                            anchors.centerIn: parent; width: 7; height: 7; rotation: 45
                            color: "transparent"; border.color: Theme.accent; border.width: 1
                            scale: 1 + 1.4 * root.beatPhase; opacity: (1 - root.beatPhase) * 0.7
                        }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
            }

            // ── body ──
            Item {
                anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right }

                // types
                Column {
                    id: side
                    width: 150; anchors { top: parent.top; topMargin: 16 }
                    Repeater {
                        model: root.cats
                        CatTab {
                            width: 150
                            label: modelData.label
                            sub: String(root.countOf(modelData.id)).padStart(2, "0")
                            active: root.cat === modelData.id
                            dir: root.catDir
                            animate: root.shown
                            pulse: root.pulse
                            onClicked: { root.setCat(modelData.id); search.forceActiveFocus() }
                        }
                    }
                }
                Rectangle { x: side.width; width: 1; height: parent.height; color: Theme.alpha(Theme.ink, 0.25) }

                // list
                Item {
                    id: mid
                    anchors { left: side.right; leftMargin: 1; top: parent.top; bottom: parent.bottom }
                    width: 430
                    Item {
                        id: searchRow
                        width: parent.width; height: 46
                        Text { x: 24; anchors.verticalCenter: parent.verticalCenter; text: "▸"; font.pixelSize: Theme.fs(12); color: Theme.accent }
                        TextInput {
                            id: search
                            x: 44; width: parent.width - 64; height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            verticalAlignment: TextInput.AlignVCenter
                            font.pixelSize: Theme.fs(13); color: Theme.inkStrong
                            cursorVisible: activeFocus; focus: root.isOpen; selectByMouse: true
                            onTextEdited: { root.query = text; root.focusIdx = 0 }
                            Keys.onEscapePressed: root.close()
                            Keys.onUpPressed:   { if (root.focusIdx > 0) root.focusIdx--; else bumpAnim.restart(); list.positionViewAtIndex(root.focusIdx, ListView.Contain) }
                            Keys.onDownPressed: { if (root.focusIdx < root.results.length - 1) root.focusIdx++; else bumpAnim.restart(); list.positionViewAtIndex(root.focusIdx, ListView.Contain) }
                            Keys.onLeftPressed:  root.stepCat(-1)
                            Keys.onRightPressed: root.stepCat(1)
                            Keys.onReturnPressed: root.copyCurrent()
                            Keys.onEnterPressed:  root.copyCurrent()
                            Keys.onDeletePressed: root.deleteCurrent()
                            // a row's number is its key: Alt+1–9 (plain digits filter)
                            Keys.onPressed: (e) => {
                                if (!(e.modifiers & Qt.AltModifier) || e.key < Qt.Key_1 || e.key > Qt.Key_9) return
                                var n = e.key - Qt.Key_1
                                if (n < root.results.length) { root.focusIdx = n; list.positionViewAtIndex(n, ListView.Contain); root.copyCurrent() }
                                e.accepted = true
                            }
                            Text {
                                visible: parent.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: "filter history…"; font.pixelSize: Theme.fs(13); font.italic: true
                                color: Theme.inkSoft; opacity: 0.5
                            }
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                    }
                    ListView {
                        id: list
                        anchors { top: searchRow.bottom; bottom: parent.bottom }
                        width: parent.width
                        clip: true
                        model: root.results
                        keyNavigationEnabled: false
                        boundsBehavior: Flickable.StopAtBounds

                        SpringSelector {
                            id: sel
                            parent: list.contentItem
                            width: list.width; rowH: root.rowH
                            targetY: root.focusIdx * root.rowH + root.bump * 6
                            hitT: root.hitT; flashV: root.flashV; pulse: root.pulse
                            visible: root.results.length > 0
                        }
                        Item { id: burstAnchor; parent: list.contentItem; x: 46; y: sel.targetY + root.rowH / 2 }
                        Connections { target: root; function onFocusIdxChanged() { sel.sheen() } }

                        delegate: Item {
                            id: row
                            width: list.width; height: root.rowH
                            readonly property bool focused: index === root.focusIdx
                            readonly property bool isImg: modelData.kind === "image"
                            Component.onCompleted: if (isImg && index < 40) root.wantThumb(modelData.id)
                            opacity: Math.min(1, root.rowsEnter * 1.6 - Math.min(index, 8) * 0.08)
                            transform: Translate { x: (1 - root.rowsEnter) * 40 * root.catDir }
                            scale: focused ? 1 + 0.04 * root.hitT : 1

                            Rectangle { anchors.bottom: parent.bottom; x: 24; width: parent.width - 48; height: 1; color: Theme.alpha(Theme.ink, 0.12) }
                            Text {
                                x: 14; anchors.verticalCenter: parent.verticalCenter; width: 22
                                text: String(index + 1).padStart(2, "0"); font.pixelSize: Theme.fs(9); font.letterSpacing: 1.5
                                color: row.focused ? Theme.alpha(Theme.paper, 0.5) : Theme.inkSoft
                            }
                            // kind mark: a frame that turns into a diamond when picked; images show a thumbnail
                            Item {
                                x: 40; width: 30; height: 30; anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.centerIn: parent; width: 26; height: 26
                                    rotation: row.focused && !row.isImg ? 45 : 0
                                    scale: row.focused && !row.isImg ? 0.82 : 1
                                    color: "transparent"; border.width: 1
                                    border.color: row.focused ? Theme.alpha(Theme.paper, 0.85) : Theme.ink
                                    Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                                }
                                Image {
                                    anchors.centerIn: parent; width: 24; height: 24
                                    visible: row.isImg && status === Image.Ready
                                    source: row.isImg ? (root.thumbs[modelData.id] || "") : ""
                                    sourceSize: Qt.size(64, 64); fillMode: Image.PreserveAspectCrop
                                    asynchronous: true; cache: false; smooth: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !row.isImg
                                    text: modelData.kind === "link" ? "↗" : "T"
                                    font.pixelSize: Theme.fs(11); font.weight: Font.Medium
                                    color: row.focused ? Theme.paper : Theme.ink
                                }
                            }
                            Column {
                                x: 82; width: parent.width - 100; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                Text {
                                    width: parent.width; elide: Text.ElideRight; maximumLineCount: 1
                                    text: row.isImg ? "IMAGE" : modelData.text.replace(/\s+/g, " ")
                                    font.pixelSize: Theme.fs(12); font.letterSpacing: 0.4
                                    color: row.focused ? Theme.paper : Theme.ink
                                }
                                Text {
                                    text: modelData.meta; font.pixelSize: Theme.fs(9); font.letterSpacing: 1.5
                                    color: row.focused ? Theme.alpha(Theme.paper, 0.5) : Theme.inkSoft
                                }
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true
                                onEntered: if (!root._busy) root.focusIdx = index
                                onClicked: { root.focusIdx = index; root.copyCurrent() }
                            }
                        }
                        Text {
                            visible: root.results.length === 0
                            anchors.centerIn: parent
                            text: root.entries.length === 0 ? "▸ CLIPBOARD IS EMPTY" : "▸ NO MATCHES"
                            font.pixelSize: Theme.fs(10); font.letterSpacing: 3; color: Theme.inkSoft; opacity: 0.6
                        }
                    }
                }
                Rectangle { x: mid.x + mid.width; width: 1; height: parent.height; color: Theme.alpha(Theme.ink, 0.25) }

                // preview
                Item {
                    anchors { left: mid.right; leftMargin: 1; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 0 }
                    Item {
                        anchors { fill: parent; margins: 20 }
                        Text {
                            id: pvHead
                            text: root.cur ? (root.cur.kind.toUpperCase() + "  ·  #" + root.cur.id) : "—"
                            font.pixelSize: Theme.fs(9); font.letterSpacing: 2.5; color: Theme.accent
                        }
                        Rectangle { id: pvRule; anchors.top: pvHead.bottom; anchors.topMargin: 8; width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                        Image {
                            anchors { top: pvRule.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom }
                            visible: root.cur !== null && root.cur.kind === "image"
                            source: visible ? (root.thumbs[root.cur.id] || "") : ""
                            fillMode: Image.PreserveAspectFit; horizontalAlignment: Image.AlignLeft; verticalAlignment: Image.AlignTop
                            asynchronous: true; cache: false; smooth: true; mipmap: true
                            sourceSize.width: 520
                        }
                        Flickable {
                            anchors { top: pvRule.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
                            visible: root.cur !== null && root.cur.kind !== "image"
                            clip: true; contentHeight: pvText.height; boundsBehavior: Flickable.StopAtBounds
                            Text {
                                id: pvText
                                width: parent.width
                                text: root.fullText !== "" ? root.fullText : (root.cur ? root.cur.text : "")
                                wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                font.pixelSize: Theme.fs(12); lineHeight: 1.25; color: Theme.inkStrong
                            }
                        }
                    }
                }
            }

            // ── footer ──
            Item {
                id: footer
                anchors.bottom: parent.bottom; width: parent.width; height: 44
                Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                Row {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    Repeater {
                        model: [["ALT 1–9", "COPY"], ["←→", "TYPE"], ["↑↓", "SELECT"], ["↵", "COPY"], ["DEL", "DELETE"], ["ESC", "CLOSE"]]
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
