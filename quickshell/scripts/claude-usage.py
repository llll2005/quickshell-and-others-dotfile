#!/usr/bin/env python3
"""Aggregate Claude Code token usage from ~/.claude/projects/**/*.jsonl.
Outputs: week_cost|month_cost|today_cost|week_tok|month_tok|today_tok
Costs are estimated using Sonnet API pricing as a proxy (not subscription billing).
"""
import json, glob, datetime, os

# Sonnet 4.x API pricing (USD per million tokens)
PRICES = {'in': 3.0, 'out': 15.0, 'cr': 0.30, 'cw': 3.75}

def cost(u):
    return (u.get('input_tokens', 0)              / 1e6 * PRICES['in'] +
            u.get('output_tokens', 0)             / 1e6 * PRICES['out'] +
            u.get('cache_read_input_tokens', 0)   / 1e6 * PRICES['cr'] +
            u.get('cache_creation_input_tokens', 0) / 1e6 * PRICES['cw'])

def tok(u):
    return (u.get('input_tokens', 0) +
            u.get('output_tokens', 0) +
            u.get('cache_read_input_tokens', 0) +
            u.get('cache_creation_input_tokens', 0))

now       = datetime.datetime.now(datetime.timezone.utc)
week_ago  = now - datetime.timedelta(days=7)
month_ago = now - datetime.timedelta(days=30)
today     = now.replace(hour=0, minute=0, second=0, microsecond=0)

wc = mc = tc = 0.0
wt = mt = tt = 0

for f in glob.glob(os.path.expanduser('~/.claude/projects/**/*.jsonl'), recursive=True):
    # A file untouched for 30 days can't hold entries inside any window below.
    if os.path.getmtime(f) < month_ago.timestamp():
        continue
    try:
        for line in open(f, errors='replace'):
            # Only lines carrying a usage block matter; skipping the rest avoids
            # json-parsing the (large) tool-result lines.
            if '"usage"' not in line:
                continue
            d = json.loads(line)
            ts_str = d.get('timestamp', '')
            msg = d.get('message', {})
            if not isinstance(msg, dict):
                continue
            u = msg.get('usage', {})
            if not u or not ts_str:
                continue
            try:
                ts = datetime.datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
            except Exception:
                continue
            c = cost(u)
            t = tok(u)
            if ts > week_ago:
                wc += c; wt += t
            if ts > month_ago:
                mc += c; mt += t
            if ts >= today:
                tc += c; tt += t
    except Exception:
        pass

def fmt(t):
    if t >= 1_000_000: return f'{t/1_000_000:.1f}M'
    if t >= 1_000:     return f'{t/1_000:.0f}K'
    return str(t)

print(f'{wc:.2f}|{mc:.2f}|{tc:.2f}|{fmt(wt)}|{fmt(mt)}|{fmt(tt)}')
