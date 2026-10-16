extends "res://tests/unit/match/match_world_test.gd"
## Match host state machine, feed timer/auto-drop and request_place accept/reject/burn (spec 1.4, 2.5, 3.7).

func after_each() -> void:
	Match._sandbox_territory_profile_enabled = false
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## Every MatchConfig this file hands to Match.start_match() goes through this
## (or _free_for_all_config()) so it always carries this test's own
## `_tiny_map` (see the field's own doc comment above) via the
## TinyMapMatchConfig seam.
##
## Swaps the script *before* the caller sets any fields: Object.set_script()
## re-initializes script-level state to its new script's declared defaults,
## so field values set on `config` before this call (player_count, hot_seat,
## etc. -- all plain MatchConfig @export vars, unrelated to the map) would
## otherwise be silently discarded (reproduced: player_count came back as the
## class default 4, not the 2 a caller had just set).
func _hotseat_config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = true
	config.block_timer = block_timer
	config.rng_seed = 12345
	return config


## 's per-player-timer path (spec 1.4's "[ORIGINAL target]"
## concurrent cadence, the normal non-hot-seat mode the interval lock
## targets): every slot's feed runs concurrently, so a lone slot can
## otherwise place blocks back to back with nothing to stop it.
func _free_for_all_config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = block_timer
	config.rng_seed = 98765
	return config


func test_start_match_runs_lobby_to_playing_with_countdown_ticks() -> void:
	# assert_signal_emitted_with_parameters only checks the LATEST emission,
	# so the exact 3, 2, 1, 0 sequence (spec 2.4) is collected by hand instead.
	var ticks: Array[int] = []
	var collect: Callable = func(seconds_left: int) -> void: ticks.append(seconds_left)
	Events.countdown_tick.connect(collect)

	Match.set_sandbox_territory_mode(
		MatchAutoload.SANDBOX_TERRITORY_CONE, 75.0,
		SandboxConeExperiment.HEIGHT_CENTER, SandboxConeExperiment.BASE_NONE
	)
	Match.start_match(_hotseat_config())
	assert_eq(Match._sandbox_territory_mode, MatchAutoload.DEFAULT_TERRITORY_MODE)
	assert_almost_eq(Match._sandbox_cone_angle, MatchAutoload.DEFAULT_CONE_ANGLE_DEGREES, 0.001)
	assert_eq(Match._sandbox_cone_height_source, SandboxConeExperiment.HEIGHT_TOP)
	assert_eq(Match._sandbox_cone_base_mode, SandboxConeExperiment.BASE_ADDITIVE)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_eq(ticks, [3] as Array[int])

	_run_countdown()

	Events.countdown_tick.disconnect(collect)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(ticks, [3, 2, 1, 0] as Array[int])


# --- Restart and teardown ordering (spec 2.4; Beads) --------
# game/main/Main.gd builds the match world synchronously inside the LOADING emit
# and reads Match.raster()/slot()/registry() right there, so the world model
# must be complete by then; and a start from a stale PLAYING/END (rehost
# after the host quit, a future rematch) must go back through LOBBY so every
# consumer tears the previous match down before the new one is built.

## Every transition Match emits, in order, as [from, to] pairs.
func _record_transitions(into: Array[Array]) -> Callable:
	var recorder: Callable = func(from_state: int, to_state: int) -> void:
		into.append([from_state, to_state])
	Events.match_state_changed.connect(recorder)
	return recorder


func test_loading_is_emitted_only_once_the_world_model_is_built() -> void:
	var seen_at_loading: Dictionary = {}
	var probe: Callable = func(_from_state: int, to_state: int) -> void:
		if to_state == Match.State.LOADING:
			seen_at_loading["raster"] = Match.raster()
			seen_at_loading["slots"] = Match.slot_count()
			seen_at_loading["config"] = Match.config
			seen_at_loading["cell_grid"] = Match.cell_grid()
	Events.match_state_changed.connect(probe)

	Match.start_match(_hotseat_config(3))
	Events.match_state_changed.disconnect(probe)

	assert_true(seen_at_loading.has("raster"), "LOADING must be emitted")
	assert_not_null(seen_at_loading.get("raster"), "The raster must exist when LOADING fires (Main binds the overlay to it).")
	assert_eq(seen_at_loading.get("raster"), Match.raster(), "and be the one the match then plays on")
	assert_not_null(seen_at_loading.get("cell_grid"))
	assert_eq(seen_at_loading.get("slots"), 3, "The slots must exist when LOADING fires (Main places the flags from them).")
	assert_not_null(seen_at_loading.get("config"), "The sanitized config must exist when LOADING fires.")


