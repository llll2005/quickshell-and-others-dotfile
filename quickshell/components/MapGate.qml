import QtQuick

// Fires ready() once this item's window has presented a frame after arm().
// Popups whose layer surface is unmapped while closed need ~10–100 ms to map
// again; a front-loaded (OutExpo) reveal started before that would lose its
// most visible first frames, so the reveal waits for this instead.
Item {
    id: gate
    signal ready()
    property bool _armed: false

    function arm() {
        _armed = true
        fallback.restart()
        if (gate.Window.window) gate.Window.window.update()   // already mapped → still get a frame
    }
    function disarm() { _armed = false; fallback.stop() }
    function _fire() {
        if (!_armed) return
        _armed = false
        fallback.stop()
        ready()
    }

    Connections {
        target: gate.Window.window
        enabled: gate._armed
        function onFrameSwapped() { gate._fire() }
    }
    Timer { id: fallback; interval: 250; onTriggered: gate._fire() }
}
