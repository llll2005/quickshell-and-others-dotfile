import QtQuick
import Quickshell.Io
import "../components"
import "../settings"
import "../theme"

Item {
    id: root

    // ── Dimensions ──
    readonly property int  pw:       Settings.playerWidth
    readonly property real sc:       Settings.scale
    readonly property int  cavaW:    40
    readonly property int  hiderW:   1
    readonly property int  matrixSz: pw - cavaW - hiderW
    readonly property int  gridN:    64
    readonly property real cellPx:   matrixSz / gridN
    readonly property int  dataSz:   64
    function s(px) { return Math.round(px * sc) }

    // ── MPRIS bindings ──
    // mprisPlayer is the active Quickshell.Services.Mpris MprisPlayer (or null).
    // Controls call its methods directly — event-driven, no subprocess.
    property var    mprisPlayer: null
    property string mpTitle:    "END OF EVANGELION"
    property string mpArtist:   "NEON GENESIS // ANNO"
    property string mpCoverUrl: ""
    property bool   mpPlaying:  false
    property real   mpPosition: 0
    property real   mpLength:   341

    function _ctlPlay() { if (mprisPlayer && mprisPlayer.canTogglePlaying) mprisPlayer.togglePlaying() }
    function _ctlNext() { if (mprisPlayer && mprisPlayer.canGoNext)        mprisPlayer.next() }
    function _ctlPrev() { if (mprisPlayer && mprisPlayer.canGoPrevious)    mprisPlayer.previous() }

    property bool   shown:       false
    property string clockStr:    "--:--"
    property var    cavaBars:    new Array(24).fill(0)
    property real   cavaBar1Pos: 0
    property real   cavaBar2Pos: 0

    // Processing lock to prevent concurrent image processing
    property bool   _processingCover: false

    // Theme sepia target color
    readonly property real themeR: 200/255
    readonly property real themeG: 184/255
    readonly property real themeB: 154/255

    // Title animation state
    property string _displayedTitle: mpTitle
    property bool   _cursorVisible:  false
    onMpTitleChanged: {
        if (mpTitle !== _displayedTitle) titleChangeAnim.restart()
    }

    implicitWidth:  pw
    implicitHeight: wipeHost.height

    // ══════════════════════════════════════════════════════════════
    // WIPE HOST
    // ══════════════════════════════════════════════════════════════
    Item {
        id: wipeHost
        width: pw; height: nowplayingCol.implicitHeight
        x: pw + 2; visible: false

        Rectangle {
            width: pw; height: parent.height
            color: Settings.playerBackground ? Settings.playerBgColor : "transparent"
        }

        Row {
            id: mainRow
            width: pw; height: nowplayingCol.implicitHeight

            // ─────────────────────────────────────────────────────
            // NOWPLAYING COLUMN
            // ─────────────────────────────────────────────────────
            Column {
                id: nowplayingCol
                width: root.matrixSz

                // Top separator
                Rectangle {
                    width: root.matrixSz; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.2; color: Theme.alpha(Theme.sepia, 0.5) }
                        GradientStop { position: 0.8; color: Theme.alpha(Theme.sepia, 0.5) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // ── CONTROLS ──
                Item {
                    width: root.matrixSz; height: root.s(52)
                    Row {
                        anchors.centerIn: parent; spacing: root.s(10)

                        // Prev
                        Item {
                            id: btnPrev
                            width: root.s(42); height: root.s(42)
                            property bool hov: false
                            property real sdw: hov ? root.s(9) : root.s(4)
                            Behavior on sdw   { NumberAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 80  } }
                            transformOrigin: Item.Center
                            Text { x: btnPrev.sdw; y: btnPrev.sdw; text: "⏮"; font.family: Theme.mono; font.pixelSize: root.s(21); color: Theme.alpha(Theme.sepiaDim, 0.28) }
                            Text { anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: "⏮"; font.family: Theme.mono; font.pixelSize: root.s(21)
                                color: btnPrev.hov ? Theme.alpha(Theme.sepia, 1) : Theme.alpha(Theme.sepia, 0.65)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered:  btnPrev.hov   = true
                                onExited:   btnPrev.hov   = false
                                onPressed:  btnPrev.scale = 0.88
                                onReleased: btnPrev.scale = 1.0
                                onClicked:  root._ctlPrev()
                            }
                        }

                        // Play / Pause
                        Item {
                            id: btnPlay
                            width: root.s(70); height: root.s(42)
                            property bool hov: false
                            property real sdw: hov ? root.s(9) : root.s(4)
                            Behavior on sdw   { NumberAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 80  } }
                            transformOrigin: Item.Center
                            Text { x: btnPlay.sdw; y: btnPlay.sdw; text: root.mpPlaying ? "⏸" : "▶"; font.family: Theme.mono; font.pixelSize: root.s(19); color: Theme.alpha(Theme.sepiaDim, 0.28) }
                            Text { anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: root.mpPlaying ? "⏸" : "▶"; font.family: Theme.mono; font.pixelSize: root.s(19)
                                color: btnPlay.hov ? Theme.alpha(Theme.sepia, 1) : Theme.alpha(Theme.sepia, 0.65)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered:  btnPlay.hov   = true
                                onExited:   btnPlay.hov   = false
                                onPressed:  btnPlay.scale = 0.88
                                onReleased: btnPlay.scale = 1.0
                                onClicked:  { root._ctlPlay(); root._startRipple() }
                            }
                        }

                        // Next
                        Item {
                            id: btnNext
                            width: root.s(42); height: root.s(42)
                            property bool hov: false
                            property real sdw: hov ? root.s(9) : root.s(4)
                            Behavior on sdw   { NumberAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 80  } }
                            transformOrigin: Item.Center
                            Text { x: btnNext.sdw; y: btnNext.sdw; text: "⏭"; font.family: Theme.mono; font.pixelSize: root.s(21); color: Theme.alpha(Theme.sepiaDim, 0.28) }
                            Text { anchors.fill: parent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: "⏭"; font.family: Theme.mono; font.pixelSize: root.s(21)
                                color: btnNext.hov ? Theme.alpha(Theme.sepia, 1) : Theme.alpha(Theme.sepia, 0.65)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered:  btnNext.hov   = true
                                onExited:   btnNext.hov   = false
                                onPressed:  btnNext.scale = 0.88
                                onReleased: btnNext.scale = 1.0
                                onClicked:  root._ctlNext()
                            }
                        }
                    }
                }

                // ── MATRIX COVER ──
                Item {
                    id: coverArea
                    width: root.matrixSz; height: root.matrixSz
                    clip: true

                    // ── Cell renderer ─────────────────────────────────
                    Canvas {
                        id: coverCanvas
                        anchors.fill: parent
                        smooth: false

                        // Current displayed state (modified in-place)
                        property var shwR:   []
                        property var shwG:   []
                        property var shwB:   []
                        property var shwOp:  []
                        // Target state from image
                        property var tgtR:   []
                        property var tgtG:   []
                        property var tgtB:   []
                        property var tgtOp:  []
                        // Zoom-in offset: 0=done, 1-100=animating
                        property var cellOff:  []
                        // Whether a cell has been snapped to new image data
                        property var revealed: []

                        // Ripple state
                        property real rippleT:       0
                        property real rippleMaxDist: 0
                        property int  rippleOX:      0   // origin cell X
                        property int  rippleOY:      0   // origin cell Y

                        function _initArrays() {
                            var n = root.gridN * root.gridN
                            shwR = Array(n).fill(root.themeR); shwG = Array(n).fill(root.themeG); shwB = Array(n).fill(root.themeB)
                            shwOp = Array(n).fill(0)
                            tgtR = Array(n).fill(root.themeR); tgtG = Array(n).fill(root.themeG); tgtB = Array(n).fill(root.themeB)
                            tgtOp = Array(n).fill(0)
                            cellOff = Array(n).fill(0); revealed = Array(n).fill(false)
                        }

                        // Called when a new image is loaded (extractCanvas → pixel data)
                        function setFromPixels(pixData, dsz) {
                            var GRID = root.gridN, DATA = dsz, n = GRID*GRID
                            var lumArr = new Array(n), minL = 1, maxL = 0
                            var tr = tgtR, tg = tgtG, tb = tgtB, to = tgtOp
                            var sr = shwR, sg = shwG, sb = shwB, so = shwOp
                            var soff = cellOff, rev = revealed
                            for (var row = 0; row < GRID; row++) {
                                for (var col = 0; col < GRID; col++) {
                                    var sx = Math.min(Math.floor(col * DATA / GRID), DATA-1)
                                    var sy = Math.min(Math.floor(row * DATA / GRID), DATA-1)
                                    var idx = (sy * DATA + sx) * 4
                                    var r = pixData[idx]/255, g = pixData[idx+1]/255, b = pixData[idx+2]/255
                                    var i = row * GRID + col
                                    tr[i] = r; tg[i] = g; tb[i] = b
                                    var l = 0.299*r + 0.587*g + 0.114*b
                                    lumArr[i] = l
                                    if (l < minL) minL = l
                                    if (l > maxL) maxL = l
                                }
                            }
                            var range = maxL - minL
                            for (var i = 0; i < n; i++) {
                                to[i] = range > 0.01 ? (lumArr[i] - minL) / range : lumArr[i]
                                so[i] = 0       // fade from 0
                                soff[i] = 0     // no zoom yet
                                rev[i] = false  // not yet snapped to new data
                            }
                        }

                        // Generate a seeded pattern when no cover art
                        function setGenerative() {
                            var GRID = root.gridN, n = GRID*GRID
                            var seed = 0, title = root.mpTitle
                            for (var k = 0; k < title.length; k++) seed = ((seed * 31 + title.charCodeAt(k)) >>> 0)
                            function rand() { seed = ((seed * 1664525 + 1013904223) >>> 0); return seed / 4294967296 }
                            var tr = tgtR, tg = tgtG, tb = tgtB, to = tgtOp
                            var so = shwOp, soff = cellOff, rev = revealed
                            for (var i = 0; i < n; i++) {
                                var col = i % GRID, row = Math.floor(i / GRID)
                                var dx = (col - GRID/2) / (GRID/2), dy = (row - GRID/2) / (GRID/2)
                                var d = Math.sqrt(dx*dx + dy*dy)
                                var v = Math.max(0, Math.min(1, (1 - d * 0.6) * 0.75 + rand() * 0.45))
                                // Sepia-toned noise
                                tr[i] = root.themeR * 0.6 + v * 0.4
                                tg[i] = root.themeG * 0.6 + v * 0.35
                                tb[i] = root.themeB * 0.6 + v * 0.3
                                to[i] = v * 0.65
                                so[i] = 0; soff[i] = 0; rev[i] = false
                            }
                        }

                        // Called by revealTimer each frame — reveals cells whose tgtOp <= ratio
                        function revealStep(ratio) {
                            var n = root.gridN * root.gridN
                            var tr = tgtR, tg = tgtG, tb = tgtB, to = tgtOp
                            var sr = shwR, sg = shwG, sb = shwB, so = shwOp, soff = cellOff, rev = revealed
                            var any = false
                            for (var i = 0; i < n; i++) {
                                if (!rev[i] && to[i] <= ratio) {
                                    sr[i] = tr[i]; sg[i] = tg[i]; sb[i] = tb[i]
                                    so[i] = 1.0  // flash to full opacity, then settle toward tgtOp
                                    soff[i] = 1  // trigger slide-in animation
                                    rev[i] = true
                                    any = true
                                }
                            }
                            if (any) requestPaint()
                        }

                        // Hover instantly reveals cells in brush radius
                        function hoverAt(mx, my) {
                            var GRID = root.gridN, CELL = root.cellPx, BRUSH = 2
                            var cc = Math.floor(mx / CELL), cr = Math.floor(my / CELL)
                            var tr = tgtR, tg = tgtG, tb = tgtB, to = tgtOp
                            var sr = shwR, sg = shwG, sb = shwB, so = shwOp, soff = cellOff, rev = revealed
                            for (var dc = -BRUSH; dc <= BRUSH; dc++) {
                                for (var dr = -BRUSH; dr <= BRUSH; dr++) {
                                    var nc = cc+dc, nr = cr+dr
                                    if (nc < 0 || nc >= GRID || nr < 0 || nr >= GRID) continue
                                    if (Math.sqrt(dc*dc+dr*dr) > BRUSH+0.5) continue
                                    var i = nr*GRID+nc
                                    sr[i] = tr[i]; sg[i] = tg[i]; sb[i] = tb[i]
                                    so[i] = 1.0; soff[i] = 1; rev[i] = true
                                }
                            }
                            requestPaint()
                        }

                        // Ripple step — called each timer tick
                        // Avoids Math.sqrt by comparing dist² using (T-thick)² < dist² < (T+thick)²
                        function rippleStep() {
                            var T = rippleT, MAX = rippleMaxDist
                            var GRID = root.gridN, MAX_THICK = 10
                            var OX = rippleOX, OY = rippleOY
                            var frac = Math.max(0, 1 - T / MAX)
                            var tr = tgtR, tg = tgtG, tb = tgtB
                            var sr = shwR, sg = shwG, sb = shwB, so = shwOp, soff = cellOff, rev = revealed
                            for (var i = 0; i < GRID*GRID; i++) {
                                var cx = i % GRID, cy = Math.floor(i / GRID)
                                var dx = cx - OX, dy = cy - OY
                                var dist2 = dx*dx + dy*dy
                                // Per-cell random thickness in [-MAX_THICK, MAX_THICK] * frac
                                var thick = (Math.random() * MAX_THICK * 2 - MAX_THICK) * frac
                                if (thick <= 0) continue
                                var lo = T - thick, hi = T + thick
                                if (lo < 0) lo = 0
                                if (dist2 >= lo*lo && dist2 <= hi*hi) {
                                    sr[i] = tr[i]; sg[i] = tg[i]; sb[i] = tb[i]
                                    so[i] = 1.0; soff[i] = 1; rev[i] = true
                                }
                            }
                            requestPaint()
                        }

                        onPaint: {
                            var ctx = getContext("2d")
                            var GRID = root.gridN, CELL = root.cellPx
                            var TR = root.themeR, TG = root.themeG, TB = root.themeB
                            var LERP = 0.20
                            ctx.clearRect(0, 0, width, height)

                            var sr = shwR, sg = shwG, sb = shwB, so = shwOp
                            var to = tgtOp, soff = cellOff, rev = revealed
                            var stillAnim = false

                            for (var i = 0; i < GRID*GRID; i++) {
                                var op = so[i]
                                // Cells only become visible after revealStep marks them
                                var effTgt = rev[i] ? to[i] : 0
                                if (op < 0.005 && effTgt < 0.005) continue

                                // Lerp color toward theme sepia
                                var r = sr[i] + (TR - sr[i]) * LERP
                                var g = sg[i] + (TG - sg[i]) * LERP
                                var b = sb[i] + (TB - sb[i]) * LERP
                                // Lerp opacity: reveal sets shwOp=1.0, it settles toward tgtOp
                                var newOp = op + (effTgt - op) * LERP
                                sr[i] = r; sg[i] = g; sb[i] = b; so[i] = newOp

                                if (Math.abs(r - TR) > 0.003 || Math.abs(newOp - effTgt) > 0.003) stillAnim = true

                                var cx = i % GRID, cy = Math.floor(i / GRID)
                                var off = soff[i]

                                if (off > 0) {
                                    // Slide-in (yorha-dots: translate from offset position, 2× opacity)
                                    var nowOff = off > 50 ? 100 - off : off   // 0→50→0
                                    var shift = (nowOff / 100) * 2 * CELL * 0.5  // max = 0.5 * CELL
                                    off = Math.min(off + (off > 50 ? 5 : 3), 100)
                                    soff[i] = off
                                    if (off < 100) stillAnim = true
                                    var drawOp = Math.min(newOp * 2, 1.0)
                                    ctx.fillStyle = "rgba("+Math.round(r*255)+","+Math.round(g*255)+","+Math.round(b*255)+","+drawOp+")"
                                    ctx.fillRect(cx*CELL+shift, cy*CELL+shift, CELL, CELL)
                                } else {
                                    ctx.fillStyle = "rgba("+Math.round(r*255)+","+Math.round(g*255)+","+Math.round(b*255)+","+newOp+")"
                                    ctx.fillRect(cx*CELL, cy*CELL, CELL, CELL)
                                }
                            }

                            if (stillAnim) requestPaint()
                        }

                        Component.onCompleted: {
                            _initArrays()
                            setGenerative()
                            revealTimer.restart()
                            requestPaint()
                        }
                    } // coverCanvas

                    // ── Source image (hidden, used for grabToImage) ──
                    Image {
                        id: coverSrc
                        width: root.matrixSz; height: root.matrixSz
                        visible: true; opacity: 0; smooth: false
                        fillMode: Image.PreserveAspectCrop; z: -1
                        onStatusChanged: {
                            if (status !== Image.Ready) return
                            if (root._processingCover) {
                                console.log("Player: Skipping cover processing - already in progress")
                                return
                            }
                            root._processingCover = true
                            coverWatchdog.restart()
                            var ok = grabToImage(function(result) {
                                extractCanvas.grabResult = result
                                extractCanvas.requestPaint()
                            }, Qt.size(root.dataSz, root.dataSz))
                            // no window on screen to grab from: try again when the card shows
                            if (!ok) { root._processingCover = false; root._lastCoverUrl = ""; root._coverPending = true }
                        }
                    }

                    // ── Pixel extraction canvas (dataSz × dataSz) ──
                    Canvas {
                        id: extractCanvas
                        width: root.dataSz; height: root.dataSz
                        visible: false
                        property var grabResult: null
                        onPaint: {
                            if (!grabResult) {
                                root._processingCover = false
                                return
                            }
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, root.dataSz, root.dataSz)
                            ctx.drawImage(grabResult.url, 0, 0, root.dataSz, root.dataSz)
                            var raw = ctx.getImageData(0, 0, root.dataSz, root.dataSz).data
                            coverCanvas.setFromPixels(raw, root.dataSz)
                            revealTimer.restart()
                            coverCanvas.requestPaint()
                            root._processingCover = false
                        }
                    }

                    // Scanlines
                    Item {
                        anchors.fill: parent; z: 3
                        Repeater {
                            model: Math.ceil(root.matrixSz / 3)
                            Rectangle { y: index*3+2; width: root.matrixSz; height: 1; color: Qt.rgba(0,0,0,0.13) }
                        }
                    }

                    // Right border
                    Rectangle {
                        anchors.right: parent.right; z: 4
                        width: 1; height: parent.height
                        color: Theme.alpha(Theme.sepia, 0.10)
                    }

                    // Hover mouse area
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; z: 5
                        cursorShape: Qt.CrossCursor
                        onPositionChanged: (m) => coverCanvas.hoverAt(m.x, m.y)
                    }
                } // coverArea

                // ── TITLE + CURSOR ──
                Item {
                    width: root.matrixSz; height: root.s(36)
                    clip: true

                    Item {
                        id: titleRow
                        x: root.s(10)
                        y: 0
                        width: parent.width - root.s(10)
                        height: parent.height

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._displayedTitle
                            font.family: Theme.mono
                            font.pixelSize: root.s(13)
                            color: Theme.alpha(Theme.sepia, 0.9)
                            elide: Text.ElideRight
                            width: parent.width - root.s(20)
                        }

                        // Cursor — hidden normally, appears during track change
                        Item {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: root.s(14); height: root.s(20)
                            opacity: root._cursorVisible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                            Rectangle { y: 0; width: parent.width; height: root.s(14); color: Theme.alpha(Theme.sepia, 0.85) }
                            Rectangle { y: parent.height-root.s(4); width: parent.width; height: root.s(4); color: Theme.alpha(Theme.sepia, 0.85) }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom; width: parent.width; height: 1
                        color: Theme.alpha(Theme.sepia, 0.06)
                    }
                }
            } // nowplayingCol

            // ── CAVA — two vertical scrolling bars ───────────────
            Item {
                width: root.cavaW; height: nowplayingCol.implicitHeight

                Item { x: 0;  y: 0; width: 15; height: parent.height; clip: true; CavaStripe { scrollY: root.cavaBar1Pos } }
                Item { x: 15; y: 0; width: 25; height: parent.height; clip: true; CavaStripe { scrollY: root.cavaBar2Pos } }
            }

            // ── HIDER STRIP ──
            Rectangle { width: root.hiderW; height: nowplayingCol.implicitHeight; color: Theme.sepiaDim }

        } // mainRow

        // Close button
        Rectangle {
            id: closeBtn
            x: pw - root.s(22); y: root.s(4)
            width: root.s(18); height: root.s(14)
            color: closeBtnMA.containsMouse ? Theme.alpha(Theme.sepia, 0.18) : "transparent"
            border.color: Theme.alpha(Theme.sepia, 0.25); border.width: 1; z: 6
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { anchors.centerIn: parent; text: "✕"; font.family: Theme.mono; font.pixelSize: root.s(7); color: Theme.alpha(Theme.sepia, 0.5) }
            MouseArea { id: closeBtnMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleVisible() }
        }

        CornerDeco {
            width: pw; height: nowplayingCol.implicitHeight
            lineColor: Theme.alpha(Theme.sepia, 0.3); size: 18; z: 5
        }

        Rectangle {
            id: curtain
            anchors { top: parent.top; bottom: parent.bottom }
            color: Theme.sepia; z: 10; width: 2; x: pw - 2
            enabled: false  // Prevent blocking mouse events
        }
    } // wipeHost

    // ══════════════════════════════════════════════════════════════
    // REVEAL TIMER — runs for 5s, reveals cells by luminance order
    // ══════════════════════════════════════════════════════════════
    Timer {
        id: revealTimer
        interval: 50; repeat: true; running: false  // Reduced from 33ms to 50ms for better performance
        property real elapsed: 0
        onRunningChanged: if (running) elapsed = 0
        onTriggered: {
            elapsed += interval
            var ratio = Math.min(elapsed / 5000, 1)
            coverCanvas.revealStep(ratio)
            if (ratio >= 1) running = false
        }
    }

    // ══════════════════════════════════════════════════════════════
    // RIPPLE TIMER — play button wave, one cell-radius step per tick
    // ══════════════════════════════════════════════════════════════
    Timer {
        id: rippleTimer
        interval: 12; repeat: true; running: false
        onTriggered: {
            coverCanvas.rippleStep()
            coverCanvas.rippleT += 1
            if (coverCanvas.rippleT >= coverCanvas.rippleMaxDist) running = false
        }
    }

    function _startRipple() {
        var GRID = root.gridN
        coverCanvas.rippleOX = Math.floor(GRID / 2)
        coverCanvas.rippleOY = 0
        var dx = Math.max(coverCanvas.rippleOX, GRID - coverCanvas.rippleOX)
        var dy = GRID
        coverCanvas.rippleMaxDist = Math.sqrt(dx*dx + dy*dy) + 10
        coverCanvas.rippleT = 0
        rippleTimer.restart()
    }

    // ══════════════════════════════════════════════════════════════
    // COVER URL / TITLE WATCHERS
    // ══════════════════════════════════════════════════════════════
    property string _lastCoverUrl: ""
    property string _lastTitle: ""

    Connections {
        target: root
        function onMpCoverUrlChanged() { root._loadCover() }
        // the cover is turned into the pixel matrix with grabToImage, which needs the
        // window on screen: while the card is hidden (its window unmapped) it waits
        function onMappedChanged() { if (root.mapped && root._coverPending) root._loadCover() }
    }
    property bool _coverPending: false
    // a grab that never calls back must not block every later cover
    Timer { id: coverWatchdog; interval: 2000; onTriggered: root._processingCover = false }
    function _loadCover() {
        if (!root.mapped) { root._coverPending = true; return }
        root._coverPending = false
        if (root.mpCoverUrl === root._lastCoverUrl) return
        root._lastCoverUrl = root.mpCoverUrl

        if (root.mpCoverUrl !== "") {
            if (root._processingCover) {
                console.log("Player: Delaying cover load - processing in progress")
                return
            }
            coverSrc.source = ""
            coverSrc.source = root.mpCoverUrl
        } else {
            root._processingCover = true
            coverCanvas.setGenerative()
            revealTimer.restart()
            coverCanvas.requestPaint()
            root._processingCover = false
        }
    }
    Connections {
        target: root
        function onMpTitleChanged() {
            if (root.mpTitle === root._lastTitle) return
            root._lastTitle = root.mpTitle

            if (root.mpCoverUrl === "") {
                root._processingCover = true
                coverCanvas.setGenerative()
                revealTimer.restart()
                coverCanvas.requestPaint()
                root._processingCover = false
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // TITLE SLIDE ANIMATION (yorha-dots nowplaying revealer style)
    // ══════════════════════════════════════════════════════════════
    // baseX = the resting position of titleRow
    readonly property int _titleBaseX: s(10)

    SequentialAnimation {
        id: titleChangeAnim
        // Cursor appears
        ScriptAction { script: root._cursorVisible = true }
        PauseAnimation  { duration: 280 }
        // Old title slides out left
        ParallelAnimation {
            NumberAnimation { target: titleRow; property: "x"; to: -root.s(28); duration: 220; easing.type: Easing.InQuad }
            NumberAnimation { target: titleRow; property: "opacity"; to: 0; duration: 200 }
        }
        // Update text, enter from right
        ScriptAction { script: { root._displayedTitle = root.mpTitle; titleRow.x = root._titleBaseX + root.s(32) } }
        ParallelAnimation {
            NumberAnimation { target: titleRow; property: "x"; to: root._titleBaseX; duration: 320; easing.type: Easing.OutExpo }
            NumberAnimation { target: titleRow; property: "opacity"; to: 1; duration: 300 }
        }
        PauseAnimation  { duration: 280 }
        // Cursor hides
        ScriptAction { script: root._cursorVisible = false }
    }

    // ══════════════════════════════════════════════════════════════
    // SLIDE ANIMATIONS
    // ══════════════════════════════════════════════════════════════
    SequentialAnimation {
        id: revealAnim
        ParallelAnimation {
            NumberAnimation { target: wipeHost; property: "x"; from: pw+2; to: 0; duration: 460; easing.type: Easing.OutExpo }
            NumberAnimation { target: curtain; property: "width"; from: pw; to: pw; duration: 460 }
        }
        ParallelAnimation {
            NumberAnimation { target: curtain; property: "x"; from: 0; to: 0; duration: 340 }
            NumberAnimation { target: curtain; property: "width"; from: pw; to: 0; duration: 340; easing.type: Easing.OutExpo }
        }
        onStarted: {
            wipeHost.x = pw+2; wipeHost.opacity = 1; wipeHost.visible = true
            curtain.visible = true; curtain.x = 0; curtain.width = pw
        }
        onFinished: { wipeHost.x = 0; curtain.x = 0; curtain.width = 0; curtain.visible = false }
    }

    SequentialAnimation {
        id: hideAnim
        ParallelAnimation {
            NumberAnimation { target: curtain; property: "x"; from: 0; to: 0; duration: 180 }
            NumberAnimation { target: curtain; property: "width"; from: 0; to: pw; duration: 180; easing.type: Easing.InOutQuart }
        }
        NumberAnimation { target: wipeHost; property: "x"; from: 0; to: pw+2; duration: 380; easing.type: Easing.InExpo }
        onStarted: { curtain.x = 0; curtain.width = 0 }
        onFinished: { wipeHost.visible = false; wipeHost.x = pw+2; curtain.x = 0; curtain.width = pw }
    }

    // ══════════════════════════════════════════════════════════════
    // CAVA — stream cava's stdout directly (SplitParser per frame).
    // No temp file, no polling: one long-lived cava process emits one ascii
    // frame per line at 30 fps, parsed event-driven as it arrives.
    // ══════════════════════════════════════════════════════════════
    Process {
        id: cavaProc
        running: root.shown
        command: ["sh", "-c",
            "printf '[general]\\nbars=24\\nframerate=30\\nsensitivity=100\\n[output]\\nmethod=raw\\nraw_target=/dev/stdout\\ndata_format=ascii\\n' > /tmp/qs-player-cava.ini; exec cava -p /tmp/qs-player-cava.ini"
        ]
        stdout: SplitParser {
            onRead: line => {
                var s = line.trim()
                if (!s) return
                var raw = s.replace(/;+$/, "").split(";")
                var bars = []
                for (var i = 0; i < 24; i++) bars.push(i < raw.length ? Math.max(0, Math.min(1000, parseInt(raw[i])||0)) : 0)
                root.cavaBars = bars
                var bass = bars.length > 1  ? bars[1]  : 0
                var mid  = bars.length > 12 ? bars[12] : 0
                root.cavaBar1Pos -= bass/1000 * 5 + 0.01
                root.cavaBar2Pos += mid/1000  * 5 + 0.01
                if (root.cavaBar1Pos < -200) root.cavaBar1Pos = 0
                if (root.cavaBar2Pos >  200) root.cavaBar2Pos = 0
            }
        }
    }

    Timer {
        interval: 1000; running: root.mapped; repeat: true; triggeredOnStart: true
        onTriggered: {
            var d = new Date()
            root.clockStr = String(d.getHours()).padStart(2,"0") + ":" + String(d.getMinutes()).padStart(2,"0")
        }
    }

    // The window (widgets/Player.qml) is mapped only while this is true; a reveal
    // waits for the freshly mapped surface's first frame (MapGate).
    readonly property bool mapped: shown || hideAnim.running
    MapGate { id: showGate; onReady: { hideAnim.stop(); revealAnim.start() } }
    function toggleVisible() {
        if (root.shown) { root.shown = false; showGate.disarm(); revealAnim.stop(); hideAnim.start() }
        else            { root.shown = true;  hideAnim.stop();   showGate.arm() }
    }

    Component.onCompleted: {
        var d = new Date()
        clockStr = String(d.getHours()).padStart(2,"0") + ":" + String(d.getMinutes()).padStart(2,"0")
    }

    // ══════════════════════════════════════════════════════════════
    // CAVA STRIPE — vertical scrolling stripe bar
    // ══════════════════════════════════════════════════════════════
    component CavaStripe: Canvas {
        property real scrollY: 0
        anchors.fill: parent
        onScrollYChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            var stripeH = height * 0.1, cycle = stripeH * 2
            var rawOff = scrollY * height / 200
            var offset = ((rawOff % cycle) + cycle) % cycle
            for (var y = -cycle + offset; y < height + cycle; y += cycle) {
                ctx.fillStyle = "rgba(72,70,61,1)"
                ctx.fillRect(0, y, width, stripeH)
                ctx.fillStyle = "rgba(72,70,61,0.25)"
                ctx.fillRect(0, y + stripeH, width, stripeH)
            }
        }
    }

}
