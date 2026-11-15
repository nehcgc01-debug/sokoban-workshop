extends RefCounted
## V7.9: a level's id is its file (levels/demo_<id>.json) and its progress key. Ids never change,
## so new maps can be inserted anywhere in ORDER without moving anyone's best records.
## Optimal = fewest moves, verified by tests/solve_levels.py and tests/dead_state_tests.gd.
const LEVELS = {
	1: {"title": "第一推", "chapter": "入门篇", "optimal": 3, "order": "工单 · 门口一只木箱挡着路，送回光圈。"},
	2: {"title": "双箱入位", "chapter": "入门篇", "optimal": 10, "order": "工单 · 两只箱子并排卸货，一起推回去。"},
	3: {"title": "转身留路", "chapter": "入门篇", "optimal": 10, "order": "工单 · 墙边空间窄，推之前先给自己留路。"},
	4: {"title": "牵引初试", "chapter": "牵引篇", "optimal": 1, "order": "工单 · 箱子贴死了墙，推不动——那就拉。",
		"insight": "顿悟：贴墙的箱子能拉出来。"},
	5: {"title": "回身取箱", "chapter": "牵引篇", "optimal": 18, "order": "工单 · 两只箱子，一次牵引，先看清谁更需要它。",
		"guide": "两只箱子，牵引只有一次。\n先看看：哪只箱子从任何方向都推不动？",
		"insight": "顿悟：墙角的箱子，可以拉出来。",
		"hints": ["左边那只箱子卡在墙角，四个方向都推不动。", "你开局就站在它右边：牵引能把它拉出墙角。", "第一步 Shift + → 拉出左箱；左箱送左下光圈，右箱送左上光圈。"]},
	8: {"title": "角落再拉", "chapter": "牵引篇", "optimal": 14, "order": "工单 · 只有一只箱子，但光圈的位置很别扭。",
		"insight": "顿悟：先推进角落，再拉出来。",
		"hints": ["这个光圈从哪个方向都推不进去。", "牵引时你后退一步，身后的箱子会跟到你原来站的位置。", "先把箱子推进左上角，再站到它下面往下拉。"]},
	6: {"title": "留一步余地", "chapter": "挑战篇", "optimal": 14, "order": "工单 · 两只箱子，两处光圈，牵引只够用一次。",
		"insight": "顿悟：牵引留给最需要的箱子。",
		"hints": ["先别急着牵引，观察两个箱子的去路。", "有些暂时推不动的位置，牵引能救回。", "先安置下箱，再用牵引救上箱。"]},
	7: {"title": "恰当时机", "chapter": "挑战篇", "optimal": 19, "order": "工单 · 左上角的光圈位置刁钻，别急着动手。",
		"insight": "顿悟：牵引早一步晚一步都不行。",
		"hints": ["先给另一个箱子留出通道。", "先安排下方箱子，再考虑上方目标。", "上箱到顶行后，从左边试着拉。"]},
	9: {"title": "让出一面", "chapter": "挑战篇", "optimal": 19, "order": "工单 · 有只箱子卡在窄槽里，它的另一面你够不着。",
		"insight": "顿悟：够不着的一面，就拉过来。",
		"hints": ["先想清楚哪只箱子先回家。", "有一面推不到的箱子，可以先拉出来。", "槽里箱子先上推一格；下箱进左下光圈后，从左边把槽箱拉出来。"]},
	10: {"title": "三箱归位", "chapter": "挑战篇", "optimal": 19, "order": "工单 · 三只箱子挤在墙角，先救哪一只？",
		"insight": "顿悟：拉回中间，就又能推了。",
		"hints": ["三只箱子里，有一只迟早会被推到左墙边。", "贴着左墙的箱子，可以用牵引拉回中间。", "先送好上、中两只，再把左墙边那只拉回中间，绕到左边往右推。"]},
	11: {"title": "最后一拉", "chapter": "挑战篇", "optimal": 31, "order": "工单 · 三只箱子，三处光圈，今晚最长的一单。",
		"insight": "顿悟：最难的那只，最后再动。",
		"hints": ["三只箱子里，有一只注定要被推进墙角。", "牵引留到最后，用来救那只进了墙角的箱子。", "最后站在右上箱子左边往左拉一格，再绕过去推进光圈。"]},
	# ---- Lab (experimental build only): tool crate chapter and a no-new-rule control level ----
	12: {"title": "开箱取绳", "code": "T1", "chapter": "工具篇 · 实验", "optimal": 8,
		"order": "工单 · 这关开局没有牵引。红绳工具箱里装着一根。",
		"guide": "开局牵引 0 次。\n工具箱推上工作台，牵引 +1。\n再把贴墙的箱子拉出来。",
		"insight": "顿悟：开箱，多一次牵引。",
		"stages": [
			{"id": "open", "when": {"open": true},
				"guide": "牵引 +1 到手，工具箱用完就没了。\n站到贴墙箱子的右边，\nShift + → 把它拉出来。"}],
		"ask": "小满：灯油箱贴着墙，我拉不动。送到门灯底下，灯就能点上。",
		"fixture": {"kind": "lamp", "cell": [2, 2], "name": "门灯", "keeps": "门灯从此亮着"},
		"thanks": "小满：门灯亮了，晚归的人看得见路。"},
	13: {"title": "绳子在箱里", "code": "T2", "chapter": "工具篇 · 实验", "optimal": 35,
		"order": "工单 · 角落的货箱要一次牵引，工具箱也挡在旁边。",
		"guide": "牵引 1 次，箱里还有 1 次。\n工具箱也能推、也能拉。\n每次牵引花在谁身上？",
		"insight": "顿悟：先拉工具箱，它会还你一次。",
		"hints": ["货箱在墙角，需要一次牵引；工具箱推不上工作台，也需要一次。", "工具箱贴着货箱和下墙，只有先拉出来才推得动。", "先在工具箱上方往上拉，再推上工作台；最后拉墙角的货箱。"],
		"stages": [
			{"id": "out", "when": {"open": true, "box_at": [2, 3]},
				"guide": "货箱出了墙角，牵引也用完了。\n它左边是墙，还不能往右推。",
				"hints": ["货箱左边是墙：站不到它左边，就没法往右推。", "先把它挪到左边能站人的格子，再往右推。", "往上推一格、往右推一格、往下推一格，再一路往右推进光圈。"]},
			{"id": "carry", "when": {"open": true, "no_box_at": [2, 4]},
				"guide": "货箱在路上了，牵引已经用完。\n只用推，把它送进贴着右墙的光圈。",
				"hints": ["牵引用完了：别把货箱推进墙角或贴到墙边。", "光圈贴着右墙，货箱最后要从左边往右推进去。", "让货箱进到光圈那一行、左边又能站人，再一路往右推。"]},
			{"id": "open", "when": {"open": true},
				"guide": "工具箱还了你 1 次牵引。\n现在轮到墙角的货箱。",
				"hints": ["牵引回来了 1 次，墙角的货箱还在等。", "货箱贴着左墙和下墙：只能站到它上面往上拉。", "往上拉出货箱，再绕开左边的墙，一路往右推进光圈。"]},
			{"id": "used_a", "when": {"open": false, "tool_at": [3, 3]},
				"guide": "牵引用掉了，工具箱能推了。\n把它送上左上角的工作台。",
				"hints": ["工具箱已经离开下墙，四面都能站人了。", "工作台在左上角：工具箱最后要从正下方推上去。", "工具箱先往上推一格、往左推一格，再往上推进工作台。"]},
			{"id": "used", "when": {"open": false, "tool_home": false},
				"guide": "牵引用掉了，工具箱能推了。\n把它送上左上角的工作台。",
				"hints": ["工具箱已经离开下墙，四面都能站人了。", "工作台在左上角：工具箱最后要停在它正下方，再往上推。", "牵引用完了：别把工具箱推到贴墙的格子里。"]}],
		"ask": "老周：炭箱卡在墙角了。送到炉子边上，我好把火生起来。",
		"fixture": {"kind": "stove", "cell": [6, 3], "name": "炉子", "keeps": "炉火从此不灭"},
		"thanks": "老周：炉子又旺了，过来烤烤手。"},
	14: {"title": "满载出发", "code": "T3", "chapter": "工具篇 · 实验", "optimal": 28,
		"order": "工单 · 开局就带满两次牵引，工具箱紧挨着工作台。",
		"guide": "开局牵引 2 次，已是上限。\n工具箱就在工作台下面。\n现在开箱，绳子放得下吗？",
		"insight": "顿悟：满了别开，先用掉一次。",
		"hints": ["牵引最多存 2 次，你现在已经满了。", "满的时候开箱，绳子没地方放；这关一共要用 3 次牵引。", "第一步走到货箱右边往右拉；然后再把工具箱往上推进工作台。"],
		"stages": [
			{"id": "top", "when": {"open": true, "box_at": [3, 1]},
				"guide": "货箱到了工作台那一格，\n光圈就在它右边。",
				"hints": ["货箱已经在顶上那一行了。", "它右边就是光圈，可这一行站不到它左边。", "绕到光圈右边，按住 Shift 往右拉。"]},
			{"id": "top_right", "when": {"open": true, "box_at": [5, 1]},
				"guide": "货箱进了顶上那一行，\n在光圈右边。",
				"hints": ["货箱已经在顶上那一行，就在光圈右边。", "它右边是墙，没法往左推。", "站到光圈上，按住 Shift 往左拉。"]},
			{"id": "open", "when": {"open": true},
				"guide": "工具箱开了，工作台现在能走过去。\n把货箱送进右上的光圈。",
				"hints": ["光圈在顶上那一行，货箱得先上去。", "往上那一步推不了：要站到货箱上面那一格，往上拉。", "把货箱送到工作台那一格，绕到光圈右边，往右拉进光圈。"]},
			{"id": "used", "when": {"open": false, "pulls_min": 1},
				"guide": "牵引剩 1 次，腾出了一个空位。\n现在开箱，补上的那次放得下。",
				"hints": ["牵引不满了：现在开箱，补上的那次不会浪费。", "工具箱就在工作台正下方，从下面往上推。", "开箱后牵引回到 2 次：货箱还要再拉两回才进得了光圈。"]}],
		"ask": "阿婆：茶叶箱送到茶壶底下，我给夜班烧壶热茶。",
		"fixture": {"kind": "kettle", "cell": [4, 0], "name": "茶壶", "keeps": "茶壶从此温着"},
		"thanks": "阿婆：水开了，给你留了一杯。"},
	15: {"title": "推不下去", "code": "C1", "chapter": "对照 · 实验", "optimal": 18,
		"order": "工单 · 没有工具箱。上面那只箱子没卡住，却推不下去。",
		"guide": "对照关，没有新规则。\n上面那只箱子要去哪一行？",
		"insight": "顿悟：没卡住，也可能要拉。",
		"hints": ["上面那只箱子要往下走一行，才能去右边的光圈。", "这一行站不到它上方：缺口只能从箱子那格进去。", "先把它推到右边缺口的正下方，再站到它下面往下拉。"],
		"stages": [
			{"id": "pulled", "when": {"pulls_min": 1, "box_at": [4, 3], "no_box_at": [4, 4]},
				"guide": "上面那只箱子下来了，牵引也用完了。\n剩下两只都只用推。",
				"hints": ["牵引已经用完：两只箱子都只能推了。", "刚拉下来的箱子，右边就是光圈。", "站到它左边往右推一格；再把下面那只一路往右推。"]},
			{"id": "pulled_one", "when": {"pulls_min": 1, "box_at": [4, 3]},
				"guide": "上面那只箱子下来了，牵引也用完了。\n它右边就是光圈。",
				"hints": ["下面那只已经到位，只剩刚拉下来的这只。", "它右边就是光圈。", "站到它左边，往右推一格。"]},
			{"id": "last", "when": {"pulls_min": 1, "box_at": [5, 3]},
				"guide": "右边的光圈满了。\n把下面那只箱子推进最后一个光圈。",
				"hints": ["只剩下面那只箱子。", "它和最后一个光圈在同一行，只差往右推。", "绕到它左边，一路往右推进光圈。"]},
			],
		"ask": "小满：两箱旧棉垫挪到猫窝旁边，猫就肯回窝睡了。",
		"fixture": {"kind": "cat", "cell": [5, 4], "name": "猫窝", "keeps": "猫从此睡在这儿"},
		"thanks": "小满：它睡着了。走路轻一点。"},
	# Lab 2: a shorter candidate for T2 (only the goal moved). Same first decision, 24 moves instead
	# of 35. It sits beside T2 for comparison; it is not part of the T1 -> C1 chain and has no fixture.
	16: {"title": "短程对照", "code": "T2b", "chapter": "工具篇 · 实验", "optimal": 24,
		"order": "工单 · T2 的短程对照版：同一个决定，光圈近了一些。",
		"guide": "牵引 1 次，箱里还有 1 次。\n工具箱也能推、也能拉。\n每次牵引花在谁身上？",
		"insight": "顿悟：先拉工具箱，它会还你一次。",
		"hints": ["货箱在墙角，需要一次牵引；工具箱推不上工作台，也需要一次。", "工具箱贴着货箱和下墙，只有先拉出来才推得动。", "先在工具箱上方往上拉，再推上工作台；最后把墙角的货箱拉出来。"],
		"stages": [
			{"id": "out", "when": {"open": true, "box_at": [3, 4]},
				"guide": "货箱出了墙角，牵引也用完了。\n它和光圈在同一行。",
				"hints": ["货箱和光圈在同一行，只差往右推。", "货箱左边那一格空出来了，从那里推。", "绕到货箱左边，一路往右推进光圈。"]},
			{"id": "carry", "when": {"open": true, "no_box_at": [2, 4]},
				"guide": "货箱在路上了，牵引已经用完。\n只用推，把它送进右下角的光圈。",
				"hints": ["牵引用完了：别把货箱推进墙角或贴到墙边。", "光圈在右下角，货箱最后要从左边或上面推进去。", "货箱进了最下面一行就从左边推；在最右一列就从上面推。"]},
			{"id": "open", "when": {"open": true},
				"guide": "工具箱还了你 1 次牵引。\n现在轮到墙角的货箱。",
				"hints": ["牵引回来了 1 次，墙角的货箱还在等。", "货箱和光圈在同一行：把它从墙角里拉出来。", "站到货箱右边往右拉一格，再绕到它左边一路往右推。"]},
			{"id": "used_a", "when": {"open": false, "tool_at": [3, 3]},
				"guide": "牵引用掉了，工具箱能推了。\n把它送上左上角的工作台。",
				"hints": ["工具箱已经离开下墙，四面都能站人了。", "工作台在左上角：工具箱最后要从正下方推上去。", "工具箱先往上推一格、往左推一格，再往上推进工作台。"]},
			{"id": "used", "when": {"open": false, "tool_home": false},
				"guide": "牵引用掉了，工具箱能推了。\n把它送上左上角的工作台。",
				"hints": ["工具箱已经离开下墙，四面都能站人了。", "工作台在左上角：工具箱最后要停在它正下方，再往上推。", "牵引用完了：别把工具箱推到贴墙的格子里。"]}]},
}
## Display / play order. Append-only ids; reordering is safe for saves.
const ORDER = [1, 2, 3, 4, 5, 8, 6, 7, 9, 10, 11]
const COUNT = 11
## Lab: extra work orders shown in their own section. They never count toward the 11-map night,
## its ending or the menu counter; they are played T1 -> T2 -> T3 -> C1.
const LAB_ORDER = [12, 13, 14, 15]
## Lab 2: comparison candidates shown after the lab orders. Playable and recorded, but outside the
## chain: finishing one returns to the menu.
const LAB_EXTRA = [16]

