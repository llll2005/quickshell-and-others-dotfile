#!/usr/bin/env python3
"""
qshare — PC <-> phone file sharing over HTTP + QR code.

CLI:
    qshare send <file|dir...> [--tunnel] [--once]
    qshare recv [-o DIR] [--tunnel] [--once]

Internal (from Quickshell):
    qshare ... --event-file $XDG_RUNTIME_DIR/qshare-events [--palette JSON] [--qr-out PNG]

The server stays up until you stop it (Ctrl-C, or SIGTERM from Quickshell) so
the phone can grab several files / upload several times from one QR. Pass
--once to fall back to the old "shut down after the first transfer" behaviour.

--tunnel publishes it through a Cloudflare quick tunnel (no account), so a phone
on mobile data reaches a PC on any Wi-Fi. Cloudflare refuses request bodies over
100 MB, so the upload page sends files in 8 MB chunks (also over the LAN).

Event file, one line each (the Control Center re-reads it whole on each change):
    STATUS <text>                     what it's waiting for (the tunnel)
    ERROR <code> <text>               cloudflared-missing · tunnel-exit · tunnel-timeout · bad-path
    URL <url> · QR <png> · QRM <n> <bits>   the link, its PNG, its module matrix (row-major 0/1)
    COUNT <n> · SIZE <human>          what is offered (send)
    READY
    VISIT <ip>                        a phone opened the page
    PROG <id> <done> <total> <name>   a transfer moving (≤ 5 a second each)
    TICK <name>                       a transfer finished
    DONE · CANCELLED
"""
from __future__ import annotations

import argparse
import html
import json
import os
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

try:
    import qrcode
    from qrcode.image.pil import PilImage
except ImportError:
    sys.exit("Missing dependency: pacman -S python-qrcode  (or pip install qrcode[pil])")


# The phone pages wear the shell's theme: the Control Center passes its tokens
# (--palette). These are the nier defaults (theme/Theme.qml).
PALETTE = {
    "paper": "#d6cfb5", "ink": "#463f2e", "inkStrong": "#2e2a1f", "inkSoft": "#7a7358",
    "accent": "#6e2a2a", "light": "#fff6cf", "warn": "#c8685c", "good": "#9ab58c",
}
ANSI_FG = "\033[38;2;168;154;126m"
ANSI_DIM = "\033[38;2;107;100;83m"
ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"

CHUNK = 8 * 1024 * 1024          # upload chunk (Cloudflare: ≤ 100 MB per request)

# Temp files created at runtime; removed on exit (including SIGTERM).
_TEMP_FILES: list[Path] = []


def human_size(n: float) -> str:
    if n < 1024:
        return f"{int(n)} B"
    for unit in ("KB", "MB", "GB"):
        n /= 1024
        if n < 1024:
            return f"{n:.1f} {unit}"
    return f"{n / 1024:.1f} TB"


def _hex(c: str) -> str:
    c = c.strip()
    if re.fullmatch(r"#[0-9a-fA-F]{8}", c):      # Qt's #aarrggbb
        c = "#" + c[3:]
    return c if re.fullmatch(r"#[0-9a-fA-F]{6}", c) else ""


def _rgba(c: str, a: float) -> str:
    r, g, b = (int(c[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r},{g},{b},{a})"


# ─── Network ──────────────────────────────────────────────────────────────────
def get_local_ip(iface: str | None = None) -> str:
    if iface:
        try:
            import fcntl, struct
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                packed = struct.pack("256s", iface.encode()[:15])
                return socket.inet_ntoa(fcntl.ioctl(s.fileno(), 0x8915, packed)[20:24])
        except OSError as e:
            sys.exit(f"Cannot read the IP of {iface}: {e}")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("", 0))
        return s.getsockname()[1]


# ─── Cloudflare Tunnel ────────────────────────────────────────────────────────
def start_cloudflared(local_port: int, events: "EventLog") -> tuple[subprocess.Popen, str]:
    cmd = [
        "cloudflared", "tunnel",
        "--url", f"http://localhost:{local_port}",
        "--protocol", "http2",
        "--edge-ip-version", "4",
        "--no-autoupdate",
    ]
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )

    url_pattern = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com")
    found: dict[str, object] = {"url": None, "registered": False}
    ready = threading.Event()

    def _read():
        for line in iter(proc.stdout.readline, ""):
            if not found["url"]:
                m = url_pattern.search(line)
                if m:
                    found["url"] = m.group(0)
                    events.emit("STATUS 連上 Cloudflare 了，等它開通…")
            if "Registered tunnel connection" in line:
                found["registered"] = True
            if found["url"] and found["registered"]:
                ready.set()
        ready.set()                     # cloudflared quit

    print(f"{ANSI_DIM}Starting Cloudflare tunnel…{ANSI_RESET}")
    events.emit("STATUS 正在開一條 Cloudflare 通道（約 5 秒）…")
    threading.Thread(target=_read, daemon=True).start()
    ready.wait(30)

    if proc.poll() is not None:
        events.emit("ERROR tunnel-exit cloudflared 沒開成通道就結束了（網路沒通？）")
        sys.exit("cloudflared quit before the tunnel came up.")
    if not (found["url"] and found["registered"]):
        proc.terminate()
        events.emit("ERROR tunnel-timeout 30 秒內沒拿到 Cloudflare 的網址")
        sys.exit("Could not obtain the tunnel URL (timeout).")
    return proc, str(found["url"])


