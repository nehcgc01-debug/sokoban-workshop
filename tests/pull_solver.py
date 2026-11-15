"""Exhaustive state-space check: demos 4/5 require optional one-use pull.
Lab: also models the tool crate (pushed or pulled onto the bench it opens: it disappears and gives
+gain pulls, never above CAP). gain=0 models "the crate opens but gives nothing" (bypass check);
opens=False models a crate that never opens (it is just an obstacle)."""
import json
from collections import deque
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DIRS = {'R':(1,0),'L':(-1,0),'U':(0,-1),'D':(0,1)}
CAP = 2
def solve(data, charge, gain=1, opens=True):
 walls=set(map(tuple,data['walls'])); goals=set(map(tuple,data['goals']))
 tool0=tuple(data['tool']) if data.get('tool') and data['tool'][0]>=0 else None
 bench=tuple(data['bench']) if data.get('bench') and data['bench'][0]>=0 else None
 start=(tuple(data['player']),tuple(sorted(map(tuple,data['boxes']))),charge,tool0)
 q=deque([(start,'')]); seen={start}
 def block(p):return not (0<=p[0]<7 and 0<=p[1]<6) or p in walls
 def land(t,c):
  if opens and t==bench: return None,min(c+gain,CAP)
  return t,c
 while q:
  (p,b,c,t),route=q.popleft()
  if set(b)==goals:return route,len(seen)
  for letter,(dx,dy) in DIRS.items():
   n=(p[0]+dx,p[1]+dy)
   if block(n):continue
   nb=set(b); nt=t; nc=c
   nn=(n[0]+dx,n[1]+dy)
   if n in nb:
    if not block(nn) and nn not in nb and nn!=t:
     nb.remove(n);nb.add(nn)
    else:continue
   elif n==t:
    if not block(nn) and nn not in nb:
     nt,nc=land(nn,c)
    else:continue
   state=(n,tuple(sorted(nb)),nc,nt)
   if state not in seen:seen.add(state);q.append((state,route+letter))
  if c:
   for letter,(dx,dy) in DIRS.items():
    n=(p[0]+dx,p[1]+dy);behind=(p[0]-dx,p[1]-dy)
    if block(n) or n in b or n==t:continue
    if behind in b:
     nb=set(b);nb.remove(behind);nb.add(p);nt,nc=t,c-1
    elif behind==t:
     nb=set(b);nt,nc=land(p,c-1)
    else:continue
    state=(n,tuple(sorted(nb)),nc,nt)
    if state not in seen:seen.add(state);q.append((state,route+letter.lower()))
 return None,len(seen)
if __name__=='__main__':
 for n in [4,5]:
  data=json.loads((ROOT/f'levels/demo_{n}.json').read_text())
  no,count=solve(data,0);yes,with_count=solve(data,1)
  assert no is None and yes is not None
  print(f'Demo {n}: no-pull exhausts {count} states; one-pull solution {yes}, visited {with_count}')
