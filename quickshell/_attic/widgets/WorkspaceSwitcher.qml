import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════
//  WorkspaceSwitcher — 精緻小卡 B 向  NieR × 地雷系 × Y2K
//  5 cards, stride 154 px, 128×146 base. Appears on ws change, 2.8s.
// ═══════════════════════════════════════════════════════════════════════
ShellRoot {
    id: wsRoot

    // ── CJK numerals ────────────────────────────────────────────────
    readonly property var cjk: [
        "","壹","貳","參","肆","伍","陸","柒","捌","玖","拾",
        "拾壹","拾貳","拾參","拾肆","拾伍","拾陸","拾柒","拾捌","拾玖","貳拾"
    ]
    function wsNum(n) { return (n >= 1 && n <= 20) ? cjk[n] : String(n) }

    // ── Y2K 暗黑甜美 Palette ─────────────────────────────────────────
    readonly property color cBg:     "#07040f"   // void black
    readonly property color cSurf:   "#0d0618"   // deep plum surface
    readonly property color cRose:   "#8c1a4a"   // blood rose
    readonly property color cHot:    "#e8246a"   // hot pink glow
    readonly property color cPink:   "#ff6eb4"   // bright pink
    readonly property color cPurple: "#5c1090"   // deep violet
    readonly property color cCream:  "#f4dde8"   // warm parchment
    readonly property color cMuted:  "#b890a8"   // dusty rose
    readonly property color cDim:    "#351530"   // dark plum

    // ── Global state ─────────────────────────────────────────────────
    property var clients:  []
    property var monWsMap: ({})

    function appsForWs(wsId) {
        return clients.filter(function(c) { return c.workspace && c.workspace.id === wsId })
    }

    // ── Hyprland events ──────────────────────────────────────────────
    Process {
        id: evtProc; running: false
        command: ["python3", "/home/LnoArch/.config/quickshell/scripts/hypr-events.py"]
        stdout: SplitParser {
            onRead: function(line) {
                line = line.trim()
                if (line.startsWith("workspace>>")) {
                    var id = parseInt(line.slice(11))
                    if (!isNaN(id)) clientProc.running = true
                } else if (line.startsWith("focusedmon>>")) {
                    var p = line.slice(12).split(",")
                    if (p.length >= 2) {
                        var m = wsRoot.monWsMap; m[p[0]] = parseInt(p[1]); wsRoot.monWsMap = m
                    }
                } else if (line.startsWith("monitorWorkspace>>")) {
                    var q = line.slice(18).split(",")
                    if (q.length >= 2) {
                        var m2 = wsRoot.monWsMap; m2[q[0]] = parseInt(q[1]); wsRoot.monWsMap = m2
                    }
                }
            }
        }
        onRunningChanged: if (!running) evtRestart.start()
    }
    Timer { id: evtRestart; interval: 1000; onTriggered: evtProc.running = true }

    Process {
        id: clientProc; running: false
        command: ["sh", "-c", "hyprctl clients -j"]
        stdout: StdioCollector {
            onStreamFinished: { try { wsRoot.clients = JSON.parse(this.text) } catch(e) {} }
        }
        onRunningChanged: if (!running) monProc.running = true
    }
    Process {
        id: monProc; running: false
        command: ["sh", "-c", "hyprctl monitors -j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var ms = JSON.parse(this.text); var m = {}
                    for (var i = 0; i < ms.length; i++)
                        m[ms[i].name] = ms[i].activeWorkspace.id
                    wsRoot.monWsMap = m
                } catch(e) {}
            }
        }
    }

    Component.onCompleted: { evtProc.running = true; clientProc.running = true }
    Timer { interval: 400; running: true; repeat: true; onTriggered: monProc.running = true }

    // ── Per-screen panels ────────────────────────────────────────────
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors.top: true; anchors.left: true; anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            aboveWindows: shown
            implicitWidth:  modelData.width
            implicitHeight: modelData.height

            property bool shown:   false
            property int  curWs:   wsRoot.monWsMap[modelData.name] ?? 1
            property int  _prevWs: -1

            onCurWsChanged: {
                if (_prevWs !== -1 && curWs !== _prevWs) { shown = true; dismissTimer.restart() }
                _prevWs = curWs
            }
            Component.onCompleted: _prevWs = curWs
            Timer { id: dismissTimer; interval: 2800; onTriggered: win.shown = false }

            // ── Overlay ────────────────────────────────────────────
            Item {
                anchors.fill: parent
                opacity: win.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.InOutQuad } }

                Item {
                    id: carousel
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: win.shown
                        ? Math.round(win.modelData.height * 0.09)
                        : Math.round(win.modelData.height * 0.09) - 60
                    Behavior on y {
                        NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.5 }
                    }

                    readonly property int cW:     128
                    readonly property int cH:     146
                    readonly property int stride: 154
                    readonly property var scls:   [0.55, 0.77, 1.0, 0.77, 0.55]
                    readonly property var opcs:   [0.12, 0.44, 1.0, 0.44, 0.12]
                    readonly property var appClr: ["#e8246a", "#ff6eb4", "#8c3aaa", "#c8a050"]

                    width:  stride * 5
                    height: cH

                    // ── Backdrop ──────────────────────────────────
                    Rectangle {
                        anchors {
                            fill: parent; margins: -22
                            topMargin: -14; bottomMargin: -14
                        }
                        radius: 12
                        color: wsRoot.cBg
                        opacity: 0.93

                        // top gradient line
                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 1
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.00; color: "transparent" }
                                GradientStop { position: 0.15; color: wsRoot.cDim }
                                GradientStop { position: 0.40; color: wsRoot.cRose }
                                GradientStop { position: 0.60; color: wsRoot.cHot }
                                GradientStop { position: 0.85; color: wsRoot.cPurple }
                                GradientStop { position: 1.00; color: "transparent" }
                            }
                        }
                        // bottom gradient line
                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                            height: 1
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.3; color: wsRoot.cDim }
                                GradientStop { position: 0.7; color: wsRoot.cRose }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                        }
                        // inner top glow bleed
                        Rectangle {
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 18
                            gradient: Gradient {
                                GradientStop { position: 0; color: Qt.rgba(wsRoot.cRose.r, wsRoot.cRose.g, wsRoot.cRose.b, 0.06) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                        }
                        // scanlines
                        Repeater {
                            model: Math.ceil((carousel.cH + 28) / 4)
                            Rectangle { y: index * 4; width: parent.width; height: 1; color: Qt.rgba(0,0,0,0.08) }
                        }
                    }

                    // ── 5 Cards ────────────────────────────────────
                    Repeater {
                        model: 5
                        delegate: Item {
                            id: card
                            property int  off:     index - 2
                            property int  wsId:    win.curWs + off
                            property bool isCur:   off === 0
                            property bool phantom: wsId < 1 || wsId > 20
                            property var  apps:    wsRoot.appsForWs(wsId)

                            width:  carousel.cW
                            height: carousel.cH
                            x:      index * carousel.stride + (carousel.stride - carousel.cW) / 2
                            y:      0
                            scale:  carousel.scls[index]
                            opacity: phantom ? carousel.opcs[index] * 0.28 : carousel.opcs[index]
                            transformOrigin: Item.Center
                            z: 3 - Math.abs(off)

                            // outer glow rings (current card only)
                            Repeater {
                                model: isCur ? 2 : 0
                                Rectangle {
                                    anchors.centerIn: parent
                                    width:  card.width  + (index + 1) * 10
                                    height: card.height + (index + 1) * 7
                                    radius: 11 + (index + 1) * 3
                                    color: "transparent"
                                    border.color: index === 0
                                        ? Qt.rgba(wsRoot.cHot.r, wsRoot.cHot.g, wsRoot.cHot.b, 0.28)
                                        : Qt.rgba(wsRoot.cRose.r, wsRoot.cRose.g, wsRoot.cRose.b, 0.10)
                                    border.width: 1
                                }
                            }

                            // card border → inner fill
                            Rectangle {
                                anchors.fill: parent; radius: 10
                                color: isCur ? wsRoot.cRose : wsRoot.cDim
                                opacity: isCur ? 1.0 : 0.45

                                SequentialAnimation on color {
                                    running: isCur && win.shown; loops: Animation.Infinite
                                    ColorAnimation { from: wsRoot.cRose; to: wsRoot.cPurple; duration: 2200; easing.type: Easing.InOutSine }
                                    ColorAnimation { from: wsRoot.cPurple; to: wsRoot.cRose; duration: 2200; easing.type: Easing.InOutSine }
                                }
                                Rectangle {
                                    anchors.fill: parent; anchors.margins: 1; radius: 9
                                    color: isCur ? "#0c0418" : "#080212"
                                }
                            }

                            // top accent strip
                            Rectangle {
                                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 1; topMargin: 1 }
                                height: 3; radius: 1
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: isCur ? wsRoot.cRose : wsRoot.cDim }
                                    GradientStop { position: 0.5; color: isCur ? wsRoot.cHot  : Qt.rgba(wsRoot.cDim.r, wsRoot.cDim.g, wsRoot.cDim.b, 0.5) }
                                    GradientStop { position: 1.0; color: isCur ? wsRoot.cPurple : wsRoot.cDim }
                                }
                                SequentialAnimation on opacity {
                                    running: isCur && win.shown; loops: Animation.Infinite
                                    NumberAnimation { to: 0.5; duration: 1400; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                                }
                            }

                            // corner ✦ ornaments
                            Repeater {
                                model: 4
                                Text {
                                    x: [5, card.width-12, 5, card.width-12][index]
                                    y: [4, 4, card.height-13, card.height-13][index]
                                    text: "✦"; font.pixelSize: 6
                                    color: isCur ? wsRoot.cHot : wsRoot.cDim
                                    SequentialAnimation on opacity {
                                        running: isCur && win.shown; loops: Animation.Infinite
                                        NumberAnimation { to: 0.18; duration: 720 + index * 190; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 0.85; duration: 720 + index * 190; easing.type: Easing.InOutSine }
                                    }
                                }
                            }

                            // ── Content ──────────────────────────
                            Column {
                                anchors {
                                    top: parent.top; topMargin: 14
                                    left: parent.left; right: parent.right
                                }
                                spacing: 0

                                // Numeral
                                Item {
                                    width: parent.width; height: 46
                                    // shadow
                                    Text {
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: 1
                                        anchors.verticalCenterOffset:   1
                                        text: phantom ? "·" : wsRoot.wsNum(wsId)
                                        font.pixelSize: isCur ? 26 : 20
                                        font.family:    "Share Tech Mono"
                                        color: Qt.rgba(wsRoot.cRose.r, wsRoot.cRose.g, wsRoot.cRose.b, 0.55)
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        text: phantom ? "·" : wsRoot.wsNum(wsId)
                                        font.pixelSize: isCur ? 26 : 20
                                        font.family:    "Share Tech Mono"
                                        color: isCur ? wsRoot.cCream : wsRoot.cMuted
                                    }
                                }

                                // ◆ divider
                                Item {
                                    width: parent.width; height: 14
                                    Text {
                                        anchors.centerIn: parent
                                        text: "◆"; font.pixelSize: 5
                                        color: isCur ? wsRoot.cHot : wsRoot.cDim
                                    }
                                    Rectangle {
                                        anchors.right: parent.horizontalCenter; anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width * 0.30; height: 1
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: "transparent" }
                                            GradientStop { position: 1; color: isCur ? wsRoot.cRose : wsRoot.cDim }
                                        }
                                    }
                                    Rectangle {
                                        anchors.left: parent.horizontalCenter; anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width * 0.30; height: 1
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0; color: isCur ? wsRoot.cRose : wsRoot.cDim }
                                            GradientStop { position: 1; color: "transparent" }
                                        }
                                    }
                                }

                                // app dots row
                                Item {
                                    width: parent.width; height: 18; visible: !phantom
                                    Text {
                                        anchors.centerIn: parent
                                        visible: card.apps.length === 0
                                        text: "空"; font.pixelSize: 9; font.family: "Share Tech Mono"
                                        color: wsRoot.cDim; opacity: 0.7
                                    }
                                    Row {
                                        anchors.centerIn: parent; spacing: 5
                                        visible: card.apps.length > 0
                                        Repeater {
                                            model: Math.min(card.apps.length, 4)
                                            Rectangle {
                                                width: 6; height: 6; radius: 3
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: carousel.appClr[index % 4]
                                                opacity: isCur ? 1.0 : 0.6
                                            }
                                        }
                                        Text {
                                            visible: card.apps.length > 4
                                            text: "+" + (card.apps.length - 4)
                                            font.pixelSize: 7; font.family: "Share Tech Mono"
                                            color: wsRoot.cMuted
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // app names — current card only
                                Item {
                                    width: parent.width
                                    height: isCur && !phantom && card.apps.length > 0 ? namesCol.implicitHeight + 4 : 0
                                    visible: isCur && !phantom && card.apps.length > 0
                                    Column {
                                        id: namesCol
                                        anchors { top: parent.top; topMargin: 4; left: parent.left; right: parent.right }
                                        spacing: 1
                                        Repeater {
                                            model: Math.min(card.apps.length, 3)
                                            Text {
                                                width: parent.width
                                                text: card.apps[index] ? card.apps[index].class : ""
                                                font.pixelSize: 9; font.family: "Share Tech Mono"
                                                color: wsRoot.cMuted; horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Text {
                                            visible: card.apps.length > 3
                                            width: parent.width
                                            text: "+" + (card.apps.length - 3) + " more"
                                            font.pixelSize: 8; font.family: "Share Tech Mono"
                                            color: wsRoot.cDim; horizontalAlignment: Text.AlignHCenter
                                        }
                                    }
                                }

                            } // Column (content)
                        } // card delegate
                    } // Repeater (5 cards)
                } // carousel
            } // overlay
        } // PanelWindow
    } // Variants
} // ShellRoot
