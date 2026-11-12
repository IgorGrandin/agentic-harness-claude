#!/usr/bin/env python3
"""Cost per skill from the Claude Code transcripts, in Sonnet-input equivalents.

Weights: cache read x0.1, cache write x1.25, input x1, output x5. Haiku is weighted 1/3
(ASSUMPTION, not verified against the plan's real metering). Messages are de-duplicated by
message.id; subagent transcripts count toward their session. A session is attributed to the
skill named in its first user message (`skills/<name>`), else "outro".

Usage:
  python scripts/skill-cost.py [--since 2026-10-15] [--projects-dir ~/.claude/projects]
                               [--match brixbroker] [--sessions N]
Prints one line per skill (sessions, root, subagents, total, mean) and, with --sessions,
the N most recent sessions. Read-only; prints nothing but numbers and the first 70 chars of
each session's opening message.
"""
import argparse, collections, glob, json, os, re


def weight(model):
    return 1 / 3 if 'haiku' in (model or '').lower() else 1.0


def session_cost(path):
    seen, first, started = {}, None, None
    for fp in [path] + glob.glob(path[:-6] + '/subagents/*.jsonl'):
        sub = fp != path
        with open(fp, encoding='utf-8', errors='ignore') as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if not sub and first is None and o.get('type') == 'user':
                    c = (o.get('message') or {}).get('content')
                    if isinstance(c, list):
                        c = ' '.join(x.get('text', '') for x in c if isinstance(x, dict))
                    if c and not c.startswith('<'):
                        first, started = c[:400], o.get('timestamp')
                m = o.get('message') or {}
                u, mid = m.get('usage'), m.get('id')
                if u and mid:
                    seen[mid] = (m.get('model'), u, sub)
    total = collections.Counter()
    for model, u, sub in seen.values():
        v = (u.get('cache_read_input_tokens', 0) * 0.1 + u.get('cache_creation_input_tokens', 0) * 1.25
             + u.get('input_tokens', 0) + u.get('output_tokens', 0) * 5) * weight(model)
        total['sub' if sub else 'root'] += v
    return first, started, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--since', default='1970-01-01')
    ap.add_argument('--projects-dir', default=os.path.expanduser('~/.claude/projects'))
    ap.add_argument('--match', default='', help='substring of the project folder name')
    ap.add_argument('--sessions', type=int, default=0)
    a = ap.parse_args()
    rows = []
    for d in sorted(glob.glob(os.path.join(a.projects_dir, '*'))):
        if a.match and a.match.lower() not in os.path.basename(d).lower():
            continue
        for p in glob.glob(os.path.join(d, '*.jsonl')):
            first, started, tot = session_cost(p)
            if not first or (started or '') < a.since:
                continue
            m = re.search(r'skills.([a-z0-9-]+)', first)
            rows.append((started or '', m.group(1) if m else 'outro', tot['root'], tot['sub'], first[:70].replace('\n', ' ')))
    rows.sort()
    agg = collections.defaultdict(lambda: [0, 0.0, 0.0])
    for _, c, r, s, _ in rows:
        x = agg[c]; x[0] += 1; x[1] += r; x[2] += s
    print(f'since {a.since} (Sonnet-input equivalents, millions; Haiku x1/3 assumed)')
    for c, (n, r, s) in sorted(agg.items(), key=lambda kv: -(kv[1][1] + kv[1][2])):
        print(f'{c:22} sessions={n:3} root={r/1e6:6.2f} sub={s/1e6:6.2f} total={(r+s)/1e6:6.2f} mean={(r+s)/n/1e6:5.2f}')
    for t, c, r, s, f in rows[-a.sessions:] if a.sessions else []:
        print(f'{t[:16]} {c:14} {(r+s)/1e6:6.2f}  {f}')


if __name__ == '__main__':
    main()
