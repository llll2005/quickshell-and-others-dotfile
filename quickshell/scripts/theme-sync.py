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

    theme-sync.py [theme]        default: `[general] theme` from config/shell.conf

`[sync] fcitx5 = false` / `hyprland = false` in shell.conf hand each back to its own
look (fcitx5's `nier` theme; Hyprland's palette in ui/theme.lua). Idempotent: nothing
is reloaded unless a generated file actually changed. Quickshell runs this whenever
the theme (its name or its file) changes.

The parser and fallbacks mirror settings/Config.qml and theme/Theme.qml.
"""
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
    r['mono'] = str(t.get('font.mono') or 'Share Tech Mono')
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


def sync_hyprlock(r, name):
    """The fallback lock, in the same Void as lock.qml (always written: it is what you see
    if the shell's lock fails, whatever the sync options)."""
    L, W, F = rgb(r['light']), rgb(r['warn']), r['mono']
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
    if sync_hyprlock(r, name):
        done.append('hyprlock')
    print('theme-sync %s: %s' % (name, ', '.join(done) if done else 'up to date'))


if __name__ == '__main__':
    main()
