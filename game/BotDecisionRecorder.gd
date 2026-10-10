class_name BotDecisionRecorder
extends Node
## Bontago-1t5.11 (BT2, docs/BOT_TRAINING_SOAK_PLAN.md sections 1-2): passive
## observer that writes one JSONL file per bot per match (schema v1,
## core/ai/BotDecisionRecord.gd). Host only, OFF unless a sink dir is configured.
##
## Passivity contract: the recorder holds NO RandomNumberGenerator, never mutates a
## candidate, countdown or state, never awaits, and only reads. BotController calls
## capture() after the choice is made and on_decision() after the request was sent.
## A failure (unwritable path, write error, byte cap) disables the recorder, prints
## one `BOT_RECORD_ERROR` line (deliberately not push_error, so triage_log's
## signatures do not change) and the match keeps running.

const FILE_PREFIX: String = "match"
const FILE_EXT: String = ".jsonl"

var config: BotRecordingConfig = preload("res://config/bot_recording.tres")
## Test seam for the Match autoload (null = the real one), like BotController's.
var _match_provider: Variant = null

var _dir: String = ""
var _enabled: bool = false
var _error: String = ""
var _match_index: int = 0
var _time_s: float = 0.0
var _next_id: int = 1
var _bytes: int = 0
var _files: Dictionary = {}
var _lines_since_flush: Dictionary = {}
var _slot_stats: Dictionary = {}
var _pending: Array[Dictionary] = []
var _eliminated_at: Dictionary = {}
var _tuning: BotTuning = preload("res://config/bot_tuning.tres")
var _match_active: bool = false


func set_match_provider(provider: Variant) -> void:
	_match_provider = provider


func _match() -> Variant:
	return _match_provider if _match_provider != null else Match


## Validates `dir` (absolute, not res://, creatable) and enables recording. Returns false
## and stays disabled (with one BOT_RECORD_ERROR line) otherwise.
func configure(dir: String) -> bool:
	if dir.is_empty() or dir.begins_with("res://") or dir.begins_with("user://") or not dir.is_absolute_path():
		return _fail("sink dir must be an absolute filesystem path, got '%s'" % dir)
	var err: Error = DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		return _fail("cannot create '%s' (error %d)" % [dir, err])
	_dir = dir.rstrip("/")
	_enabled = true
	_error = ""
	return true


func is_enabled() -> bool:
	return _enabled


func last_error() -> String:
	return _error


func _fail(message: String) -> bool:
	_error = message
	_enabled = false
	_close_files()
	print("BOT_RECORD_ERROR ", message)
	return false


func _physics_process(delta: float) -> void:
	if not _enabled or not _match_active:
		return
	on_tick(_time_s + delta)


## Opens one file per bot slot and writes each header line. `header` carries the match-level
## facts (seed, mode, map_id, bot_count, difficulty, git_revision, ...); kind,
## schema_version, weights snapshot, match_index and slot are added here.
func begin_match(header: Dictionary, bot_slots: PackedInt32Array, match_index: int) -> void:
	if not _enabled:
		return
	_close_files()
	_match_index = match_index
	_time_s = 0.0
	_pending.clear()
	_eliminated_at.clear()
	_slot_stats.clear()
	_match_active = true
	for slot_id: int in bot_slots:
		var path: String = "%s/%s%03d_slot%d%s" % [_dir, FILE_PREFIX, match_index, slot_id, FILE_EXT]
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_fail("cannot open '%s' (error %d)" % [path, FileAccess.get_open_error()])
			return
		_files[slot_id] = file
		_lines_since_flush[slot_id] = 0
		_slot_stats[slot_id] = {"decisions": 0, "special": 0, "mismatches": 0, "outcomes": 0, "bytes": 0}
		var record: Dictionary = header.duplicate()
		record["kind"] = BotDecisionRecord.KIND_HEADER
		record["schema_version"] = config.schema_version
		record["match_index"] = match_index
		record["slot"] = slot_id
		record["horizons_s"] = Array(config.horizons_s)
		record["weights"] = BotDecisionRecord.weights_snapshot(_tuning)
		_write(slot_id, record)


## Pre-request half of a decision: snapshots everything the request itself could change.
## `terms` are score_terms() of every candidate, computed by the controller with the exact
## pick_best inputs. Returns {} when not recording.
func capture(
	slot_id: int, team_id: int, shape_id: StringName, candidates: Array[BotCandidate],
	terms: Array[BotScoreTerms], chosen: int, special_policy: bool, state: Dictionary
) -> Dictionary:
	if not _enabled or not _files.has(slot_id):
		return {}
	return {
		"slot": slot_id, "team": team_id, "shape_id": shape_id,
		"candidates": candidates.duplicate(), "terms": terms, "chosen": chosen,
		"special": special_policy, "state": state, "t": _time_s,
	}


