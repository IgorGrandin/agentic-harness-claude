#!/usr/bin/env python3
"""Tokens and time per slice, per host and model, read from the local transcripts.

The slice commits of /execute-ig carry Execute-Plan, Execute-Slice, Execute-Host,
Execute-Model and Execute-Started trailers. This script takes each slice's window
(Execute-Started .. commit time) and sums the tokens every host recorded inside it:

  claude       ~/.claude/projects/**/*.jsonl (+ subagents), message.usage, de-duplicated by message.id
  codex        ~/.codex/sessions/**/rollout-*.jsonl, token_count events (delta of total_token_usage)
  antigravity  ~/.gemini/antigravity/conversations/*.db, table gen_metadata (protobuf)

Usage:
  python scripts/ai-usage.py --plan .cursor/plans/wi_1_x.plan.md [--repo .] [--match brixbroker]
  python scripts/ai-usage.py --from 2026-11-18T10:00:00-03:00 --to 2026-11-18T11:00:00-03:00

Read-only. Columns: input = uncached input, cache = cache reads, cache_wr = cache writes (billed above input), out = output (reasoning included
where the host reports it inside output), calls = model requests.

Limits (OBSERVED unless marked):
  * The window is by time. Work from other projects in the same minutes is counted unless --match
    narrows it (Claude project folder name, Codex cwd; Antigravity has no project field).
  * Antigravity field mapping (INFERENCE, not checked against its UI): usage message field 2 = uncached
    input, 3 = output, 5 = cache read; model name = field 19 of the gen_metadata row; time = the step
    named by the row's last_step_index. Compare one conversation with the Antigravity UI before trusting it.
  * Tokens are not cost: the models have different prices. Compare tokens per model, then apply prices.
"""
import argparse, collections, datetime as dt, glob, json, os, re, sqlite3, subprocess, sys


def parse_iso(s):
    s = s.strip().replace('Z', '+00:00')
    d = dt.datetime.fromisoformat(s)
    if d.tzinfo is None:
        raise ValueError(f'timestamp without offset: {s}')
    return d.astimezone(dt.timezone.utc)


class Usage:
    __slots__ = ('input', 'cache', 'cache_write', 'out', 'calls')

    def __init__(self):
        self.input = self.cache = self.cache_write = self.out = self.calls = 0

    def add(self, i, c, cw, o):
        self.input += i; self.cache += c; self.cache_write += cw; self.out += o; self.calls += 1


# Each reader yields (utc datetime, model, input, cache_read, cache_write, output).

def read_claude(root, match, lo, hi):
    seen = set()
    for fp in glob.glob(os.path.join(root, '*', '**', '*.jsonl'), recursive=True):
        proj = os.path.relpath(fp, root).split(os.sep)[0]
        if match and match.lower() not in proj.lower():
            continue
        if dt.datetime.fromtimestamp(os.path.getmtime(fp), dt.timezone.utc) < lo:
            continue
        with open(fp, encoding='utf-8', errors='ignore') as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                    m = o.get('message') or {}
                    u, mid = m.get('usage'), m.get('id')
                    if not u or not mid or mid in seen:
                        continue
                    t = parse_iso(o['timestamp'])
                except (ValueError, KeyError, TypeError):
                    continue
                if lo <= t <= hi:
                    seen.add(mid)
                    yield (t, m.get('model') or 'claude-unknown', u.get('input_tokens', 0),
                           u.get('cache_read_input_tokens', 0), u.get('cache_creation_input_tokens', 0),
                           u.get('output_tokens', 0))


def read_codex(root, match, lo, hi):
    for fp in glob.glob(os.path.join(root, '**', 'rollout-*.jsonl'), recursive=True):
        if dt.datetime.fromtimestamp(os.path.getmtime(fp), dt.timezone.utc) < lo:
            continue
        model, cwd, prev = 'codex-unknown', '', {}
        with open(fp, encoding='utf-8', errors='ignore') as fh:
            for line in fh:
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                p = o.get('payload') or {}
                if o.get('type') == 'turn_context':
                    model = p.get('model') or model
                    cwd = p.get('cwd') or cwd
                    if p.get('effort'):
                        model = f"{p.get('model') or model}"
                if p.get('type') != 'token_count' or not p.get('info'):
                    continue
                tot = p['info'].get('total_token_usage') or {}
                delta = {k: tot.get(k, 0) - prev.get(k, 0) for k in tot}
                if delta.get('total_tokens', 0) < 0:  # counter reset (new thread, compaction): the new total is the delta
                    delta = dict(tot)
                prev = tot
                if delta.get('total_tokens', 0) <= 0 or (match and match.lower() not in cwd.lower()):
                    continue
                try:
                    t = parse_iso(o['timestamp'])
                except (ValueError, KeyError):
                    continue
                if lo <= t <= hi:
                    cached = delta.get('cached_input_tokens', 0)
                    yield (t, model, delta.get('input_tokens', 0) - cached, cached,
                           delta.get('cache_write_input_tokens', 0), delta.get('output_tokens', 0))


def _pb(b, depth=0):
    """Minimal protobuf wire reader: list of (field, kind, value); None when not a message."""
    out, i = [], 0

    def varint():
        nonlocal i
        v = s = 0
        while True:
            x = b[i]; i += 1
            v |= (x & 0x7F) << s; s += 7
            if x < 0x80:
                return v
    try:
        while i < len(b):
            k = varint(); fn, wt = k >> 3, k & 7
            if wt == 0:
                out.append((fn, 'v', varint()))
            elif wt == 2:
                n = varint(); d = b[i:i + n]; i += n
                if len(d) != n:
                    return None
                sub = _pb(d, depth + 1) if depth < 3 and n > 1 else None
                if sub:
                    out.append((fn, 'm', sub))
                else:
                    try:
                        out.append((fn, 's', d.decode('utf-8')))
                    except UnicodeDecodeError:
                        out.append((fn, 'b', d))
            elif wt == 1:
                i += 8
            elif wt == 5:
                i += 4
            else:
                return None
    except IndexError:
        return None
    return out


