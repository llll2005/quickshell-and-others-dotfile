package main

// choose / confirm — the questions scripts ask, as the cards pacman's questions use, drawn
// inline on /dev/tty (stdout stays free for the answer, so `$(voidbox choose …)` works):
//
//	voidbox choose TITLE ITEM…     a numbered list; prints the picked ITEM ("LABEL<TAB>NOTE"
//	                               items show the note dimmed, print the label)
//	voidbox confirm QUESTION       YES / NO (NO by default); exit 0 = yes
//
// ↑↓ select · 1–9 pick · ←→ / Y / N (confirm) · ↵ confirm · Esc cancel (exit 1). When it's
// done the card folds to one line in the scrollback: ◆ TITLE  ANSWER.

import (
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
)

type chooseModel struct {
	l         look
	title     string
	items     []string // choose: the items · confirm: nil
	sel       int
	w         int
	done      bool
	cancelled bool
}

func (m chooseModel) Init() tea.Cmd { return nil }

func (m chooseModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w = msg.Width
	case tea.KeyMsg:
		n := len(m.items)
		if m.items == nil {
			n = 2
		}
		switch k := msg.String(); k {
		case "esc", "ctrl+c", "q":
			m.cancelled = true
			return m, tea.Quit
		case "enter":
			m.done = true
			return m, tea.Quit
		case "up", "left", "shift+tab":
			m.sel = (m.sel + n - 1) % n
		case "down", "right", "tab":
			m.sel = (m.sel + 1) % n
		case "y", "Y":
			if m.items == nil {
				m.sel, m.done = 0, true
				return m, tea.Quit
			}
		case "n", "N":
			if m.items == nil {
				m.sel, m.done = 1, true
				return m, tea.Quit
			}
		default:
			if len(k) == 1 && k[0] >= '1' && k[0] <= '9' && m.items != nil && int(k[0]-'1') < n {
				m.sel, m.done = int(k[0]-'1'), true
				return m, tea.Quit
			}
		}
	}
	return m, nil
}

func splitItem(it string) (label, note string) {
	label, note, _ = strings.Cut(it, "\t")
	return
}

func (m chooseModel) answer() string {
	if m.items == nil {
		return []string{"YES", "NO"}[m.sel]
	}
	label, _ := splitItem(m.items[m.sel])
	return label
}

func (m chooseModel) View() string {
	l := m.l
	w := m.w
	if w <= 0 {
		w = 80
	}
	key := func(k, v string) string { return l.faint.Render(k+" ") + l.dim.Render(spaced(v)) }
	arrowsV, arrowsH, enter, digits, marker := "↑↓", "←→", "↵", "1–9", "▸ "
	if l.pal.ascii { // a Linux VT's default font has no arrows or triangles
		arrowsV, arrowsH, enter, digits, marker = "UP/DN", "LT/RT", "ENTER", "1-9", "> "
	}
	head := l.fg.Render(l.dia) + "  " + l.bold.Render(spaced(strings.ToUpper(m.title)))
	if m.cancelled {
		return l.faint.Render(l.hollow) + "  " + l.dim.Render(spaced(strings.ToUpper(m.title))) + "    " + l.faint.Render(spaced("CANCELLED")) + "\n"
	}
	if m.done {
		return head + "   " + l.fg.Render(m.answer()) + "\n"
	}
	out := []string{head, ""}
	if m.items == nil {
		button := func(label string, on bool) string {
			if on {
				return l.r.NewStyle().Background(lipgloss.Color(l.pal.light)).Foreground(lipgloss.Color(voidBlack)).Bold(true).Render("  " + spaced(label) + "  ")
			}
			return l.dim.Render("[ " + spaced(label) + " ]")
		}
		out = append(out, "   "+button("YES", m.sel == 0)+"   "+button("NO", m.sel == 1), "",
			"   "+key(arrowsH, "SELECT")+"    "+key("Y / N", "ANSWER")+"    "+key(enter, "CONFIRM")+"    "+key("ESC", "CANCEL"))
		return strings.Join(out, "\n") + "\n"
	}
	wide := 0
	for _, it := range m.items {
		if lb, _ := splitItem(it); ansi.StringWidth(lb) > wide {
			wide = ansi.StringWidth(lb)
		}
	}
	start := 0
	if m.sel > 8 {
		start = m.sel - 8
	}
	for i := start; i < len(m.items) && i < start+9; i++ {
		label, note := splitItem(m.items[i])
		mark, lab := "  ", l.dim.Render(label)
		if i == m.sel {
			mark, lab = l.fg.Render(marker), l.fg.Render(label)
		}
		row := "   " + mark + l.faint.Render(fmt.Sprintf("%d  ", i+1)) + lab
		if note != "" {
			row += strings.Repeat(" ", wide-ansi.StringWidth(label)+3) + l.faint.Render(note)
		}
		out = append(out, ansi.Truncate(row, w-1, "…"))
	}
	out = append(out, "", "   "+key(arrowsV, "SELECT")+"    "+key(digits, "PICK")+"    "+key(enter, "CONFIRM")+"    "+key("ESC", "CANCEL"))
	return strings.Join(out, "\n") + "\n"
}

func runChoose(title string, items []string, confirm bool) int {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return 2
	}
	defer tty.Close()
	m := chooseModel{l: newLook(lipgloss.NewRenderer(tty), loadPalette()), title: title}
	if confirm {
		m.sel = 1 // NO by default
	} else {
		m.items = items
		if len(items) == 0 {
			return 2
		}
	}
	res, err := tea.NewProgram(m, tea.WithInput(tty), tea.WithOutput(tty)).Run()
	if err != nil {
		return 2
	}
	mm := res.(chooseModel)
	if mm.cancelled || !mm.done {
		return 1
	}
	if confirm {
		if mm.sel == 0 {
			return 0
		}
		return 1
	}
	fmt.Println(mm.answer())
	return 0
}
