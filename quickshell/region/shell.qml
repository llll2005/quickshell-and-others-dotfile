import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    property string _targetScreen: ""
    property string _regionCmd:    ""
    property string _freezeFile:   ""   // frozen frame to show + crop from ("" = live)
    property bool   _filesRead:    false
    signal dataReady()

    // When launched via nohup in background, Quickshell.screens may be empty
    // at startup (Wayland screen list not yet received by the new process).
    // Poll every 50ms until at least one screen is available, then read files.
    Timer {
        id: screenWatcher; interval: 50; repeat: true; running: true
        onTriggered: {
            if (Quickshell.screens.length > 0 && !root._filesRead) {
                root._filesRead    = true
                root._targetScreen = Quickshell.screens[0].name
                running            = false
                readScreenP.running = true
            }
        }
    }

    Process {
        id: readScreenP
        command: ["sh", "-c", "cat /tmp/qs-region-screen 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var s = this.text.trim()
                if (s !== "") root._targetScreen = s
                readCmdP.running = true
            }
        }
    }

    Process {
        id: readCmdP
        command: ["sh", "-c", "cat /tmp/qs-region-cmd 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root._regionCmd = this.text.trim()
                readFreezeP.running = true
            }
        }
    }

    Process {
        id: readFreezeP
        command: ["sh", "-c", "cat /tmp/qs-region-freeze 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root._freezeFile = this.text.trim()
                root.dataReady()
            }
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors.top: true; anchors.left: true; anchors.right: true; anchors.bottom: true
            exclusionMode: ExclusionMode.Ignore
            // Only the target monitor maps; Overlay so it also covers fullscreen windows.
            visible: regItem.active
            WlrLayershell.layer: WlrLayer.Overlay
            color: "transparent"
            WlrLayershell.keyboardFocus: regItem.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            implicitWidth: modelData.width; implicitHeight: modelData.height

            RegionSelect {
                id: regItem
                anchors.fill: parent
                screenW: modelData.width
                screenH: modelData.height
                screenX: modelData.x
                screenY: modelData.y
                // Quickshell reports logical pixels (QT_SCALE_FACTOR applied).
                // Compute physical scale from env var, default to 1.0 if unset.
                screenScale: {
                    var envScale = scaleProc.scaleValue
                    return envScale > 0 ? envScale : 1.0
                }
            }

            // Read QT_SCALE_FACTOR once at PanelWindow creation
            property real _scale: 1.0
            Process {
                id: scaleProc
                property real scaleValue: 1.0
                command: ["sh", "-c", "echo ${QT_SCALE_FACTOR:-1.0}"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        var val = parseFloat(this.text.trim())
                        scaleProc.scaleValue = isNaN(val) ? 1.0 : val
                    }
                }
            }

            Connections {
                target: root
                function onDataReady() {
                    if (modelData.name !== root._targetScreen) return
                    regItem.frozenSource = root._freezeFile
                    regItem.open(root._regionCmd)
                }
            }

            Connections {
                target: regItem
                function onFinished() { Qt.quit() }
            }
        }
    }
}