# ─── QR ───────────────────────────────────────────────────────────────────────
def _qr(url: str, border: int) -> qrcode.QRCode:
    qr = qrcode.QRCode(border=border, error_correction=qrcode.constants.ERROR_CORRECT_M)
    qr.add_data(url)
    qr.make(fit=True)
    return qr


def print_qr(url: str) -> None:
    _qr(url, 1).print_ascii(invert=True)


def qr_bits(url: str) -> tuple[int, str]:
    """The module matrix, no quiet zone: the Control Center draws it in its own ink."""
    m = _qr(url, 0).get_matrix()
    return len(m), "".join("1" if v else "0" for row in m for v in row)


def write_qr_png(url: str, path: Path) -> None:
    """A PNG of the QR: dark modules on paper, the way every scanner expects."""
    qr = _qr(url, 2)
    qr.box_size = 12
    img = qr.make_image(image_factory=PilImage,
                        fill_color=PALETTE["inkStrong"], back_color=PALETTE["paper"])
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# ─── Event file (IPC to Quickshell) ───────────────────────────────────────────
class EventLog:
    def __init__(self, path: str | None):
        self.path = Path(path) if path else None
        if self.path:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text("")  # reset
        self._lock = threading.Lock()
        self._last: dict[str, float] = {}

    def emit(self, line: str) -> None:
        if not self.path:
            return
        with self._lock:
            with self.path.open("a") as f:
                f.write(line.rstrip("\n").replace("\n", " ") + "\n")

    def progress(self, tid: str, done: int, total: int, name: str) -> None:
        """PROG, at most 5 a second per transfer (the last one always)."""
        now = time.monotonic()
        if done < total and now - self._last.get(tid, 0) < 0.2:
            return
        self._last[tid] = now
        self.emit(f"PROG {tid} {done} {total} {name}")


# ─── Payload for SEND ─────────────────────────────────────────────────────────
class Entry:
    """One thing the phone can download: a plain file, or a directory served as a zip."""

    def __init__(self, path: Path):
        self.path = path
        self.is_dir = path.is_dir()
        self.name = path.name + ".zip" if self.is_dir else path.name
        self._zip: Path | None = None
        self._lock = threading.Lock()
        self.sent = 0                 # finished downloads, for the page's ✓
        if self.is_dir:
            self.size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
        else:
            self.size = path.stat().st_size

    def served_path(self) -> Path:
        """Path to stream. Zips a directory on first request, then caches it."""
        if not self.is_dir:
            return self.path
        with self._lock:
            if self._zip is None:
                self._zip = _zip_paths([self.path], self.path.parent)
            return self._zip


def _zip_paths(paths: list[Path], rel_root: Path) -> Path:
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".zip", prefix="qshare-")
    tmp.close()
    zip_path = Path(tmp.name)
    _TEMP_FILES.append(zip_path)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for p in paths:
            if p.is_file():
                zf.write(p, p.name)
            else:
                for f in p.rglob("*"):
                    if f.is_file():
                        zf.write(f, f.relative_to(rel_root))
    return zip_path


