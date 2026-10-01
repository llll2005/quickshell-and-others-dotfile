import QtQuick
import Quickshell
import Quickshell.Wayland
import "../settings"

// Animated sprites in the bottom-right corner of every screen (CompanionsCard).
// Off unless `[companions] enabled = true` in config/shell.conf.
Scope {
    Variants {
        model: Settings.companionsEnabled ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { bottom: true; right: true }
            margins.right: Settings.companionsMarginRight
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            implicitWidth: Settings.companionsSpriteSize + 58
            implicitHeight: card.implicitHeight
            CompanionsCard { id: card; anchors.fill: parent }
        }
    }
}
