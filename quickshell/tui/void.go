package main

// The Void in a terminal: the shell's palette (config/themes/<theme>.conf, parsed the
// way settings/Config.qml does), the glyphs, and the few pieces every screen shares —
// a scramble that types words in, a rule with a diamond, centred lines.

import (
	"bufio"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

type palette struct {
	light, warn string
	ascii       bool // a Linux VT (TERM=linux): plain glyphs
}

func shellDir() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return filepath.Join(d, "quickshell")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "quickshell")
}

var hexRe = regexp.MustCompile(`^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$`)

// parseConf: `[section]` (a trailing `# note` allowed), `key = value` read as
// section.key; a comment is a whole line or " # " after a value; "quoted" verbatim.
func parseConf(path string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return out
	}
	defer f.Close()
	section := ""
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") {
			if i := strings.Index(line, "]"); i > 0 {
				section = strings.TrimSpace(line[1:i])
			}
			continue
		}
		eq := strings.Index(line, "=")
		if eq < 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.TrimSpace(line[eq+1:])
		if strings.HasPrefix(val, "\"") && strings.Count(val, "\"") >= 2 {
			val = val[1:strings.LastIndex(val, "\"")]
		} else if m := regexp.MustCompile(`\s#\s`).FindStringIndex(val); m != nil {
			val = strings.TrimSpace(val[:m[0]])
		}
		if section != "" {
			key = section + "." + key
		}
		out[key] = val
	}
	return out
}

func hexOr(v, d string) string {
	if hexRe.MatchString(v) {
		return "#" + v[len(v)-6:]
	}
	return d
}

func loadPalette() palette {
	dir := shellDir()
	shell := parseConf(filepath.Join(dir, "config", "shell.conf"))
	name := shell["general.theme"]
	if name == "" {
		name = "nier"
	}
	// the Void's ink is its own, not the theme's: [void] in shell.conf (月白, a muted red)
	_ = name
	return palette{
		light: hexOr(shell["void.light"], "#d6ecf0"),
		warn:  hexOr(shell["void.warn"], "#b8403c"),
		ascii: os.Getenv("TERM") == "linux",
	}
}

// look: the styles and glyphs for one screen (colours degrade on a plain terminal)
type look struct {
	r                          *lipgloss.Renderer
	pal                        palette
	fg, dim, faint, warn, bold lipgloss.Style
	dia, hollow, line          string
}

func newLook(r *lipgloss.Renderer, pal palette) look {
	// the Void is black by definition: never ask the terminal for its background (an
	// OSC 11 query that a silent pty never answers, and whose reply can eat keystrokes)
	r.SetHasDarkBackground(true)
	lipgloss.SetHasDarkBackground(true)
	l := look{r: r, pal: pal, dia: "◆", hollow: "◇", line: "─"}
	if pal.ascii {
		l.dia, l.hollow, l.line = "*", "o", "-"
	}
	c := lipgloss.Color(pal.light)
	l.fg = r.NewStyle().Foreground(c)
	l.bold = r.NewStyle().Foreground(c).Bold(true)
	l.dim = r.NewStyle().Foreground(c).Faint(true)
	l.faint = r.NewStyle().Foreground(lipgloss.Color("#555555"))
	l.warn = r.NewStyle().Foreground(lipgloss.Color(pal.warn))
	return l
}

// spaced: "AUTHORIZED" → "A U T H O R I Z E D" (the letterspaced system voice)
func spaced(s string) string {
	rs := []rune(s)
	var b strings.Builder
	for i, r := range rs {
		if i > 0 {
			b.WriteRune(' ')
		}
		b.WriteRune(r)
	}
	return b.String()
}

const glyphs = "▸◆▪▫░▒▓█/\\|-_=+*"

// scramble types `s` in left to right as t goes 0 → 1, through random glyphs
func scramble(s string, t float64, ascii bool) string {
	if t >= 1 {
		return s
	}
	g := []rune(glyphs)
	if ascii {
		g = []rune("#%*+=-/\\|")
	}
	rs := []rune(s)
	var b strings.Builder
	n := float64(len(rs))
	for i, r := range rs {
		at := float64(i) / n
		switch {
		case r == ' ' || t > at+0.15:
			b.WriteRune(r)
		case t > at:
			b.WriteRune(g[rand.Intn(len(g))])
		default:
			b.WriteRune(' ')
		}
	}
	return b.String()
}

// rule: ─────◆───── of width w (shrunk by k ∈ 0..1 toward its middle)
func (l look) rule(w int, k float64, mark lipgloss.Style) string {
	half := int(float64(w/2) * k)
	if half < 0 {
		half = 0
	}
	side := strings.Repeat(l.line, half)
	return l.faint.Render(side) + mark.Render(l.dia) + l.faint.Render(side)
}

func centre(s string, w int) string { return lipgloss.PlaceHorizontal(w, lipgloss.Center, s) }

var ansiRe = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\a]*(\a|\x1b\\)|\x1b[()][0-9A-Za-z]`)

func stripANSI(s string) string { return ansiRe.ReplaceAllString(s, "") }
