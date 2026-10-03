//@ pragma IconTheme breeze
// NieR:Automata desktop shell for Hyprland — entry point. Each part is
// self-contained (its windows, IPC and data); this file only lists them.
// Configuration: config/shell.conf and config/themes/*.conf (live-reloaded).
import QtQuick
import Quickshell
import "widgets"
import "components"
import "settings"
import "services"

ShellRoot {
    ThemeManager {}     // theme IPC + fcitx5 / Hyprland colour sync

    // ── resident ──
    CornerHud {}        // top-right HUD: stats, calendar, workspaces, volume/brightness OSD
    Notifications {}    // notification daemon + popups (history: services/Notifs.qml)
    ImePanel {}         // fcitx5 candidate window (kimpanel bridge)
    Player {}           // floating media player
    Companions {}       // sprites (off by default)
    WindowFx {}         // window open / close / focus effects (imecaret plugin)

    // ── popups (components/Popup.qml: glass backdrop, focused screen, Overlay) ──
    Menu {}             // app launcher          qs ipc call menu toggle
    ScreenCapture {}    // capture panel         qs ipc call capture toggle
    ControlCenter {}    // system controls       qs ipc call ctrl toggle
    Clipboard {}        // clipboard history     qs ipc call clip toggle
    AuthPrompt {}       // the polkit agent      qs ipc call auth status · cancel
    WsMover {}          // move a workspace      qs ipc call wsmove open
    SettingsPanel {}    // every switch + health qs ipc call settings toggle — always on, no option disables it

    // the effects layer (click / typing bursts), and the helpers every feature needs
    // (the Hyprland plugin, the cliphist watchers) checked and started with the shell
    Component.onCompleted: { Fx.init(); Health.init() }
}
