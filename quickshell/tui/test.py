#!/usr/bin/env python3
"""Drive `voidbox pacman` in a pty against fake-pacman.sh — no sudo, no real pacman:
the password card (askpass over the socket), the provider list, the yes/no card, the
log printed after the screen goes. Usage: test.py [path/to/voidbox]"""
import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time

here = os.path.dirname(os.path.abspath(__file__))
vb = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.local/bin/voidbox")
out = b""


def pump(t):
    global out
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            out += data
            # answer like a terminal: termenv asks for the colours (OSC 10/11) and the cursor (DSR)
            if b"\x1b]11;?" in data:
                os.write(fd, b"\x1b]11;rgb:0000/0000/0000\x1b\\")
            if b"\x1b]10;?" in data:
                os.write(fd, b"\x1b]10;rgb:ffff/ffff/ffff\x1b\\")
            if b"\x1b[6n" in data:
                os.write(fd, b"\x1b[1;1R")


def seen(s):
    return s.encode() in re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]", b"", out)


pid, fd = pty.fork()
if pid == 0:
    os.environ.update(VOIDBOX_TEST_CMD=os.path.join(here, "fake-pacman.sh"), TERM="xterm-256color")
    os.execv(vb, [vb, "pacman", "-S", "java-runtime"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))

ok = True
def check(name, cond):
    global ok
    ok &= cond
    print(("PASS " if cond else "FAIL ") + name, flush=True)
    if not cond:
        print(re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]", b"", out).decode("utf8", "replace")[-1800:], flush=True)

pump(1.5)
check("password card", seen("A U T H O R I Z A T I O N"))
os.write(fd, b"secret\r")
pump(1.5)
check("provider list", seen("S E L E C T") and seen("jre-openjdk"))
os.write(fd, b"2")
pump(1.0)
check("yes/no card", seen("C O N F I R M") and seen("進行安裝嗎"))
os.write(fd, b"y")
pump(2.5)
text = re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]", b"", out).decode("utf8", "replace")
check("answers reached pacman", "picked provider 2" in text and "answered y" in text)
check("log + result printed", "C O M P L E T E D" in text and "error: example failure line" in text)
check("password never shown", "secret" not in text)
for _ in range(50):
    done, status = os.waitpid(pid, os.WNOHANG)
    if done:
        break
    time.sleep(0.1)
else:
    os.kill(pid, 9)
    done, status = os.waitpid(pid, 0)
    print("--- voidbox didn't exit; last screen:\n" + text[-2500:])
check("exit 0", os.waitstatus_to_exitcode(status) == 0)
sys.exit(0 if ok else 1)
