"""Level metrics for the lab maps. Independent of the game code (pure Python BFS on single moves).
A state is (player, boxes, charges, crate). Rules as in game.gd: push, pull (costs 1), crate opens on
the bench (+1, cap 2), crate never counts toward goals."""
import json, sys
from collections import deque
DIRS = {'R': (1, 0), 'L': (-1, 0), 'U': (0, -1), 'D': (0, 1)}
CAP = 2
def parse(rows, charges):
    d = {'walls': [], 'goals': [], 'boxes': [], 'player': None, 'pull_charges': charges, 'tool': None, 'bench': None}
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == '#': d['walls'].append((x, y))
            if ch in '.*+': d['goals'].append((x, y))
            if ch in '$*': d['boxes'].append((x, y))
            if ch in '@+': d['player'] = (x, y)
            if ch == 'T': d['tool'] = (x, y)
            if ch == 'K': d['bench'] = (x, y)
    return d
def load(path):
    j = json.load(open(path))
    return {'walls': [tuple(p) for p in j['walls']], 'goals': [tuple(p) for p in j['goals']], 'boxes': [tuple(p) for p in j['boxes']],
            'player': tuple(j['player']), 'pull_charges': j.get('pull_charges', 0),
            'tool': tuple(j['tool']) if j.get('tool') else None, 'bench': tuple(j['bench']) if j.get('bench') else None}
class Level:
    def __init__(s, d, charges=None, gain=1, opens=True):
        s.walls = set(d['walls']); s.goals = frozenset(d['goals']); s.bench = d['bench'] if opens else None
        s.gain = gain
        s.start = (d['player'], tuple(sorted(d['boxes'])), d['pull_charges'] if charges is None else charges, d['tool'])
    def block(s, p): return not (0 <= p[0] < 7 and 0 <= p[1] < 6) or p in s.walls
    def done(s, st): return frozenset(st[1]) == s.goals
    def moves(s, st):
        """yields (letter, next_state, kind); kind: walk / push / toolpush / open / waste / pull / toolpull / pullopen"""
        p, b, c, t = st
        for L, (dx, dy) in DIRS.items():
            n1 = (p[0]+dx, p[1]+dy); n2 = (n1[0]+dx, n1[1]+dy)
            if s.block(n1): continue
            if n1 in b:
                if s.block(n2) or n2 in b or n2 == t: continue
                yield L, (n1, tuple(sorted((set(b) - {n1}) | {n2})), c, t), 'push'
            elif n1 == t:
                if s.block(n2) or n2 in b: continue
                if n2 == s.bench: yield L, (n1, b, min(c + s.gain, CAP), None), ('waste' if c + s.gain > CAP else 'open')
                else: yield L, (n1, b, c, n2), 'toolpush'
            else: yield L, (n1, b, c, t), 'walk'
        if c:
            for L, (dx, dy) in DIRS.items():
                n1 = (p[0]+dx, p[1]+dy); bh = (p[0]-dx, p[1]-dy)
                if s.block(n1) or n1 in b or n1 == t: continue
                if bh in b: yield L.lower(), (n1, tuple(sorted((set(b) - {bh}) | {p})), c - 1, t), 'pull'
                elif bh == t:
                    if p == s.bench: yield L.lower(), (n1, b, min(c - 1 + s.gain, CAP), None), 'pullopen'
                    else: yield L.lower(), (n1, b, c - 1, p), 'toolpull'
    def explore(s):
        """BFS from the start. Returns dist, and the forward graph."""
        dist = {s.start: 0}; q = deque([s.start]); graph = {}
        while q:
            st = q.popleft(); out = []
            if not s.done(st):
                for L, ns, kind in s.moves(st):
                    out.append((L, ns, kind))
                    if ns not in dist: dist[ns] = dist[st] + 1; q.append(ns)
            graph[st] = out
        return dist, graph
