#!/usr/bin/env python3
"""Hyprland socket2 event streamer — reconnects automatically on disconnect."""
import socket, os, sys, glob, time

def find_socket():
    uid = os.getuid()
    sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE', '')
    if sig:
        p = f'/run/user/{uid}/hypr/{sig}/.socket2.sock'
        if os.path.exists(p):
            return p
    paths = sorted(
        glob.glob(f'/run/user/{uid}/hypr/*/.socket2.sock'),
        key=lambda p: os.path.getmtime(p), reverse=True
    )
    return paths[0] if paths else None

while True:
    path = find_socket()
    if not path:
        time.sleep(2)
        continue
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(path)
        buf = b''
        while True:
            data = s.recv(4096)
            if not data:
                break
            buf += data
            while b'\n' in buf:
                line, buf = buf.split(b'\n', 1)
                sys.stdout.write(line.decode('utf-8', errors='replace') + '\n')
                sys.stdout.flush()
    except Exception:
        pass
    finally:
        try: s.close()
        except: pass
    time.sleep(1)
