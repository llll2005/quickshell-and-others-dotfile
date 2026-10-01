pragma Singleton
import QtQuick
import Quickshell

// Settings — typed options for the whole shell, read from config/shell.conf through
// Config (live: saving the file updates every binding). The second argument of each
// read is the built-in default, used when the file doesn't set the key. Colours live
// in Theme (theme/Theme.qml) — Settings doesn't import it (Theme reads Config from
// this module; the other way round would make the two modules import each other).
QtObject {

    // ── general ──
    readonly property real scale: Config.num("general.scale", 1)

    // Dimensions de l'écran principal (équivalent 100vw / 100vh)
    readonly property real screenW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width  : 1920
    readonly property real screenH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080
    // Settings.vw(5) = 5 % of the screen width; Settings.s(320) = 320 × scale
    function vw(pct) { return Math.round(screenW * pct / 100) }
    function vh(pct) { return Math.round(screenH * pct / 100) }
    function s(px)   { return Math.round(px * scale) }

    // ── top status UI: CornerHud (true) or the full-width TopBar (false) ──
    readonly property bool cornerHudEnabled: Config.bool("hud.enabled", true)
    readonly property int  hudHideDelay:     Config.num("hud.hideDelay", 1400)
    readonly property int  hudOsdDuration:   Config.num("hud.osdDuration", 1700)
    readonly property bool hudTrackToast:   Config.bool("hud.trackToast", true)

    // ── glass triangle backdrop (components/TriField.qml) ──
    readonly property real backdropOpacity: Config.num("backdrop.opacity", 0.42)
    readonly property real backdropDim:     Config.num("backdrop.dim", 0.28)
    readonly property real backdropCell:    Config.num("backdrop.cellSize", 180)
    readonly property real backdropFlicker: Config.num("backdrop.flicker", 0.6)

    // ── effects (components/Fx.qml) ──
    readonly property bool clickFx:   Config.bool("effects.click", true)
    readonly property real burstSize: Config.num("effects.burstSize", 0.7)
    // window effects (widgets/WindowFx.qml, via the imecaret plugin)
    readonly property bool windowOpenFx:      Config.bool("effects.windowOpen", true)
    readonly property bool windowCloseFx:     Config.bool("effects.windowClose", true)
    readonly property bool focusReticle:      Config.bool("effects.focusReticle", true)
    readonly property bool focusReticleHover: Config.bool("effects.focusReticleHover", false)

    // ── fcitx5 candidate window (widgets/ImePanel.qml) ──
    readonly property bool imePanelEnabled: Config.bool("ime.panel", true)
    readonly property bool imeSparks:       Config.bool("ime.sparks", true)

    // ── lyrics (services/Lyrics.qml, shown in the HUD) ──
    readonly property bool lyricsEnabled: Config.bool("lyrics.enabled", true)
    readonly property real lyricsOffset:  Config.num("lyrics.offset", 0)

    // ── screen capture ──
    readonly property bool   captureFreeze:    Config.bool("capture.freeze", true)
    readonly property string captureOpenStyle: Config.str("capture.style", "iris")

    // ── notifications ──
    readonly property int notifyTimeout:         Config.num("notifications.timeout", 5000)
    readonly property int notifyCriticalTimeout: Config.num("notifications.criticalTimeout", 10000)
    readonly property int notifyHistory:         Config.num("notifications.history", 50)

    // ── player ──
    readonly property bool  playerBackground:  Config.bool("player.background", true)
    readonly property color _sepiaBg:          Config.color("sepia.bg", "#0b0a09")
    readonly property color playerBgColor:     Qt.rgba(_sepiaBg.r, _sepiaBg.g, _sepiaBg.b, 0.92)
    readonly property real  playerPositionY:   Config.num("player.positionY", 0.39)
    readonly property int   playerMarginRight: s(Config.num("player.marginRight", 20))
    readonly property int   playerWidth:       s(Config.num("player.width", 420))

    // ── companions ──
    readonly property bool companionsEnabled:     Config.bool("companions.enabled", false)
    readonly property int  companionsMarginRight: s(Config.num("companions.marginRight", 20))
    readonly property int  companionsSpriteSize:  s(Config.num("companions.spriteSize", 128))
}
