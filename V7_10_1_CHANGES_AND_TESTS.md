# V7.10.1 · Progress record section-order fix

This is an independent copy of V7.10. No GitHub repository or real user save was changed.

## Change
- Reject progress entries before the `[builtin]` section header. Godot would otherwise parse them into an empty section and silently omit those best-move records.
- Existing malformed files are not overwritten by `record()`. The existing integrity check preserves the original bytes under an unused `.corrupt` name and tells the player.
- Normal old seven-level records, stable IDs, eleven-level additions, Windows CRLF, empty files and empty sections retain their previous behavior.
- No gameplay, map, sharing format or editor behavior changes.

## Regression coverage
The new `tests/progress_order_tests.gd` adds 12 assertions covering rejection, whitespace variants, write refusal, exact-byte preservation, visible recovery notice, archival, old-record compatibility, addition of new level records, normal serialization and CRLF.

## Verification
- Linux / Godot 4.6.3: full 414 assertions across 25 suites passed; all 11 curated levels passed the solver.
- Single-threaded Web export succeeded. Browser interaction could not be verified: both local preview ports were refused by the available cloud browser. This is an environment limitation, not evidence that the game's Web behavior passes or fails.
- Windows native runtime, audio and human playtesting remain untested.
- Some existing test processes still emit ObjectDB cleanup warnings on exit; no test assertion failed.
