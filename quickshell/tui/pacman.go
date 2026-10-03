package main

// pacman — a package transaction in the Void. Queries run pacman as is; anything that
// changes the system runs `sudo -A pacman …` in a pty while voidbox draws:
//   · the header, the operation, pacman's output scrolling (errors in warn)
//   · downloads as one live line each (pacman redraws them in place)
//   · pacman's questions as cards: YES / NO for [Y/n] [y/N], a numbered list for
//     providers (↑↓ · 1–9 · ↵), a toggled list for group members, and for anything it
//     doesn't recognise, the question with a line to type into
//   · sudo's password as a card too: sudo calls voidbox-askpass, which hands the
//     question to this screen over a private socket ($XDG_RUNTIME_DIR, a token) and
//     returns what you type — it never passes through pacman's output
// When pacman ends, the screen goes and the whole log is printed to the terminal, so the
// scrollback keeps every error, then one result line.

import (
	"bufio"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"golang.org/x/sys/unix"
)

// needsRoot: does this pacman operation change the system?
func needsRoot(args []string) bool {
	op, flags := byte(0), ""
	long := map[string]byte{"--sync": 'S', "--remove": 'R', "--upgrade": 'U', "--database": 'D',
		"--files": 'F', "--query": 'Q', "--deptest": 'T', "--version": 'V', "--help": 'h'}
	for _, a := range args {
		if a == "--" {
			break
		}
		if strings.HasPrefix(a, "--") {
			if o, ok := long[a]; ok && op == 0 {
				op = o
			}
			switch a {
			case "--search":
				flags += "s"
			case "--info":
				flags += "i"
			case "--list":
				flags += "l"
			case "--groups":
				flags += "g"
			case "--print":
				flags += "p"
			case "--refresh":
				flags += "y"
			case "--sysupgrade":
				flags += "u"
			case "--clean":
				flags += "c"
			case "--downloadonly":
				flags += "w"
			case "--check":
				flags += "k"
			}
			continue
		}
		if strings.HasPrefix(a, "-") && len(a) > 1 {
			for i := 1; i < len(a); i++ {
				ch := a[i]
				if ch >= 'A' && ch <= 'Z' && op == 0 {
					op = ch
				} else {
					flags += string(ch)
				}
			}
		}
	}
	has := func(s string) bool { return strings.ContainsAny(flags, s) }
	switch op {
	case 'R', 'U':
		return true
	case 'S':
		return has("yucw") || !has("silgp")
	case 'F':
		return has("y")
	case 'D':
		return !has("k")
	}
	return false
}

type outMsg []byte
type exitMsg int
type idleMsg int
type quitMsg struct{}
type askMsg struct {
	conn   net.Conn
	prompt string
}

type pkind int

const (
	pNone pkind = iota
	pAuth
	pYesNo
	pChoice
	pMulti
	pRaw
)

type item struct {
	n     int
	label string
}

type pacModel struct {
	l      look
	w, h   int
	args   []string
	master *os.File

	lines    []string // finished lines, as pacman wrote them
	cur      string   // the line being drawn (\r rewinds it)
	cr       bool
	rest     []byte // an incomplete UTF-8 sequence carried to the next read
	prog     map[string]string
	progKeys []string
	errs     []string
	seq      int

	kind    pkind
	q       string
	yes     bool
	items   []item
	sel     int
	picked  map[int]bool
	input   []rune
	conn    net.Conn
	authTry int

	done bool
	code int
	t0   time.Time
	tick bool
}

var (
	progRe   = regexp.MustCompile(`\d+%\s*$`)
	yesnoRe  = regexp.MustCompile(`^(.*?)\s*\[([Yy])/([Nn])\]\s*$`)
	choiceRe = regexp.MustCompile(`[(（][^()（）]*=\s*([^()（）]+?)\s*[)）]\s*[:：]?\s*$`)
	numRe    = regexp.MustCompile(`(\d+)\)\s+(\S+)`)
	askEndRe = regexp.MustCompile(`[:：?？]\s*$`)
	errRe    = regexp.MustCompile(`^\s*(error|錯誤)[:：]`)
	warnRe   = regexp.MustCompile(`^\s*(warning|警告)[:：]`)
)

func (m pacModel) Init() tea.Cmd { return pulse() }

