pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Config — the user-editable settings behind Settings.qml and Theme.qml:
//
//   config/shell.conf            general options  ([general] theme = nier, …)
//   config/themes/<theme>.conf   the palette, fonts, backdrop colours
//
// INI style: `[section]`, `key = value`, `#` / `;` comments (a whole line, or ` # `
// after a value — a `#` glued to text is a colour: `c = #d6cfb5, #a99bc9  # note`),
// `"quoted"` to keep a value verbatim. Values become booleans (true/false, yes/no,
// on/off), numbers, or strings. Keys are read as "section.key".
//
// Both files are watched: saving one re-parses it and every binding on Settings /
// Theme follows at once — no restart. A theme file only needs the keys it changes;
// the rest fall back to the defaults written in Theme.qml / Settings.qml.
Singleton {
    id: cfg

    readonly property string dir: Quickshell.shellDir + "/config"
    property var shell: ({})
    property var theme: ({})
    // `qs ipc call theme set <name>` previews a theme without touching shell.conf
    property string themeOverride: ""
    readonly property string themeName: themeOverride !== "" ? themeOverride : str("general.theme", "nier")

    // ── typed reads (shell.conf) ──
    function bool(key, def) { var v = shell[key]; return typeof v === "boolean" ? v : def }
    function num(key, def)  { var v = shell[key]; return typeof v === "number" ? v : def }
    function str(key, def)  { var v = shell[key]; return v === undefined || v === "" ? def : String(v) }
    // ── theme reads ──
    function color(key, def) {
        var v = theme[key]
        return typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) ? v : def
    }
    function tnum(key, def) { var v = theme[key]; return typeof v === "number" ? v : def }
    function tstr(key, def) { var v = theme[key]; return v === undefined || v === "" ? def : String(v) }
    function colors(key, def) {     // comma-separated list of colours
        var v = theme[key]
        if (typeof v !== "string") return def
        var out = v.split(",").map(function(s) { return s.trim() })
                    .filter(function(s) { return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(s) })
        return out.length ? out : def
    }

    function parse(text) {
        var out = ({}), section = ""
        var lines = (text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            if (!l || l[0] === "#" || l[0] === ";") continue
            var sec = l.match(/^\[([^\]]+)\]\s*([#;].*)?$/)   // "[dark]   # note"
            if (sec) { section = sec[1].trim(); continue }
            var eq = l.indexOf("=")
            if (eq < 0) continue
            var k = l.substring(0, eq).trim()
            var raw = l.substring(eq + 1).trim()
            var v
            if (raw[0] === "\"") {
                var end = raw.indexOf("\"", 1)
                v = end > 0 ? raw.substring(1, end) : raw.substring(1)
            } else {
                raw = raw.replace(/\s+[#;](\s.*)?$/, "")   // "  # note" — never "#a99bc9"
                if (/^(true|yes|on)$/i.test(raw)) v = true
                else if (/^(false|no|off)$/i.test(raw)) v = false
                else if (/^-?\d+(\.\d+)?$/.test(raw)) v = parseFloat(raw)
                else v = raw
            }
            out[(section ? section + "." : "") + k] = v
        }
        return out
    }

    FileView {
        id: shellFile
        path: cfg.dir + "/shell.conf"
        blockLoading: true            // values in place before the widgets bind
        watchChanges: true
        onFileChanged: reload()
        onLoaded: cfg.shell = cfg.parse(text())
        onLoadFailed: cfg.shell = ({})
    }
    FileView {
        id: themeFile
        path: cfg.dir + "/themes/" + cfg.themeName + ".conf"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: cfg.theme = cfg.parse(text())
        onLoadFailed: cfg.theme = ({})
    }
}
