#!/usr/bin/env python3
"""dpms.py off|on — hypridle's screen-off, held against DisplayPort.

A DisplayPort monitor that goes to standby drops its hot-plug line, then raises it again
when it wakes to scan its inputs: Hyprland sees a monitor being plugged in and lights it,
so the screen never stays asleep (the MSI on DP-2, 2026-10: 194 hot-plug events in a day;
on HDMI it stayed off). So:

  off   marks the screens as meant to be off ($XDG_RUNTIME_DIR/hypr-dpms-off), turns them
        off, and stays as a guard on Hyprland's event socket: while the mark is there, a
        monitor that comes back is turned off again
  on    removes the mark (the guard leaves at its next look) and turns the screens on;
        the shell's HUD then says which task group this is

hypridle.conf runs `off` on its idle timeout and `on` on resume and after sleep.
"""
import os
import socket
import subprocess
import sys
import time

RUN = os.environ.get('XDG_RUNTIME_DIR') or '/run/user/%d' % os.getuid()
MARK = os.path.join(RUN, 'hypr-dpms-off')


def dpms(action):
    subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.dpms({ action = "%s" })' % action],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def event_socket():
    sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    if not sig:     # hypridle's children have it; a bare shell may not
        d = os.path.join(RUN, 'hypr')
        sig = max(os.listdir(d), key=lambda n: os.path.getmtime(os.path.join(d, n)))
    s = socket.socket(socket.AF_UNIX)
    s.connect(os.path.join(RUN, 'hypr', sig, '.socket2.sock'))
    s.settimeout(2)
    return s


def guard():
    """until the mark goes: a monitor that reappears is turned off again"""
    try:
        s = event_socket()
    except OSError:
        return
    buf = b''
    while os.path.exists(MARK):
        try:
            data = s.recv(4096)
        except socket.timeout:
            continue
        except OSError:
            return
        if not data:
            return
        buf = (buf + data)[-8192:]
        if b'monitoradded' in buf:
            buf = b''
            time.sleep(1.5)                 # let Hyprland finish bringing it up
            if os.path.exists(MARK):
                dpms('disable')


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else ''
    if what == 'off':
        open(MARK, 'w').close()
        dpms('disable')
        if os.fork() == 0:                  # the guard outlives hypridle's command
            os.setsid()
            guard()
            os._exit(0)
    elif what == 'on':
        try:
            os.remove(MARK)
        except OSError:
            pass
        dpms('enable')
        try:
            subprocess.run(['qs', 'ipc', 'call', 'tasks', 'prompt'], timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.TimeoutExpired):
            pass
    elif what == 'guard':                   # for testing: just the guard, in the foreground
        guard()
    else:
        sys.exit('usage: dpms.py off|on')


if __name__ == '__main__':
    main()
