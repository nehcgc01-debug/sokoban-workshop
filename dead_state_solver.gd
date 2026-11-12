extends RefCounted
## V7.7: exact solvability under game.gd rules (push + optional pull), used for built-in maps.
## Walking is collapsed into reachable regions, so states = (region, boxes, charges). Results are cached.
const W = 7
const H = 6
const DIRS = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
var walls: Dictionary
var goals: Dictionary
var cache := {}

func _init(walls_: Dictionary, goals_: Dictionary) -> void:
	walls = walls_; goals = goals_

func _blocked(p: Vector2i) -> bool:
	return p.x < 0 or p.x >= W or p.y < 0 or p.y >= H or walls.has(p)

func _region(p: Vector2i, bset: Dictionary) -> Dictionary:
	var seen := {p: true}
	var q: Array[Vector2i] = [p]
	var i := 0
	while i < q.size():
		var a := q[i]; i += 1
		for d in DIRS:
			var n: Vector2i = a + d
			if not seen.has(n) and not _blocked(n) and not bset.has(n):
				seen[n] = true; q.append(n)
	return seen

func _key(reg: Dictionary, boxes: Array, c: int) -> String:
	var m := 999
	for p in reg: m = mini(m, p.y * W + p.x)
	var bs: Array = []
	for b in boxes: bs.append(b.y * W + b.x)
	bs.sort()
	return "%d|%s|%d" % [m, str(bs), c]

func _bset(boxes: Array) -> Dictionary:
	var s := {}
	for b in boxes: s[b] = true
	return s

## Returns "solvable", "dead" or "unknown" (state cap reached).
func status(player: Vector2i, boxes0: Array, charges: int, cap: int = 20000) -> String:
	var k0 := _key(_region(player, _bset(boxes0)), boxes0, charges)
	if cache.has(k0):
		return cache[k0]
	var q: Array = [[player, boxes0, charges]]
	var seen := {k0: true}
	var i := 0
	var result := "dead"
	while i < q.size():
		if seen.size() > cap:
			result = "unknown"; break
		var s: Array = q[i]; i += 1
		var boxes: Array = s[1]; var c: int = s[2]
		var done := true
		for b in boxes:
			if not goals.has(b): done = false; break
		if done:
			result = "solvable"; break
		var bset := _bset(boxes)
		var reg := _region(s[0], bset)
		for bi in boxes.size():
			var b: Vector2i = boxes[bi]
			for d in DIRS:
				if reg.has(b - d) and not _blocked(b + d) and not bset.has(b + d):
					var nb := boxes.duplicate(); nb[bi] = b + d
					_enqueue(q, seen, b, nb, c)
				if c > 0 and reg.has(b + d) and not _blocked(b + d * 2) and not bset.has(b + d * 2):
					var nb2 := boxes.duplicate(); nb2[bi] = b + d
					_enqueue(q, seen, b + d * 2, nb2, c - 1)
	cache[k0] = result
	return result

func _enqueue(q: Array, seen: Dictionary, p: Vector2i, nb: Array, c: int) -> void:
	var k := _key(_region(p, _bset(nb)), nb, c)
	if not seen.has(k):
		seen[k] = true; q.append([p, nb, c])