def analyse(d, name=''):
    lv = Level(d); dist, graph = lv.explore()
    goals = [st for st in dist if lv.done(st)]
    if not goals: return None
    best = min(dist[g] for g in goals)
    # solvable set (backward closure)
    rev = {}
    for st, out in graph.items():
        for L, ns, kind in out: rev.setdefault(ns, []).append(st)
    ok = set(goals); q = deque(goals)
    while q:
        x = q.popleft()
        for pr in rev.get(x, []):
            if pr not in ok: ok.add(pr); q.append(pr)
    # (a) number of shortest move sequences, and one of them
    ways = {lv.start: 1}; order = sorted(dist, key=dist.get)
    for st in order:
        for L, ns, kind in graph[st]:
            if dist[ns] == dist[st] + 1: ways[ns] = ways.get(ns, 0) + ways.get(st, 0)
    shortest = sum(ways[g] for g in goals if dist[g] == best)
    # one shortest route + its box moves
    par = {lv.start: None}; q = deque([lv.start])
    while q:
        st = q.popleft()
        for L, ns, kind in graph[st]:
            if ns not in par: par[ns] = (st, L, kind); q.append(ns)
    g = next(x for x in goals if dist[x] == best); route = []; kinds = []
    while par[g]: st, L, kind = par[g]; route.append(L); kinds.append(kind); g = st
    route = ''.join(reversed(route)); kinds = list(reversed(kinds))
    box_moves = [k for k in kinds if k != 'walk']
    # (b) fewest box moves (pushes + pulls, crate included) and how many different box-move sequences reach that
    INF = 10**9; cost = {lv.start: 0}; dq = deque([lv.start])
    while dq:   # 0-1 BFS: walking is free
        st = dq.popleft()
        for L, ns, kind in graph[st]:
            w = 0 if kind == 'walk' else 1
            if cost[st] + w < cost.get(ns, INF):
                cost[ns] = cost[st] + w
                (dq.appendleft if w == 0 else dq.append)(ns)
    least_box = min(cost[g] for g in goals)
    def sig(st): return (st[1], st[2], st[3])      # box layout without the player
    # distinct sequences of box layouts along minimal-box-move solutions
    layer = {(lv.start,)}; seqs = None
    frontier = {(sig(lv.start),): {lv.start}}
    for step in range(least_box):
        nxt = {}
        for seq, states in frontier.items():
            # close under free walking
            closed = set(states); stack = list(states)
            while stack:
                st = stack.pop()
                for L, ns, kind in graph[st]:
                    if kind == 'walk' and ns not in closed: closed.add(ns); stack.append(ns)
            for st in closed:
                if cost[st] != step: continue
                for L, ns, kind in graph[st]:
                    if kind != 'walk' and cost.get(ns) == step + 1 and ns in ok:
                        nxt.setdefault(seq + (sig(ns),), set()).add(ns)
        frontier = nxt
    box_seqs = sum(1 for seq, states in frontier.items() if any(lv.done(st) for st in states))
    # traps: decisive moves (solvable -> dead) by kind, and the earliest one
    traps = {}
    for st in ok:
        for L, ns, kind in graph[st]:
            if ns not in ok and kind != 'walk': traps[kind] = traps.get(kind, 0) + 1
    return {'name': name, 'optimal_moves': best, 'box_moves_in_that_route': len(box_moves), 'walk_steps': best - len(box_moves),
            'route': route, 'kinds': box_moves, 'shortest_move_sequences': shortest, 'fewest_box_moves': least_box,
            'box_move_sequences_at_fewest': box_seqs, 'reachable_states': len(dist), 'solvable_states': len(ok), 'decisive_moves_by_kind': traps}
def bypass(d):
    out = {}
    out['crate_never_opens'] = any(Level(d, opens=False).done(st) for st in Level(d, opens=False).explore()[0]) if d['tool'] else None
    out['crate_gives_nothing'] = any(Level(d, gain=0).done(st) for st in Level(d, gain=0).explore()[0]) if d['tool'] else None
    if d['pull_charges'] > 0:
        l = Level(d, charges=d['pull_charges'] - 1); out['one_pull_fewer'] = any(l.done(st) for st in l.explore()[0])
    return out
if __name__ == '__main__':
    for n in sys.argv[1:]:
        d = load(str(__import__('pathlib').Path(__file__).resolve().parents[2] / f'levels/demo_{n}.json'))
        a = analyse(d, n); print(json.dumps(a, ensure_ascii=False)); print('  bypass solvable?', bypass(d))
