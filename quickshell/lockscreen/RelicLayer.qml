import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../theme"
import "../settings"
import "../components"
import "../services"

// RelicLayer — the lock as a relic (`[lock] style = relic`): an old dark ground with embers
// smouldering in the bottom corners (shaders/relic.frag), a sun emblem half over the top
// edge (emblem.svg, from scripts/gen-emblem.py), pillars of diamonds ending in four-point
// stars, the time in gold over two lines of runes (the date, and "the seal holds until the
// key is spoken", transliterated to the elder futhark), and a white subtitle at the
// bottom, like a cutscene's. Typing brings the diamonds up under the runes.
// Motion (embers, the emblem's breath and turn, grain) runs only while active — the first
// seconds and 12 s after each key — so an idle lock draws nothing new.
Item {
    id: rl
    required property var face
    readonly property var  st: face.st
    readonly property real u: face.u
    readonly property color gold:  Theme._hex(Config.str("void.relic", ""), "#d9a04a")
    readonly property color white: Theme.voidLight
    readonly property color warn:  Theme.voidWarn
    readonly property bool  typing: st.text !== "" || st.phase !== "idle"

    // ── active: motion for a while after locking and after each key ──
    property bool active: true
    Timer { id: idleT; interval: 12000; running: true; onTriggered: rl.active = false }
    function wake() { active = true; idleT.restart() }
    Connections {
        target: rl.st
        function onTextChanged() { rl.wake() }
        function onPhaseChanged() { rl.wake() }
    }
    property real time: 0
    NumberAnimation on time { from: 0; to: 100000; duration: 100000000; loops: Animation.Infinite; running: true; paused: !rl.active }
    property real breath: 0
    SequentialAnimation on breath {
        running: true; paused: !rl.active; loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 2600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 2600; easing.type: Easing.InOutSine }
    }

    // ── the failure and the way out ──
    property real flash: 0
    property real shake: 0
    property real flare: 0
    function fail() { failAnim.restart() }
    function ok()   { okAnim.restart() }
    SequentialAnimation {
        id: failAnim
        ParallelAnimation {
            NumberAnimation { target: rl; property: "flash"; from: 0; to: 1; duration: 140 }
            NumberAnimation { target: rl; property: "shake"; from: 0; to: 1; duration: 560 }
        }
        NumberAnimation { target: rl; property: "flash"; to: 0; duration: 1000; easing.type: Easing.OutCubic }
    }
    NumberAnimation { id: okAnim; target: rl; property: "flare"; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }

    // ── how many times this machine has slept (the subtitle counts them) ──
    property int count: 0
    FileView {
        path: Quickshell.statePath("lock-count")
        blockLoading: true
        printErrors: false
        readonly property bool preview: Quickshell.env("QS_LOCK_PREVIEW") === "1"
        onLoaded: { var n = parseInt(text()) || 0; rl.count = preview ? n : n + 1; if (!preview) setText(String(rl.count)) }
        onLoadFailed: { rl.count = 1; if (!preview) setText("1") }
    }

    // ── runes: English set in the elder futhark ──
    readonly property var futhark: ({ A: "ᚨ", B: "ᛒ", C: "ᚲ", D: "ᛞ", E: "ᛖ", F: "ᚠ", G: "ᚷ", H: "ᚺ", I: "ᛁ", J: "ᛃ",
        K: "ᚲ", L: "ᛚ", M: "ᛗ", N: "ᚾ", O: "ᛟ", P: "ᛈ", Q: "ᚲ", R: "ᚱ", S: "ᛊ", T: "ᛏ", U: "ᚢ", V: "ᚹ", W: "ᚹ",
        X: "ᛉ", Y: "ᛃ", Z: "ᛉ" })
    function runes(s) {
        s = String(s).toUpperCase().replace(/TH/g, "ᚦ").replace(/NG/g, "ᛜ")
        var o = ""
        for (var i = 0; i < s.length; i++) o += futhark[s[i]] || s[i]
        return o
    }
    readonly property var monthsFull: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
                                       "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

    opacity: face.inT

    // ── the ground ──
    ShaderEffect {
        anchors.fill: parent
        property point res: Qt.point(width, height)
        property real  time: rl.time
        property real  glow: 0.85 + 0.25 * rl.flare
        property real  flash: rl.flash
        property color ember: "#7a2c10"
        property color gold: rl.gold
        fragmentShader: Qt.resolvedUrl("../components/shaders/relic.frag.qsb") + "?v=2"
    }

    // ── the emblem: half over the top edge, a slow turn and a warm breath while active ──
    Item {
        id: emblemBox
        width: 760 * rl.u; height: width
        anchors.horizontalCenter: parent.horizontalCenter
        y: -width * 0.33
        transform: Translate { x: 16 * rl.u * Math.sin(rl.shake * Math.PI * 6) * (1 - rl.shake) }
        Image {      // the glow: a blurred, gold copy behind
            anchors.fill: parent
            anchors.margins: -30 * rl.u
            source: emblemImg.source
            sourceSize: Qt.size(800, 800)
            rotation: emblemImg.rotation
            opacity: 0.32 + 0.22 * rl.breath + 0.45 * rl.flare
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true; blur: 1.0; blurMax: 64
                colorization: 1.0; colorizationColor: rl.flash > 0.01 ? rl.warn : rl.gold
                brightness: 0.25
            }
        }
        Image {
            id: emblemImg
            anchors.fill: parent
            source: Qt.resolvedUrl("emblem.svg")
            sourceSize: Qt.size(1600, 1600)
            smooth: true; mipmap: true
            rotation: rl.time * 0.5
            layer.enabled: true
            layer.effect: MultiEffect {
                brightness: -0.06 + 0.12 * rl.flare
                colorization: 0.18 + 0.5 * rl.flash
                colorizationColor: rl.flash > 0.01 ? rl.warn : rl.gold
            }
        }
    }

    // ── pillars: a thread of diamonds ending in a four-point star ──
    component Sparkle: Shape {
        id: sp
        property real size: 40
        property color tint: rl.gold
        width: size; height: size
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: sp.tint; strokeColor: "transparent"
            startX: sp.size * 0.5; startY: 0
            PathLine { x: sp.size * 0.535; y: sp.size * 0.465 }
            PathLine { x: sp.size; y: sp.size * 0.5 }
            PathLine { x: sp.size * 0.535; y: sp.size * 0.535 }
            PathLine { x: sp.size * 0.5; y: sp.size }
            PathLine { x: sp.size * 0.465; y: sp.size * 0.535 }
            PathLine { x: 0; y: sp.size * 0.5 }
            PathLine { x: sp.size * 0.465; y: sp.size * 0.465 }
            PathLine { x: sp.size * 0.5; y: 0 }
        }
    }
    component Pillar: Item {
        id: pl
        property real len: 300
        property int  beads: 5
        property bool starAtTop: false
        readonly property real star: 54 * rl.u
        width: star; height: len
        Rectangle {
            x: (pl.width - 1) / 2; width: 1
            y: pl.starAtTop ? pl.star * 0.6 : 0
            height: pl.height - pl.star * 0.6
            color: Theme.alpha(rl.gold, 0.45)
        }
        Repeater {
            model: pl.beads
            Rectangle {
                readonly property real span: pl.height - pl.star * 1.2
                width: (index % 2 ? 7 : 11) * rl.u; height: width; rotation: 45
                x: (pl.width - width) / 2
                y: (pl.starAtTop ? pl.star : 0) + (index + 0.5) * span / pl.beads - height / 2
                color: index % 2 ? rl.gold : "transparent"
                border.color: rl.gold; border.width: 1
            }
        }
        Sparkle {
            size: pl.star
            anchors.horizontalCenter: parent.horizontalCenter
            y: pl.starAtTop ? 0 : pl.height - size
        }
    }
    Pillar { x: rl.width * 0.215 - width / 2; y: 0; len: rl.height * 0.33; beads: 5 }
    Pillar { x: rl.width * 0.785 - width / 2; y: 0; len: rl.height * 0.33; beads: 5 }
    Pillar { x: rl.width * 0.36 - width / 2; y: rl.height * 0.77; len: rl.height * 0.25; beads: 3; starAtTop: true }
    Pillar { x: rl.width * 0.64 - width / 2; y: rl.height * 0.77; len: rl.height * 0.25; beads: 3; starAtTop: true }
    Sparkle { size: 30 * rl.u; x: rl.width * 0.25; y: rl.height * 0.86; opacity: 0.7 }
    Sparkle { size: 30 * rl.u; x: rl.width * 0.75 - size; y: rl.height * 0.86; opacity: 0.7 }
    Sparkle { size: 22 * rl.u; x: rl.width * 0.17; y: rl.height * 0.42; opacity: 0.5 }
    Sparkle { size: 22 * rl.u; x: rl.width * 0.83 - size; y: rl.height * 0.42; opacity: 0.5 }

    // ── the time in gold, the runes, the diamonds ──
    Column {
        id: block
        anchors.horizontalCenter: parent.horizontalCenter
        y: rl.height * 0.49
        spacing: 0
        transform: Translate { x: 10 * rl.u * Math.sin(rl.shake * Math.PI * 6) * (1 - rl.shake) }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: hero.width; height: hero.height
            FixedDigits {   // the glow
                anchors.centerIn: parent
                text: hero.text; font: hero.font; color: hero.color
                opacity: 0.55 + 0.25 * rl.breath
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 40; brightness: 0.2 }
            }
            FixedDigits {
                id: hero
                anchors.centerIn: parent
                text: rl.face.pad(rl.face.now.getHours()) + ":" + rl.face.pad(rl.face.now.getMinutes())
                font.family: "Cinzel"; font.weight: Font.Medium
                font.pixelSize: Math.round(116 * rl.u); font.letterSpacing: 0.12 * 116 * rl.u
                color: rl.st.phase === "failed" ? rl.warn : rl.gold
            }
        }
        Item { width: 1; height: 16 * rl.u }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rl.runes(rl.face.days[rl.face.now.getDay()] + "  " + rl.monthsFull[rl.face.now.getMonth()])
            font.family: "Noto Sans Runic"; font.pixelSize: Math.round(36 * rl.u); font.letterSpacing: 0.32 * 36 * rl.u
            color: rl.gold
        }
        Item { width: 1; height: 10 * rl.u }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rl.runes("THE SEAL HOLDS UNTIL THE KEY IS SPOKEN")
            font.family: "Noto Sans Runic"; font.pixelSize: Math.round(25 * rl.u); font.letterSpacing: 0.3 * 25 * rl.u
            color: Theme.alpha(rl.gold, 0.85)
        }
        Item { width: 1; height: 34 * rl.u }
        VoidField {
            id: field
            anchors.horizontalCenter: parent.horizontalCenter
            u: rl.u
            fg: rl.gold
            hint: ""
            text: rl.st.text
            phase: rl.st.phase
            blink: rl.face.blinkV
            opacity: rl.typing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240 } }
        }
    }

    // ── the subtitle, a cutscene's ──
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: rl.height * 0.885
        text: rl.st.phase === "failed" ? "密碼錯誤，封印仍在"
            : rl.st.phase === "verifying" ? "驗證中……"
            : rl.st.phase === "authorized" ? "封印解除"
            : "這是本機第 " + rl.count + " 次沉睡　輸入密碼以甦醒"
        font.family: "Noto Sans CJK TC"; font.weight: Font.Medium
        font.pixelSize: Math.round(27 * rl.u); font.letterSpacing: 0.12 * 27 * rl.u
        color: rl.st.phase === "failed" ? rl.warn : rl.white
        style: Text.Raised; styleColor: "#000000"
    }
    Text {
        x: 64 * rl.u; anchors.bottom: parent.bottom; anchors.bottomMargin: 40 * rl.u
        text: "USER  " + rl.face.user.toUpperCase()
        font.family: "Noto Sans CJK TC"; font.pixelSize: Math.round(14 * rl.u); font.letterSpacing: 0.2 * 14 * rl.u
        color: Theme.alpha(rl.white, 0.4)
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 64 * rl.u; y: 40 * rl.u
        visible: Battery.available
        text: Battery.percent + "%" + (Battery.charging ? "  ⚡" : "")
        font.family: "Noto Sans CJK TC"; font.pixelSize: Math.round(14 * rl.u); font.letterSpacing: 0.15 * 14 * rl.u
        color: Theme.alpha(rl.white, 0.5)
    }
}