func pulse() tea.Cmd {
	return tea.Tick(500*time.Millisecond, func(t time.Time) tea.Msg { return frameMsg(t) })
}

func (m *pacModel) send(s string) { _, _ = m.master.Write([]byte(s)) }

func (m *pacModel) feed(b []byte) {
	b = append(m.rest, b...)
	m.rest = nil
	// keep a split multi-byte rune for the next read
	cut := len(b)
	for i := len(b) - 1; i >= 0 && i >= len(b)-3; i-- {
		c := b[i]
		if c&0xC0 == 0x80 {
			continue
		}
		if c >= 0xC0 {
			need := 2
			if c >= 0xE0 {
				need = 3
			}
			if c >= 0xF0 {
				need = 4
			}
			if len(b)-i < need {
				cut = i
			}
		}
		break
	}
	m.rest = append([]byte{}, b[cut:]...)
	for _, r := range string(b[:cut]) {
		switch r {
		case '\n':
			m.endLine()
		case '\r':
			m.cr = true
		default:
			if m.cr {
				m.cur, m.cr = "", false
			}
			m.cur += string(r)
		}
	}
}

func (m *pacModel) endLine() {
	line := m.cur
	m.cur, m.cr = "", false
	plain := strings.TrimRight(stripANSI(line), " ")
	if strings.TrimSpace(plain) == "" && len(m.lines) > 0 && strings.TrimSpace(stripANSI(m.lines[len(m.lines)-1])) == "" {
		return
	}
	if progRe.MatchString(plain) && strings.Contains(plain, "[") {
		key := strings.TrimSpace(plain)
		if i := strings.Index(key, "  "); i > 0 {
			key = key[:i]
		} else if i := strings.Index(key, "["); i > 0 {
			key = strings.TrimSpace(key[:i])
		}
		if _, ok := m.prog[key]; !ok {
			m.progKeys = append(m.progKeys, key)
		}
		m.prog[key] = plain
		if strings.HasPrefix(strings.TrimSpace(plain), "(") && strings.HasSuffix(plain, "100%") {
			m.lines = append(m.lines, line) // the transaction's steps stay in the log
		}
		return
	}
	m.lines = append(m.lines, line)
	if errRe.MatchString(plain) {
		m.errs = append(m.errs, strings.TrimSpace(plain))
	}
}

// classify the line pacman is waiting on
func (m *pacModel) classify(long bool) {
	q := strings.TrimSpace(stripANSI(m.cur))
	if q == "" {
		return
	}
	if mm := yesnoRe.FindStringSubmatch(q); mm != nil {
		m.kind, m.q, m.yes = pYesNo, strings.TrimSpace(strings.TrimPrefix(mm[1], "::")), mm[2] == "Y"
		return
	}
	if mm := choiceRe.FindStringSubmatch(q); mm != nil {
		def := mm[1]
		m.items, m.q = nil, ""
		for i := len(m.lines) - 1; i >= 0 && i >= len(m.lines)-10; i-- {
			pl := stripANSI(m.lines[i])
			if found := numRe.FindAllStringSubmatch(pl, -1); found != nil && m.q == "" {
				var row []item
				for _, f := range found {
					n, _ := strconv.Atoi(f[1])
					row = append(row, item{n, f[2]})
				}
				m.items = append(row, m.items...)
				continue
			}
			if strings.HasPrefix(strings.TrimSpace(pl), "::") && !strings.Contains(pl, "Repository") && !strings.Contains(pl, "套件庫") {
				m.q = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(pl), "::"))
				break
			}
		}
		if len(m.items) == 0 {
			m.kind, m.q, m.input = pRaw, q, nil
			return
		}
		if n, err := strconv.Atoi(def); err == nil { // one of them (providers)
			m.kind, m.sel = pChoice, 0
			for i, it := range m.items {
				if it.n == n {
					m.sel = i
				}
			}
		} else { // a selection (group members), all by default
			m.kind, m.sel, m.picked = pMulti, 0, map[int]bool{}
			for _, it := range m.items {
				m.picked[it.n] = true
			}
		}
		if m.q == "" {
			m.q = q
		}
		return
	}
	if long && askEndRe.MatchString(q) {
		m.kind, m.q, m.input = pRaw, q, nil
	}
}

func idleAfter(seq int, d time.Duration) tea.Cmd {
	return tea.Tick(d, func(time.Time) tea.Msg { return idleMsg(seq) })
}

