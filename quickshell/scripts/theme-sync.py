#!/usr/bin/env python3
"""Carry the shell's theme (config/themes/<name>.conf) over to the rest of the desktop:

  fcitx5    a classic-UI theme "quickshell" (~/.local/share/fcitx5/themes/quickshell):
            paper card, ink selector with the accent edge, diamond page buttons —
            the colours of the current theme; classicui is pointed at it and reloaded
  Hyprland  ~/.config/hypr/ui/qs_theme.lua (border gradient, inactive border, shadows),
            which ui/theme.lua reads at config load, and the same values applied live
            through `hyprctl eval`
  hyprlock  ~/.config/hypr/hyprlock.conf — the fallback lock (scripts/lock.sh runs it when
            the shell's lock.qml can't), laid out like lock.qml: the Void, the theme's light
  terminal  a 16-colour palette derived from the theme (term_palette) for
              kitty  ~/.config/kitty/qs-theme.conf (included by kitty.conf; SIGUSR1 reloads),
                     and qs-font.conf: the shell's `[font] mono` as kitty's face and `[font] cjk`
                     for Chinese (the system's pair), and `[terminal] fontSize` (kitty's own
                     size, apart from the shell's `[font] size`); written whether the colours
                     sync or not
              zsh    ~/.config/zsh/qs-theme.zsh (prompt, LS_COLORS, fzf, syntax highlighting;
                     open shells re-read it at their next prompt)
              bat    ~/.config/bat/themes/qs.tmTheme (+ `bat cache --build`), which delta uses
              delta  ~/.config/git/qs-delta.gitconfig (included by ~/.gitconfig)
              atuin  ~/.config/atuin/themes/qs.toml
              yazi   ~/.config/yazi/theme.toml
              btop   ~/.config/btop/themes/qs.theme (btop.conf's color_theme = "qs")
              lazygit ~/.config/lazygit/qs-theme.yml (LG_CONFIG_FILE, set in qs-theme.zsh)
  Firefox   every profile: chrome/userChrome.css + userContent.css copied from quickshell/firefox/,
            chrome/qs-theme.css (the colours and fonts they read), a block in user.js (userChrome
            on, pages dark or light like the theme); read at Firefox's start, so a change while
            it runs sends a notification. `[sync] firefox = false` takes it all back out
  fonts     ~/.config/fontconfig/conf.d/60-quickshell.conf: the Quickshell process's fallback
            chain from `[font] mono` / `cjk` (written whatever [sync] says; a running qs sees
            it after a restart)

    theme-sync.py [theme]        default: `[general] theme` from config/shell.conf

`[sync] fcitx5 = false` / `hyprland = false` / `terminal = false` in shell.conf hand each
back to its own look (fcitx5's `nier` theme; Hyprland's palette in ui/theme.lua; kitty.conf's
own colours, with the tools on the nier palette). Idempotent: nothing
is reloaded unless a generated file actually changed. Quickshell runs this whenever
the theme (its name or its file) changes.

The parser and fallbacks mirror settings/Config.qml and theme/Theme.qml.
"""
import math
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
CONF = os.path.join(os.path.dirname(HERE), 'config')
FCITX_THEMES = os.path.expanduser('~/.local/share/fcitx5/themes')
FCITX_UI_CONF = os.path.expanduser('~/.config/fcitx5/conf/classicui.conf')
HYPR_QS = os.path.expanduser('~/.config/hypr/ui/qs_theme.lua')
HYPRLOCK = os.path.expanduser('~/.config/hypr/hyprlock.conf')
KITTY_QS = os.path.expanduser('~/.config/kitty/qs-theme.conf')
KITTY_FONT = os.path.expanduser('~/.config/kitty/qs-font.conf')
ZSH_QS = os.path.expanduser('~/.config/zsh/qs-theme.zsh')
BAT_QS = os.path.expanduser('~/.config/bat/themes/qs.tmTheme')
DELTA_QS = os.path.expanduser('~/.config/git/qs-delta.gitconfig')
ATUIN_QS = os.path.expanduser('~/.config/atuin/themes/qs.toml')
YAZI_QS = os.path.expanduser('~/.config/yazi/theme.toml')
BTOP_QS = os.path.expanduser('~/.config/btop/themes/qs.theme')
LAZYGIT_QS = os.path.expanduser('~/.config/lazygit/qs-theme.yml')
FONTCONFIG_QS = os.path.expanduser('~/.config/fontconfig/conf.d/60-quickshell.conf')
HEX = re.compile(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')


def parse(text):
    out, section = {}, ''
    for line in (text or '').split('\n'):
        l = line.strip()
        if not l or l[0] in '#;':
            continue
        m = re.match(r'^\[([^\]]+)\]\s*([#;].*)?$', l)
        if m:
            section = m.group(1).strip()
            continue
        if '=' not in l:
            continue
        k, raw = l.split('=', 1)
        k, raw = k.strip(), raw.strip()
        if raw.startswith('"'):
            end = raw.find('"', 1)
            v = raw[1:end] if end > 0 else raw[1:]
        else:
            raw = re.sub(r'\s+[#;](\s.*)?$', '', raw)
            if re.fullmatch(r'(?i)true|yes|on', raw):
                v = True
            elif re.fullmatch(r'(?i)false|no|off', raw):
                v = False
            elif re.fullmatch(r'-?\d+(\.\d+)?', raw):
                v = float(raw)
            else:
                v = raw
        out[(section + '.' if section else '') + k] = v
    return out


def read(path):
    try:
        with open(path, encoding='utf-8') as f:
            return f.read()
    except OSError:
        return ''


def resolve(t):
    def c(k, d, keep_alpha=False):      # fcitx5 / SVG get plain #rrggbb
        v = t.get(k)
        v = v.lower() if isinstance(v, str) and HEX.match(v) else d
        return v if keep_alpha else '#' + v[-6:]
    r = {}
    r['paper'] = c('palette.paper', '#d6cfb5')
    r['ink'] = c('palette.ink', '#463f2e')
    r['inkStrong'] = c('palette.inkStrong', '#2e2a1f')
    r['inkSoft'] = c('palette.inkSoft', '#7a7358')
    r['accent'] = c('palette.accent', '#6e2a2a')
    r['light'] = c('palette.light', '#fff6cf')
    r['panel'] = c('dark.panel', '#221e17')
    r['warn'] = c('palette.warn', '#c8685c')
    r['good'] = c('palette.good', '#9ab58c')
    r['raised'] = c('dark.raised', '#2e2a1f')
    r['text'] = c('dark.text', r['paper'])
    r['muted'] = c('dark.muted', '#8f8873')
    r['active'] = c('dark.active', r['light'])
    r['onFill'] = c('dark.onFill', r['raised'])
    r['urgent'] = c('notify.critical', '#cd664d')
    r['calm'] = c('notify.low', '#a0c490')
    r['monitors'] = [m.strip().lower() for m in str(t.get('dark.monitors', '')).split(',') if HEX.match(m.strip())]
    r['mono'] = str(t.get('font.mono') or 'Operator Mono')
    r['cjk'] = str(t.get('font.cjk') or 'jf金萱那提2.0')
    # Hyprland: [hyprland] border = c1, c2[, c3] · borderAngle · inactive · shadow
    border = [s.strip().lower() for s in str(t.get('hyprland.border', '')).split(',') if HEX.match(s.strip())]
    r['border'] = border or [r['light'], r['accent']]
    ang = t.get('hyprland.borderAngle')
    r['angle'] = int(ang) if isinstance(ang, float) else 45
    r['inactive'] = c('hyprland.inactive', '#66' + r['panel'][-6:], True)
    r['shadow'] = c('hyprland.shadow', r['accent'])
    return r


def rgb(hexc):          # "#aarrggbb" / "#rrggbb" → "rrggbb"
    return hexc[-6:]


def hypr_rgba(hexc, alpha='ee'):
    h = hexc[1:]
    return 'rgba(%s%s)' % (h[-6:], h[:2] if len(h) == 8 else alpha)


def write_if_changed(path, text):
    if read(path) == text:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.replace(tmp, path)
    return True


# ── fcitx5 ──
def fcitx5_files(r):
    paper, ink, accent, light = r['paper'], r['ink'], r['accent'], r['light']
    files = {
        'panel.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">
  <defs><linearGradient id="rim" x1="0" x2="1" y1="0" y2="0">
    <stop offset="0" stop-color="{light}" stop-opacity="0"/><stop offset="0.35" stop-color="{light}" stop-opacity="0.9"/><stop offset="1" stop-color="{light}" stop-opacity="0"/>
  </linearGradient></defs>
  <rect x="3.5" y="3.5" width="41" height="41" fill="{paper}" stroke="{ink}" stroke-width="1"/>
  <rect x="7.5" y="7.5" width="33" height="33" fill="none" stroke="{ink}" stroke-width="1" stroke-opacity="0.28"/>
  <rect x="4" y="4" width="40" height="1" fill="url(#rim)"/>
  <g fill="{ink}"><path d="M3.5 0.5 L6.5 3.5 L3.5 6.5 L0.5 3.5 Z"/><path d="M44.5 0.5 L47.5 3.5 L44.5 6.5 L41.5 3.5 Z"/><path d="M3.5 41.5 L6.5 44.5 L3.5 47.5 L0.5 44.5 Z"/><path d="M44.5 41.5 L47.5 44.5 L44.5 47.5 L41.5 44.5 Z"/></g>
</svg>
''',
        'highlight.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <rect width="24" height="24" fill="{ink}"/><rect width="3" height="24" fill="{accent}"/>
</svg>
''',
        'prev.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14">
  <path d="M7 1.5 L12.5 7 L7 12.5 L1.5 7 Z" fill="none" stroke="{ink}"/><path d="M8.2 4.6 L5.8 7 L8.2 9.4" fill="none" stroke="{ink}" stroke-width="1.2"/>
</svg>
''',
        'next.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14">
  <path d="M7 1.5 L12.5 7 L7 12.5 L1.5 7 Z" fill="none" stroke="{ink}"/><path d="M5.8 4.6 L8.2 7 L5.8 9.4" fill="none" stroke="{ink}" stroke-width="1.2"/>
</svg>
''',
        'menu.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <rect x="0.5" y="0.5" width="15" height="15" fill="{paper}" stroke="{ink}"/>
</svg>
''',
        'radio.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12"><path d="M6 1.5 L10.5 6 L6 10.5 L1.5 6 Z" fill="{ink}"/></svg>
''',
        'arrow.svg': f'''<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 12 12"><path d="M4.5 2.5 L8 6 L4.5 9.5" fill="none" stroke="{ink}" stroke-width="1.3"/></svg>
''',
    }
    m = lambda l, rr, t, b: f'Left={l}\nRight={rr}\nTop={t}\nBottom={b}\n'
    files['theme.conf'] = f'''# Generated by ~/.config/quickshell/scripts/theme-sync.py from the shell's theme —
# edits here are overwritten; change config/themes/<theme>.conf instead.
[Metadata]
Name=Quickshell
Version=1
Author=quickshell
Description=Follows the Quickshell theme
ScaleWithDPI=True

[InputPanel]
NormalColor={ink}
HighlightCandidateColor={paper}
HighlightColor={paper}
HighlightBackgroundColor={ink}
EnableBlur=False
FullWidthHighlight=True
PageButtonAlignment=Last Candidate

[InputPanel/Background]
Image=panel.svg

[InputPanel/Background/Margin]
{m(10, 10, 10, 10)}
[InputPanel/ContentMargin]
{m(11, 11, 10, 10)}
[InputPanel/TextMargin]
{m(9, 9, 7, 7)}
[InputPanel/Highlight]
Image=highlight.svg

[InputPanel/Highlight/Margin]
{m(8, 8, 5, 5)}
[InputPanel/Highlight/HighlightClickMargin]
{m(0, 0, 0, 0)}
[InputPanel/PrevPage]
Image=prev.svg

[InputPanel/PrevPage/ClickMargin]
{m(4, 4, 4, 4)}
[InputPanel/NextPage]
Image=next.svg

[InputPanel/NextPage/ClickMargin]
{m(4, 4, 4, 4)}
[InputPanel/ShadowMargin]
{m(0, 0, 0, 0)}
[Menu]
NormalColor={ink}
HighlightCandidateColor={paper}
Spacing=0

[Menu/Background]
Image=menu.svg

[Menu/Background/Margin]
{m(2, 2, 2, 2)}
[Menu/ContentMargin]
{m(3, 3, 3, 3)}
[Menu/Highlight]
Image=highlight.svg

[Menu/Highlight/Margin]
{m(4, 1, 1, 1)}
[Menu/Separator]
Color={ink}40

[Menu/CheckBox]
Image=radio.svg

[Menu/SubMenu]
Image=arrow.svg

[Menu/TextMargin]
{m(8, 8, 5, 5)}'''
    return files


def set_fcitx_theme(name):
    text = read(FCITX_UI_CONF)
    if not text:
        return False
    new = re.sub(r'(?m)^Theme=.*$', 'Theme=' + name, text)
    new = re.sub(r'(?m)^DarkTheme=.*$', 'DarkTheme=' + name, new)
    return write_if_changed(FCITX_UI_CONF, new)


def fcitx5_reload():
    subprocess.run(['busctl', '--user', 'call', 'org.fcitx.Fcitx5', '/controller', 'org.fcitx.Fcitx.Controller1',
                    'ReloadAddonConfig', 's', 'classicui'], capture_output=True, timeout=5)


def sync_fcitx5(r, on):
    changed = False
    if on:
        for fn, text in fcitx5_files(r).items():
            changed |= write_if_changed(os.path.join(FCITX_THEMES, 'quickshell', fn), text)
        changed |= set_fcitx_theme('quickshell')
    else:
        changed |= set_fcitx_theme('nier')
    if changed:
        fcitx5_reload()
    return changed


# ── Hyprland ──
def sync_hyprland(r, on, name, window_fx):
    """Colours (when `on`) and the window-effects flag: with the shell's close melt on,
    ui/animations.lua turns Hyprland's own close slide off (it would slide the closing
    window out from under the melt). A flag change needs a config reload."""
    old = read(HYPR_QS)
    fx_changed = ('windowFx = true' in old) != window_fx
    if on:
        active = [hypr_rgba(c) for c in r['border']]
        inactive = hypr_rgba(r['inactive'], '66')
        shadow = '0x2a' + rgb(r['shadow'])
        lua = ('-- Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) — read by\n'
               '-- ui/theme.lua; set `[sync] hyprland = false` in config/shell.conf to go back to its own palette.\n'
               'return {\n    enabled = true,\n    active = { %s },\n    angle = %d,\n    inactive = "%s",\n'
               '    shadow = %s,\n    shadow_idle = 0x08000000,\n    windowFx = %s,\n}\n') % (
            name, ', '.join('"%s"' % a for a in active), r['angle'], inactive, shadow, 'true' if window_fx else 'false')
        if not write_if_changed(HYPR_QS, lua):
            return False
        if fx_changed:
            subprocess.run(['hyprctl', 'reload', 'config-only'], capture_output=True, timeout=10)
            return True
        live = ('hl.config({ general = { col = { active_border = { colors = { %s }, angle = %d }, inactive_border = "%s" } },'
                ' decoration = { shadow = { color = %s, color_inactive = 0x08000000 } } })') % (
            ', '.join('"%s"' % a for a in active), r['angle'], inactive, shadow)
        subprocess.run(['hyprctl', 'eval', live], capture_output=True, timeout=5)
        return True
    # off: ui/theme.lua falls back to its own palette on the next config load
    off = '-- theme sync off (config/shell.conf [sync] hyprland = false)\nreturn { enabled = false, windowFx = %s }\n' % (
        'true' if window_fx else 'false')
    if not write_if_changed(HYPR_QS, off):
        return False
    subprocess.run(['hyprctl', 'reload', 'config-only'], capture_output=True, timeout=10)
    return True


def sync_hyprlock(r, name, shell):
    """The fallback lock, in the same Void as lock.qml (always written: it is what you see
    if the shell's lock fails, whatever the sync options). The Void's ink is its own
    ([void] in shell.conf: 月白, a muted red), not the theme's."""
    def hexv(k, d):
        v = shell.get(k)
        return v.lower()[-6:] if isinstance(v, str) and HEX.match(v) else d
    L, W = hexv('void.light', 'ffffff'), hexv('void.warn', 'b8403c')
    F = str(shell.get('font.void') or r['mono'])
    conf = f"""# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: {name}).
# The fallback lock: scripts/lock.sh runs hyprlock when the shell's lock (lock.qml)
# doesn't come up or dies while locked. Laid out like lock.qml.
general {{
    hide_cursor = true
    ignore_empty_input = true
}}
background {{
    monitor =
    color = rgb(000000)
}}
label {{
    monitor =
    text = SYSTEM LOCKED  ·  FALLBACK
    color = rgba({L}8c)
    font_family = {F}
    font_size = 10
    position = 72, -48
    halign = left
    valign = top
}}
label {{
    monitor =
    text = $TIME
    color = rgb({L})
    font_family = {F}
    font_size = 96
    position = 0, 90
    halign = center
    valign = center
}}
label {{
    monitor =
    text = cmd[update:60000] date +'%A  ·  %d %b %Y' | tr '[:lower:]' '[:upper:]'
    color = rgba({L}8c)
    font_family = {F}
    font_size = 12
    position = 0, 10
    halign = center
    valign = center
}}
label {{
    monitor =
    text = AUTHORIZATION REQUIRED
    color = rgb({L})
    font_family = {F}
    font_size = 11
    position = 0, -50
    halign = center
    valign = center
}}
input-field {{
    monitor =
    size = 360, 32
    outline_thickness = 1
    rounding = 0
    dots_size = 0.22
    dots_spacing = 0.7
    dots_center = true
    dots_rounding = 0
    outer_color = rgba({L}66)
    inner_color = rgb(000000)
    font_color = rgb({L})
    font_family = {F}
    check_color = rgb({L})
    fail_color = rgb({W})
    fail_text = FAILED
    placeholder_text = TYPE TO UNLOCK
    fade_on_empty = false
    position = 0, -100
    halign = center
    valign = center
}}
"""
    return write_if_changed(HYPRLOCK, conf)



# ── the terminal ──
# One palette for kitty and the tools, derived from the theme in OKLCH: the HUD's panel and
# text as background and foreground, and for each ANSI hue the theme's own colour nearest
# to it (its warn for red, good for green, light for yellow…) — or the plain hue nudged
# toward the accent — set to one lightness for the normal colours and one for the bright,
# picked for the background, so every theme reads the same in a terminal.

def _lin(v):
    v /= 255
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def _delin(x):
    x = min(1.0, max(0.0, x))
    return 255 * (12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055)


def oklch(hexc):
    r, g, b = (_lin(int(hexc[i:i + 2], 16)) for i in (1, 3, 5))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    A = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    B = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(A, B), math.degrees(math.atan2(B, A)) % 360


def from_oklch(L, C, H):
    while True:     # shed chroma until it fits in sRGB
        A, B = C * math.cos(math.radians(H)), C * math.sin(math.radians(H))
        l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3
        m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3
        s = (L - 0.0894841775 * A - 1.2914855480 * B) ** 3
        out = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
               -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        if all(-0.001 <= v <= 1.001 for v in out) or C < 0.005:
            return '#%02x%02x%02x' % tuple(round(_delin(v)) for v in out)
        C *= 0.94


def mix(a, b, t):       # t of b over a
    pa = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
    pb = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
    return '#%02x%02x%02x' % tuple(round(x + (y - x) * t) for x, y in zip(pa, pb))


def _hue_gap(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


def term_palette(r):
    bg, fg = r['panel'], r['text']
    dark = oklch(bg)[0] < 0.5
    Ln, Lb = (0.74, 0.84) if dark else (0.50, 0.42)
    acc_h = oklch(r['accent'])[2]
    cands = [oklch(c) for c in [r['warn'], r['urgent'], r['good'], r['calm'], r['light'], r['accent'],
                                r['active']] + r['monitors']]

    def role(h0):
        near = [(_hue_gap(H, h0), H, C) for (L, C, H) in cands if C > 0.045 and _hue_gap(H, h0) <= 32]
        if near:
            _, H, C = min(near)
        else:
            gap = ((acc_h - h0 + 180) % 360) - 180
            H, C = (h0 + 0.15 * gap) % 360, 0.12
        C = min(max(C, 0.085), 0.16)
        return from_oklch(Ln, C, H), from_oklch(Lb, min(C + 0.02, 0.18), H)

    p = {'bg': bg, 'fg': fg, 'raised': r['raised'], 'muted': r['muted'], 'light': r['light'],
         'accent': r['accent'], 'dark': dark}
    for name, h0 in (('red', 27), ('green', 145), ('yellow', 88), ('blue', 255), ('magenta', 335), ('cyan', 200)):
        p[name], p['br_' + name] = role(h0)
    if dark:
        p['black'], p['br_black'] = r['raised'], r['muted']
        p['white'], p['br_white'] = mix(fg, bg, 0.18), fg
    else:
        p['black'], p['br_black'] = fg, r['muted']
        p['white'], p['br_white'] = mix(fg, bg, 0.35), fg
    p['sel'] = mix(bg, r['light'] if dark else r['accent'], 0.28)
    p['suggest'] = mix(r['muted'], bg, 0.35)
    p['line'] = mix(r['muted'], bg, 0.5)        # the prompt's frame: a hairline, quieter than muted
    return p


ANSI = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']


def kitty_conf(p, name):
    lines = ['# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) — included by' % name,
             '# kitty.conf after its own colours; `[sync] terminal = false` empties it.',
             'foreground %s' % p['fg'], 'background %s' % p['bg'],
             'selection_foreground %s' % p['fg'], 'selection_background %s' % p['sel'],
             'cursor %s' % p['light'], 'cursor_text_color %s' % p['bg'], 'cursor_trail_color %s' % p['light'],
             'url_color %s' % p['yellow'],
             'scrollbar_handle_color %s' % p['light'], 'scrollbar_track_color %s' % p['muted']]
    for i, n in enumerate(ANSI):
        lines.append('color%d %s' % (i, p[n]))
        lines.append('color%d %s' % (i + 8, p['br_' + n]))
    return '\n'.join(lines) + '\n'


def sgr(hexc, bold=False):
    r_, g, b = (int(hexc[i:i + 2], 16) for i in (1, 3, 5))
    return ('1;' if bold else '') + '38;2;%d;%d;%d' % (r_, g, b)


def ls_colors(p):
    out = ['di=' + sgr(p['br_blue'], True), 'ln=' + sgr(p['cyan']), 'or=' + sgr(p['red']), 'mi=' + sgr(p['red']),
           'ex=' + sgr(p['br_green'], True), 'so=' + sgr(p['magenta']), 'pi=' + sgr(p['yellow']),
           'bd=' + sgr(p['yellow'], True), 'cd=' + sgr(p['yellow'], True), 'su=' + sgr(p['red'], True),
           'sg=' + sgr(p['red'], True), 'tw=' + sgr(p['blue'], True), 'ow=' + sgr(p['blue'], True)]
    groups = (('red', 'tar gz tgz zip zst xz 7z rar bz2 lz4 deb rpm iso img'),
              ('magenta', 'png jpg jpeg gif webp svg ico bmp avif heic tiff psd kra xcf'),
              ('br_magenta', 'mp3 flac ogg opus wav m4a mp4 mkv webm mov avi'),
              ('yellow', 'pdf epub md txt rst tex docx odt pptx xlsx csv'),
              ('white', 'conf toml yaml yml json ini cfg lock'),
              ('br_black', 'bak old orig tmp swp log'))
    for role, exts in groups:
        out += ['*.%s=%s' % (e, sgr(p[role])) for e in exts.split()]
    return ':'.join(out)


def _q(s):              # a single-quoted shell word
    return "'" + s.replace("'", "'\\''") + "'"


def zsh_conf(p, name):
    keys = ['bg', 'fg', 'raised', 'muted', 'light', 'accent', 'sel', 'suggest', 'line'] + ANSI[1:7] + ['br_' + a for a in ANSI[1:7]]
    fzf = ('--color=fg:%s,fg+:%s,bg:-1,bg+:%s,hl:%s,hl+:%s,info:%s,prompt:%s,pointer:%s,marker:%s,'
           'spinner:%s,header:%s,border:%s,label:%s,query:%s,gutter:-1,separator:%s,scrollbar:%s'
           % (p['white'], p['fg'], p['raised'], p['yellow'], p['br_yellow'], p['muted'], p['light'], p['light'],
              p['light'], p['light'], p['muted'], p['raised'], p['light'], p['fg'], p['raised'], p['muted']))
    fg = lambda k, extra='': 'fg=' + p[k] + extra
    fsh = {'default': 'none', 'unknown-token': fg('red'), 'reserved-word': fg('magenta'),
           'alias': fg('br_green'), 'suffix-alias': fg('br_green'), 'global-alias': fg('cyan'),
           'builtin': fg('br_green'), 'function': fg('br_green'), 'command': fg('br_green'),
           'precommand': fg('green', ',italic'), 'hashed-command': fg('br_green'),
           'subcommand': fg('magenta'), 'commandseparator': fg('muted'),
           'single-hyphen-option': fg('cyan'), 'double-hyphen-option': fg('cyan'),
           'single-quoted-argument': fg('yellow'), 'double-quoted-argument': fg('yellow'),
           'dollar-quoted-argument': fg('yellow'), 'back-quoted-argument': fg('magenta'),
           'back-or-dollar-double-quoted-argument': fg('cyan'), 'variable': fg('cyan'),
           'assign': fg('cyan'), 'redirection': fg('magenta'), 'comment': fg('muted', ',italic'),
           'path': fg('fg', ',underline'), 'path-to-dir': fg('fg', ',underline'),
           'path_pathseparator': fg('muted', ',underline'), 'globbing': fg('br_magenta'),
           'globbing-ext': fg('br_magenta'), 'history-expansion': fg('br_blue'),
           'mathvar': fg('cyan'), 'mathnum': fg('yellow'), 'matherr': fg('red'),
           'paired-bracket': 'bg=' + p['raised'], 'bracket-level-1': fg('light'),
           'bracket-level-2': fg('br_magenta'), 'bracket-level-3': fg('br_cyan'),
           'here-string-text': fg('yellow'), 'here-string-var': fg('cyan'),
           'correct-subtle': fg('muted'), 'incorrect-subtle': fg('red'),
           'subtle-separator': fg('muted'), 'secondary': fg('muted')}
    grep = 'ms=%s:mc=%s:sl=:cx=:fn=%s:ln=%s:bn=%s:se=%s' % (
        sgr(p['br_yellow'], True), sgr(p['br_red'], True), sgr(p['magenta']), sgr(p['green']),
        sgr(p['green']), sgr(p['muted']))
    out = ['# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) — read by' % name,
           '# ~/.config/zsh/prompt.zsh and tools.zsh; open shells re-read it at their next prompt.',
           'typeset -gA QS',
           'QS=(' + ' '.join('%s %s' % (k, _q(p[k])) for k in keys) + ')',
           'export LS_COLORS=' + _q(ls_colors(p)),
           'export GREP_COLORS=' + _q(grep),
           'export BAT_THEME=qs',
           'export LG_CONFIG_FILE=' + _q(os.path.expanduser('~/.config/lazygit/config.yml') + ',' + LAZYGIT_QS),
           'QS_FZF_COLORS=' + _q(fzf),
           'ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE=' + _q('fg=' + p['suggest']),
           'typeset -gA QS_FSH',
           'QS_FSH=(' + ' '.join('%s %s' % (k, _q(v)) for k, v in fsh.items()) + ')']
    return '\n'.join(out) + '\n'


def bat_theme(p, name):
    def entry(scope, fg=None, style=None):
        d = ''.join('<key>%s</key><string>%s</string>' % kv for kv in
                    (('foreground', fg), ('fontStyle', style)) if kv[1])
        return '\t\t<dict><key>scope</key><string>%s</string><key>settings</key><dict>%s</dict></dict>' % (scope, d)
    rules = [
        entry('comment, punctuation.definition.comment', p['muted'], 'italic'),
        entry('string, punctuation.definition.string', p['green']),
        entry('string.regexp, constant.character.escape', p['cyan']),
        entry('constant.numeric, constant.language, constant.character, constant.other, variable.other.constant', p['yellow']),
        entry('keyword, storage, storage.type, storage.modifier, keyword.operator.word', p['magenta']),
        entry('keyword.operator, punctuation, meta.brace', p['white']),
        entry('entity.name.function, support.function, meta.function-call variable.function', p['br_blue']),
        entry('entity.name.type, entity.name.class, support.type, support.class, entity.other.inherited-class', p['cyan']),
        entry('variable.parameter', p['fg'], 'italic'),
        entry('variable.language, support.variable', p['red']),
        entry('entity.name.tag', p['magenta']),
        entry('entity.other.attribute-name', p['yellow']),
        entry('markup.heading, entity.name.section', p['light'], 'bold'),
        entry('markup.bold', None, 'bold'),
        entry('markup.italic', None, 'italic'),
        entry('markup.underline.link, string.other.link', p['br_blue'], 'underline'),
        entry('markup.quote', p['muted'], 'italic'),
        entry('markup.raw, markup.inline.raw', p['green']),
        entry('markup.inserted', p['green']),
        entry('markup.deleted', p['red']),
        entry('markup.changed', p['yellow']),
        entry('meta.diff.header, meta.diff.range, meta.diff.index', p['br_blue']),
        entry('invalid', p['br_red'], 'underline'),
    ]
    head = '\t\t<dict><key>settings</key><dict>' + ''.join(
        '<key>%s</key><string>%s</string>' % kv for kv in (
            ('background', p['bg']), ('foreground', p['fg']), ('caret', p['light']),
            ('lineHighlight', p['raised']), ('selection', p['sel']), ('gutter', p['bg']),
            ('gutterForeground', p['muted']), ('invisibles', p['raised']),
            ('findHighlight', p['yellow']))) + '</dict></dict>'
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!-- Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) -->\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0"><dict><key>name</key><string>qs</string><key>settings</key><array>\n' % name
            + '\n'.join([head] + rules) + '\n</array></dict></plist>\n')


