package main

// pinentry — gpg-agent's pinentry in the Void (pinentry-void, a symlink; gpg-agent.conf:
// pinentry-program). It speaks the Assuan lines gpg-agent sends and asks through the
// shell's socket (widgets/AuthPrompt.qml), wherever gpg was run from. Without the shell
// it hands over to the stock pinentry before saying a word, so gpg never loses its prompt.

import (
	"bufio"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

const (
	errCancelled    = "ERR 83886179 Operation cancelled <Pinentry>"
	errNotConfirmed = "ERR 83886194 Not confirmed <Pinentry>"
)

// Assuan percent-escapes: %25 %0A %0D (and anything else gpg chose to escape)
func assuanDecode(s string) string {
	if v, err := url.PathUnescape(strings.ReplaceAll(s, "+", "%2B")); err == nil {
		return v
	}
	return s
}

func assuanEncode(s string) string {
	return strings.NewReplacer("%", "%25", "\r", "%0D", "\n", "%0A").Replace(s)
}

func runPinentry(args []string) int {
	if _, err := os.Stat(filepath.Join(runtimeDir(), "qs-void-ask.sock")); err != nil {
		for _, p := range []string{"/usr/bin/pinentry", "/usr/bin/pinentry-curses", "/usr/bin/pinentry-tty"} {
			if _, err := os.Stat(p); err == nil {
				_ = syscall.Exec(p, append([]string{p}, args...), os.Environ())
			}
		}
		return 1
	}

	out := bufio.NewWriter(os.Stdout)
	say := func(lines ...string) {
		for _, l := range lines {
			out.WriteString(l + "\n")
		}
		out.Flush()
	}
	var desc, prompt, errText, repeat, repeatErr string
	reset := func() { desc, prompt, errText, repeat, repeatErr = "", "", "", "", "" }

	ask := func(kind askKind, message, hint, status string) (string, bool) {
		v, ok, err := shellAsk(askReq{kind: kind, message: message, detail: "gpg", hint: hint, status: status})
		return v, ok && err == nil
	}
	hintOf := func(p string) string {
		h := strings.ToUpper(strings.TrimRight(strings.TrimSpace(p), ":："))
		if h == "" {
			return "PASSPHRASE"
		}
		return h
	}

	say("OK Pleased to meet you")
	in := bufio.NewScanner(os.Stdin)
	in.Buffer(make([]byte, 64*1024), 1<<20)
	for in.Scan() {
		line := in.Text()
		cmd, arg, _ := strings.Cut(line, " ")
		arg = assuanDecode(arg)
		switch strings.ToUpper(cmd) {
		case "SETDESC":
			desc = arg
		case "SETPROMPT":
			prompt = arg
		case "SETERROR":
			errText = arg
		case "SETREPEAT":
			repeat = arg
			if repeat == "" {
				repeat = "Repeat"
			}
		case "SETREPEATERROR":
			repeatErr = arg
		case "RESET":
			reset()
		case "GETINFO":
			switch arg {
			case "pid":
				say(fmt.Sprintf("D %d", os.Getpid()))
			case "flavor":
				say("D void")
			case "version":
				say("D 1.0.0")
			case "ttyinfo":
				say("D - - - - 0/0 -")
			}
		case "GETPIN":
			status := strings.ToUpper(errText)
			var pin string
			ok := false
			for try := 0; try < 3; try++ {
				p1, ok1 := ask(kSecret, desc, hintOf(prompt), status)
				if !ok1 {
					break
				}
				if repeat == "" {
					pin, ok = p1, true
					break
				}
				p2, ok2 := ask(kSecret, desc, hintOf(repeat), "")
				if !ok2 {
					break
				}
				if p1 == p2 {
					pin, ok = p1, true
					say("S PIN_REPEATED")
					break
				}
				status = strings.ToUpper(repeatErr)
				if status == "" {
					status = "THE TWO DON'T MATCH"
				}
			}
			errText = ""
			if !ok {
				say(errCancelled)
				continue
			}
			if pin != "" {
				say("D " + assuanEncode(pin))
			}
		case "CONFIRM", "MESSAGE":
			one := cmd == "MESSAGE" || strings.Contains(line, "--one-button")
			_, ok := ask(kConfirm, desc, "", strings.ToUpper(errText))
			errText = ""
			if !ok && !one {
				say(errNotConfirmed)
				continue
			}
		case "BYE":
			say("OK closing connection")
			return 0
		}
		// everything else (OPTION, SETTITLE, SETOK, SETCANCEL, SETQUALITYBAR, SETTIMEOUT,
		// NOP…) is fine as it is
		say("OK")
	}
	return 0
}
