#!/usr/bin/env python3
"""fcitx5 ⇄ Quickshell input-method panel bridge (the KDE "kimpanel" protocol).

fcitx5's kimpanel addon (UIPriority 50, above classicui) switches to an external
panel as soon as the D-Bus name org.kde.impanel is owned, and falls back to its own
classic candidate window when the name goes away — so if this bridge (or the shell)
stops, typing keeps working with the stock UI.

stdout: one JSON object per line
  {"t":"ready"}                                  panel registered
  {"t":"enable","on":b}                          IM active in the focused field
  {"t":"table","show":b}                         candidate list shown / hidden
  {"t":"cands","labels":[..],"cands":[..],"prev":b,"next":b,"cursor":i,"layout":i}
  {"t":"cursor","i":i}                           highlighted candidate (on this page)
  {"t":"aux","show":b} / {"t":"auxText","text":s}
  {"t":"pre","show":b} / {"t":"preText","text":s} / {"t":"preCaret","i":i}
  {"t":"spot","mon":s,"mw":i,"mh":i,"x":i,"y":i,"w":i,"h":i}
        the text cursor, in that monitor's layout px. Source: `hyprctl caret` from
        the imecaret Hyprland plugin (hypr-plugin/imecaret) — the compositor's own
        text-input cursor box, the only place Wayland apps typing through
        input-method-v2 report it (fcitx5 gets no rect for them). When the plugin
        has nothing (XWayland / D-Bus-module apps), fcitx5's own rect is used.
  {"t":"commit",…spot fields…,"n":i}          the IM committed n characters there
  {"t":"spark",…spot fields…}                  the preedit changed: the caret after it
  {"t":"enter",…spot fields…}                  Enter in a text input (no IM commit came of it)
        (both from the imecaret plugin's imecommit / imepreedit events on
        Hyprland's event socket)
stdin: "select N" · "prev" · "next"
"""
import json
import os
import socket
import sys
import warnings

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib  # noqa: E402

PANEL_XML = """<node>
 <interface name="org.kde.impanel">
  <signal name="MovePreeditCaret"><arg type="i" name="position"/></signal>
  <signal name="SelectCandidate"><arg type="i" name="index"/></signal>
  <signal name="LookupTablePageUp"/>
  <signal name="LookupTablePageDown"/>
  <signal name="TriggerProperty"><arg type="s" name="key"/></signal>
  <signal name="PanelCreated"/>
  <signal name="Exit"/>
  <signal name="ReloadConfig"/>
  <signal name="Configure"/>
 </interface>
 <interface name="org.kde.impanel2">
  <signal name="PanelCreated2"/>
  <method name="SetSpotRect">
   <arg type="i" name="x" direction="in"/><arg type="i" name="y" direction="in"/>
   <arg type="i" name="w" direction="in"/><arg type="i" name="h" direction="in"/>
  </method>
  <method name="SetRelativeSpotRect">
   <arg type="i" name="x" direction="in"/><arg type="i" name="y" direction="in"/>
   <arg type="i" name="w" direction="in"/><arg type="i" name="h" direction="in"/>
  </method>
  <method name="SetRelativeSpotRectV2">
   <arg type="i" name="x" direction="in"/><arg type="i" name="y" direction="in"/>
   <arg type="i" name="w" direction="in"/><arg type="i" name="h" direction="in"/>
   <arg type="d" name="scale" direction="in"/>
  </method>
  <method name="SetLookupTable">
   <arg type="as" name="label" direction="in"/><arg type="as" name="text" direction="in"/>
   <arg type="as" name="attr" direction="in"/><arg type="b" name="hasPrev" direction="in"/>
   <arg type="b" name="hasNext" direction="in"/><arg type="i" name="cursor" direction="in"/>
   <arg type="i" name="layout" direction="in"/>
  </method>
 </interface>
</node>"""

PATH = '/org/kde/impanel'
bus = None


def out(**msg):
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + '\n')
    sys.stdout.flush()


# ── Hyprland: focused window origin + monitors (straight from its socket) ──
def hypr(cmd):
    sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    rt = os.environ.get('XDG_RUNTIME_DIR')
    if not sig or not rt:
        return None
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(0.2)
        s.connect(f'{rt}/hypr/{sig}/.socket.sock')
        s.sendall(cmd.encode())
        data = b''
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
        s.close()
        return json.loads(data.decode())
    except (OSError, ValueError):
        return None