def delta_conf(p, name):
    rows = [
        ('syntax-theme', 'qs'), ('navigate', 'true'), ('line-numbers', 'true'), ('hyperlinks', 'true'),
        ('minus-style', 'syntax "%s"' % mix(p['bg'], p['red'], 0.20)),
        ('minus-emph-style', 'syntax "%s"' % mix(p['bg'], p['red'], 0.38)),
        ('plus-style', 'syntax "%s"' % mix(p['bg'], p['green'], 0.18)),
        ('plus-emph-style', 'syntax "%s"' % mix(p['bg'], p['green'], 0.34)),
        ('line-numbers-minus-style', '"%s"' % p['red']),
        ('line-numbers-plus-style', '"%s"' % p['green']),
        ('line-numbers-zero-style', '"%s"' % p['muted']),
        ('line-numbers-left-style', '"%s"' % p['raised']),
        ('line-numbers-right-style', '"%s"' % p['raised']),
        ('file-style', 'bold "%s"' % p['light']),
        ('file-decoration-style', '"%s" ul' % p['accent']),
        ('hunk-header-style', 'file line-number syntax'),
        ('hunk-header-decoration-style', '"%s" box' % p['muted']),
        ('hunk-header-file-style', '"%s"' % p['light']),
        ('hunk-header-line-number-style', '"%s"' % p['yellow']),
        ('commit-decoration-style', '"%s" box' % p['accent']),
    ]
    return ('# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) — included by\n'
            '# ~/.gitconfig; delta pages git\'s diffs when installed (GIT_PAGER, ~/.config/zsh/tools.zsh)\n'
            '[delta]\n' % name + ''.join('    %s = %s\n' % kv for kv in rows))


