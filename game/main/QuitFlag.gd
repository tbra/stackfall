class_name QuitFlag
extends RefCounted
## Bontago-xtq.46: dependency-free "the process is really quitting" flag. Every real quit
## path (Boot window close/load failure, MainMenu quit, headless bots done, AgentProbe)
## calls mark(); Main._exit_tree releases the process-wide caches (ExitRelease) only then,
## so GUT tests that free Main mid-process leave live caches alone.
## DECISION: kept apart from ExitRelease so early-loaded scripts (Boot, AgentProbe) do not
## pull ExitRelease's whole cache-class closure into the autoload layer.
## NOTE (xtq.46 review): Main and Boot mark on any WM_CLOSE_REQUEST; a future close-confirm
## dialog must mark only after the quit is confirmed, never on a cancellable request.

static var _quitting: bool = false


static func mark() -> void:
	_quitting = true


static func is_quitting() -> bool:
	return _quitting