# ─── The phone pages: Paper, like the shell's panels ──────────────────────────
# A paper sheet with a fine grid, ink text, diamond corners on the card, an ink
# selector with the accent edge under a pressed row, and the shell's one confirm:
# a pop, then a diamond ring from the touch.
BASE_CSS = """
:root { --paper:__paper__; --ink:__ink__; --ink-strong:__inkStrong__; --ink-soft:__inkSoft__;
  --accent:__accent__; --light:__light__; --warn:__warn__; --good:__good__;
  --grid:__grid__; --rule:__rule__; --veil:__veil__; }
* { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
html { background:var(--paper); }
body { margin:0; min-height:100vh; color:var(--ink);
  font:15px/1.5 ui-monospace,"SF Mono","Roboto Mono","Noto Sans Mono",monospace;
  background-image:linear-gradient(var(--grid) 1px,transparent 1px),
                   linear-gradient(90deg,var(--grid) 1px,transparent 1px);
  background-size:20px 20px; }
main { max-width:560px; margin:0 auto; padding:28px 18px 40px; }
.kicker { display:flex; align-items:center; gap:10px; font-size:11px; letter-spacing:.32em;
  color:var(--ink-soft); }
.dia { width:7px; height:7px; background:var(--accent); transform:rotate(45deg); flex:none; }
h1 { margin:10px 0 0; font-weight:500; font-size:30px; letter-spacing:.14em; color:var(--ink-strong); }
.hair { width:40px; height:1px; background:var(--ink); opacity:.5; margin:14px 0; }
.meta { font-size:13px; color:var(--ink-soft); letter-spacing:.04em; }
.card { position:relative; margin-top:18px; border:1px solid var(--ink); background:var(--paper); }
.card > .c { position:absolute; width:8px; height:8px; background:var(--ink); transform:rotate(45deg); }
.c.tl { left:-4px; top:-4px; } .c.tr { right:-4px; top:-4px; }
.c.bl { left:-4px; bottom:-4px; } .c.br { right:-4px; bottom:-4px; }
.card::before { content:""; position:absolute; left:1px; right:1px; top:1px; height:1px;
  background:linear-gradient(90deg,transparent,var(--light) 35%,transparent); opacity:.9; }
ul.rows { list-style:none; margin:0; padding:6px 0; }
.row { position:relative; display:flex; align-items:center; gap:12px; min-height:56px;
  padding:8px 16px; color:var(--ink); text-decoration:none; cursor:pointer; user-select:none; }
.row + .row, li + li .row { border-top:1px solid var(--rule); }
.row .sel { position:absolute; inset:0; background:var(--ink); transform:scaleX(0);
  transform-origin:left; transition:transform .16s cubic-bezier(.2,.9,.3,1.2); }
.row .sel::before { content:""; position:absolute; left:0; top:0; bottom:0; width:3px; background:var(--accent); }
.row:active .sel, .row.hit .sel { transform:scaleX(1); }
.row:active > span, .row.hit > span { color:var(--paper); }
.row > span { position:relative; }
.mk { width:16px; text-align:center; color:var(--accent); font-size:13px; flex:none; }
.nm { flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.sz { color:var(--ink-soft); font-size:12px; white-space:nowrap; letter-spacing:.04em; }
.mk.ok { color:var(--ink-strong) !important; } .sz.ok { color:var(--ink) !important; }
.row.done .bar > i { background:var(--good); } .err { color:var(--warn) !important; }
.bar { position:absolute; left:16px; right:16px; bottom:6px; height:2px; background:var(--rule); }
.bar > i { display:block; height:100%; width:0; background:var(--accent); transition:width .15s linear; }
.btn { position:relative; display:flex; align-items:center; justify-content:center; gap:12px;
  width:100%; min-height:56px; margin-top:18px; border:0; background:var(--ink); color:var(--paper);
  font:inherit; font-size:14px; letter-spacing:.3em; text-decoration:none; cursor:pointer; }
.btn::before { content:""; position:absolute; left:0; top:0; bottom:0; width:3px; background:var(--accent); }
.btn:active { transform:scale(.97); }
.btn .k { font-size:11px; opacity:.6; letter-spacing:.2em; }
.empty { padding:22px 16px; text-align:center; color:var(--ink-soft); font-size:13px; }
.foot { margin-top:22px; font-size:12.5px; color:var(--ink-soft); line-height:1.8; }
.foot b { color:var(--ink); font-weight:500; }
.pop { animation:pop .1s ease-out; }
@keyframes pop { 50% { transform:scale(1.04); } }
.ring { position:fixed; width:18px; height:18px; margin:-9px 0 0 -9px; border:1.5px solid var(--accent);
  transform:rotate(45deg) scale(.4); pointer-events:none; animation:ring .5s ease-out forwards; z-index:9; }
@keyframes ring { to { transform:rotate(45deg) scale(4.2); opacity:0; } }
.shard { position:fixed; width:5px; height:5px; background:var(--ink); pointer-events:none; z-index:9;
  animation:shard .42s ease-out forwards; }
@keyframes shard { to { transform:translate(var(--dx),var(--dy)) rotate(45deg) scale(.2); opacity:0; } }
#drop { position:fixed; inset:0; display:none; align-items:center; justify-content:center;
  background:var(--veil); color:var(--paper); letter-spacing:.3em; font-size:16px; z-index:8; }
body.dragging #drop { display:flex; }
@media (prefers-reduced-motion:reduce) { .ring,.shard { display:none; } .row .sel { transition:none; } }
"""