static func has_level(id: int) -> bool:
	return LEVELS.has(id)

static func is_lab(id: int) -> bool:
	return LAB_ORDER.has(id) or LAB_EXTRA.has(id)

static func position(id: int) -> int:
	if LAB_EXTRA.has(id):
		return COUNT + LAB_ORDER.size() + LAB_EXTRA.find(id) + 1
	if is_lab(id):
		return COUNT + LAB_ORDER.find(id) + 1
	return ORDER.find(id) + 1

## Short label on cards and work orders: "05" for the night's maps, "T1" / "C1" for lab maps.
static func code(id: int) -> String:
	return String(LEVELS[id]["code"]) if is_lab(id) else "%02d" % position(id)

static func level_title(id: int) -> String:
	return ("实验 %s · %s" % [code(id), LEVELS[id]["title"]]) if is_lab(id) else ("第 %d 关 · %s" % [position(id), LEVELS[id]["title"]])

static func next_id(id: int) -> int:
	if LAB_EXTRA.has(id):
		return 0
	var list = LAB_ORDER if is_lab(id) else ORDER
	var p = list.find(id)
	return list[p + 1] if p >= 0 and p + 1 < list.size() else 0

## Lab 3: guide and hints follow the board. A level may list "stages", each with a "when" made of
## facts about the current state; the first stage whose facts all hold wins, otherwise the level's
## start text is used. Facts (all optional):
##   open: bool (the crate has been opened)   tool_home: bool (the crate is on its start cell)
##   tool_at / box_at / no_box_at: [x, y]      pulls_min: int (pulls made in this attempt)
## Texts must only say what every state matching the stage makes true; tests/lab3_tests.gd checks
## that over every solvable state of every lab map.
static func stage_for(id: int, facts: Dictionary) -> String:
	if not LEVELS.has(id):
		return ""
	for st in LEVELS[id].get("stages", []):
		if _stage_matches(st["when"], facts):
			return String(st["id"])
	return ""

