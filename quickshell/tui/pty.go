package main

import (
	"fmt"
	"os"
	"syscall"

	"golang.org/x/sys/unix"
)

// openPty: a pseudo-terminal pair, so pacman sees a terminal (its progress bars, its
// questions) while voidbox reads and answers it.
func openPty() (master *os.File, slave string, err error) {
	m, err := os.OpenFile("/dev/ptmx", os.O_RDWR|syscall.O_NOCTTY|syscall.O_CLOEXEC, 0)
	if err != nil {
		return nil, "", err
	}
	fd := int(m.Fd())
	if err := unix.IoctlSetPointerInt(fd, unix.TIOCSPTLCK, 0); err != nil { // unlockpt
		m.Close()
		return nil, "", err
	}
	n, err := unix.IoctlGetInt(fd, unix.TIOCGPTN)
	if err != nil {
		m.Close()
		return nil, "", err
	}
	return m, fmt.Sprintf("/dev/pts/%d", n), nil
}

func setPtySize(f *os.File, rows, cols int) {
	if rows < 2 {
		rows = 2
	}
	if cols < 20 {
		cols = 20
	}
	_ = unix.IoctlSetWinsize(int(f.Fd()), unix.TIOCSWINSZ, &unix.Winsize{Row: uint16(rows), Col: uint16(cols)})
}
