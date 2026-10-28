#!/usr/bin/env python3
"""session.py — the desktop as you left it: every window back in its task group and cell.

    session.py save [--final]     snapshot the windows (services/TaskGroups.qml: a few seconds
                                  after windows change, every two minutes, and --final when
                                  logind announces a shutdown or the session is left)
    session.py restore [--force] [--dry-run] [--skip]
                                  once per login: relaunch what was open and put each window
                                  back where it was (--skip: [session] restore is off — only
                                  mark the login, so saving can start)
    session.py status             what the snapshot holds

What comes back:
  · browsers restore their own windows and tabs (Firefox: browser.startup.page = 3, set in
    every profile's user.js; Chromium-family: --restore-last-session); their windows are
    then matched to the saved ones by title
  · kitty reopens in each window's directory (the shell's cwd)
  · other apps are started again with the command line they ran with
  · floating windows get their place and size back; the screens show the cells they showed
What can't: a terminal's scrollback and running commands, unsaved documents, games
(steam_app_*), dialogs.

While restoring, the new windows open on a hidden workspace (special:qsrestore, a window
rule switched on for the classes being launched) and are moved out to their place, so
nothing flashes up where you are.

--final freezes the snapshot ($XDG_RUNTIME_DIR/qs-session.frozen.<Hyprland instance>): the
first final save wins, and windows closing during the shutdown or the logout must not
overwrite the desktop you are leaving. It comes from logind's PrepareForShutdown (the shell
holds a delay lock) and from Hyprland's own shutdown (hypr/core/tasks.lua), so a power-off,
a reboot and a logout all take it.
"""
from __future__ import annotations

import difflib
import json
import os
import re
import socket
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local/state"), "quickshell")
SNAP = os.environ.get("QS_SESSION_FILE") or os.path.join(STATE, "session.json")   # (a test's own)
PREV = os.path.join(STATE, "session.prev.json")
LOG = os.path.join(STATE, "session.log")
RUN = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
# per Hyprland instance: a new login is a new instance, restored once and not frozen
INSTANCE = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "x")
FROZEN = os.path.join(RUN, f"qs-session.frozen.{INSTANCE}")
RESTORED = os.path.join(RUN, f"qs-session.restored.{INSTANCE}")
# the part of a program's environment worth carrying to its next start (IME, video,
# toolkit backends); the rest (the bus, the display, the session) belongs to the new login
ENV_KEEP = re.compile(r"^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|SDL_IM_MODULE|LIBVA_DRIVER_NAME|"
                      r"GDK_BACKEND|QT_QPA_PLATFORM|MOZ_[A-Z_]+|ELECTRON_[A-Z_]+|NVD_BACKEND|__NV_[A-Z_]+|"
                      r"__GLX_[A-Z_]+|GSK_RENDERER)$")

STAGE = "special:qsrestore"
WAIT = 90                     # seconds a restore waits for windows to come
BROWSERS = re.compile(r"(firefox|librewolf|zen|chrom(e|ium)|msedge|microsoft-edge|brave|vivaldi|opera)", re.I)
CHROMIUM = re.compile(r"(chrom(e|ium)|msedge|microsoft-edge|brave|vivaldi|opera)", re.I)
SKIP = re.compile(r"^(steam_app_.*|zenity|kdialog|xdg-desktop-portal.*|polkit.*|.*pinentry.*|"
                  r"org\.kde\.polkit-kde-authentication-agent-1|hyprland-share-picker|qstest.*|)$", re.I)
SKIP_TITLES = re.compile(r"^(Picture-in-Picture|子母畫面)$", re.I)

USERJS_BEGIN = "// ── quickshell session (scripts/session.py) ──"
USERJS_END = "// ── end quickshell session ──"
FIREFOX_ROOTS = [os.path.join(HOME, ".mozilla/firefox"), os.path.join(HOME, ".config/mozilla/firefox")]


def log(msg: str) -> None:
    os.makedirs(STATE, exist_ok=True)
    with open(LOG, "a") as f:
        f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")


def hypr(*args: str):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except ValueError:
        return []


def dispatch(lua: str) -> None:
    subprocess.run(["hyprctl", "dispatch", lua], capture_output=True)


