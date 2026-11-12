# Version 3: game identity and one bounded mechanic

## Intent
A small warm workshop puzzle game, with authored introductory puzzles and an editor. The menu presents a character and board vignette rather than an instructional dashboard. The original three puzzles remain standard Sokoban.

## One-use pull
New puzzles optionally grant one pull charge. Hold Shift and press a direction to step into a free cell while pulling the box immediately behind you into your previous cell. A wall, another box, missing rear box or exhausted charge rejects the action without spending it. Undo restores position and charge; restart restores the original allowance.

This is not an originality claim: push/pull puzzles are an established genre technique. Here its purpose is a small, explicit resource decision: where to spend the one opportunity to recover a box that cannot be pushed from its initial position. Two levels introduce and combine the rule. The editor exposes the rule as an optional checkbox; older maps default to no charge.

## Limits
No claim of commercial-product completeness. Limited puzzle count, no bespoke soundtrack, no native Windows runtime verification in this Linux environment. Automated and actual Web-export tests are documented separately.

## V4 art direction refinement
The user's rough crate sketch is the style reference: an inked outline, warm wood, front cross-brace, visible top and side. Crate, floor and wall assets are original code-native SVG artwork made for this project, not the user's sketch pasted over the board. The board stays orthogonal and the slight drawn depth is purely visual: no movement/collision rules change. UI panels move from cool navy to warm charcoal/brown so the editor, play scene and menu feel related. The generated character remains replaceable at `art/player.png` without changing game logic.
