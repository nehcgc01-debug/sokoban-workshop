import sys, json
from collections import deque
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parents[2] / 'tests'))
import pull_solver as PS
from functools import lru_cache
def analyse(n):
    d = json.load(open(__import__('pathlib').Path(__file__).resolve().parents[2] / f'levels/demo_{n}.json'))
    walls = set(map(tuple, d['walls'])); goals = set(map(tuple, d['goals']))
    tool0 = tuple(d['tool']) if d.get('tool') else None
    bench = tuple(d['bench']) if d.get('bench') else None
    def block(p): return not (0 <= p[0] < 7 and 0 <= p[1] < 6) or p in walls
    def moves(st):
        p, b, c, t = st
        out = []
        for L, (dx, dy) in PS.DIRS.items():
            n1 = (p[0]+dx, p[1]+dy); n2 = (n1[0]+dx, n1[1]+dy)
            if block(n1): continue
            if n1 in b:
                if block(n2) or n2 in b or n2 == t: continue
                nb = tuple(sorted((set(b) - {n1}) | {n2})); out.append((L, (n1, nb, c, t), 'push'))
            elif n1 == t:
                if block(n2) or n2 in b: continue
                if n2 == bench: out.append((L, (n1, b, min(c+1, 2), None), 'waste' if c == 2 else 'open'))
                else: out.append((L, (n1, b, c, n2), 'toolpush'))
            else: out.append((L, (n1, b, c, t), 'walk'))
        if c:
            for L, (dx, dy) in PS.DIRS.items():
                n1 = (p[0]+dx, p[1]+dy); bh = (p[0]-dx, p[1]-dy)
                if block(n1) or n1 in b or n1 == t: continue
                if bh in b:
                    nb = tuple(sorted((set(b) - {bh}) | {p})); out.append((L.lower(), (n1, nb, c-1, t), 'pull'))
                elif bh == t:
                    if p == bench: out.append((L.lower(), (n1, b, c, None), 'pullopen'))
                    else: out.append((L.lower(), (n1, b, c-1, p), 'toolpull'))
        return out
    @lru_cache(None)
    def ok(st):
        p, b, c, t = st
        dd = dict(d); dd['player'] = list(p); dd['boxes'] = [list(x) for x in b]
        dd['tool'] = list(t) if t else None
        return PS.solve(dd, c)[0] is not None
    start = (tuple(d['player']), tuple(sorted(map(tuple, d['boxes']))), d['pull_charges'], tool0)
    q = deque([(start, '')]); seen = {start}; found = {}
    while q:
        st, r = q.popleft()
        if not ok(st): continue
        for L, ns, kind in moves(st):
            if not ok(ns) and kind not in found and kind != 'walk':
                found[kind] = r + L
            if ns not in seen: seen.add(ns); q.append((ns, r + L))
    print(n, found)
for n in [int(x) for x in sys.argv[1:]]: analyse(n)