## Post-request half: writes the decision line and queues its outcome horizons.
func on_decision(context: Dictionary, feed_seq: int, placed_origin: Vector2, reason: StringName) -> void:
	if not _enabled or context.is_empty():
		return
	var slot_id: int = int(context["slot"])
	if not _files.has(slot_id):
		return
	var stats: Dictionary = _slot_stats[slot_id]
	var terms: Array[BotScoreTerms] = []
	terms.assign(context["terms"])
	var candidates: Array[BotCandidate] = []
	candidates.assign(context["candidates"])
	var chosen: int = int(context["chosen"])
	var scored_best: int = BotDecisionRecord.scored_best_index(terms, _tuning)
	var is_special: bool = bool(context["special"])
	var id: int = _next_id
	_next_id += 1
	var meta: Dictionary = {
		"id": id, "t": context["t"], "slot": slot_id, "team": context["team"],
		"shape_id": context["shape_id"], "feed_seq": feed_seq,
		"piece_index": int(stats["decisions"]) + int(stats["special"]), "state": context["state"],
	}
	var policy: String = BotDecisionRecord.POLICY_SPECIAL if is_special else BotDecisionRecord.POLICY_SCORE
	var record: Dictionary = BotDecisionRecord.to_dict(
		meta, candidates, terms, chosen, scored_best, placed_origin, reason, policy, config.round_step)
	if is_special:
		stats["special"] = int(stats["special"]) + 1
	else:
		stats["decisions"] = int(stats["decisions"]) + 1
		if chosen != scored_best:
			stats["mismatches"] = int(stats["mismatches"]) + 1
	_write(slot_id, record)
	var own_share: float = float((context["state"] as Dictionary).get("own_share", 0.0))
	_pending.append({
		"id": id, "slot": slot_id, "team": int(context["team"]), "t0": float(context["t"]),
		"share0": own_share, "deltas": PackedFloat32Array(),
	})


## Horizon sampler: call with the current match time (seconds).
func on_tick(t: float) -> void:
	_time_s = t
	if not _enabled:
		return
	var match_ref: Variant = _match()
	for slot_id: int in _files:
		if _eliminated_at.has(slot_id):
			continue
		var slot: PlayerSlot = match_ref.slot(slot_id) as PlayerSlot
		if slot != null and not slot.home_flag_alive:
			_eliminated_at[slot_id] = t
	if _pending.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		var deltas: PackedFloat32Array = entry["deltas"]
		while deltas.size() < config.horizons_s.size() and t >= float(entry["t0"]) + config.horizons_s[deltas.size()]:
			deltas.append(float(match_ref.territory_share(int(entry["team"]))) - float(entry["share0"]))
		entry["deltas"] = deltas
		if deltas.size() >= config.horizons_s.size():
			_write_outcome(entry, true)
		else:
			remaining.append(entry)
	_pending = remaining


func _write_outcome(entry: Dictionary, complete: bool) -> void:
	var slot_id: int = int(entry["slot"])
	if not _files.has(slot_id):
		return
	var match_ref: Variant = _match()
	var slot: PlayerSlot = match_ref.slot(slot_id) as PlayerSlot
	var record: Dictionary = BotDecisionRecord.outcome_to_dict(
		int(entry["id"]), slot_id, config.horizons_s, entry["deltas"],
		_own_block_count(match_ref, slot_id), slot != null and slot.home_flag_alive, config.round_step)
	record["complete"] = complete
	var stats: Dictionary = _slot_stats[slot_id]
	stats["outcomes"] = int(stats["outcomes"]) + 1
	_write(slot_id, record)


## Writes pending (truncated) outcomes, one match_end per bot and a footer, then closes files.
func end_match(winner_team: int) -> void:
	if not _match_active:
		return
	var match_ref: Variant = _match()
	if _enabled:
		for entry: Dictionary in _pending:
			_write_outcome(entry, false)
		for slot_id: int in _files.keys():
			var team: int = int(match_ref.team_of(slot_id))
			var end_record: Dictionary = BotDecisionRecord.match_end_to_dict(
				slot_id, team, winner_team, float(match_ref.territory_share(team)),
				float(_eliminated_at.get(slot_id, -1.0)), config.round_step)
			_write(slot_id, end_record)
			var footer: Dictionary = (_slot_stats[slot_id] as Dictionary).duplicate()
			footer["kind"] = BotDecisionRecord.KIND_FOOTER
			footer["policy_mismatch"] = footer["mismatches"]
			_write(slot_id, footer)
	_pending.clear()
	_match_active = false
	_close_files()


