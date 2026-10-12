class_name ChatConfig
extends Resource
## Tunables for player chat (Bontago-1pi.192, docs/CHAT_PLAN.md sections 2, 3, 7).
## Owner defaults accepted 2026-10-12 (Bontago-oov).

## Master switch; the host refuses lines when false.
@export var enabled: bool = true
## Longest line in code points.
@export var max_chars: int = 140
## Token bucket: lines allowed in a burst, then refill_per_s lines per second.
@export var burst: int = 3
@export var refill_per_s: float = 0.5
## The same text from one sender inside this window is refused.
@export var duplicate_window_s: float = 3.0
## Minimum gap between notices sent to one sender.
@export var notice_min_interval_s: float = 1.5
## Host ring size, also the history a late joiner receives.
@export var history_lines: int = 30
## Lines the in-game HUD panel shows.
@export var hud_lines: int = 6
## In-game: seconds a new line stays fully visible, then the fade length.
@export var line_visible_s: float = 8.0
@export var fade_s: float = 1.0

## Clamp every field into a usable range (called on any loaded resource).
func sanitize() -> void:
	max_chars = clampi(max_chars, 1, 500)
	burst = clampi(burst, 1, 20)
	refill_per_s = clampf(refill_per_s, 0.05, 20.0)
	duplicate_window_s = clampf(duplicate_window_s, 0.0, 60.0)
	notice_min_interval_s = clampf(notice_min_interval_s, 0.0, 60.0)
	history_lines = clampi(history_lines, 1, 200)
	hud_lines = clampi(hud_lines, 1, 20)
	line_visible_s = clampf(line_visible_s, 1.0, 120.0)
	fade_s = clampf(fade_s, 0.0, 10.0)
