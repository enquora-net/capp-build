#!/usr/bin/env python3
"""Grep-derived ground truth for capp-build phase 6 symbol-table counts.

Mirrors the pipeline's file set (phase 2: *.j/*.sj, skipping Frameworks,
Build, .cappuccino case-insensitively) and the table's counting rules:
every textual declaration counts, including those inside #if branches
(both branches are recorded, condition-tagged).

Counted independently of the compiler:
  classes (primary), categories, protocols, @class forwards, @typedef,
  @global, explicit method definitions inside @implementation blocks,
  protocol method declarations (required/optional via ordered markers),
  ivar field definitions, @accessors directives, and the expected
  synthesized-accessor count (2 per directive, minus readonly, minus
  collisions with explicit instance methods of the same class block).
"""
import os, re, sys
from collections import defaultdict

SKIP = {"frameworks", "build", ".cappuccino"}

def strip_comments(src):
    out = []; i = 0; n = len(src); state = None; quote = ''
    while i < n:
        c = src[i]; nxt = src[i+1] if i+1 < n else ''
        if state is None:
            if c == '/' and nxt == '/': state = 'line'; i += 2; continue
            if c == '/' and nxt == '*': state = 'block'; i += 2; continue
            if c in ('"', "'"): state = 'str'; quote = c; out.append(' '); i += 1; continue
            out.append(c); i += 1; continue
        if state == 'line':
            if c == '\n': state = None; out.append('\n')
            i += 1; continue
        if state == 'block':
            if c == '*' and nxt == '/': state = None; i += 2; continue
            if c == '\n': out.append('\n')
            i += 1; continue
        if state == 'str':
            if c == '\\': i += 2; continue
            if c == quote: state = None; out.append(' '); i += 1; continue
            if c == '\n': state = None; out.append('\n'); i += 1; continue
            i += 1; continue
    return ''.join(out)

IMPL_RE  = re.compile(r'^\s*@implementation\s+(\w+)\s*(?::\s*(\w+))?\s*(?:\(\s*(\w+)\s*\))?', re.M)
PROTO_RE = re.compile(r'^\s*@protocol\s+(\w+)(?!\s*\()')
FWD_RE   = re.compile(r'^\s*@class\s+(.+?)\s*$')
TYPEDEF_RE = re.compile(r'^\s*@typedef\s+(\w+)')
GLOBAL_RE  = re.compile(r'^\s*@global\s+(\w+)')
METHOD_RE  = re.compile(r'^\s*([-+])\s*\(')
ACCESSORS_RE = re.compile(r'@accessors(?:\s*\(([^)]*)\))?')

def method_selector(lines, idx):
    # join continuation lines until '{' or ';' or blank
    buf = lines[idx]
    j = idx + 1
    while j < len(lines) and '{' not in buf and ';' not in buf and lines[j].strip() and not lines[j].lstrip().startswith(('-', '+', '@', '#', '/')):
        buf += ' ' + lines[j].strip(); j += 1
    sig = buf.split('{')[0].split(';')[0]
    sig = re.sub(r'^\s*[-+]\s*', '', sig)
    sig = re.sub(r'^\([^)]*\)\s*', '', sig)          # return type
    parts = re.findall(r'([A-Za-z_]\w*)\s*:', re.sub(r'\([^)]*\)', '', sig))
    if parts and ':' in sig:
        return ''.join(p + ':' for p in parts)
    m = re.match(r'\s*([A-Za-z_]\w*)', sig)
    return m.group(1) if m else '?'

def default_setter(prop):
    pre, stem = ('', prop)
    if prop.startswith('_'): pre, stem = '_', prop[1:]
    if not stem: return pre + 'set:'
    return f"{pre}set{stem[0].upper()}{stem[1:]}:"

