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
    if path.name.startswith('demo_'):
        assert solution is not None, 'Demo must be solvable under its configured rules'
        solutions[path.stem] = solution
        if charge:
            classic, exhausted = solve(data, 0)
            assert classic is None, 'Ability tutorials must require at least one pull'
            print('  Without pull: no solution after exhausting', exhausted, 'states')
print(f'All {len(solutions)} curated demo levels are solvable.')
assert [len(solutions[f'demo_{n}']) for n in range(1,8)] == [3,10,10,1,18,14,19]
# Both tempting opening pulls are legal but exhaust the only charge in a dead state.
for n, delta in [(6,(1,0)),(7,(-1,0))]:
    data=json.loads((root/f'levels/demo_{n}.json').read_text())
    p=tuple(data['player']); behind=(p[0]-delta[0],p[1]-delta[1]); dest=(p[0]+delta[0],p[1]+delta[1])
    assert list(behind) in data['boxes'] and list(dest) not in data['walls']+data['boxes']
    data['boxes'].remove(list(behind));data['boxes'].append(list(p));data['player']=list(dest)
    assert solve(data,0)[0] is None
print('A/B optimal lengths and tempting first-pull deadlocks verified.')
