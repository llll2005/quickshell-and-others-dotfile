import QtQuick

// ScrambleText — a Text that types its `target` in through a scramble of glyphs, left to
// right, whenever `target` changes (the Void's way of putting words on screen: the power
// exit, the lock). `play()` replays it; `duration` is the whole reveal.
Text {
    id: st
    property string target: ""
    property int    duration: 420
    property string glyphs: "▸◆▪▫░▒▓█/\\|-_=+*"
    property bool   playOnChange: true

    text: target
    onTargetChanged: if (playOnChange) play()
    function play() { _t0 = Date.now(); tick.restart() }

    property double _t0: 0
    Timer {
        id: tick
        interval: 16; repeat: true
        onTriggered: {
            var t = Math.min(1, (Date.now() - st._t0) / st.duration), out = "", n = st.target.length
            for (var i = 0; i < n; i++) {
                var at = i / Math.max(1, n)
                if (t > at + 0.15 || st.target[i] === " ") out += st.target[i]
                else if (t > at) out += st.glyphs[Math.floor(Math.random() * st.glyphs.length)]
                else out += " "
            }
            st.text = out
            if (t >= 1) { st.text = st.target; stop() }
        }
    }
}
