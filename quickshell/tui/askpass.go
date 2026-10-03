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
	what := "$ sudo"
	if m.cmd != "" {
		what = "$ sudo " + m.cmd
	}
	status := ""
	if m.attempt > 1 {
		status = fmt.Sprintf("WRONG PASSWORD  ·  TRY %d/3", m.attempt)
	}
	return m.l.voidPrompt(m.w, m.h, promptView{
		title: "AUTHORIZATION REQUIRED", what: what, n: len(m.pass), caret: !m.blink,
		done: m.done, status: status, warn: m.attempt > 1,
	})
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
