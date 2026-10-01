pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Audio — shared volume/mute state backed by native Pipewire.
// Reactive (no wpctl / pactl polling), shared by the HUD and the Control Center. volume is the raw Pipewire scale (1.0 == 100%, up to ~1.5).
QtObject {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool   ready:  sink !== null && sink.ready
    readonly property real   volume: (sink && sink.audio) ? sink.audio.volume : 0
    readonly property bool   muted:  (sink && sink.audio) ? sink.audio.muted  : false

    // the default input (microphone)
    readonly property PwNode source:   Pipewire.defaultAudioSource
    readonly property bool   micMuted: (source && source.audio) ? source.audio.muted : false

    // output devices (no streams), for pickers; setDefaultSink() switches by name
    readonly property var sinks: Pipewire.nodes.values.filter(function(n) {
        return n && n.audio && n.isSink && !n.isStream
    })
    function setDefaultSink(name) {
        for (var i = 0; i < sinks.length; i++)
            if (sinks[i].name === name) { Pipewire.preferredDefaultAudioSink = sinks[i]; return }
    }

    // Keep the default sink's / source's audio properties bound/live.
    property var _tracker: PwObjectTracker { objects: [root.sink, root.source].filter(function(n) { return n }) }

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
    function toggleMic() {
        if (!source || !source.audio) return
        source.audio.muted = !source.audio.muted
    }
}