def atuin_theme(p, name):
    rows = [('AlertInfo', p['green']), ('AlertWarn', p['yellow']), ('AlertError', p['red']),
            ('Annotation', p['muted']), ('Base', p['fg']), ('Guidance', p['muted']),
            ('Important', p['light']), ('Title', p['light']), ('Muted', p['muted'])]
    return ('# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s)\n'
            '[theme]\nname = "qs"\n\n[colors]\n' % name + ''.join('%s = "%s"\n' % kv for kv in rows))


def yazi_theme(p, name):
    """yazi in the shell's terms: the mode and tab chips are blocks in the light colour with
    the background's text (the HUD's picked item), borders hairlines, the hovered row the
    selection colour, code previews through bat's qs theme"""
    s = lambda **kw: '{ ' + ', '.join('%s = %s' % (k, ('"%s"' % v) if isinstance(v, str) else str(v).lower())
                                     for k, v in kw.items()) + ' }'
    chip = lambda c: (s(fg=p['bg'], bg=c, bold=True), s(fg=c, bg=p['raised']))
    nm, na = chip(p['light'])
    sm, sa = chip(p['red'])
    um, ua = chip(p['br_red'])
    rows = [
        '[mgr]',
        'cwd = ' + s(fg=p['light']),
        'find_keyword  = ' + s(fg=p['br_yellow'], bold=True, underline=True),
        'find_position = ' + s(fg=p['magenta'], bg='reset', bold=True),
        'marker_copied   = ' + s(fg=p['green'], bg=p['green']),
        'marker_cut      = ' + s(fg=p['red'], bg=p['red']),
        'marker_marked   = ' + s(fg=p['cyan'], bg=p['cyan']),
        'marker_selected = ' + s(fg=p['light'], bg=p['light']),
        'count_copied   = ' + s(fg=p['bg'], bg=p['green']),
        'count_cut      = ' + s(fg=p['bg'], bg=p['red']),
        'count_selected = ' + s(fg=p['bg'], bg=p['light']),
        'border_symbol = "│"',
        'border_style  = ' + s(fg=p['line']),
        'syntect_theme = "%s"' % BAT_QS,
        '',
        '[tabs]',
        'active   = ' + nm,
        'inactive = ' + s(fg=p['muted'], bg=p['raised']),
        '',
        '[mode]',
        'normal_main = ' + nm, 'normal_alt  = ' + na,
        'select_main = ' + sm, 'select_alt  = ' + sa,
        'unset_main  = ' + um, 'unset_alt   = ' + ua,
        '',
        '[indicator]',
        'parent  = ' + s(fg=p['fg'], bg=p['raised']),
        'current = ' + s(fg=p['fg'], bg=p['sel'], bold=True),
        'preview = ' + s(underline=True),
        '',
        '[status]',
        'perm_sep   = ' + s(fg=p['line']),
        'perm_type  = ' + s(fg=p['light']),
        'perm_read  = ' + s(fg=p['yellow']),
        'perm_write = ' + s(fg=p['red']),
        'perm_exec  = ' + s(fg=p['green']),
        'progress_label  = ' + s(fg=p['fg'], bold=True),
        'progress_normal = ' + s(fg=p['light'], bg=p['raised']),
        'progress_error  = ' + s(fg=p['br_red'], bg=p['raised']),
        '',
        '[which]',
        'border = ' + s(fg=p['line']),
        'cand   = ' + s(fg=p['light']),
        'rest   = ' + s(fg=p['muted']),
        'desc   = ' + s(fg=p['fg']),
        'separator_style = ' + s(fg=p['line']),
    ]
    for sec in ('confirm', 'spot', 'pick', 'input', 'cmp', 'tasks', 'help'):
        rows += ['', '[%s]' % sec, 'border = ' + s(fg=p['line'])]
        if sec in ('confirm', 'spot', 'input', 'tasks'):
            rows.append('title  = ' + s(fg=p['light'], bold=True))
        if sec in ('pick', 'cmp'):
            rows.append('active = ' + s(fg=p['bg'], bg=p['light'], bold=True))
        if sec in ('tasks', 'help'):
            rows.append('hovered = ' + s(fg=p['bg'], bg=p['light'], bold=True))
        if sec == 'confirm':
            rows.append('btn_yes = ' + s(fg=p['bg'], bg=p['light'], bold=True))
        if sec == 'spot':
            rows += ['tbl_col  = ' + s(fg=p['muted']), 'tbl_cell = ' + s(fg=p['bg'], bg=p['light'])]
        if sec == 'help':
            rows.append('chord   = ' + s(fg=p['light']))
    rows += ['', '[notify]',
             'title_info  = ' + s(fg=p['light']),
             'title_warn  = ' + s(fg=p['yellow']),
             'title_error = ' + s(fg=p['red']),
             '', '[filetype]', 'rules = [']
    # the same families as LS_COLORS (ls_colors), so yazi and ls agree
    rules = [('mime = "**/image/*"', p['magenta']),
             ('mime = "**/{audio,video}/*"', p['br_magenta']),
             ('mime = "**/application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}"', p['red']),
             ('mime = "**/application/{pdf,doc,rtf,epub*}"', p['yellow']),
             ('mime = "vfs/{absent,stale}"', p['muted'])]
    rows += ['\t{ %s, fg = "%s" },' % rule for rule in rules]
    rows += ['\t{ url = "*", is = "orphan", fg = "%s", bg = "%s" },' % (p['red'], p['raised']),
             '\t{ url = "*", is = "exec", fg = "%s" },' % p['br_green'],
             '\t{ url = "*", is = "link", fg = "%s" },' % p['cyan'],
             '\t{ url = "*", is = "dummy", fg = "%s", bg = "%s" },' % (p['red'], p['raised']),
             '\t{ url = "*/", is = "dummy", fg = "%s", bg = "%s" },' % (p['red'], p['raised']),
             '\t{ url = "*/", fg = "%s", bold = true },' % p['br_blue'],
             ']']
    return ('# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) — never edit by hand;\n'
            '# yazi reads it at start (open yazis keep the old colours).\n\n' % name + '\n'.join(rows) + '\n')


