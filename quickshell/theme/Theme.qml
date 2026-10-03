pragma Singleton
import QtQuick
import Quickshell
import "../settings"

// Theme — the palette every widget draws with. Values come from
// config/themes/<theme>.conf (see settings/Config.qml; the theme is picked by
// `[general] theme = …` in config/shell.conf); anything a theme file leaves out
// falls back to the NieR defaults written here. Saving the file recolours the shell
// live.
//
// Names are roles, not colours: `paper` is whatever the cards are made of, `ink`
// whatever is written on them — a theme can turn the whole thing over.
QtObject {
    id: t

    // ── paper & ink: the popups' cards (Control Center, launcher, capture, IME…) ──
    readonly property color paper:     Config.color("palette.paper",     "#d6cfb5")   // card surface
    readonly property color ink:       Config.color("palette.ink",       "#463f2e")   // text, lines, the selector
    readonly property color inkStrong: Config.color("palette.inkStrong", "#2e2a1f")   // emphasis on paper; deepest ink
    readonly property color inkSoft:   Config.color("palette.inkSoft",   "#7a7358")   // secondary text on paper
    readonly property color accent:    Config.color("palette.accent",    "#6e2a2a")   // selector edge, marks
    readonly property color light:     Config.color("palette.light",     "#fff6cf")   // glints, flashes, active on dark
    readonly property color warn:      Config.color("palette.warn",      "#c8685c")   // warnings on dark
    readonly property color good:      Config.color("palette.good",      "#9ab58c")   // ok / charging

    // ── dark panels: the resident HUD ──
    readonly property color panel:       Config.color("dark.panel",  "#221e17")      // base
    readonly property color panelRaised: Config.color("dark.raised", "#2e2a1f")      // tracks, raised bits
    readonly property color panelText:     Config.color("dark.text",   paper)          // text & lines on it
    readonly property color panelMuted: Config.color("dark.muted", "#8f8873")     // secondary text on it
    // selected day, pins, markers (a light HUD needs something deeper than `light`) …
    readonly property color panelActive: Config.color("dark.active", light)
    // … and the text on any filled HUD block (active tab/row, selected day, current workspace)
    readonly property color panelOnFill: Config.color("dark.onFill", panelRaised)
    // open workspaces are tinted by the monitor they're on
    readonly property var   monitorColors: Config.colors("dark.monitors", [light, "#a99bc9", good, "#c98a70"])
    // how much of the month artwork's tone the HUD's lower half takes on (0 = none)
    readonly property real  monthTint: Config.tnum("dark.monthTint", 0.45)

    // ── notifications: urgency accents ──
    readonly property color urgent: Config.color("notify.critical", "#cd664d")
    readonly property color calm:   Config.color("notify.low",      "#a0c490")

    // ── sepia: the media player ──
    readonly property color sepia:   Config.color("sepia.fg", "#c8b89a")
    readonly property color sepiaBg: Config.color("sepia.bg", "#0b0a09")
    readonly property color sepiaDim: Config.color("sepia.dim", "#48463d")

    // ── glass triangle backdrop (components/TriField.qml) ──
    readonly property color triangle:      Config.color("backdrop.triangle", paper)
    readonly property color triangleGlint: Config.color("backdrop.glint",    light)
    readonly property color triangleShade: Config.color("backdrop.shade",    ink)

    // ── fonts ──
    // `[font] mono` / `cjk` in shell.conf, else the theme's, else these. One pair for the
    // whole system: kitty uses the same two. Qt falls from any face to Operator Mono, then
    // 金萱, for the glyphs it lacks (~/.config/fontconfig/conf.d/60-quickshell.conf).
    readonly property string mono: Config.str("font.mono", "") || Config.tstr("font.mono", "Operator Mono")
    readonly property string cjk:  Config.str("font.cjk", "")  || Config.tstr("font.cjk",  "jf金萱那提2.0")
    // the size of all text outside the Void: `[font] size` steps of ×1.09 (about a pixel at
    // 11 px; +2 ≈ ×1.19). Every Paper / Ink surface sets its sizes through fs(); the Void
    // (lock, polkit, the power exit, voidbox) keeps its own scale, voidStep().
    readonly property int  fontStep: Config.num("font.size", 0)
    readonly property real fontScale: Math.pow(1.09, fontStep)
    function fs(px) { return Math.max(1, Math.round(px * fontScale)) }
    // the Void's voice (lock, polkit, the power exit): `[font] void` in shell.conf (your
    // choice, any theme), else the theme's, else mono. A display face like Norse lacks
    // ◆ ▸ ░ …: the scramble then uses its own letters (voidGlyphs), and the clock sets its
    // digits in fixed cells (components/FixedDigits.qml) since its figures aren't tabular.
    // QS_VOID_FONT / QS_VOID_WEIGHT override both, for trying a face in the lock preview
    readonly property string voidFont: Quickshell.env("QS_VOID_FONT") || Config.str("font.void", "") || Config.tstr("font.void", mono)
    readonly property int    voidWeight: Number(Quickshell.env("QS_VOID_WEIGHT")) || Config.num("font.voidWeight", 400)
    // the Void's sizes: a modular scale, px at 1080 p — step k = voidBase × voidRatio^k.
    // Golden (1.618) suits the Void: few levels, a dramatic drop (12 → 19 → 31 → 51 → 82 → 133).
    //   0 labels, corners, key hints · 1 prompts, dates · 2 titles · clockStep the lock's clock
    readonly property real voidBase:      Config.num("font.voidBase", 12)
    readonly property real voidRatio:     Config.num("font.voidRatio", 1.618)
    readonly property int  voidClockStep: Config.num("font.voidClockStep", 5)
    function voidStep(k) { return Math.round(voidBase * Math.pow(voidRatio, k)) }
    // the scramble's noise: block glyphs whatever the face (Qt draws the ones a face lacks
    // from a fallback font — that's part of the decoding look)
    readonly property string voidGlyphs: "▸◆▪▫░▒▓█/\\|-_=+*"
    // the Void's ink is its own, not the theme's ([void] in shell.conf): 月白 and a muted red
    readonly property color voidLight: _hex(Config.str("void.light", ""), "#ffffff")
    readonly property color voidWarn:  _hex(Config.str("void.warn", ""), "#b8403c")
    function _hex(v, d) { return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) ? v : d }

    // ── helpers ──
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // ── legacy names (the old Theme.qml / Settings colours, for older widgets) ──
    readonly property color bg:   sepiaBg
    readonly property color fg:   sepia
    readonly property color a1:   "#c87060"
    readonly property color a2:   "#60a880"
    readonly property color a3:   "#6090c8"
    readonly property color a4:   "#c8a860"
    readonly property color ln:   alpha(sepia, 0.12)
    readonly property color lnm:  alpha(sepia, 0.22)
}
