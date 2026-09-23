class_name MatchLifecycle
extends RefCounted
## Match's state machine (Lobby -> Loading -> Countdown -> Playing -> End ->
## Lobby, spec 3.7), slots/teams, disconnect grace and hot-seat turn logic.
##
## Split out of autoload/Match.gd (pure refactor: no behaviour change). See
## that file's own header comment for the full state-machine contract.

var _match: MatchAutoload = null

var _state: MatchAutoload.State = MatchAutoload.State.LOBBY
var _countdown_remaining: float = 0.0
var _countdown_last_whole: int = 0

var _slots: Array[PlayerSlot] = []
var _active_slot: int = -1

## True for the duration of a start_match() call (set at its first line,
## cleared at its last). net/MatchNet.gd's _on_match_state_changed() reads
## this through is_starting_match() to decide whether a state change is worth
## replicating on its own: every transition start_match() produces internally
## -- the leading old_state->LOBBY from abort_match() when restarting from
## PLAYING/END, then LOBBY->LOADING, then LOADING->COUNTDOWN -- is already
## fully reproduced the moment a client runs this same start_match() locally
## from net_match_start (see that RPC's own doc). Replicating them again as
## separate EVENT_STATE_CHANGED events would land on a client after its own
## _state has already moved past them (this function runs synchronously
## start-to-finish, with no yield in between), so apply_replicated_state_
## change() would read them as new backward transitions instead of the no-ops
## they should be (Bontago-mv0.1.13: a client-observed COUNTDOWN->LOADING
## immediately followed by LOADING->COUNTDOWN, spurious both times). Only
## net_match_start carries the start across the wire; every OTHER state
## change -- PLAYING->END from a win, a future standalone "return to lobby"
## that is not part of starting a new match -- happens outside this window
## and keeps replicating exactly as before.
var _starting: bool = false

## Slots whose peer has vanished and whose NetConfig.disconnect_grace is still
## running: the feed is stopped and the timer is not ticking, but the slot is
## still alive and its towers still hold territory. Parallel to _slots;
## negative means "connected".
var _disconnect_grace_left: Array[float] = []


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref


# --- Lifecycle --------------------------------------------------------------

## Lobby -> Loading -> Countdown -> Playing. Builds the player slots, the
## per-slot block bags, the solver, the raster and the win checker from
## `match_config`, then starts the countdown.
##
## Legal from **any** state, on the host and on a client alike (a client's
## copy is called by net/MatchNet.gd's net_match_start with whatever state
## its mirror was left in). A start from anything but LOBBY first goes back
## through the lobby -- abort_match(), which emits (old -> LOBBY) so every
## consumer tears the previous match down -- so the transition consumers see
## for a genuine start is always exactly LOBBY -> LOADING (spec 3.7's
## `End -> Lobby -> Loading`), never PLAYING -> LOADING. A start from LOBBY
## still resets every per-match scalar silently: a client mirror sits in
## LOBBY with the previous match's slots and feed state after the host's
## replicated LOBBY change, and nothing of that may leak into the new match.
##
## **LOADING is emitted only once the world model is complete.** Main builds
## the match world synchronously inside that emit -- Field.set_overlay_source
## (Match.raster()), Field.place_flags(config), SnapshotSync.begin_match
## (Match.registry(), config.map_def()) -- so the raster, the slots and the
## configured registry must all exist before the signal goes out; emitting
## first and building afterwards handed those consumers a null raster (Beads
## Bontago-mv0.1.9). Nothing in the build reads _state, so building while
## still LOBBY costs nothing.
func start_match(match_config: MatchConfig) -> void:
	# DECISION (autoload/Match.gd): a repeated or stale start is handled here
	# rather than by every caller (the Lobby, net_match_start, the tests, a
	# future rematch button): Match owns its state machine, so it is Match
	# that guarantees the sequence consumers can rely on.
	#
	# Bontago-mv0.1.13: set before the abort_match() branch below, not just
	# around the two _set_state() calls further down, so the leading
	# old_state->LOBBY transition a restart-from-PLAYING/END produces is
	# covered too -- see _starting's own doc.
	_starting = true
	if _state != MatchAutoload.State.LOBBY:
		abort_match()
	else:
		_reset_match_state()

	_match.config = match_config.duplicate(true) as MatchConfig
	_match.config.sanitize()

	# Bontago-1en.23 (M4 P5-TILT): register_world() itself runs before
	# start_match() on every path (hot-seat, sandbox and the lobby -- see
	# game/Main.gd's own "Wiring order matters" doc), before Match.config
	# exists, so this is the first point at which both the Field and the new
	# match's tilt_mode are known together. Runs on the host and on a client
	# alike: this whole function is what net/MatchNet.gd's net_match_start RPC
	# calls locally on a client's own Match copy (see this file's start_match()
	# doc above), so a client's Field spring stays enabled in step with the
	# host's rather than only reacting to specials it never simulates itself.
	_apply_tilt_mode()

	# DECISION (autoload/match/MatchLifecycle.gd, Bontago-mv0.20a): the lobby's
	# gravity_multiplier (spec 2.8 "Gravity 0.5x-2x") is written straight into
	# the shared config/physics_tuning.tres *instance* Match already holds
	# (_physics_tuning), not a config-local copy -- BlockFactory.build() and
	# every already-standing Block.apply_physics_tuning() (ui/TuningPanel.gd's
	# same live-apply path) both read that one shared object, so this is the
	# only write needed for every future spawn this match to pick it up. The
	# lobby value therefore overwrites the shared PhysicsTuning resource for
	# the rest of the process session; the F4 tuning panel's Reset re-reads
	# the .tres from disk, which still restores the shipped default, so this
	# is acceptable.
	_match._physics_tuning.gravity_multiplier = _match.config.gravity_multiplier
	for node: Node in _match.get_tree().get_nodes_in_group(Block.TUNING_GROUP):
		var block: Block = node as Block
		if block != null:
			block.apply_physics_tuning(_match._physics_tuning)

	_match._feed._feed_timer_enabled = not _match.config.sandbox

	_match._placement._clear_blocks()
	_build_slots()
	_match._feed._build_bags()
	_match._territory._build_territory()
	_match._placement._blocks_spawned = 0
	if _match._registry != null:
		_match._registry.set_host_authority(_match._is_host())
		_match._registry.configure(_match._field, _match.config.map_def())
		_match._registry.reset()

	_set_state(MatchAutoload.State.LOADING)

	_set_state(MatchAutoload.State.COUNTDOWN)
	_countdown_remaining = MatchAutoload.COUNTDOWN_SECONDS
	_countdown_last_whole = int(ceil(_countdown_remaining))
	Events.countdown_tick.emit(_countdown_last_whole)
	_starting = false