def btop_theme(p, name):
    """btop: boxes in hairlines, the light colour for titles and the picked row, graphs
    ramping from the quiet colour to the warning one"""
    ramp = lambda a, b: (a, mix(a, b, 0.5), b)
    keys = {'main_bg': p['bg'], 'main_fg': p['fg'], 'title': p['light'], 'hi_fg': p['light'],
            'selected_bg': p['sel'], 'selected_fg': p['fg'], 'inactive_fg': p['muted'],
            'graph_text': p['white'], 'meter_bg': p['raised'], 'proc_misc': p['light'],
            'cpu_box': p['line'], 'mem_box': p['line'], 'net_box': p['line'], 'proc_box': p['line'],
            'div_line': p['line']}
    for k, (a, b) in (('temp', (p['green'], p['br_red'])), ('cpu', (p['muted'], p['light'])),
                      ('free', (p['raised'], p['green'])), ('cached', (p['raised'], p['cyan'])),
                      ('available', (p['raised'], p['yellow'])), ('used', (p['muted'], p['br_red'])),
                      ('download', (p['muted'], p['cyan'])), ('upload', (p['muted'], p['magenta'])),
                      ('process', (p['light'], p['muted']))):
        for part, c in zip(('start', 'mid', 'end'), ramp(a, b)):
            keys['%s_%s' % (k, part)] = c
    return ('# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s)\n' % name
            + ''.join('theme[%s]="%s"\n' % kv for kv in keys.items()))


