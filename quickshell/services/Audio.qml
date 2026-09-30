pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Audio — shared volume/mute state backed by native Pipewire.
// Reactive (no wpctl polling) and used by BOTH TopBar and ControlCenter so the
// two never desync. volume is the raw Pipewire scale (1.0 == 100%, up to ~1.5).
QtObject {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool   ready:  sink !== null && sink.ready
    readonly property real   volume: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool   muted:  (sink && sink.audio) ? sink.audio.muted  : false

    // Keep the default sink's audio properties bound/live.
    property var _tracker: PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    function setVolume(v) {
        if (!sink || !sink.audio) return
        sink.audio.volume = Math.max(0, Math.min(1.5, v))
    }
    function toggleMute() {
        if (!sink || !sink.audio) return
        sink.audio.muted = !sink.audio.muted
    }
    function setMuted(m) {
        if (!sink || !sink.audio) return
        sink.audio.muted = m
    }
}