## Back to Lobby from anywhere, clearing the field. Emits (old -> LOBBY) even
## from LOBBY itself: callers that want silence check state() first
## (game/Main.gd does), and the emit is what tells every consumer -- Main's
## world, RemoteCursors, MatchNet's start flag -- that the match is over.
func abort_match() -> void:
	var old_state: MatchAutoload.State = _state
	_reset_match_state()
	_state = MatchAutoload.State.LOBBY
	Events.match_state_changed.emit(old_state, MatchAutoload.State.LOBBY)


## Everything one match owns, back to the empty state: blocks, slots, bags,
## feed and grace timers, the territory objects and the config. Shared by
## abort_match() and start_match() so neither can forget a field the other
## resets. Leaves _state alone -- the two callers differ only in what they
## emit about it.
func _reset_match_state() -> void:
	_match._placement._clear_blocks()
	_slots.clear()
	_match._feed._bags.clear()
	_match._feed._held_shapes.clear()
	_match._feed._feed_time_left.clear()
	_match._feed._feed_expired.clear()
	_match._feed._feed_seq.clear()
	_match._feed._release_locked.clear()
	_disconnect_grace_left.clear()
	_match._placement._blocks_spawned = 0
	_active_slot = -1
	_countdown_remaining = 0.0
	_countdown_last_whole = 0
	_match._territory._cell_grid = null
	_match._territory._raster = null
	_match._territory._solver = null
	_match._territory._win_checker = null
	_match._territory._last_groups = null
	_match._territory._solve_accum = 0.0
	_match._feed._feed_timer_enabled = true
	_match._gifts.reset()
	_match.config = null
	# Bontago-1en.23 (M4 P5-TILT): shared by abort_match() (teardown back to
	# LOBBY) and start_match()'s own leading call to this function (tearing
	# down whatever match was running before the new one's _apply_tilt_mode()
	# call re-enables it) -- Field is a persistent node game/Field.gd's own
	# clear_match_state() doc describes, so a tilt (and its spring velocity)
	# left enabled here would otherwise still be live the moment the field
	# sits idle behind the main menu. set_tilt_enabled(false) is also what
	# levels the disc (game/Field.gd: "Disabling mid-match also snaps the tilt
	# itself back to level"); a no-op if tilt was never enabled this match.
	if _match._field != null:
		_match._field.set_tilt_enabled(false)


