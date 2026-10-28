import QtQuick
import Quickshell
import "../components"
import "../services"
import "../theme"

// The task groups menu (SUPER+G · qs ipc call tasks menu): services/TaskGroups.qml's list.
// ↑↓ pick · ↵ open (every screen jumps to it, the focused one at cell 13) · 1–9 open that
// row. A row slides: → shows DELETE under it (→ / ↵ again asks, then closes the group's
// windows), ← shows RENAME (← / ↵ again edits the name in place). + names a new group.
// A window in the preview (or a whole cell of its 5×5) can be dragged onto a group (it lands
// in cell 13), onto NEW GROUP (named, then moved), or — after holding it over a group for a
// moment, which turns the preview to that group — onto one of its cells.
Popup {
    id: root

    readonly property int  lw: 780
    readonly property int  lh: 570
    readonly property real rowH: 58
    readonly property real swipeW: 132

    burst.spreadX: 1.2
    burst.spreadY: 0.7
    Connections { target: TaskGroups; function onMenuRequested() { root.toggle() } }

    // ── state ──
    readonly property var groups: TaskGroups.groups
    readonly property int rowCount: groups.length + 1          // the last row: + NEW GROUP
    property int    focusIdx: 0
    property int    swipe: 0          // 1 = DELETE showing (→), -1 = RENAME showing (←)
    property string editing: ""       // "rename" | "new"
    property bool   asking: false     // the delete confirm
    property bool   askYes: false
    property string notice: ""
    property bool   noticeOk: false
    readonly property bool onNew: focusIdx >= groups.length
    readonly property var  cur: onNew ? null : groups[focusIdx]
    Timer { id: noticeT; interval: 4200; onTriggered: root.notice = "" }
    function say(s, ok) { notice = s; noticeOk = ok === true; noticeT.restart() }

    // ── drag a window (or a cell's windows) onto a group or a cell ──
    property bool   dragging: false
    property var    dragAddrs: []
    property string dragLabel: ""
    property int    dragFromSlot: 0
    property int    dragFromCell: 0
    property int    dropRow: -1          // the group row under it (groups.length = NEW GROUP)
    property int    dropCell: 0          // a cell of the previewed group under it
    property var    frozenWins: []       // the preview's list stays put while one of its rows is carried
    property var    pendingMove: null    // dropped on NEW GROUP: moved once it has a name
    // the ghost starts under the pointer; the MouseArea's drag then moves it along
    function placeGhost(item, mx, my) {
        var p = item.mapToItem(ghost.parent, mx, my)
        ghost.x = p.x - 12; ghost.y = p.y - ghost.height / 2
    }
    function beginDrag(addrs, label, slot, cell) {
        if (!addrs.length || editing !== "" || asking) return
        frozenWins = preview.wins.slice(0, 6)
        dragAddrs = addrs; dragLabel = label; dragFromSlot = slot; dragFromCell = cell
        dropRow = -1; dropCell = 0; swipe = 0
        dragging = true
    }
    function endDrag() {
        if (!dragging) return
        var addrs = dragAddrs, row = dropRow, cell = dropCell
        springT.stop()
        if (cell > 0 && cur) land(addrs, cur.slot, cell)
        else if (row >= 0 && row < groups.length) land(addrs, groups[row].slot, TaskGroups.home)
        else if (row === groups.length) { pendingMove = addrs; focusIdx = row; startNew() }
        dragging = false; dropRow = -1; dropCell = 0
    }
    function cancelDrag() { springT.stop(); dragging = false; dropRow = -1; dropCell = 0 }
    function land(addrs, slot, cell) {
        if (slot === dragFromSlot && cell === dragFromCell) { bumpAnim.restart(); return }
        TaskGroups.moveWindows(addrs, slot, cell)
        root.burst.playAt(ghost, 12, ghost.height / 2, 0.9)
        say((addrs.length > 1 ? addrs.length + " 個視窗" : "視窗") + "移到 " + TaskGroups.label(slot) + " 的第 " + cell + " 格", true)
    }
    // held over a group for a moment: the preview turns to it, so a cell can take the drop
    Timer {
        id: springT; interval: 450
        onTriggered: if (root.dragging && root.dropRow >= 0 && root.dropRow < root.groups.length) root.focusIdx = root.dropRow
    }
    onDropRowChanged: if (dragging) springT.restart()

    function pick(i) {
        i = Math.max(0, Math.min(rowCount - 1, i))
        if (i === focusIdx) { bumpAnim.restart(); return }
        focusIdx = i; swipe = 0
        list.positionViewAtIndex(i, ListView.Contain)
    }

    // ── the one confirm: hit-stop, burst, then the action ──
    property real hitT: 0
    property real flashV: 0
    property bool _busy: false
    property var  _after: null
    SequentialAnimation {
        id: confirmAnim
        ScriptAction { script: { root.flashV = 1; root.burst.playAt(burstAnchor, 0, 0, 1) } }
        ParallelAnimation {
            NumberAnimation { target: root; property: "flashV"; to: 0; duration: 420; easing.type: Easing.OutQuad }
            SequentialAnimation {
                NumberAnimation { target: root; property: "hitT"; from: 0; to: 1; duration: 45; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 65 }
                ScriptAction { script: { var f = root._after; root._after = null; if (f) f() } }
                NumberAnimation { target: root; property: "hitT"; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }
        }
        onFinished: root._busy = false
    }
    function confirm(f) { if (_busy) return; _busy = true; _after = f; confirmAnim.restart() }

    function openCurrent() {
        if (onNew) { startNew(); return }
        var slot = cur.slot
        confirm(function() { TaskGroups.go(slot); root.close() })
    }
    function openNumber(n) { if (n <= groups.length) { focusIdx = n - 1; swipe = 0; openCurrent() } }

    // ── slide → delete ──
    function swipeRight() {
        if (onNew) { bumpAnim.restart(); return }
        if (swipe < 0) { swipe = 0; return }
        if (swipe === 0) {
            if (groups.length < 2) { shake(); say("至少要留一個任務組。"); return }
            swipe = 1; return
        }
        askDelete()
    }
    function askDelete() { askYes = false; asking = true }
    function answer(yes) {
        asking = false
        if (!yes) { swipe = 0; return }
        var slot = cur.slot, n = TaskGroups.windowsIn(slot).length
        confirm(function() {
            if (!TaskGroups.remove(slot)) { root.say("刪不了：至少要留一個任務組。"); return }
            if (n > 0) root.say("正在關閉 " + n + " 個視窗…")
        })
    }
    Connections {
        target: TaskGroups
        function onRemoveDone(slot, left) {
            root.swipe = 0
            if (left > 0) root.say(left + " 個視窗沒有關（可能在問你要不要存檔），這組先留著。")
            else { root.say(""); root.focusIdx = Math.min(root.focusIdx, root.groups.length - 1) }
        }
    }

    // ── slide ← rename, + new ──
    function swipeLeft() {
        if (onNew) { bumpAnim.restart(); return }
        if (swipe > 0) { swipe = 0; return }
        if (swipe === 0) { swipe = -1; return }
        startRename()
    }
    function startRename() {
        if (onNew) return
        editing = "rename"; swipe = 0
        nameEdit.text = cur.name
        nameEdit.selectAll()
        nameEdit.forceActiveFocus()
    }
    function startNew() {
        editing = "new"; swipe = 0
        nameEdit.text = ""
        nameEdit.forceActiveFocus()
    }
    function commitEdit() {
        var name = nameEdit.text.trim()
        if (name === "") { shake(); return }
        if (editing === "rename") TaskGroups.rename(cur.slot, name)
        else {
            var slot = TaskGroups.add(name)
            focusIdx = TaskGroups.indexOf(slot)
            list.positionViewAtIndex(focusIdx, ListView.Contain)
            Qt.callLater(function() { root.burst.playAt(burstAnchor, 0, 0, 0.8) })
            if (pendingMove) {
                TaskGroups.moveWindows(pendingMove, slot, TaskGroups.home)
                say((pendingMove.length > 1 ? pendingMove.length + " 個視窗" : "視窗") + "移到新的 " + TaskGroups.label(slot), true)
                pendingMove = null
            }
        }
        editing = ""
        keys.forceActiveFocus()
    }
    function cancelEdit() { editing = ""; pendingMove = null; keys.forceActiveFocus() }

    property real bump: 0
    SequentialAnimation {
        id: bumpAnim
        NumberAnimation { target: root; property: "bump"; from: 0; to: 1; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "bump"; to: 0; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }
    property real shakeX: 0
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: -8; duration: 45 }
        NumberAnimation { target: root; property: "shakeX"; to: 7; duration: 60 }
        NumberAnimation { target: root; property: "shakeX"; to: -4; duration: 55 }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: 90; easing.type: Easing.OutBack }
    }
    function shake() { shakeAnim.restart() }
    property real rowsEnter: 1
    NumberAnimation { id: rowsIn; target: root; property: "rowsEnter"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }

    // ── lifecycle (components/Popup.qml) ──
    onOpening: {
        focusIdx = Math.max(0, TaskGroups.indexOf(TaskGroups.currentSlot))
        swipe = 0; editing = ""; asking = false; notice = ""; _busy = false
        dragging = false; pendingMove = null
    }
    onIntro:    { host.reveal(); keys.forceActiveFocus() }
    onOutro:    host.conceal()
    onFinished: host.reset()

    IrisHost {
        id: host
        x: (root.screenW - root.lw) / 2 + root.shakeX
        y: (root.screenH - root.lh) / 2
        width: root.lw; height: root.lh
        visible: root.shown || root.warming
        forceLayer: root.warming
        onMidReveal: rowsIn.restart()
        onConcealed: root.panelGone()

        // the keys (the name field takes them while editing)
        Item {
            id: keys
            anchors.fill: parent
            focus: root.isOpen && root.editing === ""
            Keys.onPressed: (e) => {
                var k = e.key
                e.accepted = true
                if (root.asking) {
                    if (k === Qt.Key_Escape || k === Qt.Key_N) root.answer(false)
                    else if (k === Qt.Key_Y) root.answer(true)
                    else if (k === Qt.Key_Left) root.askYes = true
                    else if (k === Qt.Key_Right) root.askYes = false
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.answer(root.askYes)
                    return
                }
                if (root.dragging) { if (k === Qt.Key_Escape) root.cancelDrag(); return }
                if (k === Qt.Key_Escape) { if (root.swipe !== 0) root.swipe = 0; else root.close() }
                else if (k === Qt.Key_Up)    root.pick(root.focusIdx - 1)
                else if (k === Qt.Key_Down)  root.pick(root.focusIdx + 1)
                else if (k === Qt.Key_Right) root.swipeRight()
                else if (k === Qt.Key_Left)  root.swipeLeft()
                else if (k === Qt.Key_Delete) { if (root.swipe === 1) root.askDelete(); else root.swipeRight() }
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                    if (root.swipe === 1) root.askDelete()
                    else if (root.swipe === -1) root.startRename()
                    else root.openCurrent()
                }
                else if (k === Qt.Key_Plus || k === Qt.Key_Equal) root.startNew()
                else if (k >= Qt.Key_1 && k <= Qt.Key_9) root.openNumber(k - Qt.Key_0)
                else e.accepted = false
            }
        }

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
                    Text { text: "TASK GROUPS"; font.pixelSize: Theme.ts(2); font.letterSpacing: 3.5; font.weight: Font.Medium; color: Theme.inkStrong }
                    Rectangle { width: 24; height: 1; color: Theme.inkSoft; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: "タスク"; font.pixelSize: Theme.ts(1); font.letterSpacing: 2; color: Theme.inkSoft }
                }
                Row {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 12
                    Text {
                        text: root.groups.length + " GROUPS  ·  NOW " + TaskGroups.label(TaskGroups.currentSlot)
                        font.pixelSize: Theme.ts(1); font.letterSpacing: 2; color: Theme.inkSoft
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item {
                        width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { anchors.centerIn: parent; width: 7; height: 7; rotation: 45; color: Theme.accent; scale: 1 + 0.45 * root.pulse }
                    }
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
            }

            // ── the list ──
            Item {
                id: mid
                anchors { top: header.bottom; bottom: footer.top; left: parent.left }
                width: 420
                ListView {
                    id: list
                    anchors { fill: parent; topMargin: 10; bottomMargin: 10 }
                    clip: true
                    model: root.rowCount
                    keyNavigationEnabled: false
                    boundsBehavior: Flickable.StopAtBounds

                    // the selector rides the row when it slides
                    SpringSelector {
                        id: sel
                        parent: list.contentItem
                        width: list.width; rowH: root.rowH
                        x: root.swipe * root.swipeW
                        Behavior on x { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.25 } }
                        targetY: root.focusIdx * root.rowH + root.bump * 6
                        hitT: root.hitT; flashV: root.flashV; pulse: root.pulse
                        edge: root.swipe > 0 ? Theme.warn : Theme.accent
                    }
                    Item { id: burstAnchor; parent: list.contentItem; x: 44 + sel.x; y: sel.targetY + root.rowH / 2 }
                    Connections { target: root; function onFocusIdxChanged() { sel.sheen() } }

                    delegate: Item {
                        id: row
                        required property int index
                        width: list.width; height: root.rowH
                        readonly property bool isNew: index >= root.groups.length
                        readonly property var  g: isNew ? null : root.groups[index]
                        readonly property bool focused: index === root.focusIdx
                        readonly property bool isCurrent: !isNew && g.slot === TaskGroups.currentSlot
                        readonly property var  occ: isNew ? [] : TaskGroups.occupancy(g.slot)
                        readonly property int  wins: { var n = 0; for (var i = 0; i < occ.length; i++) n += occ[i]; return n }
                        readonly property real slide: focused ? root.swipe * root.swipeW : 0
                        opacity: Math.min(1, root.rowsEnter * 1.6 - Math.min(index, 8) * 0.08)
                        transform: Translate { x: (1 - root.rowsEnter) * 40 }

                        // what the slide uncovers: DELETE on the left, RENAME on the right
                        Rectangle {
                            visible: row.focused && root.swipe > 0
                            width: root.swipeW; height: parent.height; color: Theme.warn
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Text { text: "✕"; color: Theme.paper; font.pixelSize: Theme.ts(2); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "DELETE"; color: Theme.paper; font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                        Rectangle {
                            visible: row.focused && root.swipe < 0
                            anchors.right: parent.right
                            width: root.swipeW; height: parent.height; color: Theme.accent
                            Row {
                                anchors.centerIn: parent; spacing: 8
                                Text { text: "✎"; color: Theme.paper; font.pixelSize: Theme.ts(2); anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "RENAME"; color: Theme.paper; font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }

                        // the face
                        Item {
                            id: face
                            width: parent.width; height: parent.height
                            x: row.slide
                            Behavior on x { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.25 } }
                            scale: row.focused ? 1 + 0.04 * root.hitT : 1
                            readonly property color fg: row.focused ? Theme.paper : Theme.ink
                            readonly property color dim: row.focused ? Theme.alpha(Theme.paper, 0.55) : Theme.inkSoft

                            Rectangle { anchors.bottom: parent.bottom; x: 24; width: parent.width - 48; height: 1; color: Theme.alpha(Theme.ink, 0.12); visible: !row.focused }
                            Text {
                                x: 22; anchors.verticalCenter: parent.verticalCenter; width: 26
                                text: row.isNew ? "＋" : String(row.index + 1).padStart(2, "0")
                                font.pixelSize: Theme.ts(row.isNew ? 3 : 2); font.letterSpacing: 1.5
                                color: row.isNew ? (row.focused ? Theme.paper : Theme.accent) : face.dim
                            }
                            Column {
                                x: 62; width: parent.width - 62 - 96; anchors.verticalCenter: parent.verticalCenter; spacing: 3
                                Row {
                                    spacing: 9
                                    Text {
                                        visible: !(row.focused && root.editing === "rename")
                                        width: Math.min(implicitWidth, 230); elide: Text.ElideRight
                                        text: row.isNew ? "NEW GROUP" : row.g.name
                                        font.pixelSize: Theme.ts(row.isNew ? 2 : 3); font.letterSpacing: row.isNew ? 2.5 : 0.5
                                        color: face.fg
                                    }
                                    Rectangle {   // you are here
                                        visible: row.isCurrent && !(row.focused && root.editing === "rename")
                                        width: 6; height: 6; rotation: 45; antialiasing: true
                                        color: row.focused ? Theme.paper : Theme.accent
                                        anchors.verticalCenter: parent.verticalCenter
                                        scale: 1 + 0.3 * root.pulse
                                    }
                                }
                                Text {
                                    text: row.isNew ? "按 + 或 ↵，取個名字" : (row.wins === 0 ? "EMPTY" : row.wins + " WIN")
                                          + (row.isCurrent ? "  ·  NOW" : "")
                                    font.family: row.isNew ? Theme.cjk : Theme.mono
                                    font.pixelSize: Theme.ts(1); font.letterSpacing: row.isNew ? 0.5 : 1.5; color: face.dim
                                }
                            }
                            // the group's 5×5, in small (21–25 on top, like the HUD)
                            Grid {
                                visible: !row.isNew
                                anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                                columns: 5; spacing: 2
                                Repeater {
                                    model: 25
                                    Rectangle {
                                        required property int index
                                        readonly property int cell: (4 - Math.floor(index / 5)) * 5 + (index % 5) + 1
                                        readonly property bool has: (row.occ[cell - 1] || 0) > 0
                                        width: 5; height: 5
                                        color: has ? face.fg : "transparent"
                                        border.width: has ? 0 : 1
                                        border.color: cell === TaskGroups.home ? (row.focused ? Theme.alpha(Theme.paper, 0.7) : Theme.accent)
                                                                               : Theme.alpha(face.fg, 0.25)
                                    }
                                }
                            }
                        }

                        // a carried window over this row: it would land here (cell 13; NEW: a new group)
                        Rectangle {
                            anchors { fill: parent; margins: 3 }
                            visible: root.dragging && root.dropRow === row.index
                            color: Theme.alpha(Theme.accent, 0.08)
                            border.color: Theme.accent; border.width: 1.5
                            Text {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: row.isNew ? "＋ NEW" : "→ CELL 13"
                                font.pixelSize: Theme.ts(0); font.letterSpacing: 2; color: Theme.accent
                            }
                        }
                        DropArea {
                            anchors.fill: parent; keys: ["qs-window"]
                            onEntered: root.dropRow = row.index
                            onExited: if (root.dropRow === row.index) root.dropRow = -1
                        }

                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            onEntered: if (!root._busy && !root.asking && root.editing === "" && root.swipe === 0 && !root.dragging) root.focusIdx = row.index
                            onClicked: {
                                if (root.asking || root.editing !== "") return
                                root.focusIdx = row.index
                                if (root.swipe > 0 && mouseX < root.swipeW) root.askDelete()
                                else if (root.swipe < 0 && mouseX > width - root.swipeW) root.startRename()
                                else root.openCurrent()
                            }
                        }
                    }
                }
            }
            Rectangle { x: mid.width; y: header.height; width: 1; height: mid.height; color: Theme.alpha(Theme.ink, 0.25) }

            // ── the picked group: its 5×5 and its windows ──
            Item {
                id: preview
                anchors { top: header.bottom; bottom: footer.top; left: mid.right; leftMargin: 1; right: parent.right }
                readonly property var g: root.cur
                readonly property var occ: g ? TaskGroups.occupancy(g.slot) : []
                readonly property var wins: g ? TaskGroups.windowsIn(g.slot) : []
                Column {
                    anchors { fill: parent; margins: 24 }
                    spacing: 12
                    Text {
                        text: preview.g ? "GROUP " + String(root.focusIdx + 1).padStart(2, "0") + (preview.g.slot === TaskGroups.currentSlot ? "  ·  NOW" : "") : "NEW GROUP"
                        font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5; color: Theme.accent
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: preview.g ? preview.g.name : "＋"
                        font.pixelSize: Theme.ts(5); color: Theme.inkStrong
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                    // the 5×5: windows filled, cell 13 (where it opens) marked
                    Grid {
                        visible: preview.g !== null
                        columns: 5; spacing: 4
                        Repeater {
                            model: 25
                            Rectangle {
                                id: pcell
                                required property int index
                                readonly property int cell: (4 - Math.floor(index / 5)) * 5 + (index % 5) + 1
                                readonly property int n: preview.occ[cell - 1] || 0
                                readonly property bool target: root.dragging && root.dropCell === cell
                                width: 52; height: 26
                                color: target ? Theme.accent : n > 0 ? Theme.ink : "transparent"
                                border.width: target ? 1.5 : 1
                                border.color: target ? Theme.accent : cell === TaskGroups.home ? Theme.accent : Theme.alpha(Theme.ink, n > 0 ? 1 : 0.2)
                                scale: target ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.n > 0 ? parent.cell + (parent.n > 1 ? "·" + parent.n : "")
                                        : root.dragging ? parent.cell : (parent.cell === TaskGroups.home ? "◇" : "")
                                    font.pixelSize: Theme.ts(0); font.letterSpacing: 1
                                    color: parent.target || parent.n > 0 ? Theme.paper : Theme.accent
                                    opacity: parent.n > 0 || parent.target || parent.cell === TaskGroups.home ? 1 : 0.5
                                }
                                DropArea {
                                    anchors.fill: parent; keys: ["qs-window"]
                                    onEntered: root.dropCell = pcell.cell
                                    onExited: if (root.dropCell === pcell.cell) root.dropCell = 0
                                }
                                // a whole cell can be carried too
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: pcell.n > 0 || root.dragging
                                    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    drag.target: ghost; drag.threshold: 6
                                    onPressed: (m) => root.placeGhost(pcell, m.x, m.y)
                                    drag.onActiveChanged: {
                                        if (drag.active) {
                                            var ws = preview.wins.filter(function(w) { return w.cell === pcell.cell })
                                            root.beginDrag(ws.map(function(w) { return w.address }),
                                                           "CELL " + String(pcell.cell).padStart(2, "0") + "  ·  " + ws.length + " WIN",
                                                           preview.g.slot, pcell.cell)
                                        } else root.endDrag()
                                    }
                                }
                            }
                        }
                    }
                    Column {
                        width: parent.width; spacing: 3
                        visible: preview.g !== null
                        Text {
                            visible: preview.wins.length > 0 || root.dragging
                            width: parent.width; elide: Text.ElideRight
                            text: root.dragging ? "放到格子上；放到左邊的任務組會進第 13 格，按住停一下會打開它"
                                                : "拖曳視窗（或上面的格子）到別的任務組"
                            font.family: Theme.cjk; font.pixelSize: Theme.ts(0); color: root.dragging ? Theme.accent : Theme.inkSoft
                            bottomPadding: 2
                        }
                        Repeater {
                            model: root.dragging ? root.frozenWins : preview.wins.slice(0, 6)
                            Item {
                                id: wrow
                                required property var modelData
                                width: parent.width; height: 22
                                opacity: root.dragging ? 0.35 : 1
                                Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.ink, 0.08); visible: wma.containsMouse && !root.dragging }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter; spacing: 8
                                    Rectangle {
                                        width: 6; height: 6; rotation: 45; antialiasing: true; anchors.verticalCenter: parent.verticalCenter
                                        color: wma.containsMouse ? Theme.accent : "transparent"; border.color: Theme.accent; border.width: 1
                                    }
                                    Text { text: String(wrow.modelData.cell).padStart(2, "0"); width: 18; font.pixelSize: Theme.ts(1); color: Theme.accent }
                                    Text { text: wrow.modelData.cls; width: 70; elide: Text.ElideRight; font.pixelSize: Theme.ts(1); color: Theme.ink }
                                    Text { text: wrow.modelData.title; width: wrow.width - 118; elide: Text.ElideRight; font.pixelSize: Theme.ts(1); color: Theme.inkSoft }
                                }
                                MouseArea {
                                    id: wma
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                    drag.target: ghost; drag.threshold: 6
                                    onPressed: (m) => root.placeGhost(wrow, m.x, m.y)
                                    drag.onActiveChanged: {
                                        if (drag.active) root.beginDrag([wrow.modelData.address], wrow.modelData.cls + "  ·  " + wrow.modelData.title,
                                                                        root.cur ? root.cur.slot : 0, wrow.modelData.cell)
                                        else root.endDrag()
                                    }
                                }
                            }
                        }
                        Text {
                            visible: preview.wins.length > 6 && !root.dragging
                            text: "+ " + (preview.wins.length - 6) + " MORE"
                            font.pixelSize: Theme.ts(0); font.letterSpacing: 2; color: Theme.inkSoft
                        }
                        Text {
                            visible: preview.wins.length === 0 && !root.dragging
                            width: parent.width; wrapMode: Text.WordWrap
                            text: "還沒有視窗。打開它會先到第 13 格（◇）。"
                            font.family: Theme.cjk; font.pixelSize: Theme.ts(1); color: Theme.inkSoft
                        }
                    }
                    Text {
                        visible: preview.g === null
                        width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.3
                        text: "一個任務組有 25 格（HUD 的 5×5），打開時兩個螢幕會一起切過去，目前的螢幕停在第 13 格。\nSUPER + 數字直接跳到第幾組。"
                        font.family: Theme.cjk; font.pixelSize: Theme.ts(1); color: Theme.inkSoft
                    }
                }
            }

            // ── footer: what the keys do now (or a notice) ──
            Item {
                id: footer
                anchors.bottom: parent.bottom; width: parent.width; height: 44
                Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.25) }
                Text {
                    visible: root.notice !== ""
                    anchors { left: parent.left; leftMargin: 28; verticalCenter: parent.verticalCenter }
                    text: root.notice; font.family: Theme.cjk; font.pixelSize: Theme.ts(1); color: root.noticeOk ? Theme.accent : Theme.warn
                }
                Row {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    Repeater {
                        model: root.dragging ? [["DROP", "GROUP → CELL 13"], ["HOLD", "OPEN IT"], ["ESC", "CANCEL"]]
                             : root.editing !== "" ? [["↵", root.editing === "new" ? "CREATE" : "SAVE"], ["ESC", "CANCEL"]]
                             : root.asking ? [["←→", "SELECT"], ["↵", "CONFIRM"], ["ESC", "CANCEL"]]
                             : root.swipe > 0 ? [["→ / ↵", "DELETE…"], ["←", "BACK"]]
                             : root.swipe < 0 ? [["← / ↵", "RENAME"], ["→", "BACK"]]
                             : [["↑↓", "SELECT"], ["1–9", "OPEN"], ["↵", "OPEN"], ["←", "RENAME"], ["→", "DELETE"], ["+", "NEW"], ["ESC", "CLOSE"]]
                        Row {
                            required property var modelData
                            spacing: 5; anchors.verticalCenter: parent.verticalCenter
                            Rectangle {
                                width: kT.implicitWidth + 8; height: 16; color: "transparent"
                                border.color: Theme.alpha(Theme.ink, 0.3); border.width: 1
                                anchors.verticalCenter: parent.verticalCenter
                                Text { id: kT; anchors.centerIn: parent; text: modelData[0]; font.pixelSize: Theme.ts(0); font.letterSpacing: 1; color: Theme.ink }
                            }
                            Text { text: modelData[1]; font.pixelSize: Theme.ts(1); font.letterSpacing: 2; color: Theme.inkSoft; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }

            // ── what's being carried: an ink chip with the accent edge, under the pointer ──
            Item {
                id: ghost
                z: 60
                width: Math.min(300, ghostRow.implicitWidth + 30); height: 30
                visible: root.dragging
                Drag.active: root.dragging
                Drag.keys: ["qs-window"]
                Drag.hotSpot.x: 12
                Drag.hotSpot.y: height / 2
                scale: root.dragging ? 1 : 0.85
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                Rectangle { anchors.fill: parent; color: Theme.ink; opacity: 0.94 }
                Rectangle { width: 3; height: parent.height; color: Theme.accent }
                Row {
                    id: ghostRow
                    x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Rectangle { width: 6; height: 6; rotation: 45; antialiasing: true; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter; scale: 1 + 0.3 * root.pulse }
                    Text { width: Math.min(implicitWidth, 250); elide: Text.ElideRight; text: root.dragLabel; font.pixelSize: Theme.ts(1); color: Theme.paper }
                }
            }

            // ── the name field: in the row (rename) or on its own card (new) ──
            Rectangle {
                id: newDim
                anchors.fill: parent; z: 40
                color: Theme.paper
                opacity: root.editing === "new" || root.asking ? 0.6 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 180 } }
                MouseArea { anchors.fill: parent; enabled: parent.visible; onClicked: { if (root.asking) root.answer(false); else root.cancelEdit() } }
            }
            Item {
                id: nameCard
                z: 41
                readonly property bool isNew: root.editing === "new"
                width: isNew ? 440 : 292; height: isNew ? 150 : root.rowH - 18
                x: isNew ? (parent.width - width) / 2 : 62
                y: isNew ? (parent.height - height) / 2 : header.height + list.y + root.focusIdx * root.rowH - list.contentY + 9
                visible: root.editing !== ""
                opacity: visible ? 1 : 0
                scale: isNew ? (visible ? 1 : 0.94) : 1
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                PaperCard { anchors.fill: parent; t: root.t; grid: nameCard.isNew; visible: nameCard.isNew }
                Rectangle { anchors.fill: parent; visible: !nameCard.isNew; color: Theme.paper; border.color: Theme.accent; border.width: 1 }
                Column {
                    visible: nameCard.isNew
                    x: 24; y: 20; width: parent.width - 48; spacing: 8
                    Text { text: "NEW TASK GROUP  ·  " + String(root.groups.length + 1).padStart(2, "0"); font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5; color: Theme.accent }
                    Rectangle { width: 36; height: 1; color: Theme.ink; opacity: 0.5 }
                }
                TextInput {
                    id: nameEdit
                    x: nameCard.isNew ? 24 : 10
                    y: nameCard.isNew ? 62 : 0
                    width: parent.width - 2 * x
                    height: nameCard.isNew ? 40 : parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Theme.ts(nameCard.isNew ? 4 : 3); color: Theme.inkStrong
                    selectionColor: Theme.ink; selectedTextColor: Theme.paper
                    maximumLength: 32
                    cursorVisible: activeFocus
                    selectByMouse: true
                    Keys.onReturnPressed: root.commitEdit()
                    Keys.onEnterPressed:  root.commitEdit()
                    Keys.onEscapePressed: root.cancelEdit()
                    Text {
                        visible: parent.text === "" && !parent.inputMethodComposing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "名字…"; font.family: Theme.cjk; font.pixelSize: parent.font.pixelSize
                        color: Theme.inkSoft; opacity: 0.5
                    }
                    Rectangle { visible: nameCard.isNew; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.ink }
                }
                Text {
                    visible: nameCard.isNew
                    anchors { right: parent.right; rightMargin: 24; bottom: parent.bottom; bottomMargin: 14 }
                    text: "↵ CREATE  ·  ESC CANCEL"; font.pixelSize: Theme.ts(0); font.letterSpacing: 2; color: Theme.inkSoft
                }
            }

            // ── delete? (YES / NO, NO first) ──
            Item {
                id: askCard
                z: 42
                width: 460; height: askCol.implicitHeight + 44
                anchors.centerIn: parent
                visible: root.asking
                scale: root.asking ? 1 : 0.94
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                PaperCard { anchors.fill: parent; t: root.t; grid: false }
                Column {
                    id: askCol
                    x: 24; y: 22; width: parent.width - 48; spacing: 0
                    Row {
                        spacing: 8
                        Rectangle { width: 6; height: 6; rotation: 45; color: Theme.warn; anchors.verticalCenter: parent.verticalCenter; scale: 1 + 0.35 * root.pulse }
                        Text { text: "DELETE GROUP"; font.pixelSize: Theme.ts(2); font.letterSpacing: 5; font.weight: Font.Medium; color: Theme.ink; opacity: 0.6 }
                    }
                    Item { width: 1; height: 12 }
                    Text { width: parent.width; elide: Text.ElideRight; text: root.cur ? String(root.focusIdx + 1).padStart(2, "0") + "  " + root.cur.name : ""; font.pixelSize: Theme.ts(5); color: Theme.inkStrong }
                    Item { width: 1; height: 8 }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap; lineHeight: 1.2
                        readonly property int n: root.cur ? TaskGroups.windowsIn(root.cur.slot).length : 0
                        text: n > 0 ? "會關閉這組的 " + n + " 個視窗。還沒存檔的程式可能會先問你。" : "這組沒有視窗，直接刪除。"
                        font.family: Theme.cjk; font.pixelSize: Theme.ts(2); color: Theme.inkSoft
                    }
                    Item { width: 1; height: 18 }
                    Row {
                        spacing: 16
                        Repeater {
                            model: [true, false]
                            Item {
                                required property bool modelData
                                readonly property bool on: root.askYes === modelData
                                width: (askCol.width - 16) / 2; height: 36
                                Rectangle { anchors.fill: parent; color: parent.on ? Theme.ink : "transparent"; border.color: Theme.ink; border.width: 1 }
                                Rectangle { visible: parent.on; width: 3; height: parent.height; color: modelData ? Theme.warn : Theme.accent }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData ? "YES · DELETE" : "NO"
                                    font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5
                                    color: parent.on ? Theme.paper : Theme.ink
                                }
                                MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: root.answer(modelData) }
                            }
                        }
                    }
                }
            }
        }
    }
}