func (m pacModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
		setPtySize(m.master, 24, m.w-6)
	case frameMsg:
		m.tick = !m.tick
		return m, pulse()
	case outMsg:
		m.feed(msg)
		m.seq++
		if m.kind == pRaw || m.kind == pYesNo || m.kind == pChoice || m.kind == pMulti {
			m.kind = pNone // pacman moved on
		}
		return m, tea.Batch(idleAfter(m.seq, 150*time.Millisecond), idleAfter(-m.seq, 1200*time.Millisecond))
	case idleMsg:
		if m.kind == pNone && !m.done {
			if int(msg) == m.seq {
				m.classify(false)
			} else if int(msg) == -m.seq {
				m.classify(true)
			}
		}
	case askMsg:
		if m.conn != nil {
			m.conn.Close()
		}
		m.authTry++
		m.kind, m.conn, m.input = pAuth, msg.conn, nil
	case exitMsg:
		m.done, m.code, m.kind = true, int(msg), pNone
		if m.cur != "" {
			m.endLine()
		}
		return m, tea.Tick(900*time.Millisecond, func(time.Time) tea.Msg { return quitMsg{} })
	case quitMsg:
		return m, tea.Quit
	case tea.KeyMsg:
		return m.key(msg)
	}
	return m, nil
}

func (m pacModel) key(k tea.KeyMsg) (tea.Model, tea.Cmd) {
	s := k.String()
	switch m.kind {
	case pAuth:
		switch k.Type {
		case tea.KeyEnter:
			if len(m.input) > 0 && m.conn != nil {
				fmt.Fprintf(m.conn, "OK %s\n", string(m.input))
				m.conn.Close()
				m.conn, m.input, m.kind = nil, nil, pNone
			}
		case tea.KeyEsc, tea.KeyCtrlC:
			if m.conn != nil {
				fmt.Fprint(m.conn, "CANCEL\n")
				m.conn.Close()
			}
			m.conn, m.input, m.kind = nil, nil, pNone
		case tea.KeyBackspace:
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}
		case tea.KeyCtrlU:
			m.input = nil
		case tea.KeySpace:
			m.input = append(m.input, ' ')
		case tea.KeyRunes:
			if !k.Alt {
				m.input = append(m.input, k.Runes...)
			}
		}
		return m, nil
	case pYesNo:
		switch s {
		case "left", "right", "tab":
			m.yes = !m.yes
		case "y", "Y":
			m.send("y\n")
			m.kind = pNone
		case "n", "N":
			m.send("n\n")
			m.kind = pNone
		case "enter":
			if m.yes {
				m.send("y\n")
			} else {
				m.send("n\n")
			}
			m.kind = pNone
		case "ctrl+c":
			m.send("\x03")
		}
		return m, nil
	case pChoice, pMulti:
		switch s {
		case "up":
			if m.sel > 0 {
				m.sel--
			}
		case "down":
			if m.sel < len(m.items)-1 {
				m.sel++
			}
		case " ":
			if m.kind == pMulti {
				n := m.items[m.sel].n
				m.picked[n] = !m.picked[n]
			}
		case "enter":
			if m.kind == pChoice {
				m.send(strconv.Itoa(m.items[m.sel].n) + "\n")
			} else {
				var nums []string
				all := true
				for _, it := range m.items {
					if m.picked[it.n] {
						nums = append(nums, strconv.Itoa(it.n))
					} else {
						all = false
					}
				}
				if all {
					m.send("\n")
				} else {
					m.send(strings.Join(nums, ",") + "\n")
				}
			}
			m.kind = pNone
		case "ctrl+c":
			m.send("\x03")
		default: // a row's number is its key
			if len(s) == 1 && s[0] >= '1' && s[0] <= '9' {
				n := int(s[0] - '0')
				for i, it := range m.items {
					if it.n == n {
						m.sel = i
						if m.kind == pChoice {
							m.send(strconv.Itoa(n) + "\n")
							m.kind = pNone
						} else {
							m.picked[n] = !m.picked[n]
						}
					}
				}
			}
		}
		return m, nil
	case pRaw:
		switch k.Type {
		case tea.KeyEnter:
			m.send(string(m.input) + "\n")
			m.input, m.kind = nil, pNone
		case tea.KeyBackspace:
			if len(m.input) > 0 {
				m.input = m.input[:len(m.input)-1]
			}
		case tea.KeySpace:
			m.input = append(m.input, ' ')
		case tea.KeyRunes:
			m.input = append(m.input, k.Runes...)
		case tea.KeyCtrlC:
			m.send("\x03")
		}
		return m, nil
	}
	if s == "ctrl+c" && !m.done {
		m.send("\x03")
	}
	return m, nil
}

