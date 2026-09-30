import QtQuick

// Emblem — NieR-style glowing star-flower: a central 4-point star + a ring of 12
// stars alternating elongated (petal) and normal, all outer tips on one circle.
// Size follows width/height (square). Reusable: set `color`, `glow`, `glowStrength`.
Item {
    id: root
    property color color: "#fff6cf"     // star colour
    property bool  glow: true
    property real  glowStrength: 1.0    // multiplies glow opacity
    implicitWidth: 64
    implicitHeight: 64

    Canvas {
        id: cv
        anchors.fill: parent
        // Canvas inside an initially-hidden parent doesn't auto-paint; repaint
        // whenever it (re)appears or resizes.
        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: root
            function onColorChanged()        { cv.requestPaint() }
            function onGlowChanged()         { cv.requestPaint() }
            function onGlowStrengthChanged() { cv.requestPaint() }
        }
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var S = Math.min(width, height), c = S/2
            ctx.translate(width/2, height/2)

            function glow(x,y,gr,a){
                a *= root.glowStrength
                var rg = ctx.createRadialGradient(x,y,0, x,y,gr)
                rg.addColorStop(0.0, "rgba(255,224,90,"+a+")")
                rg.addColorStop(0.55,"rgba(232,178,40,"+(a*0.45)+")")
                rg.addColorStop(1.0, "rgba(232,178,40,0)")
                ctx.fillStyle = rg
                ctx.beginPath(); ctx.arc(x,y,gr,0,2*Math.PI); ctx.fill()
            }
            // 4-point star centred at radius Cr along `ang`, oriented radially.
            function star4(ang, Cr, pOut, pIn, pSide, ri, col){
                var rux=Math.cos(ang), ruy=Math.sin(ang)
                var tux=-Math.sin(ang), tuy=Math.cos(ang)
                var cx=rux*Cr, cy=ruy*Cr
                var pts=[[pOut,0],[ri,ri],[0,pSide],[-ri,ri],
                         [-pIn,0],[-ri,-ri],[0,-pSide],[ri,-ri]]
                ctx.fillStyle=col; ctx.beginPath()
                for(var k=0;k<8;k++){
                    var rc=pts[k][0], tc=pts[k][1]
                    var x=cx+rux*rc+tux*tc, y=cy+ruy*rc+tuy*tc
                    if(k===0) ctx.moveTo(x,y); else ctx.lineTo(x,y)
                }
                ctx.closePath(); ctx.fill()
            }

            var N  = 12
            var Ro = S*0.45, arm = S*0.10, Cr = Ro - arm
            var petIn = Cr - S*0.15, vri = S*0.023
            var starCol = root.color

            if (root.glow) {
                glow(0,0, S*0.34, 0.55)
                for (var gi=0; gi<N; gi++){
                    var ga = gi*2*Math.PI/N - Math.PI/2
                    glow(Math.cos(ga)*Cr, Math.sin(ga)*Cr, S*0.16, 0.7)
                }
                glow(0,0, S*0.15, 0.9)
            }
            for (var i=0;i<N;i++){
                var ang = i*2*Math.PI/N - Math.PI/2
                if (i%2===1) star4(ang, Cr, arm, petIn, S*0.092, vri, starCol)  // petal
                else         star4(ang, Cr, arm, arm,   S*0.092, vri, starCol)  // normal
            }
            star4(-Math.PI/2, 0, S*0.095, S*0.095, S*0.095, vri, starCol)       // centre
        }
    }
}
