// voidbox — sudo's password and pacman's transactions in the Void, the terminal side of
// the shell's design language (see quickshell/CLAUDE.md, "Design language").
//
//	voidbox pacman <args>      a transaction (queries just run pacman)
//	voidbox askpass <prompt>   the password screen (what voidbox-askpass runs)
//	voidbox render <askpass|pacman|yesno|choice> [w h]   one frame as text, for checking the look
//
// voidbox-askpass (a symlink) is sudo's SUDO_ASKPASS: inside a voidbox pacman it hands
// the question to that screen; anywhere else it draws its own on /dev/tty.
// Shell side: tui/void.zsh. Build: make -C ~/.config/quickshell/tui
package main

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

func bridgeAskpass(prompt string) int {
	conn, err := net.Dial("unix", os.Getenv("VOIDBOX_SOCK"))
	if err != nil {
		return 1 // the screen that asked is gone; don't draw over a pty
	}
	defer conn.Close()
	fmt.Fprintf(conn, "%s\n%s\n", os.Getenv("VOIDBOX_TOKEN"), prompt)
	line, _ := bufio.NewReader(conn).ReadString('\n')
	line = strings.TrimRight(line, "\n")
	if strings.HasPrefix(line, "OK ") {
		fmt.Println(line[3:])
		return 0
	}
	return 1
}

func render(what string, w, h int) {
	r := lipgloss.NewRenderer(os.Stdout)
	r.SetColorProfile(termenv.TrueColor)
	l := newLook(r, loadPalette())
	switch what {
	case "askpass", "askpass2":
		m := askModel{l: l, w: w, h: h, cmd: "pacman -Syu", user: "user", attempt: 1, t0: time.Now().Add(-time.Second), pass: []rune("hunter")}
		if what == "askpass2" {
			m.attempt, m.pass = 2, nil
		}
		fmt.Println(m.View())
	default:
		m := pacModel{l: l, w: w, h: h, args: []string{"-S", "java-runtime"}, prog: map[string]string{}}
		for _, s := range []string{":: Synchronizing package databases...", " core is up to date", " extra is up to date",
			":: There are 2 providers available for java-runtime:", ":: Repository extra", "   1) jdk-openjdk  2) jre-openjdk",
			"warning: example warning", "error: example error"} {
			m.lines = append(m.lines, s)
		}
		m.prog["jdk-openjdk-25"] = " jdk-openjdk-25  120.4 MiB  9.81 MiB/s 00:07 [######-------]  46%"
		m.progKeys = []string{"jdk-openjdk-25"}
		switch what {
		case "yesno":
			m.cur = ":: 進行安裝嗎？ [Y/n] "
			m.classify(false)
		case "choice":
			m.cur = "輸入某個數字（預設=1）： "
			m.classify(false)
		case "auth":
			m.kind, m.authTry, m.input = pAuth, 2, []rune("abc")
		}
		fmt.Println(m.View())
	}
}

func main() {
	if filepath.Base(os.Args[0]) == "voidbox-askpass" {
		prompt := strings.Join(os.Args[1:], " ")
		if os.Getenv("VOIDBOX_SOCK") != "" {
			os.Exit(bridgeAskpass(prompt))
		}
		os.Exit(runAskpass(prompt))
	}
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: voidbox pacman <args> | askpass <prompt> | render <what> [w h]")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "pacman":
		os.Exit(runPacman(os.Args[2:]))
	case "askpass":
		os.Exit(runAskpass(strings.Join(os.Args[2:], " ")))
	case "render":
		w, h := 100, 30
		if len(os.Args) >= 5 {
			w, _ = strconv.Atoi(os.Args[3])
			h, _ = strconv.Atoi(os.Args[4])
		}
		what := "askpass"
		if len(os.Args) >= 3 {
			what = os.Args[2]
		}
		render(what, w, h)
	default:
		fmt.Fprintln(os.Stderr, "voidbox: unknown mode", os.Args[1])
		os.Exit(2)
	}
}