static func _cell(v) -> Vector2i:
	return Vector2i(int(v[0]), int(v[1]))

static func _stage_matches(when: Dictionary, f: Dictionary) -> bool:
	for k in when:
		var v = when[k]
		match k:
			"open":
				if bool(f["open"]) != bool(v): return false
			"tool_home":
				if bool(f["tool_home"]) != bool(v): return false
			"tool_at":
				if f["tool"] != _cell(v): return false
			"box_at":
				if not f["boxes"].has(_cell(v)): return false
			"no_box_at":
				if f["boxes"].has(_cell(v)): return false
			"pulls_min":
				if int(f["pulls"]) < int(v): return false
			_:
				return false   # an unknown fact never matches (a typo cannot make a text show)
	return true

static func _stage(id: int, stage: String) -> Dictionary:
	if stage.is_empty() or not LEVELS.has(id):
		return {}
	for st in LEVELS[id].get("stages", []):
		if String(st["id"]) == stage:
			return st
	return {}

static func guide(id: int, stage: String = "") -> String:
	if not LEVELS.has(id):
		return ""
	return String(_stage(id, stage).get("guide", LEVELS[id].get("guide", "")))

## Lab 2: a work order can come from someone. ask = who needs what (shown before and during play),
## fixture = the thing in the wall next to the goal that reacts when the boxes are home,
## thanks = one line shown beside the board after the win. All optional.
static func ask(id: int) -> String:
	return String(LEVELS[id].get("ask", "")) if LEVELS.has(id) else ""

