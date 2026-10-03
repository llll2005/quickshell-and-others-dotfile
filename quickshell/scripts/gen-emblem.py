#!/usr/bin/env python3
"""Draw the relic lock's emblem (lockscreen/emblem.svg): a sun of curved blades around a
stone medallion — a ring of ticks, an eight-petal rosette, the shell's four-point diamond
star at the heart. Original geometry, generated so it can be tuned here:

    scripts/gen-emblem.py            writes lockscreen/emblem.svg
"""
import math
import os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "lockscreen", "emblem.svg")
BONE, BONE_DK, SHADE, INK, CORE = "#ebe4d4", "#9a9283", "#6f685c", "#221e1a", "#f7f2e8"


def pol(r, a):
    return r * math.cos(a), r * math.sin(a)


def fmt(p):
    return "%.1f,%.1f" % p


def blade(a, r0, r1, half, bend):
    """a tapered blade leaving the ring at angle a, sweeping in an S (cubic edges) by `bend`
    to a sharp tip — flame-like rather than straight"""
    l0, rt0 = pol(r0, a - half), pol(r0, a + half)
    tip = pol(r1, a + bend)
    d = r1 - r0
    c1 = pol(r0 + d * 0.30, a - half * 0.35 + bend * 0.10)
    c2 = pol(r0 + d * 0.72, a - half * 0.05 + bend * 0.95)
    c3 = pol(r0 + d * 0.62, a + half * 0.55 + bend * 0.70)
    c4 = pol(r0 + d * 0.22, a + half * 1.15 + bend * 0.05)
    return "M%s C%s %s %s C%s %s %s Z" % (fmt(l0), fmt(c1), fmt(c2), fmt(tip), fmt(c3), fmt(c4), fmt(rt0))


def petal(a, r0, r1, w):
    """a pointed petal along angle a"""
    p0, p1 = pol(r0, a), pol(r1, a)
    rm = (r0 + r1) / 2
    cl, cr = pol(rm, a - w), pol(rm, a + w)
    return "M%s Q%s %s Q%s %s Z" % (fmt(p0), fmt(cl), fmt(p1), fmt(cr), fmt(p0))


def star4(r, inner):
    pts = []
    for i in range(8):
        a = -math.pi / 2 + i * math.pi / 4
        pts.append(pol(r if i % 2 == 0 else inner, a))
    return "M" + " L".join(fmt(p) for p in pts) + " Z"


def main():
    s = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="-500 -500 1000 1000" width="1000" height="1000">',
         '<defs>',
         f'<linearGradient id="bone" x1="0" y1="-1" x2="0" y2="1" gradientUnits="objectBoundingBox"><stop offset="0" stop-color="{BONE}"/><stop offset="1" stop-color="{BONE_DK}"/></linearGradient>',
         f'<radialGradient id="stone" cx="0" cy="-40" r="240" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#e2dccf"/><stop offset="0.7" stop-color="#bdb5a6"/><stop offset="1" stop-color="#8f877a"/></radialGradient>',
         f'<radialGradient id="ringg" cx="0" cy="-120" r="300" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="{BONE}"/><stop offset="1" stop-color="{SHADE}"/></radialGradient>',
         '</defs>']
    tau = 2 * math.pi
    # blades: 12 long, 12 medium between, 24 small at the ring
    jit = lambda i, k: 1 + 0.07 * math.sin(i * 12.9898 + k * 78.233)      # fixed, uneven lengths
    for i in range(24):
        a = -math.pi / 2 + i * tau / 24 + tau / 48
        s.append(f'<path d="{blade(a, 262, 262 + 70 * jit(i, 1), 0.04, 0.10)}" fill="url(#bone)" stroke="{INK}" stroke-width="2"/>')
    for i in range(12):
        a = -math.pi / 2 + (i + 0.5) * tau / 12
        s.append(f'<path d="{blade(a, 255, 255 + 150 * jit(i, 2), 0.085, 0.26)}" fill="url(#bone)" stroke="{INK}" stroke-width="2.5"/>')
    for i in range(12):
        a = -math.pi / 2 + i * tau / 12
        L = 250 + 245 * jit(i, 3)
        s.append(f'<path d="{blade(a, 250, L, 0.11, 0.36)}" fill="url(#bone)" stroke="{INK}" stroke-width="3"/>')
        # a dark groove down each long blade
        s.append(f'<path d="{blade(a + 0.02, 268, L - 70, 0.02, 0.31)}" fill="{SHADE}" opacity="0.5"/>')
    # the ring
    s.append(f'<circle r="252" fill="none" stroke="{INK}" stroke-width="34"/>')
    s.append(f'<circle r="252" fill="none" stroke="url(#ringg)" stroke-width="26"/>')
    for i in range(72):
        a = i * tau / 72
        r0, r1 = (240, 264) if i % 6 == 0 else (246, 258)
        s.append(f'<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="{INK}" stroke-width="{3 if i % 6 == 0 else 1.5}"/>' % (*pol(r0, a), *pol(r1, a)))
    # the medallion
    s.append(f'<circle r="232" fill="url(#stone)" stroke="{INK}" stroke-width="4"/>')
    s.append(f'<circle r="212" fill="none" stroke="{SHADE}" stroke-width="2" stroke-dasharray="4 10"/>')
    # rosette: eight dark petals, eight smaller between, a light rim on each
    for i in range(8):
        a = -math.pi / 2 + i * tau / 8
        s.append(f'<path d="{petal(a, 52, 196, 0.3)}" fill="{INK}"/>')
        s.append(f'<path d="{petal(a, 62, 176, 0.17)}" fill="#3a342e"/>')
    for i in range(8):
        a = -math.pi / 2 + (i + 0.5) * tau / 8
        s.append(f'<path d="{petal(a, 70, 150, 0.2)}" fill="{INK}" opacity="0.85"/>')
    # the heart: the shell's four-point diamond star
    s.append(f'<circle r="74" fill="url(#stone)" stroke="{INK}" stroke-width="5"/>')
    s.append(f'<path d="{star4(96, 26)}" fill="{CORE}" stroke="{INK}" stroke-width="5" stroke-linejoin="miter"/>')
    s.append(f'<path d="{star4(30, 10)}" fill="{INK}"/>')
    s.append('</svg>')
    with open(OUT, "w") as f:
        f.write("\n".join(s) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    main()
