class_name InputGate
extends RefCounted
## Whether local gameplay and camera input is blocked. Subscribes to Events itself, so no UI node is referenced.

## Events-fed: PAUSE <- pause_menu_opened/closed, CHAT <- chat_input_opened/closed, RESULTS <- match_results_ready.
## Events.match_scope_reset clears PAUSE, CHAT and RESULTS (the camera's rule). PANEL is not match-scoped and survives a reset.
enum Blocker { PAUSE, CHAT, RESULTS, PANEL }

## Active blockers by Blocker value; each is independent so closing one never unblocks another.
var _active: Dictionary = {}


## Connects the Events signals listed above.
func _init() -> void:
	Events.pause_menu_opened.connect(set_blocker.bind(Blocker.PAUSE, true))
	Events.pause_menu_closed.connect(set_blocker.bind(Blocker.PAUSE, false))
	Events.chat_input_opened.connect(set_blocker.bind(Blocker.CHAT, true))
	Events.chat_input_closed.connect(set_blocker.bind(Blocker.CHAT, false))
	Events.match_results_ready.connect(_on_match_results_ready)
	Events.match_scope_reset.connect(clear_match_scope)


## True when any blocker is active.
func is_blocked() -> bool:
	return not _active.is_empty()


## True when the given blocker is active; the camera's pan check needs CHAT alone.
func is_blocked_by(blocker: Blocker) -> bool:
	return _active.has(blocker)


## Sets or clears a blocker. Only external writer: the tuning panel sets PANEL.
func set_blocker(blocker: Blocker, active: bool) -> void:
	if active:
		_active[blocker] = true
	else:
		_active.erase(blocker)


## PAUSE, CHAT and RESULTS off; the Events reset handler's body; the camera rig's reset_view calls it.
func clear_match_scope() -> void:
	_active.erase(Blocker.PAUSE)
	_active.erase(Blocker.CHAT)
	_active.erase(Blocker.RESULTS)


func _on_match_results_ready(_results: Dictionary) -> void:
	set_blocker(Blocker.RESULTS, true)