// ── drawing ──

func (m pacModel) styleLine(raw string, w int) string {
	l := m.l
	p := strings.TrimRight(stripANSI(raw), " ")
	p = ansi.Truncate(p, w, "…")
	switch {
	case errRe.MatchString(p):
		return l.warn.Render(p)
	case warnRe.MatchString(p):
		return l.warn.Faint(true).Render(p)
	case strings.HasPrefix(strings.TrimSpace(p), "::"):
		return l.fg.Render(p)
	}
	return l.dim.Render(p)
}

func (m pacModel) card(w int) []string {
	l := m.l
	key := func(k, v string) string { return l.faint.Render(k+" ") + l.dim.Render(spaced(v)) }
	button := func(label string, on bool) string {
		if on {
			return l.r.NewStyle().Background(lipgloss.Color(l.pal.light)).Foreground(lipgloss.Color(voidBlack)).Bold(true).Render("  " + spaced(label) + "  ")
		}
		return l.dim.Render("[ " + spaced(label) + " ]")
	}
	switch m.kind {
	case pAuth:
		var dots strings.Builder
		for i := 0; i < len(m.input) && i < 24; i++ {
			dots.WriteString(l.fg.Render(l.dia) + " ")
		}
		caret := l.fg.Render(l.hollow)
		if m.tick {
			caret = l.faint.Render(l.hollow)
		}
		title, mark := l.bold.Render(spaced("AUTHORIZATION REQUIRED")), l.fg
		field := dots.String() + caret
		if len(m.input) == 0 {
			field = caret + "  " + l.faint.Render(spaced("PASSWORD"))
		}
		out := []string{mark.Render(l.dia) + "  " + title}
		if m.authTry > 1 {
			out[0] = l.warn.Render(l.dia) + "  " + title
			out = append(out, "   "+l.warn.Render(spaced(fmt.Sprintf("WRONG PASSWORD · TRY %d/3", m.authTry))))
		}
		return append(out,
			"   "+l.faint.Render("AS  ")+l.fg.Render(spaced(strings.ToUpper(os.Getenv("USER"))))+"     "+field,
			"   "+key("↵", "AUTHORIZE")+"    "+key("ESC", "CANCEL"))
	case pYesNo:
		return []string{
			l.fg.Render(l.dia) + "  " + l.bold.Render(spaced("CONFIRM")),
			"   " + l.fg.Render(ansi.Truncate(m.q, w-6, "…")),
			"   " + button("YES", m.yes) + "   " + button("NO", !m.yes),
			"   " + key("←→", "SELECT") + "    " + key("↵", "CONFIRM") + "    " + key("Y / N", "ANSWER"),
		}
	case pChoice, pMulti:
		title := "SELECT"
		if m.kind == pMulti {
			title = "SELECT MEMBERS"
		}
		out := []string{l.fg.Render(l.dia) + "  " + l.bold.Render(spaced(title)), "   " + l.dim.Render(ansi.Truncate(m.q, w-6, "…"))}
		start := 0
		if m.sel > 7 {
			start = m.sel - 7
		}
		for i := start; i < len(m.items) && i < start+8; i++ {
			it := m.items[i]
			mark := "  "
			if i == m.sel {
				mark = l.fg.Render("▸ ")
			}
			box := ""
			if m.kind == pMulti {
				box = l.faint.Render(l.hollow) + " "
				if m.picked[it.n] {
					box = l.fg.Render(l.dia) + " "
				}
			}
			label := l.dim.Render(it.label)
			if i == m.sel {
				label = l.fg.Render(it.label)
			}
			out = append(out, "   "+mark+box+l.faint.Render(fmt.Sprintf("%2d  ", it.n))+label)
		}
		keys := "   " + key("↑↓", "SELECT") + "    " + key("1–9", "PICK") + "    " + key("↵", "CONFIRM")
		if m.kind == pMulti {
			keys = "   " + key("↑↓", "SELECT") + "    " + key("SPACE / 1–9", "TOGGLE") + "    " + key("↵", "CONFIRM")
		}
		return append(out, keys)
	case pRaw:
		caret := l.fg.Render("▏")
		if m.tick {
			caret = " "
		}
		return []string{
			l.fg.Render(l.dia) + "  " + l.bold.Render(spaced("PACMAN ASKS")),
			"   " + l.fg.Render(ansi.Truncate(m.q, w-6, "…")),
			"   " + l.fg.Render(string(m.input)) + caret,
			"   " + key("↵", "SEND"),
		}
	}
	// status
	if m.done {
		if m.code == 0 {
			return []string{l.fg.Render(l.dia) + "  " + l.bold.Render(spaced("COMPLETED"))}
		}
		return []string{l.warn.Render(l.dia) + "  " + l.warn.Bold(true).Render(spaced(fmt.Sprintf("FAILED  ·  EXIT %d", m.code)))}
	}
	mark := l.fg.Render(l.dia)
	if m.tick {
		mark = l.faint.Render(l.dia)
	}
	return []string{mark + "  " + l.dim.Render(spaced("RUNNING")) + "    " + key("CTRL+C", "INTERRUPT")}
}

