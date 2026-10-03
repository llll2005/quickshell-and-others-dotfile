package main

// askpass — sudo's SUDO_ASKPASS helper, in the Void. sudo runs it (as voidbox-askpass)
// with its prompt as the argument and reads the password from stdout; the screen is
// drawn on /dev/tty, so it works inside any terminal, a Linux VT included.
// sudo calls it again after a wrong password: a state file per sudo process turns the
// second and third calls into "TRY 2/3".

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type askModel struct {
	l          look
	w, h       int
	pass       []rune
	cmd, user  string
	attempt    int
	t0         time.Time
	blink      bool
	done       bool
	cancelled  bool
	exitT0     time.Time
}

type frameMsg time.Time

func frame(d time.Duration) tea.Cmd {
	return tea.Tick(d, func(t time.Time) tea.Msg { return frameMsg(t) })
}

func (m askModel) Init() tea.Cmd { return frame(16 * time.Millisecond) }

func (m askModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
	case frameMsg:
		if m.done {
			if time.Since(m.exitT0) > 260*time.Millisecond {
				return m, tea.Quit
			}
			return m, frame(16 * time.Millisecond)
		}
		if time.Since(m.t0) < 520*time.Millisecond { // the words scrambling in
			return m, frame(16 * time.Millisecond)
		}
		m.blink = !m.blink
		return m, frame(530 * time.Millisecond)
	case tea.KeyMsg:
		if m.done {
			return m, nil
		}
		switch msg.Type {
		case tea.KeyEnter:
			if len(m.pass) > 0 {
				m.done, m.exitT0 = true, time.Now()
				return m, frame(16 * time.Millisecond)
			}
		case tea.KeyEsc, tea.KeyCtrlC, tea.KeyCtrlD:
			m.cancelled = true
			return m, tea.Quit
		case tea.KeyBackspace:
			if len(m.pass) > 0 {
				m.pass = m.pass[:len(m.pass)-1]
			}
		case tea.KeyCtrlU, tea.KeyCtrlW:
			m.pass = nil
		case tea.KeySpace:
			m.pass = append(m.pass, ' ')
		case tea.KeyRunes:
			if !msg.Alt && len(m.pass) < 256 {
				m.pass = append(m.pass, msg.Runes...)
			}
		}
	}
	return m, nil
}

func (m askModel) View() string {
	if m.w == 0 {
		return ""
	}
	l := m.l
	t := float64(time.Since(m.t0)) / float64(520*time.Millisecond)
	k := t
	if k > 1 {
		k = 1
	}
	if m.done { // the rule folds into its diamond, then the screen goes
		k = 1 - float64(time.Since(m.exitT0))/float64(260*time.Millisecond)
		if k < 0 {
			k = 0
		}
	}
	failed := m.attempt > 1
	mark := l.fg
	if failed {
		mark = l.warn
	}
	title := "AUTHORIZATION REQUIRED"
	if m.done {
		title = "SUBMITTED"
	}

	var dots strings.Builder
	n := len(m.pass)
	if n > 24 {
		n = 24
	}
	for i := 0; i < n; i++ {
		dots.WriteString(l.fg.Render(l.dia) + " ")
	}
	caret := l.fg.Render(l.hollow)
	if m.blink && !m.done {
		caret = l.faint.Render(l.hollow)
	}
	field := dots.String() + caret
	if len(m.pass) == 0 {
		field = caret + "  " + l.faint.Render(spaced("PASSWORD"))
	}
	under := l.dim.Render(strings.Repeat(l.line, 40))
	if failed {
		under = l.warn.Render(strings.Repeat(l.line, 40))
	}

	status := " "
	if failed {
		status = l.warn.Render(spaced(fmt.Sprintf("WRONG PASSWORD  ·  TRY %d/3", m.attempt)))
	}
	what := l.dim.Render("sudo " + m.cmd)
	if m.cmd == "" {
		what = l.dim.Render("sudo")
	}
	lines := []string{
		mark.Render(l.hollow),
		"",
		l.bold.Render(spaced(title)),
		"",
		l.rule(36, k, mark),
		"",
		what,
		l.faint.Render("AS  ") + l.fg.Render(spaced(strings.ToUpper(m.user))),
		"",
		field,
		under,
		"",
		status,
		"",
		l.faint.Render("↵ ") + l.dim.Render(spaced("AUTHORIZE")) + "     " + l.faint.Render("ESC ") + l.dim.Render(spaced("CANCEL")),
	}
	for i := range lines {
		lines[i] = centre(lines[i], m.w)
	}
	body := strings.Join(lines, "\n")
	return lipgloss.Place(m.w, m.h, lipgloss.Center, lipgloss.Center, body)
}

// attempt: 1 for a new sudo, then 2, 3 when the same sudo asks again
func nextAttempt() int {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	path := filepath.Join(dir, fmt.Sprintf("voidbox-askpass-%d", os.Getppid()))
	n := 1
	if st, err := os.Stat(path); err == nil && time.Since(st.ModTime()) < 2*time.Minute {
		if b, err := os.ReadFile(path); err == nil {
			if v, err := strconv.Atoi(strings.TrimSpace(string(b))); err == nil {
				n = v + 1
			}
		}
	}
	_ = os.WriteFile(path, []byte(strconv.Itoa(n)), 0600)
	return n
}

func runAskpass(prompt string) int {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return 1
	}
	defer tty.Close()
	user := os.Getenv("USER")
	if m := regexp.MustCompile(`for ([^:]+):`).FindStringSubmatch(prompt); m != nil {
		user = m[1]
	}
	l := newLook(lipgloss.NewRenderer(tty), loadPalette())
	m := askModel{l: l, cmd: os.Getenv("VOIDBOX_CMD"), user: user, attempt: nextAttempt(), t0: time.Now()}
	res, err := tea.NewProgram(m, tea.WithInput(tty), tea.WithOutput(tty), tea.WithAltScreen()).Run()
	if err != nil {
		return 1
	}
	mm := res.(askModel)
	if mm.cancelled || len(mm.pass) == 0 {
		return 1
	}
	fmt.Println(string(mm.pass))
	return 0
}
