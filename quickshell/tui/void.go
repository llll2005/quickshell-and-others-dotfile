package main

// The Void in a terminal: the shell's palette (config/themes/<theme>.conf, parsed the
// way settings/Config.qml does), the glyphs, and the few pieces every screen shares —
// a scramble that types words in, a rule with a diamond, centred lines.

import (
	"bufio"
	"fmt"
	"io"
	"math/rand"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// voidBlack: the Void's black, one step off #000000 — kitty draws a cell whose background
// equals its own default (black, unless a theme sets one) with background_opacity, so a
// pure black screen would show the desktop through
const voidBlack = "#010101"

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
		light: hexOr(shell["void.light"], "#ffffff"),
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

func (l look) centre(s string, w int) string { return l.r.PlaceHorizontal(w, lipgloss.Center, s) }

var ansiRe = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\a]*(\a|\x1b\\)|\x1b[()][0-9A-Za-z]`)

func stripANSI(s string) string { return ansiRe.ReplaceAllString(s, "") }

// ── the password screen: askpass (sudo, ssh, git), pinentry, pacman's sudo question ──
// The same composition as the shell's Void (the power exit, the lock, the polkit prompt):
// a diamond, a title, one hairline, the program's question and a mono line ("$ sudo …",
// where the exit shows its command), then the answer — a diamond per character on a
// line, the text itself, or YES / NO — a status, the keys. Every cell is painted black,
// so a translucent terminal doesn't show through.

type promptView struct {
	title   string // "AUTHORIZATION REQUIRED"
	message string // the program's own question ("Enter passphrase for key …")
	what    string // "$ sudo pacman -Syu"
	n       int    // characters typed
	echo    string // a visible answer (a user name): shown instead of the diamonds
	caret   bool   // the caret's blink phase (true = lit)
	done    bool   // submitted: no caret
	status  string // "WRONG PASSWORD · TRY 2/3"
	warn    bool   // the status (and the diamond) in warn
	confirm bool   // YES / NO instead of the field
	choice  int    // 0 YES · 1 NO
	hint    string // "TYPE PASSWORD"
	keys    [][2]string
	big     bool // kitty: the title at twice the size (see bigTitle)
}

// voidFrame: a screen as h painted lines, plus the title to lay over them at twice the
// size (kitty's text-sizing protocol draws a character over 2×2 cells; bubbletea's line
// renderer would erase its lower half, so these screens are painted whole — paint()).
type voidFrame struct {
	lines              []string
	title              string // "" = no big title
	titleRow, titleCol int
	titleSGR           string
}

func (f voidFrame) String() string { return strings.Join(f.lines, "\n") }

func (l look) voidPrompt(w, h int, p promptView) string { return l.voidScreen(w, h, p).String() }

func (l look) voidScreen(w, h int, p promptView) voidFrame {
	black := lipgloss.Color(voidBlack)
	bg := func(s lipgloss.Style) lipgloss.Style { return s.Background(black) }
	fg, dim, faint, warn := bg(l.fg), bg(l.r.NewStyle().Foreground(lipgloss.Color("#9a9a9a"))), bg(l.faint), bg(l.warn)
	sp := func(n int) string { return bg(l.r.NewStyle()).Render(strings.Repeat(" ", n)) }
	mark := fg
	if p.warn {
		mark = warn
	}

	var field strings.Builder
	switch {
	case p.confirm:
		for i, word := range []string{"YES", "NO"} {
			if i > 0 {
				field.WriteString(sp(10))
			}
			if p.choice == i {
				field.WriteString(fg.Render(l.dia) + sp(2) + fg.Render(spaced(word)))
			} else {
				field.WriteString(faint.Render(l.hollow) + sp(2) + faint.Render(spaced(word)))
			}
		}
	case p.echo != "":
		field.WriteString(fg.Render(p.echo))
		if !p.done {
			field.WriteString(sp(1))
		}
	default:
		n := p.n
		if n > 24 {
			n = 24
		}
		for i := 0; i < n; i++ {
			field.WriteString(fg.Render(l.dia) + sp(1))
		}
	}
	if !p.confirm && !p.done {
		if p.caret {
			field.WriteString(fg.Render(l.hollow))
		} else {
			field.WriteString(faint.Render(l.hollow))
		}
		if p.n == 0 && p.echo == "" {
			hint := p.hint
			if hint == "" {
				hint = "TYPE PASSWORD"
			}
			field.WriteString(sp(2) + faint.Render(spaced(hint)))
		}
	}
	under := faint
	if p.warn {
		under = warn
	}
	status := sp(1)
	if p.status != "" {
		status = warn.Render(spaced(p.status))
	}
	keys := p.keys
	if keys == nil {
		keys = [][2]string{{"↵", "AUTHORIZE"}, {"ESC", "CANCEL"}}
	}
	var kb strings.Builder
	for i, k := range keys {
		if i > 0 {
			kb.WriteString(sp(5))
		}
		kb.WriteString(faint.Render(k[0]+" ") + dim.Render(spaced(k[1])))
	}

	// the title: at twice the size where kitty can and the screen is wide enough
	title := fg.Render(spaced(p.title))
	big := p.big && !l.pal.ascii && w >= bigWidth(p.title)+6 && h >= 18
	if big {
		title = ""
	}
	lines := []string{mark.Render(l.hollow), "", title, ""}
	if big {
		lines = append(lines, "") // the big title sits a touch lower: room above the rule
	}
	lines = append(lines, dim.Render(strings.Repeat(l.line, 26)))
	if p.message != "" {
		width := w - 8
		if width > 72 {
			width = 72
		}
		msg := l.r.NewStyle().Width(width).Align(lipgloss.Center).Render(p.message)
		for _, ln := range strings.Split(msg, "\n") {
			lines = append(lines, bg(l.fg).Render(strings.TrimSpace(ln)))
		}
	}
	lines = append(lines, dim.Render(p.what), "", "", field.String())
	if !p.confirm {
		lines = append(lines, under.Render(strings.Repeat(l.line, 40)))
	}
	lines = append(lines, status, "", kb.String())

	// centred both ways, on black (the look's own renderer: the default one is bound to
	// stdout, which for askpass is the pipe to sudo — no colour, padding left unpainted)
	ws := lipgloss.WithWhitespaceBackground(black)
	blank := sp(w)
	out := make([]string, 0, h)
	top := (h - len(lines)) / 2
	if top < 0 {
		top = 0
	}
	for i := 0; i < top; i++ {
		out = append(out, blank)
	}
	for _, ln := range lines {
		if len(out) == h {
			break
		}
		out = append(out, l.r.PlaceHorizontal(w, lipgloss.Center, ln, ws))
	}
	for len(out) < h {
		out = append(out, blank)
	}
	f := voidFrame{lines: out}
	if big {
		f.title, f.titleRow, f.titleCol = p.title, top+2, (w-bigWidth(p.title))/2
		f.titleSGR = sgrRGB(l.pal.light)
	}
	return f
}

// ── big text (kitty ≥ 0.40: OSC 66, the text-sizing protocol) ──

// kittyBig: this terminal draws text at several sizes
func kittyBig() bool {
	return os.Getenv("KITTY_WINDOW_ID") != "" || os.Getenv("TERM") == "xterm-kitty"
}

// a title at twice the size keeps the Void's tracking: each letter is its own 2×2-cell
// character, with a 1-cell gap after it (3 for a word space)
func bigWidth(s string) int {
	n := 0
	for i, r := range []rune(s) {
		if i > 0 {
			n++
		}
		if r == ' ' {
			n++
		} else {
			n += 2
		}
	}
	return n
}

func bigTitle(s, sgr string) string {
	var b strings.Builder
	b.WriteString(sgr)
	for i, r := range []rune(s) {
		if i > 0 {
			b.WriteByte(' ')
		}
		if r == ' ' {
			b.WriteByte(' ')
			continue
		}
		b.WriteString("\x1b]66;s=2;" + string(r) + "\a")
	}
	b.WriteString("\x1b[0m")
	return b.String()
}

func sgrRGB(hex string) string {
	var r, g, b int
	if len(hex) == 7 {
		fmt.Sscanf(hex[1:], "%02x%02x%02x", &r, &g, &b)
	}
	return fmt.Sprintf("\x1b[0;38;2;%d;%d;%d;48;2;1;1;1m", r, g, b)
}

// sgrFG: the colour alone, on whatever the terminal's background is (the scrollback)
func sgrFG(hex string) string {
	var r, g, b int
	if len(hex) == 7 {
		fmt.Sscanf(hex[1:], "%02x%02x%02x", &r, &g, &b)
	}
	return fmt.Sprintf("\x1b[0;38;2;%d;%d;%dm", r, g, b)
}

// paint: the whole frame in one synchronized update, then the big title over it (written
// last, so the rows painted under it don't erase it)
func paint(w io.Writer, f voidFrame) {
	var b strings.Builder
	b.WriteString("\x1b[?2026h\x1b[H")
	b.WriteString(strings.Join(f.lines, "\r\n"))
	if f.title != "" {
		fmt.Fprintf(&b, "\x1b[%d;%dH%s", f.titleRow+1, f.titleCol+1, bigTitle(f.title, f.titleSGR))
	}
	b.WriteString("\x1b[?2026l")
	io.WriteString(w, b.String())
}
