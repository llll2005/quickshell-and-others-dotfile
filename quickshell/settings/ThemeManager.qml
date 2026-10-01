import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel

// Themes: config/themes/<name>.conf; `[general] theme` in config/shell.conf picks one.
//   qs ipc call theme list          the installed themes
//   qs ipc call theme set <name>    preview one now (not saved; `reset` goes back)
//   qs ipc call theme current
// It also carries the theme over to fcitx5's own candidate window and Hyprland's
// window borders (scripts/theme-sync.py; `[sync]` in shell.conf): at start and after
// any theme / config change, previews included; the script only reloads what changed.
Scope {
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

    Process {
        id: sync
        command: ["python3", Quickshell.shellDir + "/scripts/theme-sync.py", Config.themeName]
        stdout: SplitParser { onRead: (l) => console.log(l) }
    }
    Timer {
        id: syncT; interval: 400; running: true     // also once at start
        onTriggered: { if (sync.running) restart(); else sync.running = true }
    }
    Connections {
        target: Config
        function onThemeNameChanged() { syncT.restart() }
        function onThemeChanged()     { syncT.restart() }
        function onShellChanged()     { syncT.restart() }
    }
}
