extends GutTest
## MatchPhase (core/rules/MatchPhase.gd): ordinals, alias parity with Match and the predicate truth table.

const L: int = MatchPhase.State.LOBBY
const LO: int = MatchPhase.State.LOADING
const C: int = MatchPhase.State.COUNTDOWN
const P: int = MatchPhase.State.PLAYING
const S: int = MatchPhase.State.SUDDEN_DEATH
const E: int = MatchPhase.State.END


func test_ordinals_pinned() -> void:
	assert_eq([L, LO, C, P, S, E], [0, 1, 2, 3, 4, 5])


func test_alias_keys_match() -> void:
	assert_eq(MatchAutoload.State.keys(), MatchPhase.State.keys())
	assert_eq(MatchAutoload.State.values(), MatchPhase.State.values())


func _table() -> Dictionary:
	# predicate name -> states for which it is true
	return {
		"is_live": [P, S],
		"is_replicating": [C, P, S],
		"is_resetting": [LO, L, E],
		"is_in_progress": [LO, C, P, S],
		"is_pregame": [LO, C],
		"is_lobby_or_end": [L, E],
	}


func test_truth_table_and_forwards() -> void:
	var table: Dictionary = _table()
	for name: String in table:
		var expected: Array = table[name]
		for state: int in range(MatchPhase.State.size()):
			var want: bool = expected.has(state)
			assert_eq(Callable(MatchPhase, name).call(state), want, "%s(%d)" % [name, state])
			assert_eq(Callable(MatchAutoload, name).call(state), want, "forward %s(%d)" % [name, state])


func test_start_transition() -> void:
	for from_state: int in range(MatchPhase.State.size()):
		for to_state: int in range(MatchPhase.State.size()):
			var want: bool = from_state == L and to_state == LO
			assert_eq(MatchPhase.is_start_transition(from_state, to_state), want)
			assert_eq(MatchAutoload.is_start_transition(from_state, to_state), want)
