"""Breadth-first search diagnostics, not an in-game solvability guarantee.
Lowercase route letters denote Shift + movement (one-use pull).
"""
import json, pathlib
from pull_solver import solve
root = pathlib.Path(__file__).resolve().parents[1]
solutions = {}
for path in sorted((root/'levels').glob('*.json')):
    data = json.loads(path.read_text())
    charge = int(data.get('pull_charges', 0))
    solution, visited = solve(data, charge)
    print(path.name, 'solution=' + str(solution), 'visited=' + str(visited))
    if path.name.startswith('demo_') and int(path.stem.split('_')[1]) <= 11:
        assert solution is not None, 'Demo must be solvable under its configured rules'
        solutions[path.stem] = solution
        if charge:
            classic, exhausted = solve(data, 0)
            assert classic is None, 'Ability tutorials must require at least one pull'
            print('  Without pull: no solution after exhausting', exhausted, 'states')
print(f'All {len(solutions)} curated demo levels are solvable.')
# V7.9: ids 8-11 added (8 is shown between 5 and 6; see level_catalog.gd ORDER).
assert [len(solutions[f'demo_{n}']) for n in range(1,12)] == [3,10,10,1,18,14,19,14,19,19,31]
# Both tempting opening pulls are legal but exhaust the only charge in a dead state.
for n, delta in [(6,(1,0)),(7,(-1,0)),(9,(1,0))]:
    data=json.loads((root/f'levels/demo_{n}.json').read_text())
    p=tuple(data['player']); behind=(p[0]-delta[0],p[1]-delta[1]); dest=(p[0]+delta[0],p[1]+delta[1])
    assert list(behind) in data['boxes'] and list(dest) not in data['walls']+data['boxes']
    data['boxes'].remove(list(behind));data['boxes'].append(list(p));data['player']=list(dest)
    assert solve(data,0)[0] is None
print('A/B optimal lengths and tempting first-pull deadlocks verified.')

# Lab: the tool-crate maps (12-14) and the control map (15). Each must be solvable in its catalogued
# optimum, and none may be solvable by a bypass: crate never opening, crate opening empty, or one
# fewer starting pull. The control map must need its pull and contain no lab pieces.
lab = {}
for n, optimum in [(12, 8), (13, 35), (14, 28), (15, 18), (16, 24)]:
    data = json.loads((root/f'levels/demo_{n}.json').read_text())
    c = int(data.get('pull_charges', 0))
    route, _ = solve(data, c)
    assert route is not None and len(route) == optimum, (n, route)
    if n != 15:
        assert solve(data, c, opens=False)[0] is None, f'map {n}: solvable without opening the crate'
        assert solve(data, c, gain=0)[0] is None, f'map {n}: solvable when the crate gives nothing'
        if c > 0:
            assert solve(data, c - 1)[0] is None, f'map {n}: solvable with one fewer starting pull'
    else:
        assert 'tool' not in data and 'bench' not in data and solve(data, 0)[0] is None
    lab[n] = route
print('Lab maps verified (optimum, no bypass):', {k: len(v) for k, v in lab.items()})
