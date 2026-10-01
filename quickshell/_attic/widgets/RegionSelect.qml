import QtQuick
import Quickshell.Io

Item {
    id: root

    property real screenW: 1920
    property real screenH: 1080
    property real screenX: 0
    property real screenY: 0

    property bool   active:      false
    property bool   _dissolving: false
    property bool   _capturing:  false
    property bool   _triActive:  false
    property bool   _inputReady: false    // true after compositor has processed layer → overlay change
    property string pendingCmd:  ""
    property string _pendingExecCmd: ""

    signal regionDone()
    signal regionCancelled()
    signal finished()

    implicitWidth:  screenW
    implicitHeight: screenH
    visible: active || _dissolving

    readonly property color paper:   "#d6cfb5"
    readonly property color ink:     "#463f2e"
    readonly property color inkSoft: "#7a7358"
    readonly property color accent:  "#6e2a2a"

    // ── Triangle background ──────────────────────────────────────────────
    NierTriBg {
        anchors.fill: parent
        active:        root._triActive
        cellSize:      200
        targetOpacity: 0.60
        triColor:      "#d6cfb5"
        spreadMode:    "center"
        z: 0
        selActive: selState.dragging
        selX1: selState.x1; selY1: selState.y1
        selX2: selState.x2; selY2: selState.y2
    }

    // ── Dim overlay ──────────────────────────────────────────────────────
    Rectangle {
        z: 1; anchors.fill: parent
        color: Qt.rgba(70/255, 63/255, 46/255, 0.25)
    }

    // ── Status labels ─────────────────────────────────────────────────────
    Text {
        z: 3
        anchors { top: parent.top; left: parent.left; margins: 22 }
        text: "REGION SELECT · 區域選取"
        font.pixelSize: 10; font.letterSpacing: 3; font.weight: Font.Medium
        color: root.paper; opacity: 0.65
    }
    Row {
        z: 3
        anchors { bottom: parent.bottom; left: parent.left; margins: 22 }
        spacing: 18
        Repeater {
            model: [["DRAG", "SELECT"], ["ESC", "CANCEL"]]
            Row {
                spacing: 6; anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    width: kT.implicitWidth + 8; height: 16; color: "transparent"
                    border.color: Qt.rgba(214/255, 207/255, 181/255, 0.35); border.width: 1
                    Text { id: kT; anchors.centerIn: parent; text: modelData[0]
                        font.pixelSize: 8; font.letterSpacing: 1; color: root.paper }
                }
                Text { text: modelData[1]; font.pixelSize: 9; font.letterSpacing: 2
                    color: root.inkSoft; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ── Crosshair position hint ───────────────────────────────────────────
    Text {
        z: 3
        visible: !selState.dragging && root.active
        x: Math.min(dragArea.mouseX + 14, root.screenW - implicitWidth - 14)
        y: Math.max(dragArea.mouseY - 26, 8)
        text: Math.round(dragArea.mouseX) + ", " + Math.round(dragArea.mouseY)
        font.pixelSize: 9; font.letterSpacing: 2
        color: root.paper; opacity: 0.45
    }

    // ── Selection state ──────────────────────────────────────────────────
    QtObject {
        id: selState
        property bool dragging: false
        property real x1: 0; property real y1: 0
        property real x2: 0; property real y2: 0
    }

    // ── Selection rectangle ──────────────────────────────────────────────
    Item {
        z: 2
        visible: selState.dragging
        x: Math.min(selState.x1, selState.x2)
        y: Math.min(selState.y1, selState.y2)
        width:  Math.abs(selState.x2 - selState.x1)
        height: Math.abs(selState.y2 - selState.y1)

        // Pulse driven by ags geom.js CSS: animation: select_pulse 10s ease infinite
        property real _glow: 0.6
        SequentialAnimation on _glow {
            running: selState.dragging; loops: Animation.Infinite
            NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.25; duration: 1800; easing.type: Easing.InOutSine }
        }

        // Outer glow layers — approximate box-shadow: 0 0 10px #f4f0e1
        Repeater {
            model: 6
            Rectangle {
                property int pad: (index + 1) * 3
                x: -pad; y: -pad
                width: parent.width + pad * 2; height: parent.height + pad * 2
                color: "transparent"
                border.color: root.paper
                border.width: 1
                opacity: (0.20 - index * 0.03) * parent._glow
            }
        }

        // Main border — 3px like ags .nier-geom-select
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(70/255, 63/255, 46/255, 0.10)
            border.color: root.paper; border.width: 3
        }

        // Inset glow layer — approximate inset box-shadow
        Rectangle {
            anchors { fill: parent; margins: 3 }
            color: "transparent"
            border.color: Qt.rgba(214/255, 207/255, 181/255, 0.18 * parent._glow)
            border.width: 4
        }

        Text {
            anchors.centerIn: parent
            visible: parent.width > 90 && parent.height > 30
            text: Math.round(parent.width) + " × " + Math.round(parent.height)
            font.pixelSize: 10; font.letterSpacing: 2; font.weight: Font.Medium
            color: root.paper; opacity: 0.85
        }
        Repeater {
            model: 4
            Rectangle {
                x: (index === 1 || index === 3) ? parent.width  - 6 : 0
                y: (index === 2 || index === 3) ? parent.height - 6 : 0
                width: 6; height: 6; color: root.paper; opacity: 0.90
            }
        }
        Rectangle { x: parent.width/2 - 1; y: 0;               width: 2; height: 4; color: root.paper; opacity: 0.5 }
        Rectangle { x: parent.width/2 - 1; y: parent.height-4;  width: 2; height: 4; color: root.paper; opacity: 0.5 }
        Rectangle { x: 0;               y: parent.height/2 - 1; width: 4; height: 2; color: root.paper; opacity: 0.5 }
        Rectangle { x: parent.width-4;  y: parent.height/2 - 1; width: 4; height: 2; color: root.paper; opacity: 0.5 }
    }

    // ── Mouse area ───────────────────────────────────────────────────────
    MouseArea {
        id: dragArea
        z: 4; anchors.fill: parent
        // _inputReady delays enablement until compositor has committed the overlay layer change
        enabled: root.active && root._inputReady
        hoverEnabled: root.active && root._inputReady
        cursorShape: Qt.CrossCursor
        onPressed:         (mouse) => { selState.x1=mouse.x; selState.y1=mouse.y; selState.x2=mouse.x; selState.y2=mouse.y; selState.dragging=true }
        onPositionChanged: (mouse) => { selState.x2=mouse.x; selState.y2=mouse.y }
        onReleased:        (mouse) => { selState.x2=mouse.x; selState.y2=mouse.y; selState.dragging=false; root._commit() }
    }

    // ── Keyboard handler ─────────────────────────────────────────────────
    TextInput { id: keyInput; width:0; height:0; visible:false; Keys.onEscapePressed: root.cancel() }
    Timer {
        id: focusTimer; interval: 40; repeat: true; running: false
        property int attempts: 0
        onTriggered: { keyInput.forceActiveFocus(); attempts++; if (attempts>=8){ running=false; attempts=0 } }
    }

    // ── Input readiness delay ─────────────────────────────────────────────
    // 80 ms ≈ 5 frames @ 60 Hz; gives the compositor time to move the surface
    // to the overlay layer before we accept mouse input.
    Timer {
        id: inputDelayTimer; interval: 80; repeat: false
        onTriggered: root._inputReady = true
    }

    // ── Exec ─────────────────────────────────────────────────────────────
    Process {
        id: regionExecP; running: false
        onExited: {
            if (root._capturing) {
                root._capturing  = false
                root._triActive  = false
                root._dissolving = true
                // Use a Process instead of a Timer so the delay fires even when this
                // Item is invisible (Qt may suspend Timers on invisible items).
                dissolveDelayP.running = false
                dissolveDelayP.running = true
            }
        }
    }

    Process {
        id: dissolveDelayP
        command: ["sh", "-c", "sleep 0.76"]
        running: false
        onExited: { root._dissolving = false; root.finished() }
    }

    // 80 ms gives the compositor one frame to process the PanelWindow unmap
    Timer {
        id: commitTimer; interval: 80; repeat: false
        onTriggered: {
            if (root._pendingExecCmd !== "") {
                regionExecP.running = false
                regionExecP.command = ["sh", "-c", root._pendingExecCmd]
                regionExecP.running = true
                root._pendingExecCmd = ""
            }
        }
    }

    // ── API ───────────────────────────────────────────────────────────────
    function open(cmd) {
        commitTimer.stop(); _pendingExecCmd = ""
        _capturing = false; _dissolving = false
        dissolveDelayP.running = false
        pendingCmd = cmd
        selState.dragging = false
        active     = true
        _triActive = true
        _inputReady = false
        inputDelayTimer.restart()
        focusTimer.attempts = 0; focusTimer.restart()
    }

    function cancel() {
        if (!active && !_capturing) return
        commitTimer.stop(); _pendingExecCmd = ""; _capturing = false
        _triActive = false
        selState.dragging = false
        _inputReady = false
        active = false; _dissolving = true; pendingCmd = ""
        dissolveDelayP.running = false
        dissolveDelayP.running = true
        regionCancelled()
    }

    function _commit() {
        var x1 = Math.round(Math.min(selState.x1, selState.x2)) + screenX
        var y1 = Math.round(Math.min(selState.y1, selState.y2)) + screenY
        var w  = Math.abs(Math.round(selState.x2 - selState.x1))
        var h  = Math.abs(Math.round(selState.y2 - selState.y1))
        if (w < 5 || h < 5) { cancel(); return }
        var geom = x1 + "," + y1 + " " + w + "x" + h
        if (pendingCmd !== "") _pendingExecCmd = pendingCmd.replace("NIER_GEOM", geom)
        active = false
        _capturing = true
        _inputReady = false
        pendingCmd = ""
        commitTimer.start()
        regionDone()
    }
}
