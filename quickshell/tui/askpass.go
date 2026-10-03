package main

// askpass — every askpass in the Void: sudo (SUDO_ASKPASS), ssh (SSH_ASKPASS), git (which
// falls back to SSH_ASKPASS). The program runs voidbox-askpass with its prompt as the
// argument and reads the answer from stdout.
//   · in a terminal the screen is drawn on /dev/tty (a Linux VT too)
//   · with no terminal (ssh / git / sudo from a GUI app) the shell asks, over its socket
//     ($XDG_RUNTIME_DIR/qs-void-ask.sock, widgets/AuthPrompt.qml)
// The prompt picks the kind: a password (diamonds), a user name (shown), a yes/no
// question (ssh's unknown host key; SSH_ASKPASS_PROMPT=confirm), or a notice to wait on
// (SSH_ASKPASS_PROMPT=none: touch your security key). A program that asks again after a
// wrong answer gets "TRY 2/3" (a state file per asking process and prompt).

import (
	"bufio"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/term"
)

type askKind int

const (
	kSecret askKind = iota
	kText
	kConfirm
	kInfo
)

var kindNames = []string{"secret", "text", "confirm", "info"}

// askReq: one question, whoever draws it
type askReq struct {
	kind    askKind
	message string // the program's prompt
	detail  string // who asks: "$ sudo pacman -Syu", "$ ssh host"
	status  string // "WRONG PASSWORD · TRY 2/3"
	hint    string // "PASSWORD", "PASSPHRASE", "USER NAME"
	sudo    bool
	word    bool // a yes/no answered with the word on stdout (ssh's host key), not the exit code
}

func runtimeDir() string {
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return d
	}
	return os.TempDir()
}

// parentCmd: the asking process's command line
func parentCmd() (comm string, args []string) {
	ppid := os.Getppid()
	b, _ := os.ReadFile(fmt.Sprintf("/proc/%d/cmdline", ppid))
	for _, a := range strings.Split(strings.TrimRight(string(b), "\x00"), "\x00") {
		if a != "" {
			args = append(args, a)
		}
	}
	c, _ := os.ReadFile(fmt.Sprintf("/proc/%d/comm", ppid))
	return strings.TrimSpace(string(c)), args
}

