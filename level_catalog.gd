extends RefCounted
# Append only: progress keys for existing maps stay stable.
const NAMES = ["01  第一推", "02  双箱入位", "03  转身留路", "04  牵引初试", "05  回身取箱", "06  留一步余地", "07  恰当时机"]
const COUNT = 7
# V7.7: fewest-move solutions, verified by tests/solve_levels.py (BFS over moves).
const OPTIMAL = [3, 10, 10, 1, 18, 14, 19]
# V7.7: workshop work-order context, one short line per map (no story, only situation).
const ORDERS = [
	"工单 01 · 门口一只木箱挡着路，送回光圈。",
	"工单 02 · 两只箱子并排卸货，一起推回去。",
	"工单 03 · 墙边空间窄，推之前先给自己留路。",
	"工单 04 · 箱子贴死了墙，推不动——那就拉。",
	"工单 05 · 两只箱子，一次牵引，先看清谁更需要它。",
	"工单 06 · 两只箱子，两处光圈，牵引只够用一次。",
	"工单 07 · 左上角的光圈位置刁钻，别急着动手。",
]
# V7.7: one sentence naming the convention the player just broke (only maps that break one).
const INSIGHTS = {
	4: "顿悟：贴墙的箱子能拉出来。",
	6: "顿悟：角落也可以是计划。",
	7: "顿悟：有的光圈只能拉进去。",
}

static func chapter(index: int) -> String:
	return "挑战篇" if index >= 6 else "入门篇"
