#!/usr/bin/env python3
"""List launcher entries for widgets/Menu.qml, one per line:

    name|desktop-id|categories|icon|binary|exec

icon   — the Icon= key (theme name or absolute path)
binary — basename of the real executable behind Exec (symlinks resolved); the
         launcher tries it as an icon name when Icon= isn't in the theme
exec   — last, so a '|' inside it can't shift the other fields

One process instead of a dozen forks per .desktop file (the old shell loop took
~2.6 s for ~225 files). Only the [Desktop Entry] group is read, and an entry in
~/.local/share/applications overrides a system one with the same id.
"""
import os
import re
import shlex
import shutil

DIRS = ['/usr/share/applications', os.path.expanduser('~/.local/share/applications')]


def read_entry(path):
    keys, in_main = {}, False
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                line = line.strip()
                if line.startswith('['):
                    in_main = line == '[Desktop Entry]'
                    continue
                if in_main and '=' in line and not line.startswith('#'):
                    k, v = line.split('=', 1)
                    keys.setdefault(k.strip(), v.strip())
    except OSError:
        return None
    return keys


def binary_of(cmd):
    try:
        words = shlex.split(cmd)
    except ValueError:
        words = cmd.split()
    for w in words:
        if w == 'env' or re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', w):
            continue
        p = shutil.which(w)
        return os.path.basename(os.path.realpath(p) if p else w)
    return ''


def main():
    entries = {}                      # desktop id → path; later dirs override earlier
    for d in DIRS:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for n in names:
            if n.endswith('.desktop'):
                entries[n[:-len('.desktop')]] = os.path.join(d, n)

    lines = set()
    for did, path in entries.items():
        k = read_entry(path)
        if not k or k.get('NoDisplay') == 'true' or k.get('Hidden') == 'true':
            continue
        name = k.get('Name', '')
        cmd = re.sub(r' %[A-Za-z]', '', k.get('Exec', ''))
        if not name or not cmd:
            continue
        clean = lambda s: s.replace('|', ' ').replace('\n', ' ')
        lines.add('|'.join([clean(name), did, clean(k.get('Categories', '')),
                            clean(k.get('Icon', '')), binary_of(cmd), cmd]))

    for line in sorted(lines, key=lambda s: (s.casefold(), s)):
        print(line)


if __name__ == '__main__':
    main()
