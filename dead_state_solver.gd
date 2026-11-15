extends RefCounted
## V7.7: exact solvability under game.gd rules (push + optional pull).
## Walking is collapsed into reachable regions, so a state is (region, cargo boxes, tool crate cell
## or none, charges). The crate blocks like a box, can be pushed or pulled, and opens (disappears,
## +1 charge, never above CHARGE_CAP) the moment it lands on the bench. It never counts toward goals.
##
## Lab 2: every search is a SearchJob that can be stepped in small slices and cancelled, so the game
## never has to wait for it. Cells are integers (y * 7 + x) and box sets are bit masks, which makes
## a state about three times cheaper than the old string keys. Proven results are shared:
## - a finished "dead" search proves every state it visited dead;
## - a "solvable" search proves every state on the path to the solution solvable.
## "unknown" (state cap reached) is never stored as a proof and never turned into "dead".
const W = 7
const H = 6
const DIRS = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
const NONE = Vector2i(-1, -1)
const CHARGE_CAP = 2
var walls: Dictionary
var goals: Dictionary
var bench: Vector2i = NONE
var cache := {}          # state key -> "solvable" / "dead" (proofs only)
var gave_up := {}        # state key -> largest cap that was not enough
var _nb: Array = []      # cell -> [right, left, down, up] neighbour cell, -1 when blocked
var _goal_mask := 0
var _bench_i := -1

func _init(walls_: Dictionary, goals_: Dictionary, bench_: Vector2i = NONE) -> void:
	walls = walls_; goals = goals_; bench = bench_
	_bench_i = _i(bench)
	for g in goals:
		_goal_mask |= 1 << _i(g)
	for i in W * H:
		var p := Vector2i(i % W, i / W)
		var row: Array = []
		for d in DIRS:
			var n: Vector2i = p + d
			row.append(-1 if _blocked(n) else _i(n))
		_nb.append(row)

func _blocked(p: Vector2i) -> bool:
	return p.x < 0 or p.x >= W or p.y < 0 or p.y >= H or walls.has(p)

static func _i(p: Vector2i) -> int:
	return -1 if p.x < 0 else p.y * W + p.x

static func _mask(boxes: Array) -> int:
	var m := 0
	for b in boxes:
		m |= 1 << (b.y * W + b.x)
	return m

## Flood fill from p around the occupied cells. Returns [reach mask, lowest reachable cell].
func _flood(p: int, occ: int) -> Array:
	var reach := 1 << p
	var low := p
	var stack: Array[int] = [p]
	while not stack.is_empty():
		var a: int = stack.pop_back()
		for n in _nb[a]:
			if n >= 0 and (reach >> n) & 1 == 0 and (occ >> n) & 1 == 0:
				reach |= 1 << n
				if n < low: low = n
				stack.append(n)
	return [reach, low]

static func _pack(low: int, boxes: int, c: int, tool: int) -> int:
	return boxes | (low << 42) | (c << 48) | ((tool + 1) << 51)

func _key_of(p: int, boxes: int, c: int, tool: int) -> int:
	var occ := boxes if tool < 0 else boxes | (1 << tool)
	return _pack(_flood(p, occ)[1], boxes, c, tool)

func _done(boxes: int) -> bool:
	return boxes & ~_goal_mask == 0

## Every state one push or pull away: [player cell after the move, box mask, charges, tool cell].
func _next(p: int, boxes: int, c: int, tool: int) -> Array:
	var out: Array = []
	var occ := boxes if tool < 0 else boxes | (1 << tool)
	var reach: int = _flood(p, occ)[0]
	for b in W * H:
		var is_tool := b == tool
		if (boxes >> b) & 1 == 0 and not is_tool:
			continue
		for d in 4:
			var ahead: int = _nb[b][d]
			if ahead < 0 or (occ >> ahead) & 1 == 1:
				continue
			var back: int = _nb[b][d ^ 1]
			if back >= 0 and (reach >> back) & 1 == 1:
				# push: the player stands behind the box and ends on the box's old cell
				out.append(_moved(b, boxes, c, tool, b, ahead, is_tool))
			if c > 0 and (reach >> ahead) & 1 == 1:
				var beyond: int = _nb[ahead][d]
				if beyond >= 0 and (occ >> beyond) & 1 == 0:
					# pull: the player stands on `ahead`, steps to `beyond`, the box follows to `ahead`
					out.append(_moved(beyond, boxes, c - 1, tool, b, ahead, is_tool))
	return out