def spot(x, y, w, h, t='spot', **extra):
    """Absolute layout rect → the monitor it's on, in that monitor's local px."""
    mons = hypr('j/monitors') or []
    cx, cy = x + w / 2, y + h / 2
    pick = None
    for m in mons:
        if m['x'] <= cx < m['x'] + m['width'] / m['scale'] and m['y'] <= cy < m['y'] + m['height'] / m['scale']:
            pick = m
            break
    if pick is None:          # (0,0)-style placeholders land on no monitor: ignore
        return
    s = pick['scale']
    out(t=t, mon=pick['name'], mw=round(pick['width'] / s), mh=round(pick['height'] / s),
        x=round(x - pick['x']), y=round(y - pick['y']), w=round(w), h=round(h), **extra)


def relative(x, y, w, h, scale=1.0):
    global fcitx_rect
    if not (x or y or w or h):          # waylandim ICs: fcitx5 knows no rect at all
        fcitx_rect = None
    else:
        win = hypr('j/activewindow') or {}
        at = win.get('at') or [0, 0]
        if scale and scale > 0 and scale != 1.0:
            x, y, w, h = x / scale, y / scale, w / scale, h / scale
        fcitx_rect = (at[0] + x, at[1] + y, w, h)
    track()


def absolute(x, y, w, h):
    global fcitx_rect
    fcitx_rect = (x, y, w, h) if (x or y or w or h) else None
    track()


# ── where the caret is: the compositor first (plugin), fcitx5's rect second ──
fcitx_rect = None
sent_rect = None
_idle = False


def refresh():
    global _idle, sent_rect
    _idle = False
    c = hypr('j/caret')
    r = (c['x'], c['y'], c['w'], c['h']) if c and c.get('ok') else fcitx_rect
    if r and r != sent_rect:
        sent_rect = r
        spot(*r)
    return False


def track():
    """Re-read the caret now and a little later: an app reports its new cursor box
    only after it has drawn the preedit fcitx5 just sent it."""
    global _idle
    if not _idle:
        _idle = True
        GLib.idle_add(refresh)
        GLib.timeout_add(40, refresh)
        GLib.timeout_add(140, refresh)


def table(labels, cands, attrs, prev, nxt, cursor, layout):
    out(t='cands', labels=[l.strip().rstrip('.') for l in labels], cands=list(cands),
        prev=bool(prev), next=bool(nxt), cursor=int(cursor), layout=int(layout))


# ── panel side: impanel2 methods fcitx5 calls on us ──
def on_method(conn, sender, path, iface, method, params, invocation):
    a = params.unpack()
    if method == 'SetSpotRect':
        absolute(*a)
    elif method == 'SetRelativeSpotRect':
        relative(*a)
    elif method == 'SetRelativeSpotRectV2':
        relative(*a)
    elif method == 'SetLookupTable':
        table(*a)
        track()
    invocation.return_value(None)


# ── the current input method ──
# fcitx5 re-sends "/Fcitx/im:<name>:<icon>:<hint>:menu,label=<short>" on every focus
# change; only a real switch is passed on (the first one just sets the state).
last_im = None


def im_property(prop):
    global last_im
    parts = prop.split(':')
    if len(parts) < 3 or parts[0] != '/Fcitx/im':
        return
    key = parts[2]
    if key == last_im:
        return
    first = last_im is None
    last_im = key
    label = ''
    for kv in parts[-1].split(','):
        if kv.startswith('label='):
            label = kv[6:]
    out(t='im', name=parts[1], key=key, label=label, first=first)


# ── IM side: signals fcitx5 broadcasts from /kimpanel ──
def on_im_signal(conn, sender, path, iface, name, params):
    a = params.unpack()
    if name == 'ShowLookupTable':
        out(t='table', show=bool(a[0]))
    elif name == 'UpdateLookupTable':
        table(a[0], a[1], a[2], a[3], a[4], -1, 0)
    elif name == 'UpdateLookupTableCursor':
        out(t='cursor', i=int(a[0]))
    elif name == 'ShowAux':
        out(t='aux', show=bool(a[0]))
    elif name == 'UpdateAux':
        out(t='auxText', text=a[0])
    elif name == 'ShowPreedit':
        out(t='pre', show=bool(a[0]))
    elif name == 'UpdatePreeditText':
        out(t='preText', text=a[0])
    elif name == 'UpdatePreeditCaret':
        out(t='preCaret', i=int(a[0]))
    elif name == 'UpdateSpotLocation':
        absolute(a[0], a[1], 0, 0)
    elif name == 'Enable':
        out(t='enable', on=bool(a[0]))
    elif name == 'UpdateProperty':
        im_property(a[0])
    if name in ('ShowLookupTable', 'UpdateLookupTable', 'UpdateLookupTableCursor', 'ShowAux', 'UpdateAux',
                'ShowPreedit', 'UpdatePreeditText', 'UpdatePreeditCaret'):
        track()