def lua_eval(lua: str) -> None:
    subprocess.run(["hyprctl", "eval", lua], capture_output=True)


def q(s: str) -> str:
    return json.dumps(s)      # a Lua string literal (JSON's escapes are a subset)


# ─── what a process was ───────────────────────────────────────────────────────
def proc(pid: int, what: str) -> str:
    try:
        return os.readlink(f"/proc/{pid}/{what}")
    except OSError:
        return ""


def argv_of(pid: int) -> list[str]:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
    except OSError:
        return []


def environ_of(pid: int) -> dict[str, str]:
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            pairs = [a.decode(errors="replace").split("=", 1) for a in f.read().split(b"\0") if b"=" in a]
        return dict(pairs)
    except OSError:
        return {}


def children(pid: int) -> list[int]:
    out = []
    try:
        for t in os.listdir(f"/proc/{pid}/task"):
            with open(f"/proc/{pid}/task/{t}/children") as f:
                out += [int(x) for x in f.read().split()]
    except OSError:
        pass
    return out


def unit_for(c: dict) -> dict | None:
    """how to start the program that owns window c again (None: don't)"""
    pid = c.get("pid") or 0
    cls = c.get("initialClass") or c.get("class") or ""
    if pid <= 0 or SKIP.match(cls) or SKIP_TITLES.match(c.get("title") or ""):
        return None
    argv, exe, cwd = argv_of(pid), proc(pid, "exe"), proc(pid, "cwd")
    if len(argv) == 1 and " " in argv[0] and not os.path.exists(argv[0]):
        argv = argv[0].split(" ")              # Chromium rewrites its command line into one string
    if not argv or not exe or exe.startswith("/tmp/") or "(deleted)" in exe:
        return None
    env = environ_of(pid)
    if "PATH" not in env:
        # Chromium writes its process title over its own environment: its children keep it
        env = next((e for e in map(environ_of, children(pid)) if "PATH" in e), {})
    known = "PATH" in env                      # else: start it with the new login's, as it is
    u = unit_kind(pid, cls, argv, exe, cwd, env)
    if u:
        u["env"] = {k: v for k, v in env.items() if ENV_KEEP.match(k)}
        u["envKnown"] = known
    return u


def unit_kind(pid: int, cls: str, argv: list[str], exe: str, cwd: str, env: dict) -> dict | None:
    if env.get("FLATPAK_ID"):
        return {"kind": "app", "cmd": ["flatpak", "run", env["FLATPAK_ID"]], "cwd": HOME, "pid": pid, "class": cls}
    if "kitty" in os.path.basename(exe):
        # the shell's directory (kitty's own cwd is where it was started; its kittens aren't it)
        shell = next((k for k in children(pid) if "kitten" not in os.path.basename(proc(k, "exe"))), 0)
        where = proc(shell, "cwd") if shell else cwd
        prog = [a for a in argv[1:] if not a.startswith("-")]
        cmd = argv if prog else ["kitty", "--directory", where or HOME]
        return {"kind": "kitty", "cmd": cmd, "cwd": where or HOME, "pid": pid, "class": cls}
    if BROWSERS.search(exe) or BROWSERS.search(cls):
        cmd = [a for a in argv if not a.startswith("--type=")]
        if CHROMIUM.search(exe) and "--restore-last-session" not in cmd:
            cmd.append("--restore-last-session")
        return {"kind": "browser", "cmd": cmd, "cwd": HOME, "pid": pid, "class": cls,
                "firefox": "firefox" in exe or cls.lower().startswith("firefox")}
    return {"kind": "app", "cmd": argv, "cwd": cwd or HOME, "pid": pid, "class": cls}


