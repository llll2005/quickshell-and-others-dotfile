import QtQuick
import "../components"
import "../theme"

// The Control Center's Quickshare card (scripts/qshare.py), shown while a share runs or
// has just failed. The QR is drawn here from qshare's module matrix (QRM), in the
// theme's ink on paper, and assembles in a diamond wave from its centre; the phone
// opening the page lights PHONE CONNECTED, and each transfer is a row with its hairline.
// ←→ switches LAN ⇄ INTERNET (the share restarts), ↵ copies the link (or installs /
// retries after an error), Esc stops. The keys come from the Control Center.
Item {
    id: card
    width: 720
    height: body.y + body.height + 64

    // ── state, from the Control Center ──
    property real   t: 0
    property real   pulse: 0
    property bool   active: false
    property string mode: "send"          // send = PC → phone · recv = phone → PC
    property bool   tunnel: false
    property string label: ""             // what is offered / where it lands
    property string meta: ""              // "3 items · 38.1 MB"
    property string url: ""
    property int    qrN: 0
    property string qrBits: ""
    property string status: ""            // what it's waiting for
    property string errorCode: ""
    property string errorText: ""
    property int    visitors: 0
    property var    transfers: []         // [{id, name, done, total, state: run|ok|fail}], oldest first
    property int    netDir: 1             // which way the network tabs last moved

    signal impact(Item item, real x, real y, real strength)   // → the panel's HitBurst
    signal stopRequested()
    signal netRequested(bool tunnel)

    // the rows stay put while their numbers move (a rebuilt row would lose its hairline's
    // easing and its ✓ pop): synced by id, newest on top
    ListModel { id: rows }
    onTransfersChanged: {
        var seen = {}
        for (var i = 0; i < transfers.length; i++) {
            var x = transfers[i], at = -1
            seen[x.id] = true
            for (var j = 0; j < rows.count; j++) if (rows.get(j).tid === x.id) { at = j; break }
            if (at < 0) rows.insert(0, { tid: x.id, name: x.name, done: x.done, total: x.total, st: x.state })
            else {
                var r = rows.get(at)
                if (r.done !== x.done)   rows.setProperty(at, "done", x.done)
                if (r.name !== x.name)   rows.setProperty(at, "name", x.name)
                if (r.st !== x.state)    rows.setProperty(at, "st", x.state)
            }
        }
        for (var k = rows.count - 1; k >= 0; k--) if (!seen[rows.get(k).tid]) rows.remove(k)
    }

    readonly property bool ready: url !== "" && qrBits !== ""
    readonly property bool failed: errorCode !== ""

    // ── a short flash on the action line (COPIED) ──
    property string flash: ""
    Timer { id: flashT; interval: 1300; onTriggered: card.flash = "" }
    function flashMsg(s) { flash = s; flashT.restart() }

    // ↵: the one verb the card has now
    readonly property string verb: failed
        ? (errorCode === "cloudflared-missing" ? "INSTALL" : errorCode.indexOf("tunnel") === 0 ? "RETRY" : "")
        : (ready ? "COPY LINK" : "")
    function popAction() { pop.restart(); card.impact(actBox, actBox.width / 2, actBox.height / 2, 0.8) }

    opacity: active ? 1 : 0
    scale: active ? 1 : 0.94
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale   { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
    MouseArea { anchors.fill: parent; enabled: card.active }   // a click on the card isn't one outside

    PaperCard { anchors.fill: parent; t: card.t }

    // ── header: kicker · LAN | INTERNET ──
    Item {
        id: head
        x: 28; y: 22; width: parent.width - 56; height: 34
        Row {
            spacing: 10; anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                width: 7; height: 7; rotation: 45; antialiasing: true; color: Theme.accent
                anchors.verticalCenter: parent.verticalCenter
                scale: 1 + 0.3 * card.pulse
            }
            Text {
                text: "QUICKSHARE  ·  " + (card.mode === "recv" ? "PHONE → PC" : "PC → PHONE")
                font.pixelSize: Theme.ts(1); font.letterSpacing: 3; color: Theme.inkSoft
            }
        }
        Row {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            CatTab {
                width: 92; height: 28; label: "LAN"; active: !card.tunnel
                dir: card.netDir; pulse: card.pulse; animate: card.active
                onClicked: if (card.tunnel) card.netRequested(false)
            }
            CatTab {
                width: 122; height: 28; label: "INTERNET"; active: card.tunnel
                dir: card.netDir; pulse: card.pulse; animate: card.active
                onClicked: if (!card.tunnel) card.netRequested(true)
            }
        }
    }
    Rectangle { x: 28; y: head.y + head.height + 10; width: parent.width - 56; height: 1; color: Theme.alpha(Theme.ink, 0.25) }

    Item {
        id: body
        x: 28; y: head.y + head.height + 26
        width: parent.width - 56; height: Math.max(qrBox.height + 30, side.implicitHeight)

        // ── the QR (or what it's waiting for, or what went wrong) ──
        Item {
            id: qrBox
            width: 252; height: 252
            Rectangle { anchors.fill: parent; color: Theme.paper; border.color: Theme.ink; border.width: 1 }
            Repeater {      // its own small diamond corners
                model: 4
                Rectangle {
                    width: 6; height: 6; rotation: 45; antialiasing: true; color: Theme.accent
                    x: (index % 2 === 0 ? 0 : qrBox.width) - 3; y: (index < 2 ? 0 : qrBox.height) - 3
                }
            }
            Canvas {
                id: qr
                anchors.fill: parent; anchors.margins: 1
                visible: card.ready
                property real rev: 0
                onRevChanged: requestPaint()
                Connections {
                    target: card
                    function onQrBitsChanged() {
                        qr.rev = 0
                        if (card.qrBits !== "") revAnim.restart()
                        qr.requestPaint()
                    }
                }
                NumberAnimation { id: revAnim; target: qr; property: "rev"; from: 0; to: 1; duration: 620; easing.type: Easing.OutCubic }
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var n = card.qrN, bits = card.qrBits
                    if (n <= 0 || bits.length < n * n) return
                    var m = Math.floor(width / (n + 8)), o = Math.floor((width - m * n) / 2)   // a 4-module quiet zone
                    var c = (n - 1) / 2, f = rev * 1.2
                    var deep = String(Theme.inkStrong), edge = String(Theme.accent)
                    for (var y = 0; y < n; y++) {
                        for (var x = 0; x < n; x++) {
                            if (bits.charAt(y * n + x) !== "1") continue
                            var d = (Math.abs(x - c) + Math.abs(y - c)) / (2 * c)   // a diamond wavefront
                            if (d > f) continue
                            ctx.fillStyle = d > f - 0.12 ? edge : deep
                            ctx.fillRect(o + x * m, o + y * m, m, m)
                        }
                    }
                }
            }
            // one glint across once it's whole
            Rectangle {
                id: glint
                width: 40; height: qrBox.height * 1.6; rotation: 25; y: -qrBox.height * 0.3
                x: -80; opacity: 0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.5; color: Theme.alpha(Theme.light, 0.7) }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
            SequentialAnimation {
                id: glintAnim
                PauseAnimation { duration: 520 }
                PropertyAction { target: glint; property: "opacity"; value: 1 }
                NumberAnimation { target: glint; property: "x"; from: -80; to: qrBox.width + 40; duration: 520; easing.type: Easing.InOutQuad }
                PropertyAction { target: glint; property: "opacity"; value: 0 }
            }
            Connections { target: card; function onReadyChanged() { if (card.ready) glintAnim.restart() } }
            clip: true

            // waiting: a diamond breathing on the beat, what it waits for, a hairline sweeping
            Column {
                anchors.centerIn: parent; width: parent.width - 36; spacing: 14
                visible: !card.ready && !card.failed
                Item {
                    width: 22; height: 22; anchors.horizontalCenter: parent.horizontalCenter
                    Rectangle {
                        anchors.centerIn: parent; width: 14; height: 14; rotation: 45; antialiasing: true
                        color: "transparent"; border.color: Theme.ink; border.width: 1
                        scale: 1 + 0.25 * card.pulse
                    }
                    Rectangle { anchors.centerIn: parent; width: 5; height: 5; rotation: 45; color: Theme.accent }
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: card.status !== "" ? card.status : (card.tunnel ? "正在開通道…" : "準備中…")
                    font.family: Theme.cjk; font.pixelSize: Theme.ts(1); color: Theme.inkSoft
                }
            }
            Rectangle {
                visible: !card.ready && !card.failed
                y: parent.height - 3; height: 2; width: parent.width * 0.3; color: Theme.accent
                x: (parent.width * 1.3) * ((card.t * 0.45) % 1) - parent.width * 0.3
            }
            // failed: a brick diamond with a cross, and the reason
            Column {
                anchors.centerIn: parent; width: parent.width - 36; spacing: 12
                visible: card.failed
                Item {
                    width: 26; height: 26; anchors.horizontalCenter: parent.horizontalCenter
                    Rectangle {
                        anchors.centerIn: parent; width: 16; height: 16; rotation: 45; antialiasing: true
                        color: "transparent"; border.color: Theme.warn; border.width: 1.5
                    }
                    Text { anchors.centerIn: parent; text: "✕"; color: Theme.warn; font.pixelSize: Theme.ts(0) }
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter
                    text: card.errorCode.toUpperCase().replace(/-/g, " ")
                    font.pixelSize: Theme.ts(1); font.letterSpacing: 2; color: Theme.warn
                }
                Text {
                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                    text: card.errorText
                    font.family: Theme.cjk; font.pixelSize: Theme.ts(1); color: Theme.ink; lineHeight: 1.15
                }
            }
        }
        Text {
            y: qrBox.height + 10; width: qrBox.width
            text: card.url; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignHCenter
            font.family: Theme.mono; font.pixelSize: Theme.ts(0); color: Theme.inkSoft
        }

        // ── what is shared, who's there, what moved ──
        Column {
            id: side
            x: qrBox.width + 32; width: parent.width - x
            spacing: 0
            Text {
                text: card.mode === "recv" ? "UPLOAD" : "DOWNLOAD"
                font.pixelSize: Theme.ts(5); font.letterSpacing: 6; font.weight: Font.Medium; color: Theme.inkStrong
            }
            Item { width: 1; height: 6 }
            Text {
                width: parent.width; elide: Text.ElideMiddle
                text: card.mode === "recv" ? "存到 " + card.label : card.label + (card.meta !== "" ? "  ·  " + card.meta : "")
                font.family: Theme.cjk; font.pixelSize: Theme.ts(2); color: Theme.ink
            }
            Item { width: 1; height: 14 }
            // the phone: waiting ◇ → connected ◆ (a ring the moment it opens the page)
            Row {
                id: phone
                visible: !card.failed
                spacing: 9
                Item {
                    id: phoneMark
                    width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.centerIn: parent; width: 8; height: 8; rotation: 45; antialiasing: true
                        color: card.visitors > 0 ? Theme.accent : "transparent"
                        border.color: card.visitors > 0 ? Theme.accent : Theme.inkSoft; border.width: 1
                        scale: card.visitors > 0 ? 1 : 0.85 + 0.15 * card.pulse
                    }
                    Rectangle {
                        id: phoneRing
                        anchors.centerIn: parent; width: 8; height: 8; rotation: 45; antialiasing: true
                        color: "transparent"; border.color: Theme.accent; border.width: 1; opacity: 0
                    }
                    ParallelAnimation {
                        id: phoneRingAnim
                        NumberAnimation { target: phoneRing; property: "scale"; from: 1; to: 4.2; duration: 520; easing.type: Easing.OutCubic }
                        NumberAnimation { target: phoneRing; property: "opacity"; from: 0.9; to: 0; duration: 520; easing.type: Easing.OutQuad }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.visitors > 1 ? card.visitors + " PHONES CONNECTED"
                        : card.visitors === 1 ? "PHONE CONNECTED" : "WAITING FOR THE PHONE"
                    font.pixelSize: Theme.ts(1); font.letterSpacing: 2
                    color: card.visitors > 0 ? Theme.inkStrong : Theme.inkSoft
                }
            }
            Connections {
                target: card
                function onVisitorsChanged() {
                    if (card.visitors > 0 && card.active) {
                        phoneRingAnim.restart()
                        card.impact(phoneMark, phoneMark.width / 2, phoneMark.height / 2, 0.45)
                    }
                }
            }
            Item { width: 1; height: card.failed ? 0 : 14 }
            Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.ink, 0.2) }
            // the transfers, newest first
            Repeater {
                model: rows
                Item {
                    id: xrow
                    required property int index
                    required property string name
                    required property real done
                    required property real total
                    required property string st
                    width: side.width; height: index < 4 ? 40 : 0
                    visible: index < 4
                    readonly property bool ok: st === "ok"
                    readonly property bool bad: st === "fail"
                    readonly property real frac: total > 0 ? Math.min(1, done / total) : (ok ? 1 : 0)
                    onOkChanged: if (ok) { popRow.restart(); card.impact(mk, mk.width / 2, mk.height / 2, 0.35) }
                    Text {
                        id: mk
                        width: 18; anchors.verticalCenter: parent.verticalCenter
                        text: xrow.ok ? "✓" : xrow.bad ? "✕" : (card.mode === "recv" ? "↓" : "↑")
                        color: xrow.bad ? Theme.warn : xrow.ok ? Theme.inkStrong : Theme.accent
                        font.pixelSize: Theme.ts(2); horizontalAlignment: Text.AlignHCenter
                        SequentialAnimation on scale {
                            id: popRow; running: false
                            NumberAnimation { to: 1.5; duration: 70; easing.type: Easing.OutQuad }
                            NumberAnimation { to: 1; duration: 260; easing.type: Easing.OutBack }
                        }
                    }
                    Text {
                        x: 28; width: parent.width - x - 90; anchors.verticalCenter: parent.verticalCenter
                        text: xrow.name; elide: Text.ElideMiddle
                        font.pixelSize: Theme.ts(2); color: xrow.bad ? Theme.inkSoft : Theme.ink
                    }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: xrow.bad ? "STOPPED" : xrow.ok ? card.human(xrow.total) : Math.floor(xrow.frac * 100) + "%"
                        font.pixelSize: Theme.ts(1); font.letterSpacing: 1
                        color: xrow.bad ? Theme.warn : Theme.inkSoft
                    }
                    Rectangle { x: 28; y: parent.height - 7; width: parent.width - 28; height: 1; color: Theme.alpha(Theme.ink, 0.15) }
                    Rectangle {
                        x: 28; y: parent.height - 7.5; height: 2
                        width: (parent.width - 28) * xrow.frac
                        color: xrow.ok ? Theme.alpha(Theme.ink, 0.35) : Theme.accent
                        visible: !xrow.bad
                        Behavior on width { NumberAnimation { duration: 180 } }
                    }
                }
            }
            Text {
                visible: card.transfers.length > 4
                topPadding: 6
                text: "+ " + (card.transfers.length - 4) + " MORE"
                font.pixelSize: Theme.ts(0); font.letterSpacing: 2; color: Theme.inkSoft
            }
            Text {   // nothing moved yet: what to do (or how to get past the error)
                visible: card.transfers.length === 0
                width: parent.width; topPadding: 14; wrapMode: Text.WordWrap; lineHeight: 1.25
                text: card.errorCode === "cloudflared-missing"
                      ? "按 ↵ 安裝 cloudflared（會問系統密碼，控制中心會先收起來），裝好後再分享一次。\n同一個 Wi-Fi 的話，按 ← 用 LAN 就不需要它。"
                    : card.failed
                      ? "按 ↵ 再試一次；一直失敗的話，先確認電腦連得上網路。\n同一個 Wi-Fi 的話，按 ← 用 LAN。"
                    : (card.mode === "recv" ? "用手機掃描 QR，在網頁上選檔案傳過來。" : "用手機掃描 QR，在網頁上點檔名下載。")
                      + (card.tunnel ? "\n經過 Cloudflare：手機用行動數據也行，大檔案會分段傳。"
                                     : "\n手機要連同一個 Wi-Fi；不同網路就按 → 換成 INTERNET。")
                font.family: Theme.cjk; font.pixelSize: Theme.ts(1); color: Theme.inkSoft
            }
        }
    }

    // ── the action line: ↵ verb · ESC STOP ──
    Row {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 28; bottomMargin: 20 }
        spacing: 12
        Item {
            id: actBox
            visible: card.verb !== "" || card.flash !== ""
            width: actRow.implicitWidth + 24; height: 30
            SequentialAnimation on scale {
                id: pop; running: false
                NumberAnimation { to: 1.06; duration: 50 }
                NumberAnimation { to: 1; duration: 200; easing.type: Easing.OutBack }
            }
            Rectangle { anchors.fill: parent; color: Theme.ink }
            Rectangle { width: 3; height: parent.height; color: card.failed ? Theme.warn : Theme.accent }
            Row {
                id: actRow
                anchors.centerIn: parent; spacing: 8
                Text { text: card.flash !== "" ? "✓" : "↵"; font.pixelSize: Theme.ts(1); color: Theme.alpha(Theme.paper, 0.7); anchors.verticalCenter: parent.verticalCenter }
                Text { text: card.flash !== "" ? card.flash : card.verb; font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5; color: Theme.paper; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: card.verbClicked() }
        }
        Item {
            width: stopTxt.implicitWidth + 24; height: 30
            Rectangle {
                anchors.fill: parent; color: stopMA.containsMouse ? Theme.ink : "transparent"
                border.color: Theme.ink; border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                id: stopTxt; anchors.centerIn: parent
                text: card.failed ? "ESC  CLOSE" : "ESC  STOP"
                font.pixelSize: Theme.ts(1); font.letterSpacing: 2.5
                color: stopMA.containsMouse ? Theme.paper : Theme.ink
            }
            MouseArea { id: stopMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: card.stopRequested() }
        }
    }
    signal verbClicked()

    function human(n) {
        if (n < 1024) return n + " B"
        var u = ["KB", "MB", "GB", "TB"]
        for (var i = 0; i < u.length; i++) { n /= 1024; if (n < 1024 || i === u.length - 1) return n.toFixed(1) + " " + u[i] }
        return ""
    }
}
