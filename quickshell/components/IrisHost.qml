import QtQuick
import "../theme"

// Shows its content through the popups' reveal mask (shaders/reveal.frag): a
// diamond iris by default, or a scan line / blinds. reveal() opens it (midway
// through, midReveal() is the cue for rows to slide in), conceal() closes it and
// then emits concealed(). Outside those animations the mask is off (no layer).
Item {
    id: host
    property real progress: 1
    property int  mode: 0              // 0 diamond iris · 1 scan · 2 blinds
    property int  inDuration:  520
    property int  outDuration: 300
    property bool forceLayer: false    // e.g. the popup's warm-up: build the shader once
    readonly property bool masking: _masking
    property bool _masking: false

    signal midReveal()
    signal revealed()
    signal concealed()

    function reveal()  { outAnim.stop(); inAnim.start() }
    function conceal() { inAnim.stop(); outAnim.start() }
    function reset()   { inAnim.stop(); outAnim.stop(); _masking = false; progress = 1 }

    clip: true
    layer.enabled: _masking || forceLayer
    layer.effect: ShaderEffect {
        property real  progress: host.progress
        property real  mode:     host.mode
        property size  dims:     Qt.size(host.width, host.height)
        property color edge:     Theme.alpha(Theme.light, 0.75)
        fragmentShader: Qt.resolvedUrl("shaders/reveal.frag.qsb") + "?v=2"   // bump ?v= after recompiling
    }

    SequentialAnimation {
        id: inAnim
        ScriptAction { script: { host.progress = 0; host._masking = true } }
        ParallelAnimation {
            NumberAnimation { target: host; property: "progress"; to: 1; duration: host.inDuration; easing.type: Easing.OutQuart }
            SequentialAnimation {
                PauseAnimation { duration: 200 }
                ScriptAction { script: host.midReveal() }
            }
        }
        ScriptAction { script: { host._masking = false; host.revealed() } }
    }
    SequentialAnimation {
        id: outAnim
        ScriptAction { script: host._masking = true }
        NumberAnimation { target: host; property: "progress"; to: 0; duration: host.outDuration; easing.type: Easing.InCubic }
        ScriptAction { script: host.concealed() }
    }
}