func _close_files() -> void:
	for slot_id: int in _files:
		var file: FileAccess = _files[slot_id] as FileAccess
		if file != null:
			file.flush()
			file.close()
	_files.clear()
	_lines_since_flush.clear()


func _write(slot_id: int, record: Dictionary) -> void:
	if not _enabled:
		return
	var file: FileAccess = _files.get(slot_id) as FileAccess
	if file == null:
		return
	var line: String = BotDecisionRecord.to_json_line(record)
	var size: int = line.length() + 1
	if _bytes + size > config.max_bytes:
		_fail("byte cap %d reached" % config.max_bytes)
		return
	file.store_line(line)
	if file.get_error() != OK:
		_fail("write error %d on slot %d" % [file.get_error(), slot_id])
		return
	_bytes += size
	var stats: Dictionary = _slot_stats[slot_id]
	stats["bytes"] = int(stats["bytes"]) + size
	_lines_since_flush[slot_id] = int(_lines_since_flush[slot_id]) + 1
	if int(_lines_since_flush[slot_id]) >= config.flush_every:
		file.flush()
		_lines_since_flush[slot_id] = 0


## Totals for the current match (decisions, mismatches, bytes, ...) plus process-wide bytes.
func stats() -> Dictionary:
	var total: Dictionary = {"decisions": 0, "special": 0, "mismatches": 0, "outcomes": 0, "bytes": _bytes, "enabled": _enabled}
	for slot_id: int in _slot_stats:
		var s: Dictionary = _slot_stats[slot_id]
		for key: String in ["decisions", "special", "mismatches", "outcomes"]:
			total[key] = int(total[key]) + int(s[key])
	return total


# --- state snapshot (read-only; the controller passes what it already computed) ---

static func _own_block_count(match_ref: Variant, slot_id: int) -> int:
	if not match_ref.has_method("registry"):
		return 0
	var registry: Variant = match_ref.registry()
	if registry == null or not registry.has_method("all_blocks"):
		return 0
	var count: int = 0
	for block: Block in registry.all_blocks():
		if is_instance_valid(block) and block.owner_slot == slot_id:
			count += 1
	return count


## The schema's `state` object. Missing Match accessors (test fakes) degrade to zeros.
static func build_state(
	match_ref: Variant, slot_id: int, team_id: int, enemy_circle_centers: PackedVector2Array,
	active_special_count: int, mode_goal: BotModeGoal, tuning: BotTuning, step: float
) -> Dictionary:
	var own_share: float = 0.0
	var enemy_share: float = 0.0
	var has_share: bool = match_ref.has_method("territory_share")
	if has_share:
		own_share = float(match_ref.territory_share(team_id))
	var enemies_alive: int = 0
	var own_alive: bool = true
	var own_home: Vector2 = Vector2.ZERO
	var seen_teams: Dictionary = {}
	for i: int in range(int(match_ref.slot_count())):
		var slot: PlayerSlot = match_ref.slot(i) as PlayerSlot
		if slot == null:
			continue
		var other_team: int = int(match_ref.team_of(i))
		if i == slot_id:
			own_alive = slot.home_flag_alive
			own_home = slot.home_position
		elif other_team != team_id:
			if slot.home_flag_alive:
				enemies_alive += 1
			if has_share and not seen_teams.has(other_team):
				seen_teams[other_team] = true
				enemy_share = maxf(enemy_share, float(match_ref.territory_share(other_team)))
	var nearest: float = -1.0
	for center: Vector2 in enemy_circle_centers:
		var d: float = center.distance_to(own_home)
		nearest = d if nearest < 0.0 else minf(nearest, d)
	var tower: float = float(match_ref.max_height_for_slot(slot_id)) if match_ref.has_method("max_height_for_slot") else 0.0
	var target_home: int = -1
	var mode: int = MatchConfig.GameMode.CLASSIC
	if mode_goal != null:
		mode = mode_goal.mode
		if mode == MatchConfig.GameMode.ELIMINATION:
			target_home = BotPlacementScorer.target_home_index(mode_goal, tuning)
	return {
		"own_share": BotDecisionRecord.round_to(own_share, step),
		"enemy_share": BotDecisionRecord.round_to(enemy_share, step),
		"own_blocks": _own_block_count(match_ref, slot_id),
		"own_tower_max_height": BotDecisionRecord.round_to(tower, step),
		"own_home_alive": own_alive,
		"enemies_alive": enemies_alive,
		"nearest_enemy_circle_dist": BotDecisionRecord.round_to(nearest, step),
		"active_specials": active_special_count,
		"mode_goal": {"mode": mode, "target_home": target_home},
	}
