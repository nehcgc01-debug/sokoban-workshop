import itertools, json, sys, time
from metrics import *
BASE = ["#######", "# K@# #", "#     #", "##   .#", "##$T  #", "#######"]
def grid(rows): return [list(r) for r in rows]
def rows_of(g): return [''.join(r) for r in g]
def edits(g):
    """all single edits: toggle an inner wall, or move one of player / bench / goal to another inner free cell"""
    out = []
    cells = [(x, y) for y in range(1, 5) for x in range(1, 6)]
    for (x, y) in cells:
        if g[y][x] == '#': out.append(('open', x, y))
        elif g[y][x] == ' ': out.append(('wall', x, y))
    for ch in '@K.':
        for (x, y) in cells:
            if g[y][x] == ' ': out.append(('move' + ch, x, y))
    return out
def apply(g, e):
    g = [r[:] for r in g]; kind, x, y = e
    if kind == 'open': g[y][x] = ' '
    elif kind == 'wall': g[y][x] = '#'
    else:
        ch = kind[-1]
        for r in g:
            for i, c in enumerate(r):
                if c == ch: r[i] = ' '
        if g[y][x] != ' ': return None
        g[y][x] = ch
    return g
def core_ok(d, a):
    if a is None: return False
    k = a['kinds']
    if 'toolpull' not in k or 'open' not in k or 'pull' not in k: return False
    if not (k.index('toolpull') < k.index('open') < k.index('pull')): return False
    if any(bypass(d).values()): return False
    if a['decisive_moves_by_kind'].get('pull', 0) < 1: return False   # the tempting wrong pull must exist
    return True
seen = set(); results = []
base = grid(BASE); t0 = time.time()
level1 = [apply(base, e) for e in edits(base)]
level1 = [g for g in level1 if g]
cands = list(level1)
for g1 in level1:
    for e in edits(g1):
        g2 = apply(g1, e)
        if g2: cands.append(g2)
for g in cands:
    key = tuple(rows_of(g))
    if key in seen: continue
    seen.add(key)
    d = parse(rows_of(g), 1)
    a = analyse(d)
    if core_ok(d, a):
        results.append((a['optimal_moves'], a['walk_steps'], a['fewest_box_moves'], a['shortest_move_sequences'], a['box_move_sequences_at_fewest'], a['solvable_states'], a['reachable_states'], key, a['route'], a['decisive_moves_by_kind']))
results.sort()
print(len(seen), 'variants,', len(results), 'keep the core;', round(time.time() - t0), 's')
for r in results[:25]: print(r[:7], r[8], r[9]); print('   ' + ' / '.join(r[7]))
json.dump(results, open('t2_variants.json', 'w'))
