#!/usr/bin/env python3
"""The boot chain's pictures, in the Void (quickshell/CLAUDE.md, "Design language"):

  limine/void.png        Limine's backdrop: a diamond, SELECT SYSTEM, the hairline, the keys
  limine/void.f16        Limine's menu font: Operator Mono drawn into Limine's 8×16 cells
  plymouth/*.png         Plymouth's pieces, laid out by void.script like the shell's power
                         exit (widgets/ControlCenter.qml exitLayer): diamond, title, hairline,
                         the command — so a shutdown goes from the shell to Plymouth unmoved

    gen-art.py OUT_DIR [--scale 1.1] [--size 1920x1200]

The faces come from ~/.local/share/fonts (Josefin Sans, Operator Mono; not in the repo),
the ink from quickshell/config/shell.conf [void] (light, warn). boot-void.sh runs this.
"""
import argparse
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

HOME = os.path.expanduser('~' + (os.environ.get('SUDO_USER') or ''))
FONTS = os.path.join(HOME, '.local/share/fonts')
SHELL_CONF = os.path.join(HOME, '.config/quickshell/config/shell.conf')


def void_ink():
    light, warn, sect = '#ffffff', '#b8403c', ''
    try:
        for line in open(SHELL_CONF, encoding='utf-8'):
            m = re.match(r'\s*\[([^\]]+)\]', line)
            if m:
                sect = m.group(1).strip()
                continue
            m = re.match(r'\s*(light|warn)\s*=\s*(#[0-9a-fA-F]{6})', line)
            if m and sect == 'void':
                if m.group(1) == 'light':
                    light = m.group(2)
                else:
                    warn = m.group(2)
    except OSError:
        pass
    return light, warn


def rgb(h, a=255):
    return (int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16), a)


def font(path_glob, size, weight=None):
    import glob
    for p in sorted(glob.glob(os.path.join(FONTS, path_glob))):
        f = ImageFont.truetype(p, size)
        if weight is not None:
            try:
                f.set_variation_by_axes([weight])
            except (OSError, ValueError):
                pass
        return f
    return ImageFont.load_default(size)


