class_name InputGate
extends RefCounted
## Whether local gameplay and camera input is blocked. Subscribes to Events itself, so no UI node is referenced.
## STUB: signatures only. Bodies return false or do nothing until the gate is wired to the callers.

## Events-fed: PAUSE <- pause_menu_opened/closed, CHAT <- chat_input_opened/closed, RESULTS <- match_results_ready.
## Events.match_scope_reset clears PAUSE, CHAT and RESULTS (the camera's rule). PANEL is not match-scoped and survives a reset.
enum Blocker { PAUSE, CHAT, RESULTS, PANEL }


## Connects the Events signals listed above (stub: connects nothing yet).
func _init() -> void:
	pass


## True when any blocker is active (stub: always false).
func is_blocked() -> bool:
	return false


## True when the given blocker is active; the camera's pan check needs CHAT alone (stub: always false).
func is_blocked_by(blocker: Blocker) -> bool:
	return false


## Sets or clears a blocker. Only external writer: the tuning panel sets PANEL (stub: does nothing).
func set_blocker(blocker: Blocker, active: bool) -> void:
	pass


## PAUSE, CHAT and RESULTS off; the Events reset handler's body; the camera rig's reset_view calls it (stub: does nothing).
func clear_match_scope() -> void:
	pass
