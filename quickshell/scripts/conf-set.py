#!/usr/bin/env python3
"""Set one option in config/shell.conf, keeping its comments and layout:

    conf-set.py <section> <key> <value>

The value is written as given (true/false, a number, text; text holding # or ; is
quoted). A missing key is added at the end of its section, a missing section at the
end of the file. The file is rewritten in place (not renamed over), so Quickshell's
file watcher keeps following it."""
import os
import re
import sys

PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'config', 'shell.conf')


def fmt(v):
    if re.fullmatch(r'(?i)true|false|-?\d+(\.\d+)?', v):
        return v.lower() if v.lower() in ('true', 'false') else v
    return '"%s"' % v if re.search(r'[#;"]|^\s|\s$', v) else v


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    section, key, value = sys.argv[1], sys.argv[2], fmt(sys.argv[3])
    lines = open(PATH, encoding='utf-8').read().split('\n')
    head = re.compile(r'^\[([^\]]+)\]\s*([#;].*)?$')
    start = next((i for i, l in enumerate(lines) if (m := head.match(l.strip())) and m.group(1).strip() == section), None)
    if start is None:
        while lines and lines[-1] == '':
            lines.pop()
        lines += ['', '[%s]' % section, '%s = %s' % (key, value), '']
    else:
        end = next((i for i in range(start + 1, len(lines)) if head.match(lines[i].strip())), len(lines))
        kre = re.compile(r'^(\s*)' + re.escape(key) + r'(\s*=\s*)(.*)$')
        for i in range(start + 1, end):
            m = kre.match(lines[i])
            if not m:
                continue
            prefix, rest = m.group(1) + key + m.group(2), m.group(3)
            # an inline comment (whitespace, then # or ;) stays where it was
            c = re.search(r'"\s+([#;].*)$', rest) if rest.startswith('"') else re.search(r'\s+([#;](\s.*)?)$', rest)
            left = prefix + value
            if c:
                col = len(prefix) + c.start(1)
                lines[i] = left + ' ' * max(1, col - len(left)) + c.group(1)
            else:
                lines[i] = left
            break
        else:
            at = end
            while at > start + 1 and lines[at - 1].strip() == '':
                at -= 1
            lines.insert(at, '%s = %s' % (key, value))
    with open(PATH, 'r+', encoding='utf-8') as f:
        f.seek(0)
        f.write('\n'.join(lines))
        f.truncate()


if __name__ == '__main__':
    main()
