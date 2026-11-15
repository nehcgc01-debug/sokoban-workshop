"""Lab: every reachable state of the lab maps with the ground-truth answer (solvable or not), from an
independent move-level BFS with the same rules as pull_solver.py. Writes lab_dead_fixture.json.
Rows: [px, py, [[bx, by], ...], charges, tx, ty, solvable] with tx = ty = -1 once the crate is open."""
import json, pathlib
from collections import deque
ROOT = pathlib.Path(__file__).resolve().parents[1]
DIRS = [(1,0),(-1,0),(0,1),(0,-1)]
CAP = 2
def graph(data):
    walls=set(map(tuple,data['walls'])); goals=set(map(tuple,data['goals']))
    tool0=tuple(data['tool']) if data.get('tool') else None
    bench=tuple(data['bench']) if data.get('bench') else None
    block=lambda p: not (0<=p[0]<7 and 0<=p[1]<6) or p in walls
    def land(t,c): return (None,min(c+1,CAP)) if t==bench else (t,c)
    start=(tuple(data['player']),tuple(sorted(map(tuple,data['boxes']))),int(data.get('pull_charges',0)),tool0)
    seen={start}; q=deque([start]); edges={}
    while q:
        s=q.popleft(); p,b,c,t=s; out=[]
        for dx,dy in DIRS:
            n=(p[0]+dx,p[1]+dy); nn=(n[0]+dx,n[1]+dy)
            if block(n): continue
            nb=set(b); nt,nc=t,c
            if n in nb:
                if block(nn) or nn in nb or nn==t: continue
                nb.remove(n); nb.add(nn)
            elif n==t:
                if block(nn) or nn in nb: continue
                nt,nc=land(nn,c)
            out.append((n,tuple(sorted(nb)),nc,nt))
            if c:
                behind=(p[0]-dx,p[1]-dy)
                if n in b or n==t: continue
                if behind in b:
                    nb=set(b); nb.remove(behind); nb.add(p); out.append((n,tuple(sorted(nb)),c-1,t))
                elif behind==t:
                    nt,nc=land(p,c-1); out.append((n,b,nc,nt))
        edges[s]=out
        for o in out:
            if o not in seen: seen.add(o); q.append(o)
    rev={}
    for s,os in edges.items():
        for o in os: rev.setdefault(o,[]).append(s)
    good={s for s in seen if set(s[1])==goals}; q=deque(good)
    while q:
        o=q.popleft()
        for s in rev.get(o,[]):
            if s not in good: good.add(s); q.append(s)
    return seen, good
out={}
for n in [12,13,14,15]:
    path=ROOT/f'levels/demo_{n}.json'
    if not path.exists(): continue
    seen,good=graph(json.loads(path.read_text()))
    out[str(n)]=[[s[0][0],s[0][1],[list(b) for b in s[1]],s[2],(s[3] or (-1,-1))[0],(s[3] or (-1,-1))[1],1 if s in good else 0] for s in sorted(seen,key=str)]
    print(n,'states',len(seen),'solvable',len(good))
(ROOT/'tests/lab_dead_fixture.json').write_text(json.dumps(out))
