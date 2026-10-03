import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../services"
import "../settings"
import "../theme"

// Input-method candidate window drawn by the shell. scripts/imepanel.py speaks the
// kimpanel protocol to fcitx5 (which prefers it over its own classic window while it
// runs, and falls back to it when it doesn't) and streams the panel state here as
// JSON lines; picks and page flips go back on its stdin.
//
// Looks like the popups: a paper card, an ink selector springing between the
// candidates with two afterimages, diamond corners; pages slide in the way they
// flipped; a pick throws the HitBurst on the candidate. The effects on the text itself
// (the burst when a phrase lands or Enter is pressed, sparks while composing) go through
// the shared layer, components/Fx.qml. The caret comes from the imecaret plugin; sparks rise from
// the text cursor (fcitx5 reports its position as it moves).
Scope {
    id: root

    readonly property color paper:     Theme.paper
    readonly property color ink:       Theme.ink
    readonly property color inkStrong: Theme.inkStrong
    readonly property color inkSoft:   Theme.inkSoft
    readonly property color accent:    Theme.accent
    readonly property color light:     Theme.light
    readonly property string candFont: Theme.cjk   // [font] cjk in the theme
    function paperA(a) { return Theme.alpha(Theme.paper, a) }

    // ── panel state (from the bridge) ──
    property bool   enabled:    false
    property bool   tableShown: false
    property var    labels:     []
    property var    cands:      []
    property int    cursor:     -1
    property bool   hasPrev:    false
    property bool   hasNext:    false
    property int    layoutHint: 0            // 0 unset · 1 vertical · 2 horizontal
    property bool   auxShown:   false
    property string auxText:    ""
    property bool   preShown:   false
    property string preText:    ""
    property int    preCaret:   0
    // text cursor, in monitor `mon`'s layout px (mw = that monitor's layout width)
    property string mon: ""
    property real   mw: 1920
    property real   sx: 0
    property real   sy: 0
    property real   sh: 20

    readonly property bool hasTable: tableShown && cands.length > 0
    readonly property bool hasLine:  (auxShown && auxText !== "") || (preShown && preText !== "")
    readonly property bool up:       hasTable || hasLine
    readonly property bool vertical: layoutHint === 1

    // a new page slides in from pageDir; pageSerial restarts the item entrance
    property int pageDir: 1
    property int pageSerial: 0
    signal picked(int index)          // → the burst, in the window showing the table
    property double _pickedAt: 0
    onPicked: _pickedAt = Date.now()

    // ── bridge ──
    Process {
        id: bridge
        command: ["python3", Qt.resolvedUrl("../scripts/imepanel.py").toString().replace("file://", "")]
        running: Settings.imePanelEnabled
        stdinEnabled: true
        stdout: SplitParser { onRead: (line) => root.handle(line) }
        // keep a panel registered; fcitx5 uses its own window in the meantime
        onRunningChanged: if (!running && Settings.imePanelEnabled) restartT.restart()
    }
    Timer { id: restartT; interval: 3000; onTriggered: bridge.running = true }
    function send(cmd) { if (bridge.running) bridge.write(cmd + "\n") }

    function pick(i) { picked(i); send("select " + i) }
    function flip(d) { pageDir = d; send(d > 0 ? "next" : "prev") }

    function sameList(a, b) {
        if (a.length !== b.length) return false
        for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
        return true
    }

    function handle(line) {
        var m
        try { m = JSON.parse(line) } catch (e) { return }
        switch (m.t) {
        case "enable":  enabled = m.on; break
        case "im":      Ime.name = m.name; Ime.label = m.label; if (!m.first) Ime.switched(); break
        case "table":
            tableShown = m.show
            break
        case "cands":
            // fcitx5 empties the list before hiding it: that's the pick (or Esc) —
            // burst on the highlighted candidate while its item still exists
            if (m.cands.length === 0 && tableShown && cands.length && cursor >= 0) picked(cursor)
            if (!sameList(m.cands, cands)) {
                // page direction from the prev/next flags when the keyboard flipped it
                if (tableShown && cands.length) {
                    if ((!hasPrev && m.prev) || (hasNext && !m.next)) pageDir = 1
                    else if ((hasPrev && !m.prev) || (!hasNext && m.next)) pageDir = -1
                }
                labels = m.labels; cands = m.cands
                pageSerial++
            }
            hasPrev = m.prev; hasNext = m.next; layoutHint = m.layout
            cursor = m.cursor
            break
        case "cursor":   cursor = m.i; break
        case "aux":      auxShown = m.show; break
        case "auxText":  auxText = m.text; break
        case "pre":      preShown = m.show; break
        case "preText":  preText = m.text; break
        case "preCaret": preCaret = m.i; break
        case "spot":
            mon = m.mon; mw = m.mw; sx = m.x; sy = m.y; sh = m.h > 0 ? m.h : 20
            break
        // from the imecaret plugin's events (see scripts/imepanel.py)
        // the effects on the text itself go through the shared layer (components/Fx.qml)
        case "spark":       // the preedit changed; the caret after it
            if (Settings.imeSparks) Fx.sparksOn(m.mon, m.x, m.y + m.h / 2)
            break
        case "commit": {    // text landed (Enter on the phrase…): burst on it — unless a
                            // candidate pick just threw its own. The caret is at the end of
                            // the phrase; CJK glyphs are about as wide as the line is tall,
                            // so its middle is ~n·h/2 back.
            if (Date.now() - _pickedAt <= 250) break
            var ch = m.h > 0 ? m.h : 20
            Fx.burstOn(m.mon, Math.max(4, m.x - Math.min(m.n, 12) * ch * 0.45), m.y + ch / 2, 0.55 + 0.1 * Math.min(m.n, 4))
            break
        }
        case "enter": {     // Enter with nothing to commit (English, or an empty buffer)
            if (Date.now() - _pickedAt <= 250) break
            var eh = m.h > 0 ? m.h : 20
            Fx.burstOn(m.mon, Math.max(4, m.x), m.y + eh / 2, 0.5)
            break
        }
        }
    }

    Variants {
        model: Settings.imePanelEnabled ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool mine: modelData.name === root.mon
            // mapped while there's a panel, or its pick burst is still flying
            property bool hold: false
            Timer { id: holdT; interval: 700; onTriggered: win.hold = false }
            function keep() { hold = true; holdT.restart() }
            visible: mine && (root.up || hold)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            // only the card takes the pointer; everything else passes through
            mask: Region { item: root.up ? box : null }

            // layout px → this window's units (QT_SCALE_FACTOR). From the screen, not the
            // window: a freshly mapped window is 0×0 for a moment, and a burst placed
            // then would land in the corner
            readonly property real k: modelData.width / Math.max(1, root.mw)
            readonly property real caretX: root.sx * k
            readonly property real caretY: root.sy * k
            readonly property real caretH: Math.max(14, root.sh * k)

            onVisibleChanged: if (visible && root.up) appear.restart()
            Connections {
                target: root
                function onUpChanged() { if (!root.up && win.mine) win.keep(); else if (root.up && win.visible) appear.restart() }
                function onPicked(i) {
                    if (!win.mine) return
                    var it = candRep.itemAt(i)
                    if (it) { burst.playAt(it, it.width / 2, it.height / 2, 0.8); win.keep() }
                }
            }

            // ── the card ──
            Item {
                id: box
                // below the caret; above it when there's no room
                readonly property real below: win.caretY + win.caretH + 6
                x: Math.max(8, Math.min(win.caretX - 14, win.width - width - 8))
                y: below + height + 8 <= win.height ? below : win.caretY - height - 6
                width:  Math.max(60, body.implicitWidth + 20)
                height: body.implicitHeight + 16
                opacity: root.up ? appearT : 0
                Behavior on opacity { enabled: !root.up; NumberAnimation { duration: 90 } }
                property real appearT: 1
                transform: Translate { y: (1 - box.appearT) * -5 }
                NumberAnimation { id: appear; target: box; property: "appearT"; from: 0.35; to: 1; duration: 130; easing.type: Easing.OutCubic }

                Rectangle {
                    anchors.fill: parent
                    color: root.paper
                    border.color: root.ink; border.width: 1
                }
                Rectangle {   // inner offset frame (the popups' card)
                    anchors.fill: parent; anchors.margins: 3
                    color: "transparent"; border.color: root.ink; border.width: 1; opacity: 0.28
                }
                Rectangle {   // glass rim
                    x: 1; y: 1; width: parent.width - 2; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.35; color: Theme.alpha(Theme.light, 0.9) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }
                Repeater {
                    model: 4
                    Rectangle {
                        width: 5; height: 5; rotation: 45; antialiasing: true; color: root.ink
                        x: (index % 2 === 0 ? 0 : box.width) - 2.5
                        y: (index < 2 ? 0 : box.height) - 2.5
                    }
                }

                MouseArea {   // wheel over the card flips pages
                    anchors.fill: parent; acceptedButtons: Qt.NoButton
                    onWheel: (w) => {
                        if (w.angleDelta.y < 0 && root.hasNext) root.flip(1)
                        else if (w.angleDelta.y > 0 && root.hasPrev) root.flip(-1)
                    }
                }

                Column {
                    id: body
                    x: 10; y: 8
                    spacing: 6

                    // aux / preedit line (fcitx5 sends preedit here only for clients
                    // that can't show it inline)
                    Row {
                        visible: root.hasLine
                        spacing: 8
                        Text {
                            visible: root.auxShown && root.auxText !== ""
                            text: root.auxText
                            font.family: root.candFont; font.pixelSize: Theme.fs(12)
                            color: root.inkSoft
                        }
                        Item {
                            visible: root.preShown && root.preText !== ""
                            width: preT.implicitWidth + 2; height: preT.implicitHeight
                            Text {
                                id: preT
                                text: root.preText
                                font.family: root.candFont; font.pixelSize: Theme.fs(13)
                                color: root.inkStrong
                            }
                            Rectangle {   // caret
                                x: preMetrics.advanceWidth; width: 1; height: preT.height; color: root.accent
                            }
                            TextMetrics {
                                id: preMetrics
                                font: preT.font
                                text: root.preText.substring(0, root.preCaret)
                            }
                        }
                    }

                    // candidates + page arrows
                    Row {
                        visible: root.hasTable
                        spacing: 10
                        Item {
                            id: candBox
                            width: candFlow.width; height: candFlow.height

                            // the ink selector under the highlighted candidate (+ afterimages)
                            // (pageSerial: a flipped page rebuilds the items even when count and cursor stay put)
                            readonly property Item target: {
                                root.pageSerial
                                return root.cursor >= 0 && candRep.count > root.cursor ? candRep.itemAt(root.cursor) : null
                            }
                            Repeater {
                                model: [ { a: 0.12, k: 2.2, d: 0.36 }, { a: 0.24, k: 3.4, d: 0.34 }, { a: 1.0, k: 5.5, d: 0.30 } ]
                                Item {
                                    required property var modelData
                                    visible: candBox.target !== null
                                    x: candBox.target ? candBox.target.x : 0
                                    y: candBox.target ? candBox.target.y : 0
                                    width: candBox.target ? candBox.target.width : 0
                                    height: candBox.target ? candBox.target.height : 0
                                    Behavior on x { SpringAnimation { spring: modelData.k; damping: modelData.d; epsilon: 0.25 } }
                                    Behavior on y { SpringAnimation { spring: modelData.k; damping: modelData.d; epsilon: 0.25 } }
                                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    opacity: modelData.a
                                    Rectangle { anchors.fill: parent; color: root.ink }
                                    Rectangle {
                                        visible: modelData.a === 1.0
                                        width: 2; height: parent.height; color: root.accent
                                    }
                                }
                            }

                            Grid {
                                id: candFlow
                                columns: root.vertical ? 1 : Math.max(1, root.cands.length)
                                columnSpacing: 2; rowSpacing: 2
                                Repeater {
                                    id: candRep
                                    model: root.cands
                                    Item {
                                        id: cand
                                        required property int index
                                        required property string modelData
                                        readonly property bool on: index === root.cursor
                                        width: candRow.implicitWidth + 14
                                        height: 26
                                        // a new page slides in from the way it flipped, staggered
                                        property real enter: 1
                                        opacity: enter
                                        transform: Translate { x: (1 - cand.enter) * 14 * root.pageDir }
                                        SequentialAnimation {
                                            id: candIn
                                            PropertyAction { target: cand; property: "enter"; value: 0 }
                                            PauseAnimation { duration: cand.index * 14 }
                                            NumberAnimation { target: cand; property: "enter"; to: 1; duration: 170; easing.type: Easing.OutCubic }
                                        }
                                        Connections { target: root; function onPageSerialChanged() { candIn.restart() } }
                                        // press bounce when the highlight lands here
                                        onOnChanged: if (on) bounce.restart()
                                        SequentialAnimation {
                                            id: bounce
                                            NumberAnimation { target: cand; property: "scale"; to: 0.92; duration: 45 }
                                            NumberAnimation { target: cand; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                                        }

                                        Row {
                                            id: candRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                anchors.baseline: candText.baseline
                                                text: root.labels[cand.index] || ""
                                                font.family: Theme.mono; font.pixelSize: Theme.fs(9)
                                                color: cand.on ? root.paperA(0.6) : root.inkSoft
                                            }
                                            Text {
                                                id: candText
                                                text: cand.modelData
                                                font.family: root.candFont; font.pixelSize: Theme.fs(15); font.weight: Font.Medium
                                                color: cand.on ? root.paper : root.inkStrong
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.pick(cand.index)
                                        }
                                    }
                                }
                            }
                        }

                        // ‹ › page diamonds
                        Row {
                            visible: root.hasPrev || root.hasNext
                            anchors.verticalCenter: candBox.verticalCenter
                            spacing: 6
                            Repeater {
                                model: [-1, 1]
                                Item {
                                    id: pg
                                    required property int modelData
                                    readonly property bool can: modelData < 0 ? root.hasPrev : root.hasNext
                                    width: 12; height: 12
                                    opacity: can ? 1 : 0.3
                                    Rectangle {
                                        anchors.centerIn: parent; width: 8; height: 8; rotation: 45; antialiasing: true
                                        color: pgMA.containsMouse && pg.can ? root.ink : "transparent"
                                        border.color: root.ink; border.width: 1
                                    }
                                    Text {
                                        anchors.centerIn: parent; anchors.verticalCenterOffset: -1
                                        text: pg.modelData < 0 ? "‹" : "›"; font.pixelSize: Theme.fs(9)
                                        color: pgMA.containsMouse && pg.can ? root.paper : root.ink
                                    }
                                    MouseArea {
                                        id: pgMA
                                        anchors.fill: parent; anchors.margins: -3
                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: if (pg.can) root.flip(pg.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── pick burst (on the candidate; the text effects live in Fx) ──
            HitBurst { id: burst; z: 50; scale: Settings.burstSize }
        }
    }
}