# ── imecaret events (Hyprland's event socket): commits and preedit changes ──
def spark_now():
    c = hypr('j/caret')
    if c and c.get('ok'):
        spot(c['x'], c['y'], c['w'], c['h'], t='spark')
    return False


# Enter reaches us first (key event), and the IM's commit — if Enter was confirming a
# composed phrase — a few ms later: hold Enter briefly and let a commit replace it.
_enter_timer = 0


def enter_now(rect):
    global _enter_timer
    _enter_timer = 0
    spot(*rect, t='enter')
    return False


def on_hypr_event(line):
    global _enter_timer
    name, _, data = line.partition('>>')
    if name not in ('imecommit', 'imepreedit', 'imeenter'):
        return
    try:
        x, y, w, h, n = (int(v) for v in data.split(','))
    except ValueError:
        return
    if name == 'imecommit':
        if _enter_timer:
            GLib.source_remove(_enter_timer)
            _enter_timer = 0
        spot(x, y, w, h, t='commit', n=n)      # the caret as the text lands: end of the phrase
    elif name == 'imeenter':
        if _enter_timer:
            GLib.source_remove(_enter_timer)
        _enter_timer = GLib.timeout_add(70, enter_now, (x, y, w, h))
    else:
        GLib.timeout_add(45, spark_now)        # after the app has moved its caret
    track()


_evbuf = b''


def on_event_socket(channel, cond, sock):
    global _evbuf
    if cond & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
        GLib.timeout_add(2000, connect_events)
        return False
    try:
        chunk = sock.recv(65536)
    except OSError:
        chunk = b''
    if not chunk:
        GLib.timeout_add(2000, connect_events)
        return False
    _evbuf += chunk
    *lines, _evbuf = _evbuf.split(b'\n')
    for ln in lines:
        on_hypr_event(ln.decode(errors='replace'))
    return True


def connect_events():
    sig = os.environ.get('HYPRLAND_INSTANCE_SIGNATURE')
    rt = os.environ.get('XDG_RUNTIME_DIR')
    if not sig or not rt:
        return False
    try:
        sock = socket.socket(socket.AF_UNIX)
        sock.connect(f'{rt}/hypr/{sig}/.socket2.sock')
    except OSError:
        GLib.timeout_add(2000, connect_events)
        return False
    GLib.io_add_watch(GLib.IOChannel.unix_new(sock.fileno()), GLib.PRIORITY_DEFAULT,
                      GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR, on_event_socket, sock)
    return False


def emit(iface, name, args=None):
    bus.emit_signal(None, PATH, iface, name, args)


def on_stdin(channel, cond):
    if cond & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
        loop.quit()
        return False
    line = sys.stdin.readline()
    if not line:
        loop.quit()
        return False
    cmd = line.split()
    if cmd and cmd[0] == 'select' and len(cmd) > 1:
        emit('org.kde.impanel', 'SelectCandidate', GLib.Variant('(i)', (int(cmd[1]),)))
    elif cmd and cmd[0] == 'prev':
        emit('org.kde.impanel', 'LookupTablePageUp')
    elif cmd and cmd[0] == 'next':
        emit('org.kde.impanel', 'LookupTablePageDown')
    return True


def on_name(conn, name):
    emit('org.kde.impanel', 'PanelCreated')
    emit('org.kde.impanel2', 'PanelCreated2')
    out(t='ready')


def on_name_lost(conn, name):
    out(t='lost')
    loop.quit()


if __name__ == '__main__':
    warnings.filterwarnings('ignore', category=DeprecationWarning)   # register_object: still the simplest form
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    node = Gio.DBusNodeInfo.new_for_xml(PANEL_XML)
    for iface in node.interfaces:
        bus.register_object(PATH, iface, on_method if iface.name == 'org.kde.impanel2' else None, None, None)
    bus.signal_subscribe(None, 'org.kde.kimpanel.inputmethod', None, '/kimpanel', None,
                         Gio.DBusSignalFlags.NONE, on_im_signal)
    # take the name over from a previous bridge (a config reload starts the new one
    # before the old one is gone), and hand it over the same way
    Gio.bus_own_name_on_connection(bus, 'org.kde.impanel',
                                   Gio.BusNameOwnerFlags.REPLACE | Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT,
                                   on_name, on_name_lost)
    connect_events()
    loop = GLib.MainLoop()
    GLib.io_add_watch(GLib.IOChannel.unix_new(sys.stdin.fileno()),
                      GLib.PRIORITY_DEFAULT, GLib.IOCondition.IN | GLib.IOCondition.HUP | GLib.IOCondition.ERR,
                      on_stdin)
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
