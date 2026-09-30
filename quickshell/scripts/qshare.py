#!/usr/bin/env python3
"""
qshare — PC <-> phone file sharing over HTTP + QR code.

CLI:
    qshare send <file|dir...> [--tunnel] [--once]
    qshare recv [-o DIR] [--tunnel] [--once]

Internal (from Quickshell):
    qshare ... --qr-out /tmp/qshare-qr.png --event-file /tmp/qshare-events

The server stays up until you stop it (Ctrl-C, or SIGTERM from Quickshell) so
the phone can grab several files / upload several times from one QR. Pass
--once to fall back to the old "shut down after the first transfer" behaviour.
"""
from __future__ import annotations

import argparse
import html
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
from urllib.parse import quote, unquote, urlparse

try:
    import qrcode
    from qrcode.image.pil import PilImage
except ImportError:
    sys.exit("Missing dependency: pacman -S python-qrcode  (or pip install qrcode[pil])")


NIER_BG, NIER_FG, NIER_ACCENT, NIER_DIM = "#1c1a17", "#a89a7e", "#d4c8a8", "#6b6453"
ANSI_FG = "\033[38;2;168;154;126m"
ANSI_DIM = "\033[38;2;107;100;83m"
ANSI_RESET = "\033[0m"
ANSI_BOLD = "\033[1m"

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
    if not shutil.which("cloudflared"):
        events.emit("ERROR cloudflared not installed")
        sys.exit("cloudflared not found. Install it: pacman -S cloudflared")

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
    public_url: str | None = None
    registered = False
    deadline = time.monotonic() + 30

    print(f"{ANSI_DIM}Starting Cloudflare tunnel…{ANSI_RESET}")
    events.emit("STATUS Starting Cloudflare tunnel…")
    while time.monotonic() < deadline:
        line = proc.stdout.readline()
        if not line:
            if proc.poll() is not None:
                events.emit("ERROR cloudflared exited")
                sys.exit("cloudflared quit before the tunnel came up.")
            continue
        if not public_url:
            m = url_pattern.search(line)
            if m:
                public_url = m.group(0)
        if "Registered tunnel connection" in line:
            registered = True
        if public_url and registered:
            break

    if not public_url:
        proc.terminate()
        events.emit("ERROR tunnel timeout")
        sys.exit("Could not obtain the tunnel URL (timeout).")

    def _drain():
        for _ in iter(proc.stdout.readline, ""):
            pass
    threading.Thread(target=_drain, daemon=True).start()
    return proc, public_url


# ─── QR ───────────────────────────────────────────────────────────────────────
def print_qr(url: str) -> None:
    qr = qrcode.QRCode(border=1, error_correction=qrcode.constants.ERROR_CORRECT_L)
    qr.add_data(url)
    qr.make(fit=True)
    qr.print_ascii(invert=True)


