#!/usr/bin/env python3
"""Build assets/data/emoji.tsv for the launcher's ':' picker: one line per symbol,
`char<TAB>search words`. Emoji names come from Python's Unicode database; kaomoji
are hand-picked with English + Chinese tags. Re-run after a Python upgrade for
newer emoji:  python3 scripts/gen-emoji.py"""
import os
import unicodedata

RANGES = [(0x1F300, 0x1F5FF), (0x1F600, 0x1F64F), (0x1F680, 0x1F6FF), (0x1F900, 0x1F9FF),
          (0x1FA70, 0x1FAFF), (0x2600, 0x26FF), (0x2700, 0x27BF), (0x1F1E6, 0x1F1FF)]
SKIP = ('REGIONAL INDICATOR', 'TAG ', 'VARIATION', 'EMOJI COMPONENT', 'SKIN TONE')
KAOMOJI = [
    ('(╯°□°)╯︵ ┻━┻', 'table flip angry 翻桌 生氣'), ('┬─┬ノ( º _ ºノ)', 'table unflip calm 擺回桌子'),
    ('¯\\_(ツ)_/¯', 'shrug whatever 聳肩 無所謂'), ('(｡•̀ᴗ-)✧', 'wink 眨眼'),
    ('(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧', 'yay happy sparkle 開心 撒花'), ('( ˘ω˘ )', 'calm content 滿足'),
    ('(´；ω；`)', 'cry sad 哭 難過'), ('(；´Д｀)', 'tired ugh 累 無奈'),
    ('(￣▽￣)ノ', 'hi wave 嗨 揮手'), ('(っ˘ڡ˘ς)', 'yummy eat 好吃'),
    ('(⁄ ⁄•⁄ω⁄•⁄ ⁄)', 'shy blush 害羞'), ('(ง •̀_•́)ง', 'fight determined 加油'),
    ('(￣ー￣)', 'smug 得意'), ('(°ロ°)!', 'shock surprised 驚訝'),
    ('(＾▽＾)', 'happy smile 笑'), ('(´・ω・`)', 'meh sad shobon 失落'),
    ('ヽ(°〇°)ﾉ', 'panic 驚慌'), ('(=^･ω･^=)', 'cat 貓'), ('ʕ•ᴥ•ʔ', 'bear 熊'),
    ('(づ｡◕‿‿◕｡)づ', 'hug 抱抱'), ('♪(´ε｀ )', 'sing music 唱歌'), ('(¬_¬)', 'suspicious 懷疑'),
    ('(•_•) ( •_•)>⌐■-■ (⌐■_■)', 'deal with it sunglasses 墨鏡'), ('(⊙_⊙)', 'stare 瞪'),
    ('(～﹃～)~zZ', 'sleepy sleep 睏 睡'), ('ヾ(•ω•`)o', 'bye 掰掰'), ('m(_ _)m', 'sorry bow 抱歉 鞠躬'),
    ('(✿◠‿◠)', 'flower cute 可愛'), ('(ಥ﹏ಥ)', 'crying sob 大哭'), ('(╬ Ò﹏Ó)', 'rage furious 暴怒'),
]

out = []
for lo, hi in RANGES:
    for cp in range(lo, hi + 1):
        ch = chr(cp)
        try:
            name = unicodedata.name(ch)
        except ValueError:
            continue
        if any(name.startswith(s) for s in SKIP):
            continue
        out.append(f"{ch}\t{name.lower()}")
for k, tags in KAOMOJI:
    out.append(f"{k}\tkaomoji 顏文字 {tags}")

path = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'assets', 'data', 'emoji.tsv')
with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out) + '\n')
print(len(out), 'entries →', path)
