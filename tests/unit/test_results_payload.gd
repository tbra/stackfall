extends GutTest
## ResultsPayload (Bontago-fca.36.8): the single owner of the results payload
## schema -- stable wire strings, the one validator (host build and client
## receipt) and the typed accessors the UI reads through.


func _valid_row() -> Dictionary:
	return {
		ResultsPayload.KEY_SLOT_ID: 0, ResultsPayload.KEY_NAME: "Ann", ResultsPayload.KEY_TEAM_ID: 0,
		ResultsPayload.KEY_IS_BOT: false, ResultsPayload.KEY_BLOCKS_PLACED: 3, ResultsPayload.KEY_BLOCKS_LOST: 1,
		ResultsPayload.KEY_GIFTS_CLAIMED: 0, ResultsPayload.KEY_SPECIALS_USED: 0,
		ResultsPayload.KEY_TERRITORY_SHARE: 0.5, ResultsPayload.KEY_ELIMINATED_AT: -1.0,
	}


func _valid_payload() -> Dictionary:
	return {
		ResultsPayload.KEY_WINNER_KIND: ResultsPayload.WINNER_KIND_SLOT, ResultsPayload.KEY_WINNER_ID: 0,
		ResultsPayload.KEY_WINNER_NAME: "Ann", ResultsPayload.KEY_MATCH_DURATION: 12.0,
		ResultsPayload.KEY_ROWS: [_valid_row()],
	}


func test_wire_strings_are_unchanged() -> void:
	assert_eq(ResultsPayload.KEY_WINNER_ID, "winner_id")
	assert_eq(ResultsPayload.KEY_WINNER_KIND, "winner_kind")
	assert_eq(ResultsPayload.KEY_WINNER_NAME, "winner_name")
	assert_eq(ResultsPayload.KEY_MATCH_DURATION, "match_duration")
	assert_eq(ResultsPayload.KEY_ROWS, "rows")
	assert_eq(ResultsPayload.KEY_MODE, "mode")
	assert_eq(ResultsPayload.KEY_SLOT_ID, "slot_id")
	assert_eq(ResultsPayload.KEY_TERRITORY_SHARE, "territory_share")
	assert_eq(ResultsPayload.KEY_ELIMINATED_AT, "eliminated_at")
	assert_eq(ResultsPayload.KEY_WINNERS, "winners")
	assert_eq(ResultsPayload.WINNER_KIND_SLOT, "slot")
	assert_eq(ResultsPayload.WINNER_KIND_TEAM, "team")


func test_valid_payload_passes_and_matches_match_stats_delegate() -> void:
	var clean: Dictionary = ResultsPayload.validate(_valid_payload())
	assert_false(clean.is_empty())
	assert_eq(clean, MatchStats.validate_results_payload(_valid_payload()), "one validator behind both entry points")
	assert_eq(ResultsPayload.winner_name(clean), "Ann")
	assert_eq(ResultsPayload.rows(clean).size(), 1)


func test_malformed_payloads_are_rejected_on_a_client() -> void:
	assert_true(ResultsPayload.validate(42).is_empty(), "not a dictionary")
	var bad_kind: Dictionary = _valid_payload()
	bad_kind[ResultsPayload.KEY_WINNER_KIND] = "everyone"
	assert_true(ResultsPayload.validate(bad_kind).is_empty())
	var no_rows: Dictionary = _valid_payload()
	no_rows.erase(ResultsPayload.KEY_ROWS)
	assert_true(ResultsPayload.validate(no_rows).is_empty())
	var bad_row: Dictionary = _valid_payload()
	(bad_row[ResultsPayload.KEY_ROWS][0] as Dictionary)[ResultsPayload.KEY_SLOT_ID] = -4
	assert_true(ResultsPayload.validate(bad_row).is_empty())
	var inf_duration: Dictionary = _valid_payload()
	inf_duration[ResultsPayload.KEY_MATCH_DURATION] = INF
	assert_true(ResultsPayload.validate(inf_duration).is_empty())


func test_mode_block_has_one_validator() -> void:
	var block: Dictionary = {ResultsPayload.KEY_MODE_ID: MatchConfig.GameMode.CAPTURE_THE_FLAG, ResultsPayload.KEY_SCORES: [1, 2], ResultsPayload.KEY_WINNERS: "1"}
	assert_eq(ModeObjective.validate_results_block(block), ResultsPayload.validate_mode_block(block))
	var payload: Dictionary = _valid_payload()
	payload[ResultsPayload.KEY_MODE] = block
	assert_eq(ResultsPayload.mode_scores(ResultsPayload.validate(payload)), [1.0, 2.0])
	assert_eq(ResultsPayload.mode_winner_texts(payload), PackedStringArray(["1"]))
	payload[ResultsPayload.KEY_MODE] = {ResultsPayload.KEY_MODE_ID: 99, ResultsPayload.KEY_SCORES: []}
	assert_true(ResultsPayload.validate(payload).is_empty(), "unknown mode id rejected")


func test_accessor_defaults() -> void:
	assert_eq(ResultsPayload.winner_id({}), -1)
	assert_eq(ResultsPayload.winner_kind({}), ResultsPayload.WINNER_KIND_SLOT)
	assert_eq(ResultsPayload.mode_id({}), MatchConfig.GameMode.CLASSIC)
	assert_false(ResultsPayload.has_mode_block({}))
	assert_false(ResultsPayload.is_live({}))