def lazygit_theme(p, name):
    """lazygit (LG_CONFIG_FILE adds this after config.yml): the focused panel in the light
    colour, the rest hairlines, the picked line the selection colour"""
    c = lambda *v: '[' + ', '.join('"%s"' % x for x in v) + ']'
    rows = [('activeBorderColor', c(p['light'], 'bold')), ('inactiveBorderColor', c(p['line'])),
            ('searchingActiveBorderColor', c(p['yellow'], 'bold')), ('optionsTextColor', c(p['muted'])),
            ('selectedLineBgColor', c(p['sel'])), ('inactiveViewSelectedLineBgColor', c(p['raised'])),
            ('cherryPickedCommitFgColor', c(p['bg'])), ('cherryPickedCommitBgColor', c(p['cyan'])),
            ('markedBaseCommitFgColor', c(p['bg'])), ('markedBaseCommitBgColor', c(p['yellow'])),
            ('unstagedChangesColor', c(p['red'])), ('defaultFgColor', c(p['fg']))]
    return ('# Generated by ~/.config/quickshell/scripts/theme-sync.py (theme: %s) — read after\n'
            '# config.yml (LG_CONFIG_FILE in ~/.config/zsh/qs-theme.zsh)\n'
            'gui:\n  theme:\n' % name + ''.join('    %s: %s\n' % kv for kv in rows))