func clip(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

func classify(prompt string) askReq {
	q := askReq{kind: kSecret, message: strings.TrimSpace(prompt), hint: "PASSWORD"}
	comm, args := parentCmd()
	switch {
	case comm == "sudo":
		q.sudo = true
		q.message = "" // "[sudo] password for x:" says nothing the title doesn't
		cmd := os.Getenv("VOIDBOX_CMD")
		if cmd == "" && len(args) > 1 {
			rest := args[1:]
			for len(rest) > 0 && strings.HasPrefix(rest[0], "-") {
				rest = rest[1:]
			}
			cmd = strings.Join(rest, " ")
		}
		q.detail = strings.TrimSpace("$ sudo " + cmd)
	case strings.HasPrefix(comm, "git-remote-http") && len(args) > 2:
		q.detail = "$ git · " + args[2]
	case len(args) > 0:
		q.detail = "$ " + filepath.Base(args[0]) + " " + strings.Join(args[1:], " ")
	}
	q.detail = clip(strings.TrimSpace(q.detail), 90)

	low := strings.ToLower(prompt)
	switch {
	case os.Getenv("SSH_ASKPASS_PROMPT") == "confirm":
		q.kind = kConfirm
	case os.Getenv("SSH_ASKPASS_PROMPT") == "none":
		q.kind = kInfo
	case strings.Contains(low, "(yes/no"):
		q.kind, q.word = kConfirm, true
	case regexp.MustCompile(`^(username|user name|login)\b`).MatchString(low):
		q.kind, q.hint = kText, "USER NAME"
	case strings.Contains(low, "passphrase"):
		q.hint = "PASSPHRASE"
	case strings.Contains(low, "pin"):
		q.hint = "PIN"
	}
	if q.kind == kSecret || q.kind == kText {
		if n := nextAttempt(prompt); n > 1 {
			if q.sudo {
				q.status = fmt.Sprintf("WRONG PASSWORD  ·  TRY %d/3", n)
			} else {
				q.status = fmt.Sprintf("TRY AGAIN  ·  %d", n)
			}
		}
	}
	return q
}

// attempt: 1 for a new question, then 2, 3… when the same process asks the same again
func nextAttempt(prompt string) int {
	h := fnv.New32a()
	h.Write([]byte(prompt))
	path := filepath.Join(runtimeDir(), fmt.Sprintf("voidbox-askpass-%d-%x", os.Getppid(), h.Sum32()))
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

// ── the terminal screen ──

type askModel struct {
	l         look
	q         askReq
	out       *os.File // the tty this paints on (nil: View returns the frame as text)
	w, h      int
	pass      []rune
	choice    int // confirm: 0 YES · 1 NO
	blink     bool
	done      bool
	cancelled bool
	exitT0    time.Time
}

type frameMsg time.Time

func frame(d time.Duration) tea.Cmd {
	return tea.Tick(d, func(t time.Time) tea.Msg { return frameMsg(t) })
}

func (m askModel) Init() tea.Cmd { return frame(530 * time.Millisecond) }

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
		m.blink = !m.blink
		return m, frame(530 * time.Millisecond)
	case tea.KeyMsg:
		if m.done {
			return m, nil
		}
		finish := func() (tea.Model, tea.Cmd) {
			m.done, m.exitT0 = true, time.Now()
			return m, frame(16 * time.Millisecond)
		}
		switch msg.Type {
		case tea.KeyEsc, tea.KeyCtrlC, tea.KeyCtrlD:
			m.cancelled = true
			return m, tea.Quit
		}
		switch m.q.kind {
		case kInfo:
			return m, nil
		case kConfirm:
			switch msg.String() {
			case "left", "right", "tab", "h", "l":
				m.choice = 1 - m.choice
			case "y", "Y":
				m.choice = 0
				return finish()
			case "n", "N":
				m.choice = 1
				return finish()
			case "enter":
				return finish()
			}
			return m, nil
		}
		switch msg.Type {
		case tea.KeyEnter:
			if len(m.pass) > 0 {
				return finish()
			}
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

func (m askModel) promptView() promptView {
	p := promptView{
		title: "AUTHORIZATION REQUIRED", message: m.q.message, what: m.q.detail,
		n: len(m.pass), caret: !m.blink, done: m.done, status: m.q.status, warn: m.q.status != "",
		hint: "TYPE " + m.q.hint, big: m.out != nil && kittyBig(),
	}
	if !m.q.sudo {
		p.keys = [][2]string{{"↵", "SUBMIT"}, {"ESC", "CANCEL"}}
	}
	switch m.q.kind {
	case kText:
		p.echo, p.n = string(m.pass), 0
	case kConfirm:
		p.title, p.confirm, p.choice = "CONFIRMATION REQUIRED", true, m.choice
		p.keys = [][2]string{{"←→", "CHOOSE"}, {"↵", "CONFIRM"}, {"ESC", "CANCEL"}}
	case kInfo:
		p.title, p.confirm, p.done = "NOTICE", false, true
		p.keys = [][2]string{{"ESC", "DISMISS"}}
	}
	return p
}

// View paints the tty itself (paint: the big title needs the whole screen redrawn) and
// returns nothing to bubbletea, which runs without a renderer here
func (m askModel) View() string {
	if m.w == 0 {
		return ""
	}
	f := m.l.voidScreen(m.w, m.h, m.promptView())
	if m.out == nil {
		return f.String()
	}
	paint(m.out, f)
	return ""
}

func ttyAsk(tty *os.File, q askReq) (string, bool) {
	l := newLook(lipgloss.NewRenderer(tty), loadPalette())
	m := askModel{l: l, q: q, out: tty, choice: 1}
	// without its renderer bubbletea leaves the terminal alone: raw mode, the alternate
	// screen and the size are ours
	if st, err := term.MakeRaw(tty.Fd()); err == nil {
		defer term.Restore(tty.Fd(), st)
	}
	m.w, m.h, _ = term.GetSize(tty.Fd())
	tty.WriteString("\x1b[?1049h\x1b[?25l")
	p := tea.NewProgram(m, tea.WithInput(tty), tea.WithOutput(tty), tea.WithoutRenderer())
	winch := make(chan os.Signal, 1)
	signal.Notify(winch, syscall.SIGWINCH)
	defer signal.Stop(winch)
	go func() {
		for range winch {
			if w, h, err := term.GetSize(tty.Fd()); err == nil {
				p.Send(tea.WindowSizeMsg{Width: w, Height: h})
			}
		}
	}()
	res, err := p.Run()
	tty.WriteString("\x1b[2J\x1b[?25h\x1b[?1049l")
	if err != nil {
		return "", false
	}
	mm := res.(askModel)
	if mm.cancelled {
		return "", false
	}
	if q.kind == kConfirm {
		return map[int]string{0: "yes", 1: "no"}[mm.choice], true
	}
	return string(mm.pass), len(mm.pass) > 0 || q.kind == kInfo
}

// ── no terminal: the shell asks (AuthPrompt's socket) ──

func shellAsk(q askReq) (string, bool, error) {
	conn, err := net.Dial("unix", filepath.Join(runtimeDir(), "qs-void-ask.sock"))
	if err != nil {
		return "", false, err
	}
	defer conn.Close()
	b, _ := json.Marshal(map[string]string{
		"kind": kindNames[q.kind], "message": q.message, "detail": q.detail, "error": q.status, "hint": q.hint,
	})
	if _, err := conn.Write(append(b, '\n')); err != nil {
		return "", false, err
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		return "", false, nil // the prompt went away without an answer
	}
	var r struct {
		OK    bool   `json:"ok"`
		Value string `json:"value"`
	}
	if json.Unmarshal([]byte(line), &r) != nil {
		return "", false, nil
	}
	return r.Value, r.OK, nil
}

func runAskpass(prompt string) int {
	q := classify(prompt)
	var (
		val string
		ok  bool
	)
	if tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0); err == nil {
		val, ok = ttyAsk(tty, q)
		tty.Close()
	} else {
		var err error
		if val, ok, err = shellAsk(q); err != nil {
			return 1 // no terminal, no shell: nobody to ask
		}
	}
	if !ok {
		return 1
	}
	switch {
	case q.kind == kConfirm && !q.word: // ssh-agent's confirm: the exit code is the answer
		if val == "yes" {
			return 0
		}
		return 1
	case q.kind == kInfo:
		return 0
	}
	fmt.Println(val)
	return 0
}