func (m pacModel) View() string {
	if m.w == 0 {
		return ""
	}
	// sudo's question takes the whole screen, as everywhere else a password is asked
	if m.kind == pAuth {
		status := ""
		if m.authTry > 1 {
			status = fmt.Sprintf("WRONG PASSWORD  ·  TRY %d/3", m.authTry)
		}
		return m.l.voidPrompt(m.w, m.h, promptView{
			title: "AUTHORIZATION REQUIRED", what: "$ sudo pacman " + strings.Join(m.args, " "),
			n: len(m.input), caret: !m.tick, status: status, warn: m.authTry > 1,
		})
	}
	l, w := m.l, m.w-6
	pad := "   "
	op := "pacman " + strings.Join(m.args, " ")
	head := l.fg.Render(l.dia) + "  " + l.bold.Render(spaced("PACKAGE TRANSACTION"))
	gap := w - lipgloss.Width(head) - lipgloss.Width(op)
	if gap < 2 {
		gap = 2
	}
	header := []string{"", pad + head + strings.Repeat(" ", gap) + l.dim.Render(ansi.Truncate(op, w/2, "…")),
		pad + l.faint.Render(strings.Repeat(l.line, w))}

	card := m.card(w)
	for i := range card {
		card[i] = pad + card[i]
	}
	footer := append([]string{pad + l.faint.Render(strings.Repeat(l.line, w))}, card...)

	// live downloads: the ones still moving
	var live []string
	for _, k := range m.progKeys {
		v := m.prog[k]
		if !strings.HasSuffix(v, "100%") {
			live = append(live, pad+l.fg.Render(ansi.Truncate(v, w, "…")))
		}
	}
	if len(live) > 6 {
		live = live[len(live)-6:]
	}
	if c := strings.TrimSpace(stripANSI(m.cur)); c != "" && m.kind == pNone {
		live = append(live, pad+l.fg.Render(ansi.Truncate(c, w, "…")))
	}

	room := m.h - len(header) - len(footer) - len(live) - 1
	if room < 1 {
		room = 1
	}
	var body []string
	from := len(m.lines) - room
	if from < 0 {
		from = 0
	}
	for _, ln := range m.lines[from:] {
		body = append(body, pad+m.styleLine(ln, w))
	}
	for len(body) < room {
		body = append([]string{""}, body...)
	}
	all := append(append(append(header, body...), live...), "")
	all = append(all, footer...)
	return strings.Join(all, "\n")
}

// ── running it ──

func execPlain(path string, args []string) int {
	err := syscall.Exec(path, append([]string{"pacman"}, args...), os.Environ())
	fmt.Fprintln(os.Stderr, "voidbox:", err)
	return 1
}