# kitty's CJK: the ideographs, their punctuation, full-width forms and bopomofo
KITTY_CJK = ('U+2E80-U+2FDF,U+3000-U+303F,U+3100-U+312F,U+31A0-U+31BF,U+3400-U+4DBF,'
             'U+4E00-U+9FFF,U+F900-U+FAFF,U+FE30-U+FE4F,U+FF00-U+FFEF')


def font_pair(shell, r):
    """shell.conf `[font] mono` / `cjk`, else the theme's, else the defaults (as Theme.qml)"""
    return (str(shell.get('font.mono') or r['mono']).replace('"', ''),
            str(shell.get('font.cjk') or r['cjk']).replace('"', ''))


FONTCONFIG_TEMPLATE = """<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Generated by ~/.config/quickshell/scripts/theme-sync.py from shell.conf [font] mono / cjk.
     The shell's type, for the Quickshell process only (prgname is the real executable,
     "quickshell", also when started as qs), whose fallback chain becomes
       the face asked for → %(mono)s → %(cjk)s → the system's
     · text with no family set is the mono face; so are the glyphs a face lacks (fontconfig
       tags any sans with a generic sans-serif, which is what the first rule tests)
     · Chinese lands on the CJK face (Qt doesn't pair one on its own: Noto Sans CJK otherwise)
     Other programs are untouched; a running qs reads it at its next start.
     quickshell/CLAUDE.md "Design language" · Type. -->
<fontconfig>
  <match target="pattern">
    <test name="prgname" compare="eq"><string>quickshell</string></test>
    <test name="family" qual="any" compare="eq"><string>sans-serif</string></test>
    <edit name="family" mode="prepend_first" binding="strong"><string>%(mono)s</string></edit>
  </match>
  <match target="pattern">
    <test name="prgname" compare="eq"><string>quickshell</string></test>
    <test name="family" qual="first" compare="not_eq"><string>-</string></test>
    <edit name="family" mode="append" binding="strong"><string>%(cjk)s</string></edit>
  </match>
</fontconfig>
"""


