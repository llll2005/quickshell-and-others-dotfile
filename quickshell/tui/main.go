// voidbox — sudo's password and pacman's transactions in the Void, the terminal side of
// the shell's design language (see quickshell/CLAUDE.md, "Design language").
//
//	voidbox pacman <args>      a transaction (queries just run pacman)
//	voidbox askpass <prompt>   the password screen (what voidbox-askpass runs)
//	voidbox pinentry           gpg-agent's pinentry (what pinentry-void runs)
//	voidbox choose TITLE ITEM… a numbered list card; prints the pick (choose.go)
//	voidbox confirm QUESTION   a YES / NO card; exit 0 = yes
//	voidbox render <askpass|askpass2|askconfirm|asktext|pacman|yesno|choice|auth> [w h]
//	                           one frame as text, for checking the look
//
// voidbox-askpass (a symlink) is the askpass for sudo, ssh and git: inside a voidbox
// pacman it hands the question to that screen; in a terminal it draws its own on
// /dev/tty; with no terminal the shell asks (widgets/AuthPrompt.qml's socket).
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
	case "askpass", "askpass2", "askconfirm", "asktext":
		m := askModel{l: l, w: w, h: h, choice: 1, pass: []rune("hunter"),
			q: askReq{kind: kSecret, detail: "$ sudo pacman -Syu", sudo: true, hint: "PASSWORD"}}
		switch what {
		case "askpass2":
			m.q.status, m.pass = "WRONG PASSWORD  ·  TRY 2/3", nil
		case "askconfirm":
			m.q = askReq{kind: kConfirm, word: true, detail: "$ ssh example.org",
				message: "The authenticity of host 'example.org' can't be established.\nED25519 key fingerprint is SHA256:0123456789abcdef.\nAre you sure you want to continue connecting (yes/no/[fingerprint])?"}
		case "asktext":
			m.q = askReq{kind: kText, detail: "$ git · https://example.org/repo.git", hint: "USER NAME",
				message: "Username for 'https://example.org':"}
			m.pass = []rune("octocat")
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
	if filepath.Base(os.Args[0]) == "pinentry-void" {
		os.Exit(runPinentry(os.Args[1:]))
	}
	if filepath.Base(os.Args[0]) == "voidbox-askpass" {
		prompt := strings.Join(os.Args[1:], " ")
		if os.Getenv("VOIDBOX_SOCK") != "" {
			os.Exit(bridgeAskpass(prompt))
		}
		os.Exit(runAskpass(prompt))
	}
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: voidbox pacman <args> | askpass <prompt> | pinentry | choose TITLE ITEM… | confirm QUESTION | render <what> [w h]")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "pacman":
		os.Exit(runPacman(os.Args[2:]))
	case "askpass":
		os.Exit(runAskpass(strings.Join(os.Args[2:], " ")))
	case "pinentry":
		os.Exit(runPinentry(os.Args[2:]))
	case "choose":
		if len(os.Args) < 4 {
			fmt.Fprintln(os.Stderr, "usage: voidbox choose TITLE ITEM…")
			os.Exit(2)
		}
		os.Exit(runChoose(os.Args[2], os.Args[3:], false))
	case "confirm":
		os.Exit(runChoose(strings.Join(os.Args[2:], " "), nil, true))
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