def write_qr_png(url: str, path: Path) -> None:
    """Write a QR PNG using the NieR palette (dark ground, light modules)."""
    qr = qrcode.QRCode(
        border=2,
        box_size=12,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(
        image_factory=PilImage,
        fill_color=NIER_FG,
        back_color=NIER_BG,
    )
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

    def emit(self, line: str) -> None:
        if not self.path:
            return
        with self._lock:
            with self.path.open("a") as f:
                f.write(line.rstrip("\n") + "\n")


# ─── Payload for SEND ─────────────────────────────────────────────────────────
class Entry:
    """One thing the phone can download: a plain file, or a directory served as a zip."""

    def __init__(self, path: Path):
        self.path = path
        self.is_dir = path.is_dir()
        self.name = path.name + ".zip" if self.is_dir else path.name
        self._zip: Path | None = None
        self._lock = threading.Lock()
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


# ─── Shared page chrome ───────────────────────────────────────────────────────
BASE_CSS = """
  :root { --bg:__BG__; --fg:__FG__; --accent:__ACCENT__; --dim:__DIM__; }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin:0; padding:0; background:var(--bg); color:var(--fg);
    font-family:'Iosevka','JetBrains Mono',ui-monospace,monospace; min-height:100vh; }
  main { max-width:560px; margin:0 auto; padding:2rem 1.1rem 3rem; }
  h1 { font-weight:400; letter-spacing:0.38em; text-transform:uppercase;
    border-bottom:1px solid var(--dim); padding-bottom:0.6rem; font-size:0.95rem; margin:0; }
  .meta { color:var(--dim); font-size:0.78rem; letter-spacing:0.12em;
    text-transform:uppercase; margin:0.9rem 0 0; }
  .frame { border:1px solid var(--dim); padding:1.1rem; margin-top:1rem; position:relative; }
  .frame::before, .frame::after { content:""; position:absolute; width:8px; height:8px;
    border:1px solid var(--accent); background:var(--bg); }
  .frame::before { top:-4px; left:-4px; }
  .frame::after { bottom:-4px; right:-4px; }
  .btn { display:block; width:100%; background:transparent; color:var(--accent);
    border:1px solid var(--accent); padding:0.8rem; font-family:inherit; font-size:0.82rem;
    letter-spacing:0.26em; text-transform:uppercase; cursor:pointer; text-align:center;
    text-decoration:none; transition:background 0.18s, color 0.18s; }
  .btn:active, .btn:hover { background:var(--accent); color:var(--bg); }
  .btn[disabled] { opacity:0.4; cursor:wait; }
  ul.rows { list-style:none; margin:0; padding:0; }
  ul.rows li { border-bottom:1px solid rgba(107,100,83,0.45); }
  ul.rows li:last-child { border-bottom:none; }
  .row { display:flex; align-items:center; gap:0.7rem; padding:0.75rem 0.1rem;
    color:var(--fg); text-decoration:none; }
  .row .nm { flex:1; min-width:0; overflow:hidden; text-overflow:ellipsis;
    white-space:nowrap; font-size:0.88rem; }
  .row .sz { color:var(--dim); font-size:0.72rem; white-space:nowrap; }
  .row .mark { color:var(--accent); font-size:0.8rem; width:1.1rem; text-align:center; }
  .bar { height:2px; background:rgba(107,100,83,0.5); margin-top:0.35rem; overflow:hidden; }
  .bar > div { height:100%; width:0%; background:var(--accent); transition:width 0.12s linear; }
  .foot { color:var(--dim); font-size:0.72rem; margin-top:1.2rem; line-height:1.6;
    letter-spacing:0.06em; }
  .ok { color:var(--accent); }
  .err { color:#c97a6f; }
"""


def _page(title: str, body: str) -> bytes:
    css = (BASE_CSS.replace("__BG__", NIER_BG).replace("__FG__", NIER_FG)
                   .replace("__ACCENT__", NIER_ACCENT).replace("__DIM__", NIER_DIM))
    doc = (
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
        f"<title>{html.escape(title)}</title><style>{css}</style></head><body>{body}</body></html>"
    )
    return doc.encode()


# ─── HTTP handlers ────────────────────────────────────────────────────────────
class _Base(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    token: str = ""
    keep_alive: bool = True
    done_event: threading.Event = None  # type: ignore[assignment]
    events: EventLog = None  # type: ignore[assignment]

    def log_message(self, fmt, *args):
        print(f"{ANSI_DIM}[{self.address_string()}] {fmt % args}{ANSI_RESET}")

    def _send_bytes(self, payload: bytes, ctype: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _segments(self) -> list[str] | None:
        """Path segments after the token, or None if the token doesn't match."""
        parts = [unquote(p) for p in urlparse(self.path).path.split("/") if p]
        if not parts or parts[0] != self.token:
            return None
        return parts[1:]


class SendHandler(_Base):
    entries: list[Entry] = []
    zip_all: Path | None = None
    zip_lock = threading.Lock()

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
            self._send_bytes(self._index(), "text/html; charset=utf-8")
            return

        if seg[0] == "all":
            self._stream(self.all_zip(), "qshare-bundle.zip")
            return

        if seg[0] == "f" and len(seg) >= 2 and seg[1].isdigit():
            idx = int(seg[1])
            if 0 <= idx < len(self.entries):
                entry = self.entries[idx]
                self._stream(entry.served_path(), entry.name)
                return

        self.send_error(404)

    def _index(self) -> bytes:
        total = sum(e.size for e in self.entries)
        rows = []
        for i, e in enumerate(self.entries):
            icon = "▣" if e.is_dir else "▪"
            rows.append(
                f'<li><a class="row" href="/{self.token}/f/{i}/{quote(e.name)}">'
                f'<span class="mark">{icon}</span>'
                f'<span class="nm">{html.escape(e.name)}</span>'
                f'<span class="sz">{human_size(e.size)}</span></a></li>'
            )
        plural = "s" if len(self.entries) != 1 else ""
        body = [
            "<main>",
            "<h1>qshare // download</h1>",
            f'<p class="meta">{len(self.entries)} item{plural} · {human_size(total)}</p>',
            '<div class="frame">',
            f'<ul class="rows">{"".join(rows)}</ul>',
            "</div>",
        ]
        if len(self.entries) > 1:
            body.append(
                f'<p style="margin-top:1rem"><a class="btn" '
                f'href="/{self.token}/all/qshare-bundle.zip">Download all (.zip)</a></p>'
            )
        body.append(
            '<p class="foot">Tap a name to download it.<br>'
            "This page stays live until you close it on the desktop.</p></main>"
        )
        return _page("qshare // download", "".join(body))

    def _stream(self, path: Path, name: str) -> None:
        size = path.stat().st_size
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f'attachment; filename="{quote(name)}"')
        self.end_headers()
        with open(path, "rb") as f:
            shutil.copyfileobj(f, self.wfile)
        print(f"{ANSI_FG}{ANSI_BOLD}✓ {name} sent{ANSI_RESET}")
        if self.events:
            self.events.emit(f"TICK {name}")
        if not self.keep_alive:
            if self.events:
                self.events.emit("DONE")
            self.done_event.set()


class RecvHandler(_Base):
    out_dir: Path = None  # type: ignore[assignment]

    def do_GET(self):  # noqa: N802
        seg = self._segments()
        if seg is None:
            self.send_error(404)
            return
        self._send_bytes(self._page_upload(), "text/html; charset=utf-8")

    def _page_upload(self) -> bytes:
        dest = str(self.out_dir)
        home = str(Path.home())
        if dest.startswith(home):
            dest = "~" + dest[len(home):]
        body = f"""<main>
<h1>qshare // upload</h1>
<p class="meta">→ {html.escape(dest)}</p>
<div class="frame">
  <input type="file" id="files" multiple hidden>
  <button class="btn" id="pick">Choose files</button>
  <div id="drop" class="foot" style="text-align:center;padding:0.9rem 0 0">
    …or drop them anywhere on this page
  </div>
  <ul class="rows" id="list" style="margin-top:0.8rem"></ul>
</div>
<p class="foot">Files land in {html.escape(dest)} on the desktop.<br>
You can keep sending more — this page stays open.</p>
</main>
<script>
const TOKEN = "{self.token}";
const input = document.getElementById("files");
const list  = document.getElementById("list");
document.getElementById("pick").addEventListener("click", () => input.click());
input.addEventListener("change", () => {{ queue([...input.files]); input.value = ""; }});

for (const ev of ["dragenter", "dragover", "drop"]) {{
  document.addEventListener(ev, e => {{ e.preventDefault(); e.stopPropagation(); }});
}}
document.addEventListener("drop", e => queue([...e.dataTransfer.files]));

let chain = Promise.resolve();
function queue(files) {{
  for (const f of files) chain = chain.then(() => upload(f));
}}

function upload(file) {{
  const li = document.createElement("li");
  li.innerHTML =
    '<div class="row"><span class="mark">↑</span>' +
    '<span class="nm"></span><span class="sz"></span></div>' +
    '<div class="bar"><div></div></div>';
  li.querySelector(".nm").textContent = file.name;
  list.prepend(li);
  const mark = li.querySelector(".mark");
  const sz   = li.querySelector(".sz");
  const bar  = li.querySelector(".bar > div");

  return new Promise(resolve => {{
    const fd = new FormData();
    fd.append("files", file, file.name);
    const xhr = new XMLHttpRequest();
    xhr.open("POST", "/upload?t=" + TOKEN);
    xhr.upload.onprogress = e => {{
      if (e.lengthComputable) bar.style.width = (e.loaded / e.total * 100).toFixed(1) + "%";
    }};
    xhr.onload = () => {{
      if (xhr.status === 200) {{
        mark.textContent = "✓"; mark.className = "mark ok";
        sz.textContent = "sent"; bar.style.width = "100%";
      }} else {{
        mark.textContent = "✗"; mark.className = "mark err";
        sz.textContent = "error " + xhr.status;
      }}
      resolve();
    }};
    xhr.onerror = () => {{
      mark.textContent = "✗"; mark.className = "mark err";
      sz.textContent = "network error";
      resolve();
    }};
    xhr.send(fd);
  }});
}}
</script>"""
        return _page("qshare // upload", body)

    def do_POST(self):  # noqa: N802
        if not urlparse(self.path).path.startswith("/upload"):
            self.send_error(404); return
        if f"t={self.token}" not in self.path:
            self.send_error(403); return
        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" not in ctype:
            self.send_error(400, "multipart/form-data expected"); return
        boundary = ctype.split("boundary=", 1)[1].encode()
        length = int(self.headers.get("Content-Length", 0))
        saved = self._parse_multipart(boundary, length)
        self._send_bytes(b"ok", "text/plain")
        for name in saved:
            print(f"{ANSI_FG}{ANSI_BOLD}✓ received: {name}{ANSI_RESET}")
            if self.events:
                self.events.emit(f"TICK {name}")
        if saved and not self.keep_alive:
            if self.events:
                self.events.emit("DONE")
            self.done_event.set()

    def _parse_multipart(self, boundary: bytes, length: int) -> list[str]:
        saved: list[str] = []
        delim = b"--" + boundary
        end_delim = delim + b"--"
        rfile = self.rfile
        remaining = length

        def readline():
            nonlocal remaining
            line = rfile.readline()
            remaining -= len(line)
            return line

        while remaining > 0:
            line = readline()
            if line.startswith(delim):
                break

        while remaining > 0:
            headers: dict[str, str] = {}
            while True:
                line = readline()
                if line in (b"\r\n", b""):
                    break
                k, _, v = line.decode("utf-8", "replace").partition(":")
                headers[k.strip().lower()] = v.strip()
            disp = headers.get("content-disposition", "")
            filename = None
            for piece in disp.split(";"):
                piece = piece.strip()
                if piece.startswith("filename="):
                    filename = unquote(piece.split("=", 1)[1].strip().strip('"'))
            if not filename:
                while remaining > 0:
                    line = readline()
                    if line.startswith(delim):
                        break
                if line.startswith(end_delim):
                    break
                continue
            safe_name = Path(filename).name
            dest = _unique_path(self.out_dir / safe_name)
            with open(dest, "wb") as out:
                prev = b""
                while remaining > 0:
                    line = rfile.readline()
                    remaining -= len(line)
                    if line.startswith(delim):
                        if prev.endswith(b"\r\n"):
                            prev = prev[:-2]
                        out.write(prev)
                        break
                    out.write(prev)
                    prev = line
            saved.append(dest.name)
            if line.startswith(end_delim):
                break
        return saved


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


def cmd_send(args: argparse.Namespace) -> None:
    paths = [Path(p).expanduser().resolve() for p in args.paths]
    for p in paths:
        if not p.exists():
            sys.exit(f"Not found: {p}")

    token = secrets.token_urlsafe(8)
    events = EventLog(args.event_file)
    entries = [Entry(p) for p in paths]

    SendHandler.entries = entries
    SendHandler.zip_all = None
    SendHandler.token = token
    SendHandler.keep_alive = args.keep_alive
    SendHandler.done_event = threading.Event()
    SendHandler.events = events

    server, port = _start_server_with_port(SendHandler, args.port or (8080 if args.tunnel else 0))
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
    out = Path(args.output).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)
    token = secrets.token_urlsafe(8)
    events = EventLog(args.event_file)

    RecvHandler.out_dir = out
    RecvHandler.token = token
    RecvHandler.keep_alive = args.keep_alive
    RecvHandler.done_event = threading.Event()
    RecvHandler.events = events

    server, port = _start_server_with_port(RecvHandler, args.port or (8080 if args.tunnel else 0))
    url, tunnel_proc = _resolve_url(args, port, token, events)

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
    common.add_argument("--qr-out", help="write a PNG of the QR here (for Quickshell)")
    common.add_argument("--event-file", help="event file for Quickshell IPC")

    sp_send = sub.add_parser("send", parents=[common])
    sp_send.add_argument("paths", nargs="+")
    sp_send.set_defaults(func=cmd_send)

    sp_recv = sub.add_parser("recv", parents=[common])
    sp_recv.add_argument("-o", "--output", default=os.getcwd())
    sp_recv.set_defaults(func=cmd_recv)

    args = p.parse_args()

    # SIGTERM (Quickshell stopping us) must run the same cleanup as Ctrl-C.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        args.func(args)
    finally:
        _cleanup_temps()


if __name__ == "__main__":
    main()