func _moved(player: int, boxes: int, c: int, tool: int, from: int, to: int, is_tool: bool) -> Array:
	if not is_tool:
		return [player, (boxes & ~(1 << from)) | (1 << to), c, tool]
	if to == _bench_i:
		return [player, boxes, mini(c + 1, CHARGE_CAP), -1]
	return [player, boxes, c, to]

## Returns "solvable", "dead" or "unknown" (state cap reached). Runs to the end in one call.
func status(player: Vector2i, boxes0: Array, charges: int, cap: int = 20000, tool: Vector2i = NONE) -> String:
	var job := start_job(player, boxes0, charges, cap, tool)
	job.step(0)
	return job.result

## The same search in slices: step(budget) until it returns true, cancel() at any time.
func start_job(player: Vector2i, boxes0: Array, charges: int, cap: int = 20000, tool: Vector2i = NONE) -> SearchJob:
	return SearchJob.new(self, _i(player), _mask(boxes0), charges, cap, _i(tool))

class SearchJob:
	extends RefCounted
	var solver
	var queue: Array = []        # [player, boxes, charges, tool]
	var keys: Array[int] = []    # state key per queue entry
	var parents: Array[int] = [] # queue index of the state it came from
	var seen := {}
	var index := 0
	var cap := 0
	var expanded := 0            # states expanded so far (tests and budgets use it)
	var result := ""   # "" while running, then "solvable" / "dead" / "unknown" / "canceled"

	func _init(solver_, player: int, boxes0: int, charges: int, cap_: int, tool: int) -> void:
		solver = solver_
		cap = cap_
		var k: int = solver._key_of(player, boxes0, charges, tool)
		if solver.cache.has(k):
			result = solver.cache[k]
			return
		if int(solver.gave_up.get(k, 0)) >= cap:
			result = "unknown"
			return
		queue.append([player, boxes0, charges, tool])
		keys.append(k)
		parents.append(-1)
		seen[k] = true

	func cancel() -> void:
		if result.is_empty():
			result = "canceled"

	func _prove_path(i: int) -> void:
		while i >= 0:
			solver.cache[keys[i]] = "solvable"
			i = parents[i]

	## Works for at most budget_usec microseconds (0 = no time limit) and at most max_states
	## expansions (0 = no limit). Returns true when finished.
	func step(budget_usec: int, max_states: int = 0) -> bool:
		if not result.is_empty():
			return true
		var t0 = Time.get_ticks_usec()
		var done_here := 0
		while index < queue.size():
			if seen.size() > cap:
				result = "unknown"
				solver.gave_up[keys[0]] = maxi(cap, int(solver.gave_up.get(keys[0], 0)))
				return true
			var s: Array = queue[index]
			if solver._done(s[1]):
				result = "solvable"
				_prove_path(index)
				return true
			for n in solver._next(s[0], s[1], s[2], s[3]):
				var k: int = solver._key_of(n[0], n[1], n[2], n[3])
				if seen.has(k):
					continue
				var known = solver.cache.get(k, "")
				if known == "solvable":
					result = "solvable"
					_prove_path(index)
					return true
				seen[k] = true
				if known == "dead":
					continue   # proven: nothing useful beyond it
				queue.append(n); keys.append(k); parents.append(index)
			index += 1
			expanded += 1
			done_here += 1
			if max_states > 0 and done_here >= max_states:
				return false
			if budget_usec > 0 and Time.get_ticks_usec() - t0 >= budget_usec:
				return false
		result = "dead"
		for k in keys:
			solver.cache[k] = "dead"
		return true