def fontconfig_conf(shell, r):
    from xml.sax.saxutils import escape
    mono, cjk = (escape(f) for f in font_pair(shell, r))
    return FONTCONFIG_TEMPLATE % {'mono': mono, 'cjk': cjk}


def kitty_font(shell, r=None):
    """the system's font pair (shell.conf `[font] mono` / `cjk`, else the theme's, else the
    defaults — as Theme.qml reads them) and kitty's own size"""
    mono, cjk = font_pair(shell, r or resolve({}))
    lines =['# Generated by ~/.config/quickshell/scripts/theme-sync.py from shell.conf — included by',
             '# kitty.conf. The face and the Chinese are the system\'s ([font] mono / cjk); the',
             '# size is kitty\'s own ([terminal] fontSize, the settings panel\'s kitty 字級).',
             'font_family      family="%s"' % mono,
             'bold_font        auto',
             'italic_font      auto',
             'bold_italic_font auto',
             'symbol_map %s %s' % (KITTY_CJK, cjk)]
    v = shell.get('terminal.fontSize')
    if isinstance(v, float) and 6 <= v <= 48:
        lines.append('font_size %g' % v)
    return '\n'.join(lines) + '\n'


# ── Firefox ──
FIREFOX_SRC = os.path.join(os.path.dirname(HERE), 'firefox')
FIREFOX_ROOTS = [os.path.expanduser('~/.mozilla/firefox'), os.path.expanduser('~/.config/mozilla/firefox')]
USERJS_BEGIN = '// ── quickshell theme-sync (scripts/theme-sync.py) ──'
USERJS_END = '// ── end quickshell ──'


def firefox_profiles():
    out = []
    for root in FIREFOX_ROOTS:
        for line in read(os.path.join(root, 'profiles.ini')).splitlines():
            if line.startswith('Path='):
                p = line[5:].strip()
                p = p if os.path.isabs(p) else os.path.join(root, p)
                if os.path.isfile(os.path.join(p, 'prefs.js')):
                    out.append(p)
    return out