def firefox_restores() -> None:
    """every Firefox profile opens with the last session (user.js, our own block)"""
    for root in FIREFOX_ROOTS:
        try:
            ini = open(os.path.join(root, "profiles.ini")).read()
        except OSError:
            continue
        for line in ini.splitlines():
            if not line.startswith("Path="):
                continue
            p = line[5:].strip()
            p = p if os.path.isabs(p) else os.path.join(root, p)
            if not os.path.isfile(os.path.join(p, "prefs.js")):
                continue
            path = os.path.join(p, "user.js")
            try:
                text = open(path).read()
            except OSError:
                text = ""
            if USERJS_BEGIN in text:
                continue
            block = "\n".join([USERJS_BEGIN,
                               'user_pref("browser.startup.page", 3);   // open the windows and tabs from last time',
                               USERJS_END])
            with open(path, "w") as f:
                f.write((text.rstrip("\n") + "\n\n" if text.strip() else "") + block + "\n")
            log(f"firefox: session restore on in {p}")


# ─── save ─────────────────────────────────────────────────────────────────────
def snapshot() -> dict:
    mons = hypr("monitors")
    windows, units, by_pid = [], [], {}
    for c in hypr("clients"):
        ws = c.get("workspace") or {}
        if not c.get("mapped", True) or ws.get("name", "").startswith(STAGE):
            continue
        pid = c.get("pid") or 0
        if pid in by_pid and units[by_pid[pid]]["kind"] != "kitty":
            ui = by_pid[pid]
        else:
            u = unit_for(c)
            if u is None:
                continue
            units.append(u)
            ui = by_pid[pid] = len(units) - 1
        windows.append({
            "class": c.get("class") or "", "initialClass": c.get("initialClass") or "",
            "title": c.get("title") or "", "ws": ws.get("id", 0), "wsName": ws.get("name", ""),
            "floating": bool(c.get("floating")), "at": c.get("at"), "size": c.get("size"),
            "pinned": bool(c.get("pinned")), "unit": ui,
        })
    return {
        "version": 1, "time": int(time.time()),
        "monitors": [{"name": m["name"], "kind": "laptop" if m["name"].startswith("eDP") else "external",
                      "ws": (m.get("activeWorkspace") or {}).get("id", 0), "focused": bool(m.get("focused"))}
                     for m in mons],
        "windows": windows, "units": units,
    }


def save(final: bool) -> None:
    if os.path.exists(FROZEN):
        return                                  # the shutdown's snapshot stays
    if not os.path.exists(RESTORED):
        return                                  # this login's restore hasn't run: the empty desktop of
                                                # a fresh login must never replace the last one
    snap = snapshot()
    snap["final"] = final
    os.makedirs(STATE, exist_ok=True)
    try:
        old = json.load(open(SNAP))
    except (OSError, ValueError):
        old = None
    if old and old.get("windows") and snap["windows"] != old.get("windows"):
        os.replace(SNAP, PREV)                  # the one before, in case this one is wrong
    tmp = SNAP + ".tmp"
    with open(tmp, "w") as f:
        json.dump(snap, f, ensure_ascii=False, indent=1)
    os.replace(tmp, SNAP)
    if any(u.get("firefox") for u in snap["units"]):
        firefox_restores()
    if final:
        open(FROZEN, "w").close()
        log(f"final save: {len(snap['windows'])} windows, {len(snap['units'])} programs")


# ─── restore ──────────────────────────────────────────────────────────────────
def similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio()


