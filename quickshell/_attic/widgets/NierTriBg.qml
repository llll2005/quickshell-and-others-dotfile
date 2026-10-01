import QtQuick

// Animated triangle background — ported from AGS yorha-dots settingsbg.js / geom.js
// Grid of equilateral triangles spreading from origin, with optional selection-box vertex interaction.
Canvas {
    id: root

    // ── Config ────────────────────────────────────────────────────────────
    property int    cellSize:      200     // triangle base width (px)
    property int    gap:           3       // gap between triangles (px)
    property real   targetOpacity: 0.55   // opacity when fully shown
    property color  triColor:      "#d6cfb5"
    // spreadMode: "left"   → origin col 0,   spreads rightward  (default)
    //             "right"  → origin col N-1, spreads leftward   (for right-slide panels)
    //             "center" → origin col N/2 row M/2, spreads outward (exit = outside-in)
    property string spreadMode: "left"

    // ── Trigger ───────────────────────────────────────────────────────────
    property bool active: false
    onActiveChanged: active ? _doShow() : _doHide()

    // A popup whose window is only mapped while open gets its size a moment
    // *after* `active` flips; building the grid at 0×0 leaves a single 2×2 corner
    // of triangles. So a show at size 0 waits for the real size.
    property bool _pendingShow: false
    onWidthChanged:  _sizeReady()
    onHeightChanged: _sizeReady()
    function _sizeReady() {
        if (_pendingShow && width > 0 && height > 0) { _pendingShow = false; _doShow() }
    }

    // ── Selection box interaction (from geom.js — deforms triangle vertices) ──
    property bool selActive: false
    property real selX1: 0
    property real selY1: 0
    property real selX2: 0
    property real selY2: 0

    onSelActiveChanged: {
        if (!selActive && _cells.length) {
            var cells = _cells
            var n = _rows * _cols
            for (var i = 0; i < n; i++) {
                var c = cells[i]
                if (c[8]) { c[3] = 1; c[5] = 1; c[7] = 1; c[1] = targetOpacity }
            }
            _cells = cells
            requestPaint()
        }
    }

    // ── Derived geometry ──────────────────────────────────────────────────
    readonly property int _cw: cellSize
    readonly property int _ch: Math.round(Math.sqrt(_cw * _cw - (_cw/2) * (_cw/2)))

    // ── Internal state ────────────────────────────────────────────────────
    property var  _cells:    []
    property int  _cols:     0
    property int  _rows:     0
    property int  _opStep:   10
    property int  _vtStep:   2
    property real _tStart:   0
    property real _tDur:     900
    property bool _entering: false
    property bool _exiting:  false
    property int  _cx:       0
    property int  _cy:       0

    visible: false

    // ── Helpers ───────────────────────────────────────────────────────────
    function _ri(a, b) { return Math.round(Math.random() * (b - a) + a) }

    function _dist(x, y) {
        var dx = Math.abs(x - _cx) / 2, dy = Math.abs(y - _cy)
        return Math.sqrt(dx * dx + dy * dy)
    }

    // Distance from arbitrary cell-space point (matches geom.js dist_from_center)
    function _dcell(xi, yi, cx, cy) {
        var dx = (xi - cx) / 2, dy = yi - cy
        return Math.sqrt(dx * dx + dy * dy)
    }

    function _maxDist() {
        var dx = Math.max(_cx, _cols - _cx), dy = Math.max(_cy, _rows - _cy)
        return Math.sqrt(dx * dx + dy * dy) + 1
    }

    function _initCells() {
        _cols = Math.round(width  * 2 / _cw) + 2
        _rows = Math.round(height / _ch) + 2
        var arr = [], n = _rows * _cols
        // [c_op, t_op, c_L, t_L, c_R, t_R, c_Y, t_Y, inited]
        for (var i = 0; i < n; i++) arr.push([0,0, 0,0, 0,0, 0,0, false])
        _cells = arr
    }

    function _originX() {
        if (spreadMode === "right")  return _cols - 1
        if (spreadMode === "center") return Math.floor(_cols / 2)
        return 0
    }
    function _originY() {
        if (spreadMode === "center") return Math.floor(_rows / 2)
        return _ri(Math.floor(_rows / 4), Math.floor(3 * _rows / 4))
    }

    function _doShow() {
        visible = true
        if (width < 1 || height < 1) { _pendingShow = true; return }
        _initCells()
        _cx = _originX(); _cy = _originY()
        _tStart = Date.now(); _tDur = 900
        _opStep = 10; _vtStep = 2
        _entering = true; _exiting = false
        animTick.running = true
    }

    function _doHide() {
        _pendingShow = false
        _cx = _originX(); _cy = _originY()
        _tStart = Date.now(); _tDur = 700
        _opStep = 2; _vtStep = 2
        _exiting = true; _entering = false
    }

    // Deform triangle vertices based on selection-box edges (port of geom.js update_css)
    function _updateSel(cells) {
        var n = _rows * _cols
        if (!n) return

        // Map pixel → cell coords; normalise so sel*1 <= sel*2
        var rx1 = Math.min(selX1, selX2) / width  * _cols
        var ry1 = Math.min(selY1, selY2) / height * _rows
        var rx2 = Math.max(selX1, selX2) / width  * _cols
        var ry2 = Math.max(selY1, selY2) / height * _rows

        // Padded cell bounds (matches geom.js cell_x1/y1/x2/y2)
        var cx1 = rx1 - 2, cy1 = ry1 - 2
        var cx2 = rx2 + 1, cy2 = ry2 + 1
        var cenX = (cx1 + cx2) / 2
        var cenY = (cy1 + cy2) / 2
        var xd   = (cx2 - cx1) / 2   // half-width  of padded box in cell units
        var yd   = (cy2 - cy1) / 2   // half-height of padded box in cell units

        for (var i = 0; i < n; i++) {
            var c = cells[i]
            if (!c[8]) continue

            var xi = i % _cols, yi = (i - xi) / _cols
            var inv = (xi % 2 === 0 ? yi % 2 === 1 : yi % 2 === 0)

            // Four circular edge zones (matches geom.js leftside/rightside/topside/bottomside)
            var leftside   = xi < cx2 && _dcell(xi, yi, rx1 + yd, cenY) < yd
            var rightside  = xi > cx1 && _dcell(xi, yi, rx2 - yd, cenY) < yd
            var topside    = xi > cx1 && xi < cx2 && yi < cy2 && _dcell(xi, yi, cenX, ry1 + xd - 2) < xd
            var bottomside = xi > cx1 && xi < cx2 && yi > cy1 && _dcell(xi, yi, cenX, ry2 - xd + 1) < xd
            var inside     = leftside || rightside || topside || bottomside

            if (inside) {
                // Pinch one vertex toward the nearest selection edge
                if ((yi > cy2 - 1 && inv) || (yi < cy1 + 1 && !inv)) {
                    c[7] = 0; c[3] = 1; c[5] = 1   // pinch apex (y) vertex
                } else if (xi > cx2 - 1 || xi > cenX) {
                    c[7] = 1; c[3] = 0; c[5] = 1   // pinch left vertex (right side)
                } else {
                    c[7] = 1; c[3] = 1; c[5] = 0   // pinch right vertex (left side)
                }
            } else {
                // Restore all vertices
                c[7] = 1; c[3] = 1; c[5] = 1
                c[1] = targetOpacity
            }
        }
    }

    // ── Animation timer (~30 fps) ─────────────────────────────────────────
    Timer {
        id: animTick; interval: 33; repeat: true; running: false
        onTriggered: {
            var t  = (Date.now() - root._tStart) / root._tDur
            var md = root._maxDist()
            var cells = root._cells
            var n = root._rows * root._cols

            if (root._entering) {
                for (var i = 0; i < n; i++) {
                    var xi = i % root._cols, yi = (i - xi) / root._cols
                    var c = cells[i]
                    var d = root._dist(xi, yi)
                    if ((t > 1 ? 1 : t) * md * (root._ri(50, 100) / 100) > d) {
                        if (!c[8]) { c[8] = true; c[0] = 1 }
                        c[1] = root.targetOpacity
                        if (d < 2)             { c[7]=1; c[2]=1; c[3]=1; c[4]=1; c[5]=1 }
                        else if (xi < root._cx){ c[3]=1; c[4]=1; c[5]=1; c[6]=1; c[7]=1 }
                        else                   { c[5]=1; c[2]=1; c[3]=1; c[6]=1; c[7]=1 }
                    }
                }
                if (t >= 1) root._entering = false

            } else if (root._exiting) {
                // center mode: outside-in dissolve (edges fade first → center last)
                // other modes: inside-out (origin fades first)
                var outsideIn = (root.spreadMode === "center")
                var tc = t > 1 ? 1 : t
                for (var i = 0; i < n; i++) {
                    var xi = i % root._cols, yi = (i - xi) / root._cols
                    var c = cells[i]
                    var d = root._dist(xi, yi)
                    var shouldFade
                    if (outsideIn) {
                        // outer cells (large d) fade first as tc grows
                        shouldFade = d > md * (1 - tc) * (root._ri(30, 100) / 100)
                    } else {
                        shouldFade = tc * md * (root._ri(0, 100) / 100) > d
                    }
                    if (shouldFade && c[8]) { c[8] = false; c[1] = 0 }
                }
                if (t >= 1) {
                    root._exiting = false
                    animTick.running = false
                    root.visible = false
                    root._cells = cells
                    return
                }
            }

            // Selection-box vertex deformation (runs in steady state and during entry)
            if (root.selActive && !root._exiting) {
                root._updateSel(cells)
            }

            root._cells = cells
            root.requestPaint()
        }
    }

    // ── Drawing ───────────────────────────────────────────────────────────
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!_cells || !_cells.length) return

        var cs = triColor.toString()
        var cr = parseInt(cs.slice(1, 3), 16)
        var cg = parseInt(cs.slice(3, 5), 16)
        var cb = parseInt(cs.slice(5, 7), 16)

        var cells = _cells
        var n = _rows * _cols
        var cw2 = _cw / 2
        var gw = _cw - gap, gh = _ch - gap / 2
        var ops = _opStep, vts = _vtStep

        for (var i = 0; i < n; i++) {
            var c = cells[i]
            if (!c[8]) continue

            var op = c[0], tOp = c[1]
            var cL = c[2], tL  = c[3]
            var cR = c[4], tR  = c[5]
            var cY = c[6], tY  = c[7]

            if (Math.abs(op - tOp) > 0.005) op += (tOp - op) / ops; else op = tOp
            if (Math.abs(cL - tL)  > 0.001) cL += (tL - cL)  / vts; else cL = tL
            if (Math.abs(cR - tR)  > 0.001) cR += (tR - cR)  / vts; else cR = tR
            if (Math.abs(cY - tY)  > 0.001) cY += (tY - cY)  / vts; else cY = tY

            c[0] = op; c[2] = cL; c[4] = cR; c[6] = cY

            if (op < 0.005 || cL <= 0.001 || cR <= 0.001 || cY <= 0.001) continue

            var xi = i % _cols, yi = (i - xi) / _cols
            var inv = (xi % 2 === 0 ? yi % 2 === 1 : yi % 2 === 0)
            var px = xi * cw2, py = yi * _ch

            var lp, rp, yp
            if (inv) {
                lp = [px - gw/2, py + gh/2]
                rp = [px + gw/2, py + gh/2]
                yp = [px,        py - gh/2]
            } else {
                lp = [px - gw/2, py - gh/2]
                rp = [px + gw/2, py - gh/2]
                yp = [px,        py + gh/2]
            }

            if (cL < 0.9) {
                var k = 1 - cL
                lp = [lp[0] + (rp[0]-lp[0])*k/2 + (yp[0]-lp[0])*k/2,
                      lp[1] + (rp[1]-lp[1])*k/2 + (yp[1]-lp[1])*k/2]
            }
            if (cR < 0.9) {
                var k = 1 - cR
                rp = [rp[0] + (lp[0]-rp[0])*k/2 + (yp[0]-rp[0])*k/2,
                      rp[1] + (lp[1]-rp[1])*k/2 + (yp[1]-rp[1])*k/2]
            }
            if (cY < 0.9) {
                var k = 1 - cY
                yp = [yp[0] + (lp[0]-yp[0])*k/2 + (rp[0]-yp[0])*k/2,
                      yp[1] + (lp[1]-yp[1])*k/2 + (rp[1]-yp[1])*k/2]
            }

            ctx.fillStyle = "rgba(" + cr + "," + cg + "," + cb + "," + op.toFixed(3) + ")"
            ctx.beginPath()
            ctx.moveTo(lp[0], lp[1])
            ctx.lineTo(rp[0], rp[1])
            ctx.lineTo(yp[0], yp[1])
            ctx.closePath()
            ctx.fill()
        }

        _cells = cells
    }
}