func test_start_match_from_playing_returns_through_lobby_with_a_fresh_world() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)
	var old_raster: TerritoryRaster = Match.raster()
	var old_slot: PlayerSlot = Match.slot(0)
	# Spend some of slot 0's timer so a stale value would be visible.
	for _i: int in range(60):
		Match._process(1.0 / 60.0)
	assert_eq(Match.active_slot(), 0)

	var transitions: Array[Array] = []
	var recorder: Callable = _record_transitions(transitions)
	Match.start_match(_hotseat_config(3))
	Events.match_state_changed.disconnect(recorder)

	assert_eq(
		transitions,
		[
			[Match.State.PLAYING, Match.State.LOBBY],
			[Match.State.LOBBY, Match.State.LOADING],
			[Match.State.LOADING, Match.State.COUNTDOWN],
		] as Array[Array],
		"A restart goes back through LOBBY so consumers see exactly one LOBBY -> LOADING per match."
	)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_eq(Match.slot_count(), 3, "The new config, not the old one")
	assert_ne(Match.raster(), old_raster, "A fresh raster")
	assert_ne(Match.slot(0), old_slot, "Fresh slots")
	assert_eq(Match.active_slot(), -1, "No turn is active before play begins")
	# the new match's own first block is issued when its countdown
	# exists (no carry-over: the old match's held shape was cleared by the restart).
	assert_not_null(Match.held_shape(0), "The new match holds its own first block")
	assert_eq(Match.feed_seq(0), 0, "A fresh feed sequence")


# --- Hot-seat turn order and feed timer (spec 1.5, 2.4, 2.7) ----------------

func test_feed_timer_expires_exactly_at_block_timer() -> void:
	# spec 1.9's block_timer range is 3-12 s; sanitize() (called by
	# start_match) clamps to that, so the test uses the minimum rather than an
	# arbitrary short value.
	var block_timer: float = MatchConfig.BLOCK_TIMER_MIN
	watch_signals(Events)
	Match.start_match(_hotseat_config(2, block_timer))
	_run_countdown()

	var frames_just_under: int = int(block_timer * 60.0) - 1
	for _i: int in range(frames_just_under):
		Match._process(1.0 / 60.0)
	assert_signal_not_emitted(Events, "feed_timer_expired")

	for _i: int in range(5):
		Match._process(1.0 / 60.0)
	assert_signal_emitted_with_parameters(Events, "feed_timer_expired", [0])


# --- spec 1.4 "[ORIGINAL target]": the fixed-interval ------
# --- placement cadence, outside hot-seat -------------------------------------
# Every fixed config.block_timer interval permits exactly one release. An
# early release hands the slot its next piece to aim, but locked until the
# interval boundary; an untouched piece force-releases (auto-drops) at that
# boundary instead.

func test_an_early_release_issues_the_next_piece_locked_without_restarting_the_interval() -> void:
	var block_timer: float = 6.0
	Match.start_match(_free_for_all_config(2, block_timer))
	_run_countdown()
	for _i: int in range(60):  # burn one second of the interval first
		Match._process(1.0 / 60.0)
	var left_before: float = Match.feed_time_left(0)

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_not_null(Match.held_shape(0), "The next piece is issued immediately, for preparation.")
	assert_true(Match.is_release_locked(0), "but it may not be released again this interval.")
	assert_almost_eq(
		Match.feed_time_left(0), left_before, 0.05,
		"Releasing early must not restart the interval (spec 1.4)."
	)


func test_an_untouched_piece_auto_drops_at_the_interval_boundary() -> void:
	var block_timer: float = MatchConfig.BLOCK_TIMER_MIN
	# Both slots are untouched and share the same interval start, so both
	# force at the same tick -- collected by hand (like this file's own
	# countdown-tick test above) rather than
	# assert_signal_emitted_with_parameters, which only ever checks the LAST
	# emission and would see slot 1's, not slot 0's.
	var expired: Array[int] = []
	var collect: Callable = func(slot_id: int) -> void: expired.append(slot_id)
	Events.feed_timer_expired.connect(collect)
	Match.start_match(_free_for_all_config(2, block_timer))
	_run_countdown()

	for _i: int in range(int(ceil(block_timer * 60.0)) + 2):
		Match._process(1.0 / 60.0)

	Events.feed_timer_expired.disconnect(collect)
	assert_true(expired.has(0), "an unspent piece forces at the boundary")


# --- pivot is the shape's --
# --- geometric centre, not cell (0, 0, 0) ------------------------------------