HIT_JS = """
function hit(el, x, y) {
  el.classList.remove("pop"); void el.offsetWidth; el.classList.add("pop");
  const r = document.createElement("i"); r.className = "ring";
  r.style.left = x + "px"; r.style.top = y + "px"; document.body.appendChild(r);
  setTimeout(() => r.remove(), 520);
  for (let k = 0; k < 6; k++) {
    const s = document.createElement("i"); s.className = "shard";
    const a = k / 6 * Math.PI * 2 + Math.random() * .5, d = 28 + Math.random() * 22;
    s.style.left = x + "px"; s.style.top = y + "px";
    s.style.setProperty("--dx", Math.cos(a) * d + "px"); s.style.setProperty("--dy", Math.sin(a) * d + "px");
    document.body.appendChild(s); setTimeout(() => s.remove(), 440);
  }
}
function at(e, el) {
  if (e && e.clientX) return [e.clientX, e.clientY];
  const b = el.getBoundingClientRect(); return [b.left + 24, b.top + b.height / 2];
}
"""


def _page(title: str, body: str, script: str = "") -> bytes:
    p = PALETTE
    css = BASE_CSS
    for k, v in p.items():
        css = css.replace(f"__{k}__", v)
    css = (css.replace("__grid__", _rgba(p["ink"], 0.07)).replace("__rule__", _rgba(p["ink"], 0.18))
              .replace("__veil__", _rgba(p["inkStrong"], 0.82)))
    doc = (
        "<!doctype html><html lang=\"zh-Hant\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">"
        f"<meta name=\"theme-color\" content=\"{p['paper']}\">"
        f"<title>{html.escape(title)}</title><style>{css}</style></head><body>{body}"
        f"<script>{HIT_JS}{script}</script></body></html>"
    )
    return doc.encode()


def _corners() -> str:
    return '<i class="c tl"></i><i class="c tr"></i><i class="c bl"></i><i class="c br"></i>'


def _glyph(name: str, is_dir: bool) -> str:
    if is_dir:
        return "▣"
    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
    if ext in ("jpg", "jpeg", "png", "gif", "webp", "heic", "avif", "bmp", "svg"):
        return "◩"
    if ext in ("mp4", "mkv", "mov", "webm", "avi", "mp3", "flac", "wav", "ogg", "m4a", "opus"):
        return "▶"
    if ext in ("zip", "7z", "rar", "tar", "gz", "xz", "zst"):
        return "▣"
    return "◇"


