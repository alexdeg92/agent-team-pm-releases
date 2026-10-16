#!/usr/bin/env python3
"""Token and model audit for a herdr agent team. Runtime-agnostic core, with one collector per agent CLI.

For every live agent pane:
  - it finds the agent's session log (the process whose environment says HERDR_PANE_ID=<pane>, then the session
    file that process holds open, then a per-collector fallback);
  - it reads the model, effort, turns and token usage (input / cached / output / reasoning), the context fill,
    the provider rate-limit window, and the biggest input contributors (tool outputs by tool);
  - it flags spending that doesn't make sense.

Usage:  agent-usage.py [--json] [--agent NAME] [--top 5]
Adding a CLI = adding one Collector subclass to COLLECTORS. Nothing else changes.
Prints numbers and tool names only. It never prints prompt or output content (logs can hold secrets).
"""
import json, os, re, subprocess, sys, glob, time, argparse
from collections import defaultdict

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout

def herdr_agents():
    try:
        return json.loads(sh('herdr', 'agent', 'list'))['result']['agents']
    except Exception:
        return []

def pane_processes():
    """pane_id -> list of (pid, cmdline, open session files), read from /proc (Linux)."""
    out = defaultdict(list)
    for pid in filter(str.isdigit, os.listdir('/proc')):
        try:
            env = open(f'/proc/{pid}/environ', 'rb').read().split(b'\0')
        except Exception:
            continue
        pane = next((e[14:].decode() for e in env if e.startswith(b'HERDR_PANE_ID=')), None)
        if not pane:
            continue
        files = []
        try:
            for fd in os.listdir(f'/proc/{pid}/fd'):
                try:
                    t = os.readlink(f'/proc/{pid}/fd/{fd}')
                except OSError:
                    continue
                if t.endswith(('.jsonl', '.db', '.sqlite')):
                    files.append(t)
        except Exception:
            pass
        cmd = open(f'/proc/{pid}/cmdline', 'rb').read().replace(b'\0', b' ').decode(errors='replace')
        out[pane].append((pid, cmd, files))
    return out

class Usage(dict):
    def __init__(self, **kw):
        super().__init__(model=None, effort=None, turns=0, input=0, cached=0, output=0, reasoning=0,
                         last_input=0, context_window=None, limit_used_pct=None, limit_window_min=None,
                         started=None, last=None, tool_bytes={}, tool_calls={}, source=None, note=None)
        self.update(kw)

class Collector:
    kind = None
    def matches(self, agent_kind, cmd): return agent_kind == self.kind
    def session_file(self, procs, agent): return None
    def read(self, path): return Usage(source=path, note='no usage data for this CLI yet')

class Codex(Collector):
    kind = 'codex'
    def session_file(self, procs, agent):
        for _, _, files in procs:
            for f in files:
                if '/.codex/sessions/' in f and f.endswith('.jsonl'):
                    return f
    def read(self, path):
        u = Usage(source=path); tb = defaultdict(int); tc = defaultdict(int); names = {}
        with open(path, 'rb') as fh:
            for raw in fh:
                # Skip huge inline image lines cheaply: they are only counted as tool output bytes.
                try:
                    o = json.loads(raw)
                except Exception:
                    continue
                ts = o.get('timestamp'); u['started'] = u['started'] or ts; u['last'] = ts or u['last']
                t = o.get('type'); p = o.get('payload') or {}
                if t == 'turn_context':
                    u['model'] = p.get('model') or u['model']; u['effort'] = p.get('effort') or u['effort']
                    u['prompts'] = u.get('prompts', 0) + 1
                elif t == 'event_msg' and p.get('type') == 'token_count':
                    u['turns'] += 1
                    info = p.get('info') or {}
                    tot = info.get('total_token_usage') or {}
                    if tot:
                        u['input'] = tot.get('input_tokens', 0); u['cached'] = tot.get('cached_input_tokens', 0)
                        u['output'] = tot.get('output_tokens', 0); u['reasoning'] = tot.get('reasoning_output_tokens', 0)
                    last = info.get('last_token_usage') or {}
                    u['last_input'] = last.get('input_tokens', u['last_input'])
                    u['context_window'] = info.get('model_context_window') or u['context_window']
                    prim = ((p.get('rate_limits') or {}).get('primary') or {})
                    if prim:
                        u['limit_used_pct'] = prim.get('used_percent'); u['limit_window_min'] = prim.get('window_minutes')
                elif t == 'response_item':
                    pt = p.get('type', '')
                    if pt in ('function_call', 'custom_tool_call'):
                        n = p.get('name') or '?'
                        arg = str(p.get('arguments') or p.get('input') or '')
                        inner = re.findall(r'tools\.(\w+)\(', arg)          # code-mode wrapper: tools.<name>(…)
                        if inner: n = inner[0]
                        m = re.search(r'["\']?(?:cmd|command)["\']?\s*:\s*\[?\s*["\']([^"\']+)', arg)
                        if m:
                            cmd = re.sub(r'^(?:\s*(?:cd \S+|set -\w+|export \S+|pwd)\s*(?:&&|;)\s*)+', '', m.group(1)).strip()
                            w = re.match(r'[\w./-]+', cmd)
                            if w: n = f'{n}:{os.path.basename(w.group(0))}'
                        names[p.get('call_id')] = n; tc[n] += 1
                    elif pt.endswith('_output'):
                        n = names.get(p.get('call_id'), '?'); tb[n] += len(raw)
        u['tool_bytes'] = dict(tb); u['tool_calls'] = dict(tc)
        return u