# --- pivot (reported as "the ghost/body pivot is the --
# --- block's middle"): the pivot is the shape's bottom-centre now ------------

# --- placed blocks carry -------
# --- their slot's colour ------------------------------------------------------

# --- The authority's own guard against a pose it cannot evaluate -----------
# net/MatchNet.gd refuses these at the wire (tests/unit/
# test_remote_intent_validation.gd); Match refuses them too, from any caller,
# so a bad index can never reach BlockOrientations.get_basis() and a NaN
# origin can never reach the raster (Beads .6).

func test_request_place_refuses_a_malformed_pose_without_spending_the_block() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	var seq: int = Match.feed_seq(0)
	var home: Vector3 = _home_world_position(0)

	var bad_poses: Array[Array] = [
		[home, -1, Quaternion.IDENTITY],
		[home, BlockOrientations.ORIENTATION_COUNT, Quaternion.IDENTITY],
		[home, 1 << 40, Quaternion.IDENTITY],
		[Vector3(NAN, home.y, home.z), 0, Quaternion.IDENTITY],
		[Vector3(home.x, INF, home.z), 0, Quaternion.IDENTITY],
		[home, 0, Quaternion(0.0, 0.0, 0.0, 0.0)],
		[home, 0, Quaternion(0.0, 0.0, 0.0, 2.0)],
		[home, 0, Quaternion(NAN, 0.0, 0.0, 1.0)],
	]
	for pose: Array in bad_poses:
		var reason: StringName = Match.request_place(0, pose[0], int(pose[1]), pose[2], false)
		assert_eq(reason, PlacementRules.REASON_NO_BLOCK, "Pose %s must be refused." % [pose])

	assert_eq(_blocks_root.get_child_count(), 0, "A malformed pose spawns nothing, not even a burned block.")
	assert_eq(Match.feed_seq(0), seq, "and consumes nothing")
	assert_eq(Match.active_slot(), 0, "and the hot-seat turn does not pass")


# --- REPRO: far-off-disk burns must not spawn past the ---
# --- kill plane's area, or the burned body falls forever and leaks. --------
# A manual (auto_drop == false)
# release this far off-disk is refused outright now, spawning nothing -- see
# test_a_manual_drop_outside_territory_is_refused_and_the_block_stays_held()
# in tests/unit/match/test_placement_refusal.gd. The clamp this file's own repro
# tests are about only still matters for a forced auto-drop that finds no
# valid relocation point (MatchNet's own auto-drop-from-last-cursor path can
# still be handed an arbitrarily far cursor by a hostile/buggy client), so
# both tests below now drive request_place() with auto_drop == true.
#
# closest_valid_point() now falls back to a full-disk scan
# when the ring search comes up empty, so an origin merely far away no
# longer forces the burn path by itself -- the disk scan would still find
# slot 0's own territory and relocate there instead. Both tests below
# blank slot 0's owned cells in the live raster first
# (TerritoryTestHelpers.blank_owned_territory()), so the team genuinely owns
# no valid point anywhere and the burn is the only outcome left -- which is
# what these tests are actually about (the clamp on the spawned/thrown
# point), not the distance that used to trigger it.

func test_repro_far_off_disk_burn_spawns_within_the_kill_plane_area() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	TerritoryTestHelpers.blank_owned_territory(Match.raster(), Match.team_of(0))
	var hover: float = load("res://config/physics/physics_tuning.tres").hover_height as float
	var far_origin: Vector3 = _field.to_global(Vector3(1.0e6, hover, 0.0))

	var reason: StringName = Match.request_place(0, far_origin, 0, Quaternion.IDENTITY, true)

	assert_ne(reason, PlacementRules.REASON_OK, "This pose must fail territory validation, find no relocation, and burn.")
	assert_eq(_blocks_root.get_child_count(), 1, "The block is still consumed and spawned, then burned.")
	var spawned: Node3D = _blocks_root.get_child(0) as Node3D
	var local: Vector3 = _field.to_local(spawned.global_position)
	var disk_radius: Vector2 = Vector2(local.x, local.z)
	var half_extent: float = _field.map_def.field_radius * Field.KILL_PLANE_RADIUS_FACTOR * 0.5
	assert_lt(
		disk_radius.length(), half_extent,
		"A burned block must spawn inside the kill plane's box, not at the raw (unbounded) requested origin."
	)


# --- : home flag lost to a hole eliminates the slot ----------