func runPacman(args []string) int {
	test := os.Getenv("VOIDBOX_TEST_CMD") // a stand-in for `sudo -A pacman` (tests: tui/test.py)
	if test == "" && !needsRoot(args) {
		return execPlain("/usr/bin/pacman", args)
	}
	pal := loadPalette()
	l := newLook(lipgloss.DefaultRenderer(), pal)

	// sudo's question comes back here: a private socket and a token for voidbox-askpass
	tokb := make([]byte, 16)
	_, _ = rand.Read(tokb)
	token := hex.EncodeToString(tokb)
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	sock := filepath.Join(dir, fmt.Sprintf("voidbox-%d.sock", os.Getpid()))
	_ = os.Remove(sock)
	ln, err := net.Listen("unix", sock)
	if err != nil {
		fmt.Fprintln(os.Stderr, "voidbox:", err)
		return 1
	}
	_ = os.Chmod(sock, 0600)
	defer os.Remove(sock)
	defer ln.Close()

	master, slaveName, err := openPty()
	if err != nil {
		fmt.Fprintln(os.Stderr, "voidbox:", err)
		return 1
	}
	defer master.Close()
	slave, err := os.OpenFile(slaveName, os.O_RDWR|syscall.O_NOCTTY, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "voidbox:", err)
		return 1
	}
	if ws, err := unix.IoctlGetWinsize(int(os.Stdout.Fd()), unix.TIOCGWINSZ); err == nil {
		setPtySize(master, 24, int(ws.Col)-6)
	}

	self, _ := os.Executable()
	c := exec.Command("/usr/bin/sudo", append([]string{"-A", "/usr/bin/pacman"}, args...)...)
	if test != "" {
		c = exec.Command(test, args...)
	}
	c.Env = append(os.Environ(), "SUDO_ASKPASS="+filepath.Join(filepath.Dir(self), "voidbox-askpass"),
		"VOIDBOX_SOCK="+sock, "VOIDBOX_TOKEN="+token, "VOIDBOX_CMD=pacman "+strings.Join(args, " "))
	c.Stdin, c.Stdout, c.Stderr = slave, slave, slave
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true, Setctty: true, Ctty: 0}
	if err := c.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "voidbox:", err)
		return 1
	}
	slave.Close()

	m := pacModel{l: l, args: args, master: master, prog: map[string]string{}, t0: time.Now()}
	p := tea.NewProgram(m, tea.WithAltScreen())

	go func() {
		buf := make([]byte, 8192)
		for {
			n, err := master.Read(buf)
			if n > 0 {
				p.Send(outMsg(append([]byte{}, buf[:n]...)))
			}
			if err != nil {
				return
			}
		}
	}()
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			rd := bufio.NewReader(conn)
			tok, _ := rd.ReadString('\n')
			prompt, _ := rd.ReadString('\n')
			if strings.TrimSpace(tok) != token {
				conn.Close()
				continue
			}
			p.Send(askMsg{conn, strings.TrimSpace(prompt)})
		}
	}()
	go func() {
		err := c.Wait()
		code := 0
		if ee, ok := err.(*exec.ExitError); ok {
			code = ee.ExitCode()
		} else if err != nil {
			code = 1
		}
		time.Sleep(120 * time.Millisecond) // let the last output arrive
		p.Send(exitMsg(code))
	}()

	res, err := p.Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "voidbox:", err)
		return 1
	}
	mm := res.(pacModel)

	// the whole log stays in the scrollback, then one result line
	for _, ln := range mm.lines {
		fmt.Println(ln)
	}
	fmt.Println()
	cmd := l.dim.Render("pacman " + strings.Join(args, " "))
	if kittyBig() && !l.pal.ascii { // kitty: the result at twice the size, the command under it
		word, col := "COMPLETED", l.pal.light
		if mm.code != 0 {
			word, col = fmt.Sprintf("FAILED  %d", mm.code), l.pal.warn
		}
		fmt.Print(bigTitle(word, sgrFG(col)) + "\n\n")
		fmt.Println(cmd)
		if mm.code == 0 {
			return 0
		}
		for _, e := range mm.errs {
			fmt.Println("   " + l.warn.Render(e))
		}
		return mm.code
	}
	if mm.code == 0 {
		fmt.Println(l.fg.Render(l.dia) + "  " + l.bold.Render(spaced("COMPLETED")) + "   " + cmd)
	} else {
		fmt.Println(l.warn.Render(l.dia) + "  " + l.warn.Bold(true).Render(spaced(fmt.Sprintf("FAILED · EXIT %d", mm.code))) + "   " + cmd)
		for _, e := range mm.errs {
			fmt.Println("   " + l.warn.Render(e))
		}
	}
	return mm.code
}
