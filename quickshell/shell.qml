//@ pragma IconTheme breeze
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import QtQuick
import Qt.labs.folderlistmodel
import "widgets"
import "components"
import "settings"
import "theme"

ShellRoot {
    id: root

    // ── NOTIFICATIONS ──
    Notifications {}
    ImePanel {}         // fcitx5 candidate window (kimpanel) — Settings.imePanelEnabled
    Component.onCompleted: { Fx.init(); themeSyncT.restart() }   // effects layer (click bursts); theme sync

    // ── themes: config/themes/<name>.conf; `[general] theme` in config/shell.conf picks one ──
    //   qs ipc call theme list          the installed themes
    //   qs ipc call theme set <name>    preview one now (not saved; `reset` goes back)
    //   qs ipc call theme current
    FolderListModel {
        id: themeFiles
        folder: "file://" + Config.dir + "/themes"
        nameFilters: ["*.conf"]
        showDirs: false
    }
    IpcHandler {
        target: "theme"
        function list(): string {
            var out = []
            for (var i = 0; i < themeFiles.count; i++) out.push(themeFiles.get(i, "fileBaseName"))
            return out.join(" ")
        }
        function set(name: string): string { Config.themeOverride = name; return "theme: " + Config.themeName }
        function reset(): string { Config.themeOverride = ""; return "theme: " + Config.themeName }
        function current(): string { return Config.themeName }
    }

    // Carry the theme over to fcitx5's own candidate window and Hyprland's window
    // borders (scripts/theme-sync.py; `[sync]` in shell.conf). Runs at start and after
    // any theme/config change, previews included; the script only reloads what changed.
    Process {
        id: themeSync
        command: ["python3", Quickshell.shellDir + "/scripts/theme-sync.py", Config.themeName]
        stdout: SplitParser { onRead: (l) => console.log(l) }
    }
    Timer {
        id: themeSyncT; interval: 400
        onTriggered: { if (themeSync.running) restart(); else themeSync.running = true }
    }
    Connections {
        target: Config
        function onThemeNameChanged() { themeSyncT.restart() }
        function onThemeChanged()     { themeSyncT.restart() }
        function onShellChanged()     { themeSyncT.restart() }
    }

    // ── CONTROLCENTER ──

    CornerHud {}
    Menu {}
    WsMover {}
    ScreenCapture {}
    ControlCenter {}

    // ── WORKSPACE SWITCHER ── (disabled; workspace state is in TopBar)
    // WorkspaceSwitcher {}

    // ── VOLUMEBAR ── (disabled)
    // VolumeBar {}

    // ── PLAYERCTL (native MPRIS, event-driven — no subprocess polling) ──
    property bool playerVisible: false
    property bool playerOnTop:   false

    // Active player: prefer one that is currently playing, else the first
    // available. This binding reads each player's isPlaying, so it re-evaluates
    // (and switches) whenever a player starts/stops or the list changes.
    property var activePlayer: {
        var ps = Mpris.players.values
        if (!ps || ps.length === 0) return null
        for (var i = 0; i < ps.length; i++) if (ps[i] && ps[i].isPlaying) return ps[i]
        return ps[0]
    }

    readonly property string mpTitle:    activePlayer && activePlayer.trackTitle  ? activePlayer.trackTitle  : "END OF EVANGELION"
    readonly property string mpArtist:   activePlayer && activePlayer.trackArtist ? activePlayer.trackArtist : "NEON GENESIS // ANNO"
    readonly property string mpCoverUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property bool   mpPlaying:  activePlayer ? activePlayer.isPlaying : false
    readonly property real   mpPosition: activePlayer && activePlayer.lengthSupported ? activePlayer.position : 0
    readonly property real   mpLength:   activePlayer && activePlayer.length > 0 ? activePlayer.length : 341

    // ── PLAYER IPC ── (replaces /tmp/qs-toggle, /tmp/qs-front file polling)
    IpcHandler {
        target: "player"
        function toggle(): void { root.playerVisible = !root.playerVisible }
        function show():   void { root.playerVisible = true }
        function hide():   void { root.playerVisible = false }
        function front():  void { root.playerOnTop = !root.playerOnTop }
    }

    property string currentUser: Quickshell.env("USER") || "user"


    // The monitor with focus, straight from Hyprland's state. (Each popup used to run
    // active-monitor.sh — hyprctl + awk — before it could open.)
    function focusedMonitor() {
        var m = Hyprland.focusedMonitor
        return m ? m.name : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    }






    // ── PLAYER ──
    Variants {
        model:Quickshell.screens
        PanelWindow {
            required property var modelData;screen:modelData
            anchors.top:true;anchors.right:true
            margins.top:Math.round(modelData.height*Settings.playerPositionY);margins.right:20
            exclusionMode:ExclusionMode.Ignore;aboveWindows:root.playerOnTop;color:"transparent"
            implicitWidth:Settings.playerWidth;implicitHeight:playerItem.implicitHeight
            Player{id:playerItem;anchors.fill:parent
                mprisPlayer:root.activePlayer
                mpTitle:root.mpTitle;mpArtist:root.mpArtist;mpCoverUrl:root.mpCoverUrl
                mpPlaying:root.mpPlaying;mpPosition:root.mpPosition;mpLength:root.mpLength}
            Connections{target:root;function onPlayerVisibleChanged(){playerItem.toggleVisible()}}
        }
    }

    // ── COMPANIONS ──
    Variants {
        model:Settings.companionsEnabled ? Quickshell.screens : []
        PanelWindow {
            required property var modelData;screen:modelData
            anchors.bottom:true;anchors.right:true;margins.right:Settings.companionsMarginRight
            exclusionMode:ExclusionMode.Ignore;color:"transparent"
            implicitWidth:Settings.companionsSpriteSize+58;implicitHeight:compItem.implicitHeight
            Companions{id:compItem;anchors.fill:parent}
        }
    }
}