class Claude(Collector):
    kind = 'claude'
    def session_file(self, procs, agent):
        cwd = agent.get('cwd') or ''
        slug = re.sub(r'[^A-Za-z0-9]', '-', cwd)
        files = sorted(glob.glob(os.path.expanduser(f'~/.claude/projects/{slug}/*.jsonl')), key=os.path.getmtime)
        return files[-1] if files else None
    def read(self, path):
        u = Usage(source=path); tb = defaultdict(int); tc = defaultdict(int); names = {}
        with open(path, 'rb') as fh:
            for raw in fh:
                try:
                    o = json.loads(raw)
                except Exception:
                    continue
                ts = o.get('timestamp'); u['started'] = u['started'] or ts; u['last'] = ts or u['last']
                msg = o.get('message') or {}
                if o.get('type') == 'assistant' and isinstance(msg, dict):
                    us = msg.get('usage') or {}
                    if us:
                        u['turns'] += 1
                        u['model'] = msg.get('model') or u['model']
                        fresh = us.get('input_tokens', 0) + us.get('cache_creation_input_tokens', 0)
                        cr = us.get('cache_read_input_tokens', 0)
                        u['input'] += fresh + cr; u['cached'] += cr; u['output'] += us.get('output_tokens', 0)
                        u['last_input'] = fresh + cr
                    for c in msg.get('content') or []:
                        if isinstance(c, dict) and c.get('type') == 'tool_use':
                            names[c.get('id')] = c.get('name'); tc[c.get('name')] += 1
                elif o.get('type') == 'user' and isinstance(msg, dict):
                    for c in msg.get('content') or [] if isinstance(msg.get('content'), list) else []:
                        if isinstance(c, dict) and c.get('type') == 'tool_result':
                            tb[names.get(c.get('tool_use_id'), '?')] += len(json.dumps(c.get('content')))
        u['tool_bytes'] = dict(tb); u['tool_calls'] = dict(tc)
        return u

class Cursor(Collector):
    kind = 'cursor'
    def session_file(self, procs, agent):
        for _, _, files in procs:
            for f in files:
                if '/.cursor/' in f:
                    return f
    def read(self, path):
        return Usage(source=path, note='Cursor keeps usage server-side; check the Cursor dashboard')

COLLECTORS = [Codex(), Claude(), Cursor()]
# Known context windows when the log doesn't record one (model-id prefix → tokens). Unknown means no context-fill flag.
CONTEXT_WINDOWS = {'claude-opus-5': 1_000_000, 'claude-sonnet-5': 1_000_000, 'claude-haiku-5': 200_000}

# ---- judgement: thresholds are explicit so the PM can tune them ----
ROUTINE = re.compile(r'(rename|relay|status|watch|copy|format|sync|bump|lint)', re.I)
HEAVY = re.compile(r'(architect|security|critic|review|integrat|backend|onboarding|engine|art|character|image)', re.I)
TOP_EFFORT = {'high', 'xhigh', 'max'}

