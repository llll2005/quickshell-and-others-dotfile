import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../services"
import "../settings"

// Floating media player (PlayerCard) on every screen, fed by services/Media.qml.
//   qs ipc call player toggle | show | hide | front   (front: above / below windows)
// The windows are mapped only while the card is shown or sliding out.
Scope {
    id: root
    property bool visibleCards: false
    property bool onTop: false

    IpcHandler {
        target: "player"
        function toggle(): void { root.visibleCards = !root.visibleCards }
        function show(): void   { root.visibleCards = true }
        function hide(): void   { root.visibleCards = false }
        function front(): void  { root.onTop = !root.onTop }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; right: true }
            margins.top: Math.round(modelData.height * Settings.playerPositionY)
            margins.right: 20
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: root.onTop
            color: "transparent"
            visible: card.mapped
            implicitWidth: Settings.playerWidth
            implicitHeight: card.implicitHeight
            PlayerCard {
                id: card
                anchors.fill: parent
                mprisPlayer: Media.player
                mpTitle:    Media.title  !== "" ? Media.title  : "END OF EVANGELION"
                mpArtist:   Media.artist !== "" ? Media.artist : "NEON GENESIS // ANNO"
                mpCoverUrl: Media.artUrl
                mpPlaying:  Media.playing
                mpPosition: Media.position
                mpLength:   Media.length > 0 ? Media.length : 341
            }
            Connections {
                target: root
                function onVisibleCardsChanged() { if (card.shown !== root.visibleCards) card.toggleVisible() }
            }
            // its own ✕ closes them all
            Connections { target: card; function onShownChanged() { root.visibleCards = card.shown } }
        }
    }
}
