"""Exhaustive state-space check: demos 4/5 require optional one-use pull."""
import json
from collections import deque
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
DIRS = {'R':(1,0),'L':(-1,0),'U':(0,-1),'D':(0,1)}
def solve(data, charge):
 walls=set(map(tuple,data['walls'])); goals=set(map(tuple,data['goals']))
 start=(tuple(data['player']),tuple(sorted(map(tuple,data['boxes']))),charge)
 q=deque([(start,'')]); seen={start}
 def block(p):return not (0<=p[0]<7 and 0<=p[1]<6) or p in walls
 while q:
  (p,b,c),route=q.popleft()
  if set(b)==goals:return route,len(seen)
  for letter,(dx,dy) in DIRS.items():
   n=(p[0]+dx,p[1]+dy)
   if block(n):continue
   nb=set(b)
   if n in nb:
    nn=(n[0]+dx,n[1]+dy)
    if not block(nn) and nn not in nb:
     nb.remove(n);nb.add(nn)
    else:continue
   state=(n,tuple(sorted(nb)),c)
   if state not in seen:seen.add(state);q.append((state,route+letter))
  if c:
   for letter,(dx,dy) in DIRS.items():
    n=(p[0]+dx,p[1]+dy);behind=(p[0]-dx,p[1]-dy)
    if block(n) or n in b or behind not in b:continue
    nb=set(b);nb.remove(behind);nb.add(p)
    state=(n,tuple(sorted(nb)),c-1)
    if state not in seen:seen.add(state);q.append((state,route+letter.lower()))
 return None,len(seen)
if __name__=='__main__':
 for n in [4,5]:
  data=json.loads((ROOT/f'levels/demo_{n}.json').read_text())
  no,count=solve(data,0);yes,with_count=solve(data,1)
  assert no is None and yes is not None
  print(f'Demo {n}: no-pull exhausts {count} states; one-pull solution {yes}, visited {with_count}')
