#!/usr/bin/env python3
"""Answer pixel-colour queries against a binary PPM (P6), e.g. grim's freeze frame.

    pixel-probe.py FRAME.ppm
    stdin : "x y" per line (physical pixels)
    stdout: "x y #RRGGBB" per query ("x y -" when outside the image)

Loads the frame once, so the capture panel's magnifier can ask for the pixel under
the cursor on every move (Qt's Canvas cannot read an image back reliably).
"""
import sys


def load(path):
    data = open(path, 'rb').read()
    fields, i = [], 0
    while len(fields) < 4:                       # magic, width, height, maxval
        while data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b'#':                # comment line
            while data[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        j = i
        while not data[j:j + 1].isspace():
            j += 1
        fields.append(data[i:j])
        i = j
    if fields[0] != b'P6':
        raise ValueError('not a binary PPM')
    w, h, maxval = int(fields[1]), int(fields[2]), int(fields[3])
    return data, i + 1, w, h, (2 if maxval > 255 else 1), maxval


def main():
    data, off, w, h, bps, maxval = load(sys.argv[1])
    out = sys.stdout
    for line in sys.stdin:
        try:
            x, y = (int(v) for v in line.split())
        except ValueError:
            continue
        if not (0 <= x < w and 0 <= y < h):
            out.write('%d %d -\n' % (x, y))
        else:
            k = off + (y * w + x) * 3 * bps
            if bps == 1:
                r, g, b = data[k], data[k + 1], data[k + 2]
            else:                                # 16-bit samples, big-endian
                r, g, b = (((data[k + 2 * c] << 8) | data[k + 2 * c + 1]) * 255 // maxval for c in range(3))
            out.write('%d %d #%02X%02X%02X\n' % (x, y, r, g, b))
        out.flush()


if __name__ == '__main__':
    main()