# ─── HTTP handlers ────────────────────────────────────────────────────────────
class _Base(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    token: str = ""
    keep_alive: bool = True
    done_event: threading.Event = None  # type: ignore[assignment]
    events: EventLog = None  # type: ignore[assignment]
    visitors: set[str] = set()

    def log_message(self, fmt, *args):
        print(f"{ANSI_DIM}[{self.client()}] {fmt % args}{ANSI_RESET}")

    def client(self) -> str:
        # through the tunnel every request comes from cloudflared on localhost
        return self.headers.get("CF-Connecting-IP") or self.address_string()

    def _send_bytes(self, payload: bytes, ctype: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _json(self, obj, status: int = 200) -> None:
        self._send_bytes(json.dumps(obj).encode(), "application/json", status)

    def _segments(self) -> list[str] | None:
        """Path segments after the token, or None if the token doesn't match."""
        parts = [unquote(p) for p in urlparse(self.path).path.split("/") if p]
        if not parts or not secrets.compare_digest(parts[0], self.token):
            return None
        return parts[1:]

    def _visit(self) -> None:
        ip = self.client()
        if ip not in self.visitors:
            self.visitors.add(ip)
            if self.events:
                self.events.emit(f"VISIT {ip}")

    def _finished(self) -> None:
        if not self.keep_alive:
            if self.events:
                self.events.emit("DONE")
            self.done_event.set()


class SendHandler(_Base):
    entries: list[Entry] = []
    zip_all: Path | None = None
    zip_lock = threading.Lock()
    all_sent = 0
    _n = 0

    @classmethod
    def all_zip(cls) -> Path:
        with cls.zip_lock:
            if cls.zip_all is None:
                roots = [e.path for e in cls.entries]
                common = os.path.commonpath([str(p.parent) for p in roots])
                cls.zip_all = _zip_paths(roots, Path(common))
            return cls.zip_all

    def do_GET(self):  # noqa: N802
        seg = self._segments()
        if seg is None:
            self.send_error(404)
            return
        if not seg:
            self._visit()
            self._send_bytes(self._index(), "text/html; charset=utf-8")
            return
        if seg[0] == "status":
            self._json({"sent": [e.sent for e in self.entries], "all": SendHandler.all_sent})
            return
        if seg[0] == "all":
            if self._stream(self.all_zip(), "quickshare.zip"):
                SendHandler.all_sent += 1
            return
        if seg[0] == "f" and len(seg) >= 2 and seg[1].isdigit():
            idx = int(seg[1])
            if 0 <= idx < len(self.entries):
                entry = self.entries[idx]
                if self._stream(entry.served_path(), entry.name):
                    entry.sent += 1
                return
        self.send_error(404)

    def _index(self) -> bytes:
        total = sum(e.size for e in self.entries)
        rows = []
        for i, e in enumerate(self.entries):
            rows.append(
                f'<li><a class="row" data-i="{i}" href="/{self.token}/f/{i}/{quote(e.name)}" download>'
                f'<i class="sel"></i><span class="mk">{_glyph(e.name, e.is_dir)}</span>'
                f'<span class="nm">{html.escape(e.name)}</span>'
                f'<span class="sz">{human_size(e.size)}</span></a></li>'
            )
        body = [
            "<main>",
            '<div class="kicker"><i class="dia"></i>QUICKSHARE · PC → PHONE</div>',
            "<h1>DOWNLOAD</h1>",
            '<div class="hair"></div>',
            f'<div class="meta">{len(self.entries)} 個項目 · {human_size(total)}</div>',
            f'<div class="card">{_corners()}<ul class="rows">{"".join(rows)}</ul></div>',
        ]
        if len(self.entries) > 1:
            body.append(f'<a class="btn" id="all" href="/{self.token}/all/quickshare.zip" download>'
                        'DOWNLOAD ALL <span class="k">ZIP</span></a>')
        body.append(
            '<p class="foot">點一下檔名就會下載；資料夾會打包成 zip。<br>'
            "下載完成時，電腦上的分享卡片會打勾。<br>"
            "這個頁面會一直有效，直到你在電腦上按 <b>STOP</b>。</p></main>"
        )
        script = """
const T = "__TOKEN__";
const marks = [...document.querySelectorAll(".row")].map(r => r.querySelector(".mk"));
const glyph = marks.map(m => m.textContent);
let waiting = false;
document.querySelectorAll(".row, #all").forEach(el => el.addEventListener("click", e => {
  const [x, y] = at(e, el); hit(el, x, y);
  el.classList.add("hit"); setTimeout(() => el.classList.remove("hit"), 260);
  if (el.dataset.i !== undefined) { marks[+el.dataset.i].textContent = "…"; }
  waiting = true;
}));
async function poll() {
  if (waiting) {
    try {
      const s = await (await fetch("/" + T + "/status", {cache: "no-store"})).json();
      s.sent.forEach((n, i) => { if (n > 0) { marks[i].textContent = "✓"; marks[i].classList.add("ok"); } });
      if (s.sent.every(n => n > 0) || s.all > 0) waiting = false;
    } catch (e) {}
  }
  setTimeout(poll, 1200);
}
poll();
""".replace("__TOKEN__", self.token)
        return _page("Quickshare · Download", "".join(body), script)

    def _stream(self, path: Path, name: str) -> bool:
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f"attachment; filename*=UTF-8''{quote(name)}")
        self.end_headers()
        SendHandler._n += 1
        tid = f"d{SendHandler._n}"
        done = 0
        try:
            with open(path, "rb") as f:
                while True:
                    buf = f.read(256 * 1024)
                    if not buf:
                        break
                    self.wfile.write(buf)
                    done += len(buf)
                    if self.events:
                        self.events.progress(tid, done, size, name)
        except (BrokenPipeError, ConnectionResetError):
            if self.events:
                self.events.emit(f"PROG {tid} -1 {size} {name}")    # the phone gave up
            return False
        print(f"{ANSI_FG}{ANSI_BOLD}✓ {name} sent{ANSI_RESET}")
        if self.events:
            self.events.emit(f"TICK {name}")
        self._finished()
        return True


class RecvHandler(_Base):
    out_dir: Path = None  # type: ignore[assignment]
    parts: dict[str, dict] = {}
    parts_lock = threading.Lock()

    def do_GET(self):  # noqa: N802
        seg = self._segments()
        if seg is None or seg:
            self.send_error(404)
            return
        self._visit()
        self._send_bytes(self._page_upload(), "text/html; charset=utf-8")

    def _page_upload(self) -> bytes:
        dest = str(self.out_dir)
        home = str(Path.home())
        if dest.startswith(home):
            dest = "~" + dest[len(home):]
        body = f"""<main>
<div class="kicker"><i class="dia"></i>QUICKSHARE · PHONE → PC</div>
<h1>UPLOAD</h1>
<div class="hair"></div>
<div class="meta">存到電腦的 {html.escape(dest)}</div>
<input type="file" id="files" multiple hidden>
<button class="btn" id="pick">CHOOSE FILES <span class="k">↑</span></button>
<div class="card">{_corners()}<ul class="rows" id="list"><li class="empty" id="empty">還沒有傳任何檔案</li></ul></div>
<p class="foot">可以一次選很多個，也能一直傳下去；同名的檔案會自動編號。<br>
傳失敗的那一列點一下就會重傳。這個頁面會一直有效，直到你在電腦上按 <b>STOP</b>。</p>
</main>
<div id="drop">DROP TO SEND</div>"""
        script = """
const T = "__TOKEN__", CHUNK = __CHUNK__;
const input = document.getElementById("files"), list = document.getElementById("list");
const pick = document.getElementById("pick");
pick.addEventListener("click", e => { const [x, y] = at(e, pick); hit(pick, x, y); input.click(); });
input.addEventListener("change", () => { queue([...input.files]); input.value = ""; });
let depth = 0;
document.addEventListener("dragenter", e => { e.preventDefault(); depth++; document.body.classList.add("dragging"); });
document.addEventListener("dragleave", e => { if (--depth <= 0) { depth = 0; document.body.classList.remove("dragging"); } });
document.addEventListener("dragover", e => e.preventDefault());
document.addEventListener("drop", e => {
  e.preventDefault(); depth = 0; document.body.classList.remove("dragging");
  queue([...e.dataTransfer.files]);
});

let chain = Promise.resolve();
function queue(files) {
  const empty = document.getElementById("empty"); if (empty) empty.remove();
  for (const f of files) { const row = makeRow(f); chain = chain.then(() => upload(f, row)); }
}
function human(n) {
  if (n < 1024) return n + " B";
  for (const u of ["KB", "MB", "GB"]) { n /= 1024; if (n < 1024) return n.toFixed(1) + " " + u; }
  return (n / 1024).toFixed(1) + " TB";
}
function makeRow(file) {
  const li = document.createElement("li");
  li.innerHTML = '<div class="row"><i class="sel"></i><span class="mk">◇</span>' +
    '<span class="nm"></span><span class="sz">waiting</span><div class="bar"><i></i></div></div>';
  li.querySelector(".nm").textContent = file.name;
  list.prepend(li);
  return { el: li.querySelector(".row"), mk: li.querySelector(".mk"), sz: li.querySelector(".sz"),
           bar: li.querySelector(".bar > i") };
}
function send(id, file, off, blob) {
  return new Promise((resolve, reject) => {
    const x = new XMLHttpRequest();
    x.open("POST", "/" + T + "/up/" + id + "?name=" + encodeURIComponent(file.name) +
                   "&off=" + off + "&size=" + file.size);
    x.upload.onprogress = e => send.onp && send.onp(off + e.loaded);
    x.onload = () => x.status === 200 ? resolve(JSON.parse(x.responseText)) : reject(x.status);
    x.onerror = () => reject("network");
    x.send(blob);
  });
}
async function upload(file, row) {
  const id = Array.from(crypto.getRandomValues(new Uint8Array(8)), b => b.toString(16).padStart(2, "0")).join("");
  const t0 = performance.now();
  row.mk.textContent = "↑"; row.mk.className = "mk"; row.sz.className = "sz"; row.el.classList.remove("done");
  send.onp = n => {
    const pct = file.size ? n / file.size * 100 : 100, s = (performance.now() - t0) / 1000;
    row.bar.style.width = pct.toFixed(1) + "%";
    row.sz.textContent = Math.floor(pct) + "%" + (s > 1 ? " · " + human(n / s) + "/s" : "");
  };
  try {
    let off = 0, res = null;
    do {
      const blob = file.slice(off, off + CHUNK);
      for (let tries = 0; ; tries++) {
        try { res = await send(id, file, off, blob); break; }
        catch (e) { if (tries >= 2) throw e; await new Promise(r => setTimeout(r, 800)); }
      }
      off += blob.size;
    } while (off < file.size);
    row.bar.style.width = "100%";
    row.mk.textContent = "✓"; row.mk.className = "mk ok";
    row.sz.textContent = human(file.size); row.sz.className = "sz ok"; row.el.classList.add("done");
    if (res && res.name && res.name !== file.name) row.el.querySelector(".nm").textContent = res.name;
    const b = row.el.getBoundingClientRect(); hit(row.el, b.left + 24, b.top + b.height / 2);
  } catch (e) {
    row.mk.textContent = "✕"; row.mk.className = "mk err";
    row.sz.textContent = "FAILED · TAP TO RETRY"; row.sz.className = "sz err";
    row.el.onclick = ev => { row.el.onclick = null; const [x, y] = at(ev, row.el); hit(row.el, x, y);
                             chain = chain.then(() => upload(file, row)); };
  }
}
""".replace("__TOKEN__", self.token).replace("__CHUNK__", str(CHUNK))
        return _page("Quickshare · Upload", body, script)

    def do_POST(self):  # noqa: N802
        seg = self._segments()
        if seg is None or len(seg) != 2 or seg[0] != "up" or not re.fullmatch(r"[0-9a-f]{4,32}", seg[1]):
            self.send_error(404)
            return
        q = parse_qs(urlparse(self.path).query)
        try:
            name = Path(q["name"][0]).name.strip() or "file"
            off, size = int(q["off"][0]), int(q["size"][0])
            length = int(self.headers.get("Content-Length", "-1"))
        except (KeyError, ValueError, IndexError):
            self.send_error(400)
            return
        if off < 0 or size < 0 or length < 0 or length > CHUNK * 2 or off + length > size:
            self.send_error(400)
            return
        tid = "u" + seg[1]
        with self.parts_lock:
            part = self.parts.get(tid)
            if part is None:
                path = self.out_dir / f".qshare-{seg[1]}.part"
                path.touch()
                _TEMP_FILES.append(path)
                part = self.parts[tid] = {"path": path, "got": 0, "name": name, "size": size}
        with open(part["path"], "r+b") as f:
            f.seek(off)
            left = length
            while left > 0:
                buf = self.rfile.read(min(256 * 1024, left))
                if not buf:
                    self.send_error(400)
                    return
                f.write(buf)
                left -= len(buf)
                if self.events:
                    self.events.progress(tid, off + length - left, size, name)
        part["got"] = max(part["got"], off + length)
        if part["got"] < size:
            self._json({"ok": True})
            return
        with self.parts_lock:
            self.parts.pop(tid, None)
            dest = _unique_path(self.out_dir / name)
            part["path"].rename(dest)
        print(f"{ANSI_FG}{ANSI_BOLD}✓ received: {dest.name}{ANSI_RESET}")
        if self.events:
            self.events.emit(f"PROG {tid} {size} {size} {dest.name}")
            self.events.emit(f"TICK {dest.name}")
        self._json({"ok": True, "name": dest.name})
        self._finished()


def _unique_path(p: Path) -> Path:
    if not p.exists():
        return p
    stem, suf = p.stem, p.suffix
    i = 1
    while True:
        cand = p.with_name(f"{stem} ({i}){suf}")
        if not cand.exists():
            return cand
        i += 1


# ─── Commands ─────────────────────────────────────────────────────────────────
def _start_server_with_port(handler_cls, preferred_port: int):
    port = preferred_port if preferred_port else _free_port()
    try:
        return ThreadingHTTPServer(("0.0.0.0", port), handler_cls), port
    except OSError:
        port = _free_port()
        return ThreadingHTTPServer(("0.0.0.0", port), handler_cls), port


def _emit_ready(events: EventLog, url: str, qr_path: Path | None) -> None:
    events.emit(f"URL {url}")
    n, bits = qr_bits(url)
    events.emit(f"QRM {n} {bits}")
    if qr_path:
        events.emit(f"QR {qr_path}")
    events.emit("READY")


def _cleanup_temps() -> None:
    for p in _TEMP_FILES:
        try:
            p.unlink()
        except OSError:
            pass


def _serve(server, handler_cls, keep_alive: bool, events: EventLog, tunnel_proc) -> None:
    try:
        if keep_alive:
            server.serve_forever()
        else:
            t = threading.Thread(target=server.serve_forever, daemon=True)
            t.start()
            handler_cls.done_event.wait()
            server.shutdown()
    except (KeyboardInterrupt, SystemExit):
        print(f"\n{ANSI_DIM}stopped{ANSI_RESET}")
        events.emit("CANCELLED")
    finally:
        _cleanup_temps()
        if tunnel_proc:
            tunnel_proc.terminate()


def _resolve_url(args, port: int, token: str, events: EventLog, suffix: str = "") -> tuple[str, subprocess.Popen | None]:
    if args.tunnel:
        tunnel_proc, public = start_cloudflared(port, events)
        return f"{public}/{token}{suffix}", tunnel_proc
    ip = get_local_ip(args.iface)
    return f"http://{ip}:{port}/{token}{suffix}", None


def _check_tunnel(args, events: EventLog) -> None:
    if args.tunnel and not shutil.which("cloudflared"):
        events.emit("ERROR cloudflared-missing 網際網路模式需要 cloudflared，這台電腦還沒裝")
        sys.exit("cloudflared not found. Install it: pacman -S cloudflared")


def cmd_send(args: argparse.Namespace) -> None:
    events = EventLog(args.event_file)
    paths = [Path(p).expanduser().resolve() for p in args.paths]
    for p in paths:
        if not p.exists():
            events.emit(f"ERROR bad-path 找不到 {p}")
            sys.exit(f"Not found: {p}")
    _check_tunnel(args, events)

    token = secrets.token_urlsafe(12)
    entries = [Entry(p) for p in paths]

    SendHandler.entries = entries
    SendHandler.zip_all = None
    SendHandler.token = token
    SendHandler.keep_alive = args.keep_alive
    SendHandler.done_event = threading.Event()
    SendHandler.events = events

    server, port = _start_server_with_port(SendHandler, args.port)
    url, tunnel_proc = _resolve_url(args, port, token, events, suffix="/")

    qr_path = Path(args.qr_out).expanduser().resolve() if args.qr_out else None
    if qr_path:
        write_qr_png(url, qr_path)

    total = sum(e.size for e in entries)
    label = entries[0].name if len(entries) == 1 else f"{len(entries)} items"
    events.emit(f"COUNT {len(entries)}")
    events.emit(f"SIZE {human_size(total)}")
    _print_banner("SEND", f"{label} · {human_size(total)}", url, tunneled=args.tunnel)
    _emit_ready(events, url, qr_path)

    _serve(server, SendHandler, args.keep_alive, events, tunnel_proc)


def cmd_recv(args: argparse.Namespace) -> None:
    events = EventLog(args.event_file)
    _check_tunnel(args, events)
    out = Path(args.output).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(12)

    RecvHandler.out_dir = out
    RecvHandler.token = token
    RecvHandler.keep_alive = args.keep_alive
    RecvHandler.done_event = threading.Event()
    RecvHandler.events = events

    server, port = _start_server_with_port(RecvHandler, args.port)
    url, tunnel_proc = _resolve_url(args, port, token, events, suffix="/")

    qr_path = Path(args.qr_out).expanduser().resolve() if args.qr_out else None
    if qr_path:
        write_qr_png(url, qr_path)

    _print_banner("RECV", str(out), url, tunneled=args.tunnel)
    _emit_ready(events, url, qr_path)

    _serve(server, RecvHandler, args.keep_alive, events, tunnel_proc)


def _print_banner(mode: str, target: str, url: str, *, tunneled: bool) -> None:
    line = "─" * 48
    print(f"\n{ANSI_FG}{line}")
    mode_label = f"{mode} (INTERNET)" if tunneled else f"{mode} (LAN)"
    print(f"  qshare // {mode_label}")
    print(f"  {ANSI_DIM}target : {ANSI_FG}{target}")
    print(f"  {ANSI_DIM}url    : {ANSI_FG}{url}")
    print(f"{line}{ANSI_RESET}\n")
    print_qr(url)
    hint = "Public QR — reachable from anywhere (mobile data OK)." if tunneled \
           else "LAN QR — the phone must be on the same Wi-Fi."
    print(f"\n{ANSI_DIM}{hint} Ctrl-C to stop.{ANSI_RESET}\n")


# ─── CLI ──────────────────────────────────────────────────────────────────────
def main() -> None:
    p = argparse.ArgumentParser(prog="qshare",
        description="PC <-> phone file sharing over HTTP + QR")
    sub = p.add_subparsers(dest="cmd", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("-p", "--port", type=int, default=5100)
    common.add_argument("-i", "--iface")
    common.add_argument("-k", "--keep-alive", dest="keep_alive", action="store_true",
                        default=True, help="stay up after a transfer (default)")
    common.add_argument("--once", dest="keep_alive", action="store_false",
                        help="shut down after the first transfer")
    common.add_argument("-t", "--tunnel", action="store_true",
                        help="expose over the internet via a Cloudflare tunnel")
    common.add_argument("--qr-out", help="write a PNG of the QR here")
    common.add_argument("--event-file", help="event file for Quickshell IPC")
    common.add_argument("--palette", help="JSON of the theme's tokens for the phone pages")

    sp_send = sub.add_parser("send", parents=[common])
    sp_send.add_argument("paths", nargs="+")
    sp_send.set_defaults(func=cmd_send)

    sp_recv = sub.add_parser("recv", parents=[common])
    sp_recv.add_argument("-o", "--output", default=os.getcwd())
    sp_recv.set_defaults(func=cmd_recv)

    args = p.parse_args()
    if args.palette:
        try:
            for k, v in json.loads(args.palette).items():
                if k in PALETTE and _hex(str(v)):
                    PALETTE[k] = _hex(str(v))
        except ValueError:
            pass

    # SIGTERM (Quickshell stopping us) must run the same cleanup as Ctrl-C.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        args.func(args)
    finally:
        _cleanup_temps()


if __name__ == "__main__":
    main()