def flags(u, agent):
    f = []
    inp = u['input'] or 0; cached = u['cached'] or 0; turns = max(u['turns'], 1)
    fresh = inp - cached
    cache_pct = 100 * cached / inp if inp else None
    if u['context_window'] and u['last_input'] and u['last_input'] > 0.7 * u['context_window']:
        f.append(f"context {100*u['last_input']//u['context_window']}% full: start a fresh session for the next task (each turn re-reads it)")
    if cache_pct is not None and inp > 2_000_000 and cache_pct < 60:
        f.append(f'low cache reuse ({cache_pct:.0f}%): restarts or a changing prompt prefix; batch instructions, avoid re-sending big briefs')
    tb = u['tool_bytes'] or {}
    total_tb = sum(tb.values())
    if total_tb:
        top, b = max(tb.items(), key=lambda kv: kv[1])
        if b > 0.5 * total_tb and b > 20_000_000:
            f.append(f'{top} returned {b/1e6:.0f} MB of tool output ({100*b//total_tb}%): read narrower slices, summarize, avoid dumping images or logs into context')
    if u['reasoning'] and u['output'] and u['reasoning'] > 6 * u['output'] and u['reasoning'] > 500_000:
        f.append('reasoning ≫ visible output: the effort may be too high for this work, or it is looping')
    title = (agent.get('terminal_title_stripped') or '') + ' ' + (agent.get('name') or '')
    if u['effort'] in TOP_EFFORT and ROUTINE.search(title) and not HEAVY.search(title):
        f.append(f"effort '{u['effort']}' on routine work: use a lower effort or a cheaper model")
    if u['effort'] and u['effort'] not in TOP_EFFORT and HEAVY.search(title):
        f.append(f"effort '{u['effort']}' on critical or creative work: under-powered, raise it")
    if u['last_input'] and u['last_input'] > 300_000:
        f.append(f"each model call re-reads {u['last_input']/1e3:.0f}k tokens: hand off to a fresh session or compact before the next big task")
    if fresh / turns > 50_000:
        f.append(f'{fresh/turns/1e3:.0f}k uncached input tokens per call: big tool outputs or a changing prefix')
    if u['limit_used_pct'] is not None and u['limit_used_pct'] >= 80:
        f.append(f"provider window {u['limit_used_pct']:.0f}% used: throttle this kind, move work to another provider")
    return f, cache_pct

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--json', action='store_true'); ap.add_argument('--agent'); ap.add_argument('--top', type=int, default=4)
    a = ap.parse_args()
    if not os.path.isdir('/proc'):
        message = 'agent-usage: unsupported platform: requires Linux /proc; on macOS check provider dashboards and CLI usage/status for plan headroom'
        if a.json:
            print(json.dumps({'error': 'unsupported_platform', 'message': message}))
        else:
            print(message, file=sys.stderr)
        return 2
    procs = pane_processes(); rows = []
    for ag in herdr_agents():
        name = ag.get('name') or ag.get('terminal_title_stripped') or ag.get('pane_id')
        if a.agent and a.agent != name:
            continue
        col = next((c for c in COLLECTORS if c.matches(ag.get('agent'), '')), None)
        if not col:
            rows.append({'agent': name, 'kind': ag.get('agent'), 'note': 'no collector for this CLI'}); continue
        path = col.session_file(procs.get(ag['pane_id'], []), ag)
        if not path:
            rows.append({'agent': name, 'kind': ag.get('agent'), 'note': 'session log not found'}); continue
        u = col.read(path)
        if not u['context_window'] and u['model']:
            u['context_window'] = next((v for k, v in CONTEXT_WINDOWS.items() if u['model'].startswith(k)), None)
        fl, cache_pct = flags(u, ag)
        top = sorted((u['tool_bytes'] or {}).items(), key=lambda kv: -kv[1])[:a.top]
        rows.append({'agent': name, 'kind': ag.get('agent'), 'status': ag.get('agent_status'), 'model': u['model'], 'effort': u['effort'],
                     'calls': u['turns'], 'prompts': u.get('prompts'), 'input': u['input'], 'cached': u['cached'], 'cache_pct': cache_pct, 'output': u['output'],
                     'reasoning': u['reasoning'], 'context_pct': (100 * u['last_input'] / u['context_window']) if u['context_window'] and u['last_input'] else None,
                     'limit_used_pct': u['limit_used_pct'], 'limit_window_min': u['limit_window_min'], 'started': u['started'], 'last': u['last'],
                     'top_tool_output_mb': [(k, round(v / 1e6, 1)) for k, v in top], 'flags': fl, 'note': u['note']})
    if a.json:
        print(json.dumps(rows, indent=1)); return
    M = lambda n: '-' if n is None else (f'{n/1e6:.1f}M' if n >= 1e6 else f'{n/1e3:.0f}k')
    print(f"{'agent':16} {'model/effort':22} {'calls':>5} {'input':>8} {'cache%':>6} {'output':>7} {'reason':>7} {'ctx%':>5}")
    for r in rows:
        if 'calls' not in r:
            print(f"{r['agent']:16} {r.get('kind') or '':22} {r['note']}"); continue
        me = f"{r['model'] or '?'}/{r['effort'] or '-'}"
        cp = '-' if r['cache_pct'] is None else f"{r['cache_pct']:.0f}"
        cx = '-' if r['context_pct'] is None else f"{r['context_pct']:.0f}"
        print(f"{r['agent']:16} {me[:22]:22} {r['calls']:>5} {M(r['input']):>8} {cp:>6} {M(r['output']):>7} {M(r['reasoning']):>7} {cx:>5}")
        if r['top_tool_output_mb']:
            print(' ' * 17 + 'top tool output (log MB): ' + ', '.join(f'{k} {v} MB' for k, v in r['top_tool_output_mb']))
        for fl in r['flags']:
            print(' ' * 17 + '⚠ ' + fl)
        if r['note']:
            print(' ' * 17 + r['note'])
    lim = {(r['kind'], r['limit_used_pct'], r['limit_window_min']) for r in rows if r.get('limit_used_pct') is not None}
    for k, p, w in lim:
        print(f"provider window: {k} {p:.0f}% used of {w // 1440 if w else '?'}-day window")

if __name__ == '__main__':
    sys.exit(main())
