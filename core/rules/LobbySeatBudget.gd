class_name LobbySeatBudget
extends RefCounted
## Lobby seat arithmetic: seats, bots, difficulty and team mode, without any scene node.
## Immutable-style: every `with_*` returns a new value. Stub: bodies return the null answers.

var player_count: int = 0
var ai_count: int = 0
var ai_difficulty: int = 0
var team_mode: int = 0


static func from_config(_config: MatchConfig) -> LobbySeatBudget:
	return null


func write_to(_config: MatchConfig) -> void:
	pass


func max_bots(_humans: int) -> int:
	return -1


func with_roster(_humans: int) -> LobbySeatBudget:
	return null


## Null when `bots` would exceed the seat cap.
func with_bots(_humans: int, _bots: int) -> LobbySeatBudget:
	return null


func with_team_mode(_mode: int) -> LobbySeatBudget:
	return null


func with_difficulty(_value: int) -> LobbySeatBudget:
	return null