## Bontago-1en.23 (M4 P5-TILT): turns the Field tilt controller on for the
## match that just got a config, per config/MatchConfig.gd's tilt_mode (spec
## 2.8). A no-op if register_world() was never called (some unit tests never
## hand Match a field at all) or by a caller who -- unlike every real path in
## game/Main.gd -- called start_match() before register_world().
##
## DECISION (autoload/match/MatchLifecycle.gd): written as an exhaustive match
## over TiltMode's two current members, both of which tilt (config/
## MatchConfig.gd's own comment: "PHYSICAL_BALANCE's weight-driven tilt is
## M6", not "PHYSICAL_BALANCE doesn't tilt yet" -- SPECIALS_ONLY's spring still
## runs under it in the meantime), rather than "!= some OFF value" that does
## not exist yet: a future OFF mode is one new branch calling
## set_tilt_enabled(false), not an inverted condition to re-derive.
func _apply_tilt_mode() -> void:
	if _match._field == null:
		return
	match _match.config.tilt_mode:
		MatchConfig.TiltMode.SPECIALS_ONLY, MatchConfig.TiltMode.PHYSICAL_BALANCE:
			_match._field.set_tilt_enabled(true)


func state() -> MatchAutoload.State:
	return _state


## Bontago-mv0.1.13: see _starting's own doc.
func is_starting_match() -> bool:
	return _starting


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return _countdown_remaining if _state == MatchAutoload.State.COUNTDOWN else 0.0


func _tick_countdown(delta: float) -> void:
	_countdown_remaining = maxf(_countdown_remaining - delta, 0.0)
	var whole: int = int(ceil(_countdown_remaining))
	if whole < _countdown_last_whole:
		_countdown_last_whole = whole
		Events.countdown_tick.emit(whole)
	if _countdown_remaining <= 0.0:
		_begin_playing()


func _begin_playing() -> void:
	_set_state(MatchAutoload.State.PLAYING)
	_active_slot = _next_alive_slot(-1)
	for i: int in range(_slots.size()):
		# Bontago-mv0.10 follow-up: set the interval before issuing, not
		# after -- _issue_next_block() emits Events.feed_block_issued
		# synchronously, and net/MatchNet.gd's handler reads feed_time_left()
		# at that exact moment to replicate it, so a client's mirror is only
		# ever as accurate as what this slot's timer already says.
		_match._feed._feed_time_left[i] = _match.config.block_timer
		_match._feed._feed_expired[i] = false
		_match._feed._issue_next_block(i)
	if _active_slot != -1:
		Events.turn_changed.emit(_active_slot)
	# The home circles exist from the first frame of play (spec 2.2), so the
	# raster must too: without this seeding solve the first 1/solve_hz second
	# of the match has an empty raster and every placement — even one right on
	# your own home flag — reads OUTSIDE_TERRITORY. delta is 0.0 so no
	# contested time accrues and no hole can open on the seeding step.
	if _match._territory._raster != null and _match._territory._solver != null:
		_match._territory._run_territory_step(0.0)


# --- Slots and teams --------------------------------------------------------

func slot_count() -> int:
	return _slots.size()


func slot(slot_id: int) -> PlayerSlot:
	if slot_id < 0 or slot_id >= _slots.size():
		return null
	return _slots[slot_id]


func team_of(slot_id: int) -> int:
	var target: PlayerSlot = slot(slot_id)
	return target.team_id if target != null else -1


## Hot-seat: the slot whose turn it is. Outside hot-seat this is the local
## player's slot, and every slot acts at once.
func active_slot() -> int:
	return _active_slot


## Hot-seat: hands the turn to the next slot. Called after a placement
## resolves, not by input.
func advance_turn() -> void:
	if not _match.config.hot_seat:
		return
	var next_slot: int = _next_alive_slot(_active_slot)
	_active_slot = next_slot
	if next_slot == -1:
		return
	_match._feed._feed_time_left[next_slot] = _match.config.block_timer
	_match._feed._feed_expired[next_slot] = false
	Events.turn_changed.emit(next_slot)


func _next_alive_slot(after: int) -> int:
	var count: int = _slots.size()
	if count == 0:
		return -1
	for step: int in range(1, count + 1):
		var candidate: int = (after + step) % count
		if _slots[candidate].home_flag_alive:
			return candidate
	return -1


func _build_slots() -> void:
	_slots.clear()
	var map_def: MapDef = _match.config.map_def()
	for i: int in range(_match.config.player_count):
		var color: Color = _match.config.player_colors[i % _match.config.player_colors.size()]
		var home: Vector2 = PlayerSlot.home_position_for(i, _match.config.player_count, map_def)
		var new_slot: PlayerSlot = PlayerSlot.new(i, _match.config.team_of_slot(i), "Player %d" % (i + 1), color, home)
		# Bontago-d5c (M5 P1): the trailing ai_count slots become bots; every
		# slot before that stays a human seat exactly as today. See
		# docs/M5_PLAN.md P1's own doc for why this is a one-line append.
		new_slot.is_bot = i >= _match.config.player_count - _match.config.ai_count
		_slots.append(new_slot)

	_match._feed._held_shapes.resize(_slots.size())
	_match._feed._feed_time_left.resize(_slots.size())
	_match._feed._feed_expired.resize(_slots.size())
	_match._feed._feed_seq.resize(_slots.size())
	_match._feed._release_locked.resize(_slots.size())
	_disconnect_grace_left.resize(_slots.size())
	for i: int in range(_slots.size()):
		_match._feed._held_shapes[i] = null
		_match._feed._feed_time_left[i] = _match.config.block_timer
		_match._feed._feed_expired[i] = false
		_match._feed._feed_seq[i] = 0
		_match._feed._release_locked[i] = false
		_disconnect_grace_left[i] = -1.0