func test_player_eliminated_when_holes_open_under_their_home_flag() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	watch_signals(Events)

	var home_cell: Vector2i = Match.cell_grid().world_to_cell(Match.slot(0).home_position)
	var index: int = Match.cell_grid().cell_index(home_cell.x, home_cell.y)
	Match._territory._check_home_flags(PackedInt32Array([index]))

	assert_false(Match.slot(0).home_flag_alive)
	assert_signal_emitted_with_parameters(Events, "player_eliminated", [0, 0])


func test_match_ends_when_only_one_team_remains() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	watch_signals(Events)

	var home_cell: Vector2i = Match.cell_grid().world_to_cell(Match.slot(0).home_position)
	var index: int = Match.cell_grid().cell_index(home_cell.x, home_cell.y)
	Match._territory._check_home_flags(PackedInt32Array([index]))

	assert_eq(Match.state(), Match.State.END)
	assert_signal_emitted_with_parameters(Events, "match_won", [1])


# --- Point placement, goal zones, continuous elimination -------------------
# (territory v2, reconciled with SPEC.md's
# evidence audit by). The raycast + PlacementRules.validate_point
# path these tests are named "_v2_" for was package B's v2-only behaviour when
# they were written made it every MatchConfig.HoleMode's
# placement contract (autoload/Match.gd request_place()/preview_placement()),
# so config/match/match_defaults.tres's hole_mode no longer has to be OFF for these
# to hold -- they now hold at whatever the default is
# (test_match_config.gd pins the default itself; TEMPORARY as of this ticket).
# The names stay for git blame continuity; the assertions below no longer
# check which mode is active because none of them depend on it any more.

## Renamed from
## test_request_place_v2_burns_a_point_inside_another_teams_territory -- a
## manual release here is now refused, not burned (see
## tests/unit/match/test_placement_refusal.gd for the focused regression case; this
## one stays to keep the v2 point-check names together).
func test_request_place_v2_refuses_a_point_inside_another_teams_territory() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()

	var reason: StringName = Match.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(_blocks_root.get_child_count(), 0, "A refused manual release must not spawn anything.")


## Hand-crafted circles/raster state rather than a physically bridged tower:
## the v2 connectivity rule means a home-anchored circle
## reaching from slot 1's home across a real match's 50+ m gap to slot 0's
## home is exactly what the headless Lobby-to-win acceptance drive exercises
## with real physics and real placements; this test isolates
## _check_home_flags_v2()'s own trigger against a raster it did not build
## itself, the same way test_player_eliminated_when_holes_open_under_their_
## home_flag above isolates _check_home_flags()'s. Slot 1's home is nudged
## next to slot 0's home purely so TerritorySolver still anchors the injected
## enemy circle to a home (it only keeps home-anchored groups); the enemy
## circle's own radius, not the nudge, is what outscores slot 0's home.
func test_check_home_flags_v2_eliminates_a_slot_once_an_enemy_circle_outscores_its_home() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	Match.slot(1).home_position = home0 + Vector2(2.0, 0.0)
	var enemy_circle: InfluenceCircle = InfluenceCircle.new(
		home0, Match._territory_tuning.home_radius + 4.0, Match.team_of(1), 1, false, 999
	)
	var circles: Array[InfluenceCircle] = Match._territory._collect_circles()
	circles.append(enemy_circle)
	var groups: TerritoryGroups = Match._solver.solve(circles)
	Match._raster.fill_ownership(circles, groups, false)
	Match._raster.adopt_fill(Match._raster, 1.0 / Match._territory_tuning.solve_hz, false, false)

	Match._territory._check_home_flags_v2()

	assert_false(Match.slot(0).home_flag_alive)
	assert_signal_emitted_with_parameters(Events, "player_eliminated", [0, 0])
	assert_eq(
		Match.state(), Match.State.END,
		"Last team standing still ends the match, unchanged from today's rule."
	)
	assert_signal_emitted_with_parameters(Events, "match_won", [1])


func test_slow_frame_coalesces_due_territory_solves_and_keeps_fractional_time() -> void:
	var config: MatchConfig = _hotseat_config(2)
	config.hole_mode = MatchConfig.HoleMode.OFF
	Match.start_match(config)
	_run_countdown()
	Match._territory._solve_accum = 0.0
	Match._territory.mark_dirty()
	Match._sandbox_territory_profile_enabled = true
	watch_signals(Events)

	var step: float = 1.0 / Match._territory_tuning.solve_hz
	Match._territory._tick_territory(step * 3.5)
	# the first step consumes the only change, so the two
	# remaining catch-up steps advance time without a second solve/emission.
	assert_eq(int(Match._territory.sandbox_profile()["steps"]), 1)
	assert_eq(get_signal_emit_count(Events, "territory_updated"), 1)
	assert_almost_eq(Match._territory._solve_accum, step * 0.5, 0.001)
	Match._territory.mark_dirty()
	Match._territory._tick_territory(step * 0.51)
	assert_eq(int(Match._territory.sandbox_profile()["steps"]), 1)
	assert_eq(get_signal_emit_count(Events, "territory_updated"), 2)
	assert_almost_eq(Match._territory._solve_accum, step * 0.01, 0.001)
	Match._sandbox_territory_profile_enabled = false


