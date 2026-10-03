import QtQuick

// FixedDigits — a time ("10:57", "38") whose digits sit in cells as wide as the widest
// digit, so a face without tabular figures (Norse) doesn't jitter as the seconds turn.
Row {
    id: fd
    property string text: ""
    property font   font
    property color  color: "white"
    FontMetrics { id: fm; font: fd.font }
    readonly property real cell: {
        var w = 0
        for (var i = 0; i <= 9; i++) w = Math.max(w, fm.advanceWidth(String(i)))
        return Math.ceil(w)
    }
    Repeater {
        model: fd.text.split("")
        Text {
            width: /[0-9]/.test(modelData) ? fd.cell : implicitWidth
            horizontalAlignment: Text.AlignHCenter
            text: modelData
            font: fd.font
            color: fd.color
        }
    }
}