def _first(msg, fn):
    return next((v for f, _, v in (msg or []) if f == fn), None)


def read_antigravity(root, match, lo, hi):
    for fp in glob.glob(os.path.join(root, '*.db')):
        if dt.datetime.fromtimestamp(os.path.getmtime(fp), dt.timezone.utc) < lo:
            continue
        try:
            con = sqlite3.connect(f'file:{fp}?mode=ro', uri=True)
            stamps = {}
            for idx, meta in con.execute('select idx, metadata from steps'):
                ts = _first(_first(_pb(meta) or [], 1), 1) if meta else None
                if ts:
                    stamps[idx] = dt.datetime.fromtimestamp(ts, dt.timezone.utc)
            rows = con.execute('select idx, data from gen_metadata').fetchall()
            con.close()
        except sqlite3.Error as e:
            print(f'warning: skipped {os.path.basename(fp)}: {e}', file=sys.stderr)
            continue
        for _, data in rows:
            msg = _first(_pb(data) or [], 1) or []
            usage = _first(msg, 4)
            model = _first(msg, 19)
            model = model if isinstance(model, str) and model else 'antigravity-unknown'
            last = None
            for f, _, v in msg:
                if f == 20 and isinstance(v, list) and _first(v, 1) == 'last_step_index':
                    raw = _first(v, 2)
                    last = int(raw) if isinstance(raw, str) and raw.isdigit() else _first(raw, 6) if isinstance(raw, list) else None
            t = stamps.get(last)
            if not usage or t is None or not (lo <= t <= hi):
                continue
            yield (t, model, _first(usage, 2) or 0, _first(usage, 5) or 0, 0, _first(usage, 3) or 0)


def collect(lo, hi, match, host=None):
    home = os.path.expanduser('~')
    readers = {
        'claude': lambda: read_claude(os.path.join(home, '.claude', 'projects'), match, lo, hi),
        'codex': lambda: read_codex(os.path.join(home, '.codex', 'sessions'), match, lo, hi),
        'antigravity': lambda: read_antigravity(os.path.join(home, '.gemini', 'antigravity', 'conversations'), match, lo, hi),
    }
    totals = collections.defaultdict(Usage)
    for name, fn in readers.items():
        if host and name != host:
            continue
        for _, model, i, c, cw, o in fn():
            totals[(name, model)].add(i, c, cw, o)
    return totals


def slice_commits(repo, plan):
    fmt = '%H%x1f%cI%x1f%B%x1e'
    out = subprocess.run(['git', '-C', repo, 'log', '--reverse', '--fixed-strings', f'--grep=Execute-Plan: {plan}', f'--format={fmt}'],
                         capture_output=True, text=True, encoding='utf-8', check=True).stdout
    rows = []
    for rec in out.split('\x1e'):
        if not rec.strip():
            continue
        sha, when, body = rec.strip('\n').split('\x1f', 2)
        tr = dict(re.findall(r'^(Execute-[A-Za-z]+):\s*(.+?)\s*$', body, re.M))
        if 'Execute-Slice' in tr and tr.get('Execute-Plan') == plan:
            rows.append((sha, when, tr))
    return rows


def fmt_row(label, host, model, minutes, u):
    return (f'{label:14} {host:12} {model:30} {minutes:7} {u.input:>10,} {u.cache:>12,} {u.cache_write:>11,} {u.out:>9,} {u.calls:>6}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--plan', help='plan path as written in the Execute-Plan trailer')
    ap.add_argument('--repo', default='.')
    ap.add_argument('--from', dest='lo', help='window start, ISO 8601 with offset')
    ap.add_argument('--to', dest='hi', help='window end, ISO 8601 with offset')
    ap.add_argument('--match', default='', help='substring of the project (Claude folder, Codex cwd)')
    a = ap.parse_args()
    print(f'{"slice":14} {"host":12} {"model":30} {"minutes":>7} {"input":>10} {"cache":>12} {"cache_wr":>11} {"out":>9} {"calls":>6}')
    if a.plan:
        prev_end = None
        for sha, when, tr in slice_commits(a.repo, a.plan):
            end = parse_iso(when)
            try:
                start = parse_iso(tr.get('Execute-Started', ''))
            except ValueError:
                print(f'{tr["Execute-Slice"]:14} no valid Execute-Started trailer ({sha[:8]}): not measured')
                continue
            minutes = f'{(end - start).total_seconds() / 60:.1f}'
            host = tr.get('Execute-Host', '?').lower()
            totals = collect(start, end, a.match, host if host in ('claude', 'codex', 'antigravity') else None)
            if not totals:
                print(fmt_row(tr['Execute-Slice'][:14], host, tr.get('Execute-Model', '?')[:30], minutes, Usage()) + '  (no usage found)')
            for (h, model), u in sorted(totals.items()):
                print(fmt_row(tr['Execute-Slice'][:14], h, model[:30], minutes, u))
    elif a.lo and a.hi:
        for (h, model), u in sorted(collect(parse_iso(a.lo), parse_iso(a.hi), a.match).items()):
            print(fmt_row('window', h, model[:30], f'{(parse_iso(a.hi) - parse_iso(a.lo)).total_seconds() / 60:.1f}', u))
    else:
        ap.error('pass --plan, or --from and --to')


if __name__ == '__main__':
    sys.exit(main())