# --- Disconnects (docs/M3a_PLAN.md question 2) ------------------------------

## Host only. The peer holding `slot_id` vanished: stop its feed at once and
## start NetConfig.disconnect_grace. If it has not come back by then the slot
## is eliminated exactly as a lost home flag does it — home_flag_alive goes
## false, Events.player_eliminated fires, its towers unanchor and lose their
## influence on the next solve, and the match ends if one player or team is
## left standing.
##
## Its held block needs no cleanup: a held block is a ghost, drawn only on its
## owner's screen and held here as a BlockShape, so there is nothing in the
## physics world to tidy. An intent already in flight is refused by
## net/MatchNet.gd's peer check, its sender no longer holding a slot.
func on_peer_left(slot_id: int) -> void:
	if not _match._is_host():
		return
	if slot_id < 0 or slot_id >= _slots.size():
		return
	if not _slots[slot_id].home_flag_alive:
		return
	_disconnect_grace_left[slot_id] = maxf(_match._net_config.disconnect_grace, 0.0)


## Host only. The peer came back inside the grace period: resume its feed with
## a full block timer, so it is not auto-dropped the instant it reconnects.
func on_peer_rejoined(slot_id: int) -> void:
	if not _match._is_host():
		return
	if slot_id < 0 or slot_id >= _disconnect_grace_left.size():
		return
	if _disconnect_grace_left[slot_id] < 0.0:
		return
	_disconnect_grace_left[slot_id] = -1.0
	if _match.config != null:
		_match._feed._feed_time_left[slot_id] = _match.config.block_timer
		_match._feed._feed_expired[slot_id] = false


## Seconds left before `slot_id` is eliminated for being gone, or -1 when its
## peer is connected. The lobby and the HUD read this; nothing else.
func disconnect_grace_left(slot_id: int) -> float:
	if slot_id < 0 or slot_id >= _disconnect_grace_left.size():
		return -1.0
	return _disconnect_grace_left[slot_id]


func _tick_disconnect_grace(delta: float) -> void:
	for i: int in range(_disconnect_grace_left.size()):
		if _disconnect_grace_left[i] < 0.0:
			continue
		_disconnect_grace_left[i] -= delta
		if _disconnect_grace_left[i] > 0.0:
			continue
		_disconnect_grace_left[i] = -1.0
		_eliminate_slot(i)


## The one elimination path, shared by a home flag lost to a hole (spec 2.2)
## and by a peer that never came back (docs/M3a_PLAN.md question 2), so the
## two cannot drift apart.
func _eliminate_slot(slot_id: int) -> void:
	var target: PlayerSlot = _slots[slot_id]
	if not target.home_flag_alive:
		return
	target.home_flag_alive = false
	Events.player_eliminated.emit(target.slot_id, target.team_id)
	_check_last_team_standing()


func _check_last_team_standing() -> void:
	if _state != MatchAutoload.State.PLAYING:
		return
	var alive_teams: Dictionary = {}
	for slot_item: PlayerSlot in _slots:
		if slot_item.home_flag_alive:
			alive_teams[slot_item.team_id] = true
	if alive_teams.size() == 1:
		_finish_match(alive_teams.keys()[0])


func _finish_match(winning_team: int) -> void:
	_set_state(MatchAutoload.State.END)
	Events.match_won.emit(winning_team)


func _set_state(new_state: MatchAutoload.State) -> void:
	var old_state: MatchAutoload.State = _state
	_state = new_state
	Events.match_state_changed.emit(old_state, new_state)


# --- The client's read model (spec 3.4) -------------------------------------

## Mirrors the host's state machine. Re-emits match_state_changed only on a
## real change, so a client that already moved itself (the countdown it ran
## locally, say) does not emit twice.
func apply_replicated_state_change(new_state: int) -> void:
	if _state == new_state:
		return
	_set_state(new_state as MatchAutoload.State)


func apply_replicated_countdown(seconds_left: int) -> void:
	_countdown_remaining = float(seconds_left)
	_countdown_last_whole = seconds_left


func apply_replicated_turn(slot_id: int) -> void:
	_active_slot = slot_id


func apply_replicated_elimination(slot_id: int) -> void:
	var target: PlayerSlot = slot(slot_id)
	if target != null:
		target.home_flag_alive = false
