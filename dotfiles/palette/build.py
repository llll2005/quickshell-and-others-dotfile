#!/usr/bin/env python3
"""Build the theme workshop page (a claude.ai artifact, https://claude.ai/artifact/77qs2XJC3BrySY1pjNJZsW):
template.html with every quickshell/config/themes/*.conf injected as JSON at /*__THEMES__*/null.

    dotfiles/palette/build.py [out.html]     (default: /tmp/nier-shell-palette.html)

Its parser and fallbacks mirror settings/Config.qml, theme/Theme.qml and scripts/theme-sync.py;
keep them in step when theme tokens change."""
import glob
import json
import os
import sys

here = os.path.dirname(os.path.realpath(__file__))
themes_dir = os.path.join(here, '..', '..', 'quickshell', 'config', 'themes')
themes = {os.path.basename(f)[:-5]: open(f, encoding='utf-8').read() for f in sorted(glob.glob(os.path.join(themes_dir, '*.conf')))}
page = open(os.path.join(here, 'template.html'), encoding='utf-8').read()
page = page.replace('/*__THEMES__*/null', json.dumps(themes, ensure_ascii=False).replace('</', '<\\/'))
out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/nier-shell-palette.html'
open(out, 'w', encoding='utf-8').write(page)
print(f'{len(themes)} themes → {out}')