def tracked(text, f, tracking, fill):
    """the Void's tracked caps: letter by letter, `tracking` em after each"""
    pad = int(f.size * 0.6)
    w = sum(f.getlength(c) for c in text) + tracking * f.size * (len(text) - 1)
    asc, desc = f.getmetrics()
    im = Image.new('RGBA', (int(w) + 2 * pad, asc + desc + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x = pad
    for c in text:
        d.text((x, pad), c, font=f, fill=fill)
        x += f.getlength(c) + tracking * f.size
    return im.crop(im.getbbox() or (0, 0, 1, 1))


def plain(text, f, fill):
    asc, desc = f.getmetrics()
    w = int(f.getlength(text)) + 4
    im = Image.new('RGBA', (w, asc + desc + 4), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((2, 2), text, font=f, fill=fill)
    return im.crop(im.getbbox() or (0, 0, 1, 1))


def diamond(size, fill=None, outline=None, ss=8):
    """a diamond `size` px across, supersampled for clean edges"""
    n = int(round(size * 1.42)) + 3        # a square of side `size`, turned 45°
    S = n * ss
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c, r = S / 2, size * 0.7071 * ss
    pts = [(c, c - r), (c + r, c), (c, c + r), (c - r, c)]
    if fill:
        d.polygon(pts, fill=fill)
    if outline:
        d.polygon(pts, outline=outline, width=max(1, ss))
    return im.resize((n, n), Image.LANCZOS)


def keycap(key, label, fk, fl, s, light):
    """[KEY] LABEL, as the Void's key rows"""
    k = plain(key, fk, rgb(light))
    l = tracked(label, fl, 0.26, rgb(light, 140))
    bw, bh = k.width + int(fk.size * 1.1), int(fl.size * 1.9)
    w = bw + int(6 * s) + l.width
    im = Image.new('RGBA', (w, bh), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, bw - 1, bh - 1], outline=rgb(light, 90), width=1)
    im.alpha_composite(k, ((bw - k.width) // 2, (bh - k.height) // 2))
    im.alpha_composite(l, (bw + int(6 * s), (bh - l.height) // 2))
    return im


def limine_backdrop(out, W, H, s, light, warn):
    im = Image.new('RGB', (W, H), (0, 0, 0)).convert('RGBA')
    title_f = font('josefin-sans/*.ttf', int(round(31 * s)), 300)
    # the keycaps' arrows: Josefin has none
    key_f = ImageFont.truetype('/usr/share/fonts/TTF/DejaVuSans.ttf', int(round(11 * s)))
    lab_f = font('josefin-sans/*.ttf', int(round(12 * s)), 300)
    cy = int(H * 0.26)
    dia_o = diamond(12 * s, outline=rgb(light))
    dia_c = diamond(5 * s, fill=rgb(light, 230))
    im.alpha_composite(dia_o, ((W - dia_o.width) // 2, cy - dia_o.height // 2))
    im.alpha_composite(dia_c, ((W - dia_c.width) // 2, cy - dia_c.height // 2))
    t = tracked('SELECT SYSTEM', title_f, 0.26, rgb(light))
    ty = cy + int(26 * s)
    im.alpha_composite(t, ((W - t.width) // 2, ty))
    ry = ty + t.height + int(22 * s)
    d = ImageDraw.Draw(im)
    rw = int(260 * s)
    d.line([((W - rw) // 2, ry), ((W + rw) // 2, ry)], fill=rgb(light, 115), width=1)
    keys = [keycap(k, v, key_f, lab_f, s, light) for k, v in
            (('↑↓', 'SELECT'), ('↵', 'BOOT'), ('E', 'EDIT'), ('S', 'FIRMWARE'))]
    gap = int(18 * s)
    total = sum(k.width for k in keys) + gap * (len(keys) - 1)
    x, y = (W - total) // 2, int(H * 0.79)
    for k in keys:
        im.alpha_composite(k, (x, y))
        x += k.width + gap
    im.convert('RGB').save(os.path.join(out, 'void.png'), optimize=True)
    return ry


def _box(ch):
    """the strokes of a box-drawing character, from its Unicode name"""
    import unicodedata
    name = unicodedata.name(ch, '')
    if not name.startswith('BOX DRAWINGS'):
        return None
    w = name.split()[2:]
    dirs = set()
    if 'VERTICAL' in w:
        dirs |= {'u', 'd'}
    if 'HORIZONTAL' in w:
        dirs |= {'l', 'r'}
    for word, d in (('UP', 'u'), ('DOWN', 'd'), ('LEFT', 'l'), ('RIGHT', 'r')):
        if word in w:
            dirs.add(d)
    return dirs, 'DOUBLE' in w


def _shape(ch):
    """arrows, triangles and blocks, drawn so they sit in the cell like the text"""
    import math
    S = 8                                   # supersampling of the 8×16 cell
    im = Image.new('L', (8 * S, 16 * S), 0)
    d = ImageDraw.Draw(im)
    cx, cy = 4 * S, 8 * S
    tri = {'►': [(2, 4), (7, 8), (2, 12)], '◄': [(6, 4), (1, 8), (6, 12)],
           '▲': [(1, 11), (4, 5), (7, 11)], '▼': [(1, 5), (4, 11), (7, 5)]}
    if ch in tri:
        d.polygon([(x * S, y * S) for x, y in tri[ch]], fill=255)
        return im
    arrows = {'→': (0, 1), '←': (0, -1), '↑': (-1, 0), '↓': (1, 0)}
    if ch in arrows:
        vy, vx = arrows[ch]
        if vx:
            d.line([(1 * S, cy), (7 * S, cy)], fill=255, width=S)
            tip = 7 * S if vx > 0 else 1 * S
            d.polygon([(tip, cy), (tip - vx * 3 * S, cy - 3 * S), (tip - vx * 3 * S, cy + 3 * S)], fill=255)
        else:
            d.line([(cx, 3 * S), (cx, 13 * S)], fill=255, width=S)
            tip = 13 * S if vy > 0 else 3 * S
            d.polygon([(cx, tip), (cx - 3 * S, tip - vy * 3 * S), (cx + 3 * S, tip - vy * 3 * S)], fill=255)
        return im
    blocks = {'█': (0, 0, 8, 16), '▀': (0, 0, 8, 8), '▄': (0, 8, 8, 16), '▌': (0, 0, 4, 16), '▐': (4, 0, 8, 16)}
    if ch in blocks:
        x0, y0, x1, y1 = blocks[ch]
        d.rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], fill=255)
        return im
    shades = {'░': 4, '▒': 2, '▓': 1}
    if ch in shades:
        n = shades[ch]
        for y in range(16):
            for x in range(8):
                if ch == '▓' and (x + y) % 4 == 0:
                    continue
                if ch == '▓' or (x + y * (1 if n == 2 else 3)) % n == 0:
                    d.rectangle([x * S, y * S, x * S + S - 1, y * S + S - 1], fill=255)
        return im
    return None


def limine_font(out):
    """Operator Mono in Limine's 8×16 cells (code page 437), 1 bit. Box drawing, blocks,
    arrows and triangles are drawn so lines join across cells (term_font_spacing 0);
    what Operator Mono lacks comes from DejaVu Sans Mono."""
    import glob
    from fontTools.ttLib import TTFont
    op = (glob.glob(os.path.join(FONTS, 'operator-mono/OperatorMono-Book.otf')) or [None])[0]
    dv = '/usr/share/fonts/TTF/DejaVuSansMono.ttf'
    have = set(TTFont(op).getBestCmap()) if op else set()
    cp437 = ' ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼' + bytes(range(32, 127)).decode() + '⌂' \
        + bytes(range(128, 256)).decode('cp437')
    data = bytearray()
    for ch in cp437:
        bits = Image.new('1', (8, 16), 0)
        box = _box(ch)
        shape = None if box else _shape(ch)
        if box:
            dirs, double = box
            px = ImageDraw.Draw(bits)
            for off in ((-1, 1) if double else (0,)):
                x, y = 3 + off, 7 + off
                if 'u' in dirs: px.line([(x, 0), (x, 7)], fill=1)
                if 'd' in dirs: px.line([(x, 7), (x, 15)], fill=1)
                if 'l' in dirs: px.line([(0, y), (3, y)], fill=1)
                if 'r' in dirs: px.line([(3, y), (7, y)], fill=1)
        elif shape is not None:
            bits = shape.resize((8, 16), Image.LANCZOS).point(lambda v: 1 if v >= 110 else 0, '1')
        elif ch.strip():
            src = op if ord(ch) in have else dv
            big = ImageFont.truetype(src, 14 * 4)
            asc, desc = big.getmetrics()
            cell = Image.new('L', (32, 64), 0)
            d = ImageDraw.Draw(cell)
            bb = d.textbbox((0, 0), ch, font=big)
            d.text(((32 - (bb[2] - bb[0])) / 2 - bb[0], (64 - (asc + desc)) / 2 + 2), ch, font=big, fill=255)
            bits = cell.resize((8, 16), Image.LANCZOS).point(lambda v: 1 if v >= 96 else 0, '1')
        for y in range(16):
            row = 0
            for x in range(8):
                if bits.getpixel((x, y)):
                    row |= 0x80 >> x
            data.append(row)
    with open(os.path.join(out, 'void.f16'), 'wb') as fh:
        fh.write(bytes(data))


def plymouth(out, s, light, warn):
    title_f = font('josefin-sans/*.ttf', int(round(31 * s)), 300)
    mono_f = font('operator-mono/OperatorMono-Book.otf', int(round(12 * s)))
    diamond(12 * s, outline=rgb(light)).save(os.path.join(out, 'dia.png'))
    diamond(12 * s, outline=rgb(warn)).save(os.path.join(out, 'dia-warn.png'))
    diamond(5 * s, fill=rgb(light)).save(os.path.join(out, 'core.png'))
    diamond(8 * s, fill=rgb(light)).save(os.path.join(out, 'bullet.png'))
    for name, text in (('boot', 'SYSTEM BOOT'), ('shutdown', 'SYSTEM SHUTDOWN'),
                       ('reboot', 'REBOOTING'), ('password', 'AUTHORIZATION REQUIRED'),
                       ('updates', 'UPDATING SYSTEM')):
        tracked(text, title_f, 0.26, rgb(light)).save(os.path.join(out, 'title-%s.png' % name))
    for name, text in (('shutdown', '$ systemctl poweroff'), ('reboot', '$ systemctl reboot')):
        plain(text, mono_f, rgb(light, 153)).save(os.path.join(out, 'cmd-%s.png' % name))
    Image.new('RGBA', (1, 1), rgb(light, 115)).save(os.path.join(out, 'rule.png'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--scale', type=float, default=1.1)
    ap.add_argument('--size', default='1920x1200')
    a = ap.parse_args()
    W, H = (int(v) for v in a.size.split('x'))
    light, warn = void_ink()
    lim, ply = os.path.join(a.out, 'limine'), os.path.join(a.out, 'plymouth')
    os.makedirs(lim, exist_ok=True)
    os.makedirs(ply, exist_ok=True)
    ry = limine_backdrop(lim, W, H, a.scale, light, warn)
    limine_font(lim)
    plymouth(ply, a.scale, light, warn)
    print('rule_y=%d' % ry)


if __name__ == '__main__':
    sys.exit(main())