class Restore:
    def __init__(self, snap: dict, dry: bool):
        self.snap, self.dry = snap, dry
        self.units = snap.get("units", [])
        self.pending = list(range(len(snap.get("windows", []))))
        self.launched: dict[int, int] = {}            # new pid → unit index
        self.browsers = {u["class"].lower() for u in self.units if u["kind"] == "browser"}
        self.placed = 0

    def win(self, i: int) -> dict:
        return self.snap["windows"][i]

    def target(self, w: dict) -> str:
        if w.get("wsName", "").startswith("special:"):
            return w["wsName"]
        return str(w["ws"])

    def place(self, addr: str, i: int) -> None:
        w = self.win(i)
        sel = f'window = {q("address:" + addr)}'
        # 0.56's window.move reads `follow`, not `silent`: without it you'd be taken along
        dispatch(f'hl.dsp.window.move({{ workspace = {q(self.target(w))}, follow = false, {sel} }})')
        if w.get("floating") and w.get("size") and w.get("at"):
            dispatch(f'hl.dsp.window.float({{ action = "enable", {sel} }})')
            dispatch(f'hl.dsp.window.resize({{ x = {w["size"][0]}, y = {w["size"][1]}, exact = true, {sel} }})')
            dispatch(f'hl.dsp.window.move({{ x = {w["at"][0]}, y = {w["at"][1]}, exact = true, {sel} }})')
        if w.get("pinned"):
            dispatch(f"hl.dsp.window.pin({{ {sel} }})")
        self.pending.remove(i)
        self.placed += 1

    def match(self, c: dict) -> int | None:
        """the saved window a new one is: by the process we started, else by class"""
        pid, cls = c.get("pid") or 0, (c.get("initialClass") or c.get("class") or "").lower()
        title = c.get("title") or ""
        mine = self.launched.get(pid)
        if mine is not None:
            cands = [i for i in self.pending if self.win(i)["unit"] == mine]
        else:
            cands = [i for i in self.pending
                     if self.units[self.win(i)["unit"]]["kind"] != "kitty"
                     and cls and cls in ((self.win(i)["initialClass"] or "").lower(), self.win(i)["class"].lower())]
        if not cands:
            return None
        return max(cands, key=lambda i: (similarity(title, self.win(i)["title"]), -i))

    def screens(self) -> None:
        """each screen back on its cell, the focus where it was"""
        mons = {m["name"]: m for m in hypr("monitors")}
        saved = self.snap.get("monitors", [])
        by_kind = {m["kind"]: m for m in saved}
        steps, focus = [], None
        for name in mons:
            s = by_kind.get("laptop" if name.startswith("eDP") else "external")
            if not s or s.get("ws", 0) < 1:
                continue
            steps.append(f'hl.dispatch(hl.dsp.focus({{ monitor = {q(name)} }}))')
            steps.append(f'hl.dispatch(hl.dsp.focus({{ workspace = {s["ws"]}, on_current_monitor = true }}))')
            if s.get("focused"):
                focus = name
        if focus:
            steps.append(f'hl.dispatch(hl.dsp.focus({{ monitor = {q(focus)} }}))')
        if steps:
            lua_eval("\n".join(steps))

    def run(self) -> dict:
        existing = hypr("clients")
        running = {(c.get("initialClass") or c.get("class") or "").lower() for c in existing}
        launch, attach = [], []
        for ui, u in enumerate(self.units):
            if not any(self.win(i)["unit"] == ui for i in self.pending):
                continue
            if u["kind"] != "kitty" and u["class"].lower() in running:
                attach.append(ui)                     # already open: only its windows move
            else:
                launch.append(ui)
        if self.dry:
            return {"launch": [self.units[u]["cmd"] for u in launch],
                    "attach": [self.units[u]["class"] for u in attach],
                    "windows": len(self.pending)}

        self.screens()
        # windows of programs already running (an autostart): match them now
        for c in existing:
            i = self.match(c) if (c.get("initialClass") or c.get("class") or "").lower() in \
                {self.units[u]["class"].lower() for u in attach} else None
            if i is not None:
                self.place(c["address"], i)

        classes = sorted({self.win(i)["initialClass"] or self.win(i)["class"]
                          for i in self.pending if self.win(i)["unit"] in launch} - {""})
        if classes:
            rx = "^(" + "|".join(re.escape(c) for c in classes) + ")$"
            lua_eval(f'_G.qs_session_rule = hl.window_rule({{ name = "qs-session-restore", '
                     f'match = {{ class = {q(rx)} }}, workspace = "{STAGE} silent" }})')
        sock = self.events()
        for ui in launch:
            u = self.units[ui]
            cwd = u["cwd"] if os.path.isdir(u.get("cwd") or "") else HOME
            env = dict(os.environ)
            if u.get("envKnown"):                   # what it ran without stays out (Edge: LIBVA_DRIVER_NAME)
                for k in [k for k in env if ENV_KEEP.match(k) and k not in u.get("env", {})]:
                    env.pop(k)
            env.update(u.get("env") or {})
            try:
                p = subprocess.Popen(u["cmd"], cwd=cwd, env=env, start_new_session=True, stdin=subprocess.DEVNULL,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                self.launched[p.pid] = ui
            except OSError as e:
                log(f"restore: can't start {u['cmd'][:2]}: {e}")
        try:
            self.watch(sock)
        finally:
            lua_eval("if _G.qs_session_rule then _G.qs_session_rule:set_enabled(false) end")
            self.rescue()
        return {"launched": len(self.launched), "placed": self.placed, "missing": len(self.pending)}

    def events(self):
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        s = socket.socket(socket.AF_UNIX)
        s.connect(os.path.join(RUN, "hypr", sig, ".socket2.sock"))
        s.settimeout(1)
        return s

    def watch(self, sock) -> None:
        deadline, buf, waiting = time.time() + WAIT, b"", {}     # waiting: addr → since
        while self.pending and time.time() < deadline:
            try:
                data = sock.recv(65536)
            except socket.timeout:
                data = b""
            buf += data
            *lines, buf = buf.split(b"\n")
            for line in lines:
                ev = line.decode(errors="replace")
                if ev.startswith("openwindow>>"):
                    waiting["0x" + ev[12:].split(",", 1)[0]] = time.time()
            if not waiting:
                continue
            clients = {c["address"]: c for c in hypr("clients")}
            for addr in list(waiting):
                c = clients.get(addr)
                if c is None:
                    waiting.pop(addr)
                    continue
                age = time.time() - waiting[addr]
                cls = (c.get("initialClass") or c.get("class") or "").lower()
                if cls in self.browsers and age < 2.5:
                    continue                    # a restored browser window names itself after a moment
                i = self.match(c)
                if i is not None:
                    self.place(addr, i)
                    waiting.pop(addr)
                elif cls or age > 12:
                    # none of ours (opened while this ran, or one window more than last time):
                    # it goes where you are. An app that names its window late gets 12 s.
                    self.unstage(c)
                    waiting.pop(addr)

    def unstage(self, c: dict) -> None:
        if (c.get("workspace") or {}).get("name", "").startswith(STAGE):
            active = (hypr("activeworkspace") or {}).get("id", 1)
            dispatch(f'hl.dsp.window.move({{ workspace = "{active}", follow = false, '
                     f'window = {q("address:" + c["address"])} }})')

    def rescue(self) -> None:
        for c in hypr("clients"):
            self.unstage(c)


def restore(force: bool, dry: bool, skip: bool) -> None:
    """once per login; saving starts only after it (RESTORED), whatever happens in it"""
    if os.path.exists(RESTORED) and not force and not dry:
        print(json.dumps({"skipped": "already restored this login"}))
        return
    # only a fresh login: Hyprland's instance signature carries its start time, and a shell
    # restarted later in the session must never start the programs a second time
    m = re.search(r"_(\d{9,})_", INSTANCE)
    if m and time.time() - int(m.group(1)) > 300 and not force and not dry:
        open(RESTORED, "w").close()
        print(json.dumps({"skipped": "not a fresh login"}))
        return
    try:
        snap = None if skip else json.load(open(SNAP))
    except (OSError, ValueError):
        snap = None
    if snap is None:
        if not dry:
            open(RESTORED, "w").close()
        print(json.dumps({"skipped": "restore off" if skip else "no snapshot"}))
        return
    try:
        out = Restore(snap, dry).run()
    finally:
        if not dry:
            open(RESTORED, "w").close()
    if not dry:
        log(f"restore: {out}")
    print(json.dumps(out, ensure_ascii=False))


def status() -> None:
    try:
        snap = json.load(open(SNAP))
    except (OSError, ValueError):
        print(json.dumps({"windows": 0}))
        return
    print(json.dumps({
        "time": snap.get("time"), "final": snap.get("final"), "windows": len(snap.get("windows", [])),
        "programs": [u["cmd"][:3] for u in snap.get("units", [])],
        "frozen": os.path.exists(FROZEN), "restored": os.path.exists(RESTORED),
    }, ensure_ascii=False))


def main() -> None:
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    if a[0] == "save":
        save("--final" in a)
    elif a[0] == "restore":
        restore("--force" in a, "--dry-run" in a, "--skip" in a)
    elif a[0] == "status":
        status()
    elif a[0] == "unfreeze":                  # a shutdown that was called off
        try:
            os.remove(FROZEN)
        except OSError:
            pass
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