static func thanks(id: int) -> String:
	return String(LEVELS[id].get("thanks", "")) if LEVELS.has(id) else ""

static func fixture(id: int) -> Dictionary:
	return LEVELS[id].get("fixture", {}) if LEVELS.has(id) else {}

## Orders whose fixture appears in the rest corner on the main menu, in display order.
static func corner_ids() -> Array:
	var out = []
	for id in LAB_ORDER:
		if not fixture(id).is_empty():
			out.append(id)
	return out

static func last_id() -> int:
	return ORDER[ORDER.size() - 1]

static func is_last(id: int) -> bool:
	return id == last_id()

static func display_name(id: int) -> String:
	return "%s  %s" % [code(id), LEVELS[id]["title"]]

static func chapter(id: int) -> String:
	return LEVELS[id]["chapter"] if LEVELS.has(id) else ""

static func optimal(id: int) -> int:
	return int(LEVELS[id]["optimal"])

static func order_text(id: int) -> String:
	# Lab 3: lab maps say "实验委托", so they are never read as part of the 11 main-line orders.
	if not ask(id).is_empty():
		return "实验委托 %s · %s" % [code(id), ask(id)]
	if is_lab(id):
		return "实验委托 %s · " % code(id) + String(LEVELS[id]["order"]).trim_prefix("工单 · ")
	return "工单 %s · " % code(id) + String(LEVELS[id]["order"]).trim_prefix("工单 · ")

static func insight(id: int) -> String:
	return String(LEVELS[id].get("insight", ""))

static func hints(id: int, stage: String = "") -> Array:
	if not LEVELS.has(id):
		return []
	return _stage(id, stage).get("hints", LEVELS[id].get("hints", []))

static func chapter_summary() -> String:
	var parts = []
	var current = ""
	var start = 1
	for i in ORDER.size():
		var c = chapter(ORDER[i])
		if c != current:
			if current != "":
				parts.append("%02d–%02d %s" % [start, i, current])
			current = c
			start = i + 1
	parts.append("%02d–%02d %s" % [start, ORDER.size(), current])
	return "  ·  ".join(parts)