## Adds a tracked block that counts as awake (unsettled) to the registry.
func _add_awake_block() -> BlockRegistry._Entry:
	var block: Block = autofree(Block.new())
	add_child_autofree(block)
	var entry: BlockRegistry._Entry = BlockRegistry._Entry.new()
	entry.block = block
	entry.is_settled = false
	_registry._entries[block.get_instance_id()] = entry
	_registry.mark_territory_dirty()
	return entry


class _TimeSpyChecker:
	extends WinChecker
	var total: float = 0.0

	func update(raster: TerritoryRaster, delta: float) -> void:
		total += delta
		super.update(raster, delta)


func test_awake_block_defers_solves_until_cap_then_forces_one() -> void:
	var config: MatchConfig = _hotseat_config(2)
	config.hole_mode = MatchConfig.HoleMode.OFF
	Match.start_match(config)
	_run_countdown()
	Match._territory._solve_accum = 0.0
	Match._sandbox_territory_profile_enabled = true
	var cap: float = Match._territory_tuning.solve_defer_max_s
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	_add_awake_block()
	watch_signals(Events)

	Match._territory._tick_territory(step * 2.0)
	assert_eq(get_signal_emit_count(Events, "territory_updated"), 0, "No solve while a block is awake.")
	Match._territory._tick_territory(cap - step * 2.0 - 0.01)
	assert_eq(get_signal_emit_count(Events, "territory_updated"), 0, "Still deferred just under the cap.")
	Match._territory._tick_territory(0.02)
	assert_gt(get_signal_emit_count(Events, "territory_updated"), 0, "The staleness cap forces a solve.")
	Match._sandbox_territory_profile_enabled = false


## Legacy-mode regression: the pre-v2
## contest -> hole_delay -> hole -> Events.hole_cells_changed ->
## _check_home_flags() chain, run through the real _run_territory_step() call
## site rather than the direct _check_home_flags() call
## test_player_eliminated_when_holes_open_under_their_home_flag uses above,
## now that a match must set hole_mode explicitly to reach it at all.
func test_legacy_hole_mode_still_opens_holes_and_eliminates_through_run_territory_step() -> void:
	var config: MatchConfig = _hotseat_config(2)
	config.hole_mode = MatchConfig.HoleMode.TEMPORARY
	Match.start_match(config)
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	# Two different-team home circles overlapping slot 0's own home cell is
	# spec 1.5's original contest trigger; the legacy fill still stamps it
	# CONTESTED, unchanged. Nudging the homes this close together is
	# symmetric -- home 0 falls inside home 1's own circle exactly as home 1
	# falls inside home 0's, both radius home_radius -- so both cells end up
	# contested and *both* flags are expected to fall; that symmetry is fine
	# here, since this test's job is only to prove the legacy
	# contest -> hole_delay -> hole -> Events.hole_cells_changed ->
	# _check_home_flags() chain still fires through the real
	# _run_territory_step() call site, not to isolate a single elimination
	# (test_player_eliminated_when_holes_open_under_their_home_flag above
	# already does that against a hand-picked opened-cell list).
	Match.slot(1).home_position = home0 + Vector2(2.0, 0.0)

	var step: float = 1.0 / Match._territory_tuning.solve_hz
	var elapsed: float = 0.0
	while elapsed < Match._territory_tuning.hole_delay + step:
		Match._territory._run_territory_step(step)
		elapsed += step

	assert_false(Match.slot(0).home_flag_alive, "The legacy hole-opened path must still eliminate a home flag.")
	assert_false(Match.slot(1).home_flag_alive, "Both homes contest each other symmetrically here.")
	var eliminated_slots: Array = []
	for i: int in range(get_signal_emit_count(Events, "player_eliminated")):
		eliminated_slots.append(get_signal_parameters(Events, "player_eliminated", i)[0])
	assert_has(eliminated_slots, 0)
	assert_has(eliminated_slots, 1)
	assert_signal_emitted(Events, "hole_cells_changed")