def scan_corpus(root):
    stats = defaultdict(int)
    class_names = []
    per_class = {}
    anomalies = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d.lower() not in SKIP]
        for fn in sorted(filenames):
            if not fn.lower().endswith(('.j', '.sj')): continue
            stats['files'] += 1
            src = strip_comments(open(os.path.join(dirpath, fn), errors='replace').read())
            lines = src.split('\n')
            ctx = None        # None | ('impl', name) | ('proto', name)
            proto_required = True
            ivar_block = False; ivar_depth = 0; impl_line = -1
            cur = None
            for i, raw in enumerate(lines):
                line = raw
                m = IMPL_RE.match(line)
                if m and ctx is None:
                    name, sup, cat = m.groups()
                    key = f"{name}({cat})" if cat else name
                    stats['categories' if cat else 'classes'] += 1
                    if re.search(r'(?<![\w@])@end\b', line):
                        continue  # one-line implementation; nothing inside to scan
                    ctx = ('impl', key); impl_line = i
                    cur = per_class.setdefault(key, {'methods': 0, 'ivars': 0,
                        'accessors': [], 'explicit_instance': set(), 'file': os.path.relpath(os.path.join(dirpath, fn), root)})
                    # ivar block opens at first '{' before any member
                    ivar_block = False; ivar_depth = 0
                    continue
                if ctx and re.search(r'(?<![\w@])@end\b', line):
                    ctx = None; cur = None; proto_required = True; ivar_block = False
                    continue
                pm = PROTO_RE.match(line)
                if pm and ctx is None:
                    stats['protocols'] += 1; ctx = ('proto', pm.group(1)); proto_required = True
                    continue
                if ctx is None:
                    fm = FWD_RE.match(line)
                    if fm and line.strip().startswith('@class'):
                        stats['forwards'] += len([x for x in re.split(r'[,\s]+', fm.group(1).rstrip(';')) if x])
                        continue
                if TYPEDEF_RE.match(line): stats['typedefs'] += 1; continue
                if GLOBAL_RE.match(line): stats['globals'] += 1; continue
                if ctx and ctx[0] == 'proto':
                    s = line.strip()
                    if s.startswith('@optional'): proto_required = False; continue
                    if s.startswith('@required'): proto_required = True; continue
                    if METHOD_RE.match(line):
                        stats['proto_required' if proto_required else 'proto_optional'] += 1
                    continue
                if ctx and ctx[0] == 'impl':
                    s = line.strip()
                    # ivar block: a '{' before the first member
                    if not ivar_block and cur['methods'] == 0 and s.startswith('{') and ivar_depth == 0 and not METHOD_RE.match(line):
                        ivar_block = True; ivar_depth = 1
                        rest = s[1:]
                        if rest.count(';'): pass
                        continue
                    if ivar_block:
                        ivar_depth += s.count('{') - s.count('}')
                        if ivar_depth <= 0:
                            ivar_block = False; continue
                        if s.startswith('#') or s.startswith('@private') or s.startswith('@protected') or s.startswith('@public') or s.startswith('@package'):
                            continue
                        n_semis = s.count(';')
                        if n_semis:
                            stats['ivars'] += n_semis; cur['ivars'] += n_semis
                            for am in ACCESSORS_RE.finditer(s):
                                # ivar name: identifier before @accessors
                                nm = re.findall(r'([A-Za-z_]\w*)\s*@accessors', s)
                                ivar_name = nm[-1] if nm else '?'
                                cur['accessors'].append((ivar_name, am.group(1) or ''))
                                stats['accessors'] += 1
                        continue
                    if METHOD_RE.match(line):
                        stats['methods'] += 1; cur['methods'] += 1
                        sel = method_selector(lines, i)
                        if line.lstrip().startswith('-'):
                            cur['explicit_instance'].add(sel)
                        continue
            if ctx is not None:
                anomalies.append(f"unterminated {ctx} in {fn}")
    # synthesized expectation
    synth = 0; collisions = []
    for key, c in per_class.items():
        occupied = set(c['explicit_instance'])
        for ivar_name, attrs in c['accessors']:
            spec = {'property': ivar_name, 'getter': None, 'setter': None, 'readonly': False}
            for part in [p.strip() for p in attrs.split(',') if p.strip()]:
                if part == 'readonly': spec['readonly'] = True
                elif '=' in part:
                    k, v = [x.strip() for x in part.split('=', 1)]
                    if k in ('property', 'getter', 'setter'): spec[k] = v
            getter = spec['getter'] or spec['property']
            if getter in occupied: collisions.append((key, getter))
            else: occupied.add(getter); synth += 1
            if not spec['readonly']:
                setter = spec['setter'] or default_setter(spec['property'])
                if setter in occupied: collisions.append((key, setter))
                else: occupied.add(setter); synth += 1
    stats['synthesized_expected'] = synth
    return stats, collisions, anomalies

for corpus in sys.argv[1:]:
    stats, collisions, anomalies = scan_corpus(corpus)
    print(f"== {corpus}")
    order = ['files','classes','categories','protocols','forwards','typedefs','globals',
             'methods','synthesized_expected','proto_required','proto_optional','ivars','accessors']
    print('   ' + '  '.join(f"{k}={stats[k]}" for k in order))
    if collisions: print(f"   accessor collisions (explicit method wins): {len(collisions)}")
    for c in collisions[:8]: print(f"     {c[0]}: {c[1]}")
    for a in anomalies: print("   ANOMALY:", a)