def firefox_css(r, shell):
    """qs-theme.css: the colours and the font pair, as variables for userChrome / userContent"""
    dark = oklch(r['panel'])[0] < 0.5
    fill = r['active']
    mono, cjk = font_pair(shell, r)
    dia = ("url(\"data:image/svg+xml,%%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 10 10'%%3E"
           "%%3Cpath d='M5 0 10 5 5 10 0 5z' fill='%%23%s'/%%3E%%3C/svg%%3E\")" % r['ink'][1:])
    v = {'panel': r['panel'], 'raised': r['raised'], 'text': r['text'], 'muted': r['muted'],
         'line': mix(r['muted'], r['panel'], 0.5), 'light': fill, 'accent': r['accent'],
         'on-light': r['onFill'], 'paper': r['paper'], 'ink': r['ink'], 'ink-strong': r['inkStrong'],
         'ink-soft': r['inkSoft'], 'warn': r['warn'], 'good': r['good'],
         'sel': mix(r['panel'], r['light'] if dark else r['accent'], 0.28),
         'grid': 'color-mix(in srgb, %s 9%%, transparent)' % r['ink'],
         'scheme': 'dark' if dark else 'light',
         'on-light-scheme': 'dark' if oklch(fill)[0] < 0.5 else 'light',
         'paper-scheme': 'dark' if oklch(r['paper'])[0] < 0.5 else 'light',
         'mono': '"%s"' % mono, 'cjk': '"%s"' % cjk, 'dia': dia}
    return ('/* Generated by ~/.config/quickshell/scripts/theme-sync.py — never edit by hand.\n'
            '   Read by userChrome.css / userContent.css (quickshell/firefox/) at Firefox\'s start. */\n'
            ':root {\n' + ''.join('  --qs-%s: %s;\n' % kv for kv in v.items()) + '}\n')


def firefox_userjs(text, r, on):
    """user.js with our block: userChrome on, web pages dark or light like the theme"""
    keep = re.sub(r'\n?%s.*?%s\n?' % (re.escape(USERJS_BEGIN), re.escape(USERJS_END)), '\n', text, flags=re.S).strip('\n')
    if not on:
        return keep + '\n' if keep else ''
    dark = oklch(r['panel'])[0] < 0.5
    block = '\n'.join([USERJS_BEGIN,
                       'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);',
                       'user_pref("layout.css.prefers-color-scheme.content-override", %d);' % (0 if dark else 1),
                       'user_pref("browser.theme.content-theme", %d);' % (0 if dark else 1),
                       'user_pref("browser.theme.toolbar-theme", %d);' % (0 if dark else 1),
                       'user_pref("browser.uidensity", 0);',
                       USERJS_END])
    return (keep + '\n\n' if keep else '') + block + '\n'


def sync_firefox(r, on, shell):
    """[sync] firefox: link userChrome / userContent into every profile and write their
    colours; off takes the links and the user.js block back out. Firefox reads them at start:
    if it's running when something changed, say so."""
    changed = False
    for prof in firefox_profiles():
        chrome = os.path.join(prof, 'chrome')
        # copies, not links: web pages run in a sandbox that can't read outside the profile,
        # so a userContent.css linked to ~/.config is silently skipped there
        for name in ('userChrome.css', 'userContent.css'):
            src, dst = os.path.join(FIREFOX_SRC, name), os.path.join(chrome, name)
            text = read(src)
            ours = os.path.islink(dst) or 'scripts/theme-sync.py' in read(dst)[:800]
            if on:
                if os.path.lexists(dst) and not ours and not os.path.lexists(dst + '.before-quickshell'):
                    os.replace(dst, dst + '.before-quickshell')
                if os.path.islink(dst):
                    os.remove(dst)
                if write_if_changed(dst, text):
                    changed = True
            elif ours and os.path.lexists(dst):
                os.remove(dst)
                if os.path.lexists(dst + '.before-quickshell'):
                    os.replace(dst + '.before-quickshell', dst)
                changed = True
        if on and write_if_changed(os.path.join(chrome, 'qs-theme.css'), firefox_css(r, shell)):
            changed = True
        uj = os.path.join(prof, 'user.js')
        old = read(uj)
        new = firefox_userjs(old, r, on)
        if new != old and (new or os.path.exists(uj)):
            write_if_changed(uj, new)
            changed = True
    if changed and subprocess.run(['pgrep', '-x', 'firefox'], stdout=subprocess.DEVNULL).returncode == 0:
        subprocess.Popen(['notify-send', '-a', 'Firefox', '-i', 'firefox',
                          'Firefox 的主題已更新', '重開 Firefox 就會套用新的配色。'],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return changed


def sync_terminal(r, on, name, shell=None):
    """kitty follows the theme only while [sync] terminal is on; the tools always get a palette
    (the theme's, or nier's when off) so the prompt and colours never go missing."""
    changed = []
    p = term_palette(r if on else resolve({}))
    tag = name if on else 'nier (sync off)'
    kitty = kitty_conf(p, name) if on else '# [sync] terminal = false: kitty keeps the colours in kitty.conf\n'
    reload_kitty = False
    if write_if_changed(KITTY_QS, kitty):
        changed.append('kitty')
        reload_kitty = True
    if write_if_changed(KITTY_FONT, kitty_font(shell or {}, r)):
        changed.append('kitty font')
        reload_kitty = True
    if reload_kitty:   # one config reload for every kitty, colours and size alike
        subprocess.run(['pkill', '-USR1', '-x', 'kitty'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if write_if_changed(ZSH_QS, zsh_conf(p, tag)):
        changed.append('zsh')
    if write_if_changed(BAT_QS, bat_theme(p, tag)):
        changed.append('bat')
        try:
            subprocess.run(['bat', 'cache', '--build'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            pass
    if write_if_changed(DELTA_QS, delta_conf(p, tag)):
        changed.append('delta')
    if write_if_changed(ATUIN_QS, atuin_theme(p, tag)):
        changed.append('atuin')
    for path, fn, label in ((YAZI_QS, yazi_theme, 'yazi'), (BTOP_QS, btop_theme, 'btop'),
                            (LAZYGIT_QS, lazygit_theme, 'lazygit')):
        if write_if_changed(path, fn(p, tag)):
            changed.append(label)
    return changed


def main():
    shell = parse(read(os.path.join(CONF, 'shell.conf')))
    name = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else str(shell.get('general.theme') or 'nier')
    r = resolve(parse(read(os.path.join(CONF, 'themes', name + '.conf'))))
    done = []
    if sync_fcitx5(r, shell.get('sync.fcitx5', True) is not False):
        done.append('fcitx5')
    window_fx = shell.get('effects.windowClose', True) is not False
    if sync_hyprland(r, shell.get('sync.hyprland', True) is not False, name, window_fx):
        done.append('hyprland')
    if sync_hyprlock(r, name, shell):
        done.append('hyprlock')
    done += sync_terminal(r, shell.get('sync.terminal', True) is not False, name, shell)
    if write_if_changed(FONTCONFIG_QS, fontconfig_conf(shell, r)):
        done.append('fontconfig')
    if sync_firefox(r, shell.get('sync.firefox', True) is not False, shell):
        done.append('firefox')
    print('theme-sync %s: %s' % (name, ', '.join(done) if done else 'up to date'))


if __name__ == '__main__':
    main()
