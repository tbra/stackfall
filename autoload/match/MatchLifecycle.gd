class_name MatchLifecycle
extends RefCounted
## Match's state machine (Lobby -> Loading -> Countdown -> Playing -> End ->
## Lobby, spec 3.7), slots/teams, disconnect grace and hot-seat turn logic.
##
## Split out of autoload/Match.gd (pure refactor: no behaviour change). See
## that file's own header comment for the full state-machine contract.

## Bontago-1pi.18.1: the shared (F4-editable) QoL experiment toggles.
const QOL_EXPERIMENTS: QolExperiments = preload("res://config/qol_experiments.tres")
## Bontago-1pi.32: min display time and ready-wait cap of the loading-screen gate.
const LOADING_TUNING: LoadingScreenTuning = preload("res://config/loading_screen_tuning.tres")

var _match: MatchAutoload = null

var _state: MatchAutoload.State = MatchAutoload.State.LOBBY
var _countdown_remaining: float = 0.0
var _countdown_last_whole: int = 0
## Bontago-mp0.27: while true the countdown does not run down. Game/Main.gd
## holds it from LOADING until the fullscreen loading screen is done, so the
## 3-2-1 is actually seen. Cleared by every match reset.
var _countdown_held: bool = false

## -- Loading-screen ready gate (Bontago-1pi.32) ---------------------------------
## Owner playtest 2026-10-03: every human presses ready (ui_accept / gamepad A)
## on the loading screen before the countdown runs (1pi.63: no minimum display time). The rule is core/LoadingReadyGate.gd; this file owns the
## per-match state and the host's hooks. Net (autoload/Net.gd) is the transport:
## it validates the sender and hands the intent over on the Events bus.
##
## DECISION: the gate is *armed* by ui/LoadingScreen.gd when it shows for a
## match (arm_loading_ready_gate()), and only when a window exists (not
## headless) and the run is not an agent probe -- the same conditions game/Main.gd
## uses to run the staged build behind the loading screen (headless or
## AgentProbe.is_active() keep the synchronous start contract). Sandbox never
## raises the overlay so it is never gated; the tutorial, hot-seat, vs-bots and
## online matches all are. Headless tests, bot harnesses and windowed
## --agent-probe tools (screenshots, benches) drive Match by hand and see no gate
## (set_loading_gate_forced() is the test/harness seam that arms it anyway; the
## ready-prompt probe tools/screenshot_loading_ready.gd forces it). An unarmed
## gate opens immediately, so a client of an ungated host is never left waiting.
var _loading_tuning: LoadingScreenTuning = LOADING_TUNING
var _ready_gate: LoadingReadyGate = LoadingReadyGate.new()
var _gate_armed: bool = false
var _gate_forced: bool = false
## Client mirror of the host's gate (loading_ready_changed / loading_gate_opened).
var _gate_open_mirror: bool = false
var _ready_mirror: PackedInt32Array = PackedInt32Array()
var _required_mirror: PackedInt32Array = PackedInt32Array()
## Host: the sets last published, so only a real change goes out.
var _published_ready: PackedInt32Array = PackedInt32Array()
var _published_required: PackedInt32Array = PackedInt32Array()
var _published_any: bool = false
## Test-only: ready intents refused since the match started (wrong phase, a peer
## that is not required). Repeats of an accepted intent are not counted.
var loading_ready_refused: int = 0

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

## -- Match timer + sudden death (spec 2.8, M6 A3) ----------------------------

## Seconds left on the match timer, armed at State.PLAYING entry from
## config.match_timer_minutes * 60.0. 0.0 means "off" (spec 2.8's own range
## row: "Off / 10-40 min") and _tick_match_timer() is then a permanent no-op
## for the rest of the match -- config.match_timer_minutes == 0 must never
## start sudden death, timer or no.
var _match_timer_left: float = 0.0
## Whole seconds of _match_timer_left at the last timed-mode state publish, so
## clients get a once-per-second timer update; -1 = none yet this match.
var _last_published_second: int = -1
## Latest mode snapshot received before the objective was built (client).
var _pending_mode_state: Dictionary = {}

## Seconds since State.SUDDEN_DEATH was entered. Drives both the gift-chance
## ramp (MatchGifts._effective_special_frequency()) and the disk shrink
## schedule below. Reset at _begin_sudden_death().
var _sudden_death_elapsed: float = 0.0

## The last shrink radius MatchTerritory.shrink_to_radius() was actually
## called with, so _tick_sudden_death() only re-punches once the computed
## radius has actually dropped another step rather than re-scanning every
## in-disk cell every frame for no new holes. INF before sudden death has
## shrunk the disk at all, so the very first call (radius = field_radius)
## always runs once.
var _last_shrink_radius: float = INF

## -- Turn-based (spec 2.7, M6 B4) ---------------------------------------------

## Seconds left before a turn-based placement's settle-wait forces the turn to
## advance anyway, or -1.0 when no wait is running (not turn-based, or the
## current turn's placement already settled and advanced). Armed by
## begin_turn_settle_wait() and ticked down by _tick_turn_based(); cleared the
## moment advance_turn() actually fires so a second placement mid-wait (a
## bot's held block, an already-in-flight throw) cannot arm a second,
## overlapping wait -- the plan's one-active-wait-at-a-time contract.
var _turn_settle_wait_left: float = -1.0


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	# Bontago-1pi.32: Net hands over validated intents and the host's mirror on the
	# bus (it never names Match); a roster change re-evaluates the required set.
	Events.net_loading_ready_received.connect(_on_loading_ready_intent)
	Events.loading_ready_changed.connect(_on_loading_ready_changed)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)
	Events.net_peer_left.connect(_on_loading_roster_changed)
	Events.net_peer_joined.connect(_on_loading_roster_changed)
	# Bontago-1pi.49: a roster change mid-match (a late joiner taking a seat, a rejoin)
	# carries the new player's name onto the slot the results are read from.
	Events.net_roster_changed.connect(_on_roster_names_changed)


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
	# Bontago-1pi.18.1 DECISION: the host snapshots the shared QoL experiment
	# toggles once here (unless the caller already supplied some, e.g. a test);
	# a client keeps whatever net_match_start's dict carried, so both ends run
	# the same values for the whole match even if the F4 panel is edited later.
	if _match._is_host() and _match.config.qol == null:
		_match.config.qol = QOL_EXPERIMENTS.duplicate() as QolExperiments
	_match.config.sanitize()
	# Bontago-1pi.62: the host names its bots once; clients keep the names the
	# config dict carried.
	if _match._is_host():
		_assign_bot_names()
	# Bontago-470.4: the host resolves Random once; a client keeps the id it
	# was sent (net_match_start carries sky_theme_resolved).
	if _match._is_host():
		_match.config.resolve_sky_theme(randi())
		# Bontago-59o.18 (C1b follow-up): and the cycle sky's variation seed, so every
		# match (not just seeded ones) draws its own curve; it rides in to_dict().
		_match.config.resolve_sky_variation_seed(randi())
		# Bontago-1pi.75: and the random phase a Cycle sky opens at (seed-derived).
		var sky_source: SkyThemeDef = Skybox.load_theme(Skybox.DEFAULT_THEME_ID)
		if sky_source != null:
			_match.config.resolve_sky_start_phase(randi(), sky_source.cycle_random_start_min, sky_source.cycle_random_start_max)

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
	_match._physics_tuning.gravity_multiplier = _match._physics_tuning.lobby_gravity_baseline * _match.config.gravity_multiplier
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
	# Bontago-1pi.32: the real arm happens in ui/LoadingScreen.gd's LOADING handler
	# above; the test/harness seam arms here for runs with no overlay.
	if _gate_forced:
		arm_loading_ready_gate()

	_set_state(MatchAutoload.State.COUNTDOWN)
	_countdown_remaining = _match.config.effective_countdown_seconds()
	_countdown_last_whole = int(ceil(_countdown_remaining))
	Events.countdown_tick.emit(_countdown_last_whole)
	_starting = false
	# Bontago-1pi.32: after net_match_start went out (it is queued by the
	# LOADING -> COUNTDOWN emit above), so a client's reliable channel delivers
	# the gate state to a match it has already built.
	_publish_loading_gate_start()
	# Bontago-1pi.79: every slot holds its first block from the moment the
	# countdown exists (the HUD cards and the local ghost are populated when the
	# ready gate opens, not on the first PLAYING frame). Placement stays
	# PLAYING-only and the feed timers only tick in PLAYING, so nothing can be
	# released early; _begin_playing() below only arms the timers.
	if _match._is_host():
		_issue_first_blocks()


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
	_countdown_held = false
	_reset_loading_gate()
	_match_timer_left = 0.0
	_sudden_death_elapsed = 0.0
	_last_shrink_radius = INF
	_turn_settle_wait_left = -1.0
	# Bontago-1pi.11.28: no async solve outlives the territory it would apply to.
	_match._territory.cancel_pending()
	_match._territory._cell_grid = null
	_match._territory._raster = null
	_match._territory._solver = null
	_match._territory._win_checker = null
	_match._territory._objective = null
	_last_published_second = -1
	_pending_mode_state = {}
	_match._territory._last_groups = null
	_match._territory._solve_accum = 0.0
	# Bontago-1pi.46 (G3): no stale influence circles into the next match's replication.
	_match._territory.clear_circles()
	_match._feed._feed_timer_enabled = true
	_match._gifts.reset()
	# Bontago-1pi.13: shared by abort_match() and start_match()'s own leading
	# call to this function, exactly like _match._gifts.reset() just above --
	# a replay or a return-to-lobby must never leak one match's stats into
	# the next. resize_for_slots() (this file's own _build_slots()) runs
	# after this on every start, so the arrays are always re-sized before
	# anything can bump them.
	_match._stats.reset()
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
		# M6 B5: also drops PHYSICAL_BALANCE's registry link on teardown, same
		# reasoning as set_tilt_enabled(false) above -- a leftover torque
		# source must not still be wired the moment the field sits idle behind
		# the main menu.
		_match._field.set_physical_balance_enabled(false)


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
##
## M6 B5: PHYSICAL_BALANCE additionally hands Field the same BlockRegistry
## Match already holds off register_world(), and explicitly clears it back off
## for SPECIALS_ONLY -- so a match that starts PHYSICAL_BALANCE, aborts, then
## starts a fresh SPECIALS_ONLY match cannot leave a stale torque source wired
## into a mode that should never tilt from settled weight at all.
func _apply_tilt_mode() -> void:
	if _match._field == null:
		return
	match _match.config.tilt_mode:
		MatchConfig.TiltMode.SPECIALS_ONLY:
			_match._field.set_physical_balance_enabled(false)
			_match._field.set_tilt_enabled(true)
		MatchConfig.TiltMode.PHYSICAL_BALANCE:
			_match._field.set_registry(_match._registry)
			_match._field.set_physical_balance_enabled(true)
			_match._field.set_tilt_enabled(true)


func state() -> MatchAutoload.State:
	return _state


## Bontago-mv0.1.13: see _starting's own doc.
func is_starting_match() -> bool:
	return _starting


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return _countdown_remaining if _state == MatchAutoload.State.COUNTDOWN else 0.0


func set_countdown_held(held: bool) -> void:
	_countdown_held = held


## True while the countdown cannot run down: Main's loading-screen hold, or the
## ready gate still waiting for the minimum display time / the players. Match's
## _process() keeps solving territory while this is true (the loading screen's
## readiness needs the first applied result).
func is_countdown_held() -> bool:
	return _countdown_held or loading_gate_blocking()


func _tick_countdown(delta: float) -> void:
	if _tick_loading_gate(delta):
		return
	if _countdown_held:
		return
	_countdown_remaining = maxf(_countdown_remaining - delta, 0.0)
	var whole: int = int(ceil(_countdown_remaining))
	if whole < _countdown_last_whole:
		_countdown_last_whole = whole
		Events.countdown_tick.emit(whole)
	if _countdown_remaining <= 0.0:
		_begin_playing()


func _begin_playing() -> void:
	_set_state(MatchAutoload.State.PLAYING)
	# Spec 2.8: "Match timer: Off / 10-40 min", 0 meaning off. Armed here (not
	# at start_match(), which runs during LOADING/COUNTDOWN) so config changes
	# made while still counting down are picked up, and so a match aborted
	# before ever reaching PLAYING never arms a timer it will not tick.
	_match_timer_left = _armed_timer_seconds()
	_active_slot = _next_alive_slot(-1)
	_issue_first_blocks()
	if _active_slot != -1:
		Events.turn_changed.emit(_active_slot)
	# The home circles exist from the first frame of play (spec 2.2), so the
	# raster must too: without this seeding solve the first 1/solve_hz second
	# of the match has an empty raster and every placement — even one right on
	# your own home flag — reads OUTSIDE_TERRITORY. delta is 0.0 so no
	# contested time accrues and no hole can open on the seeding step.
	if _match._territory._raster != null and _match._territory._solver != null:
		_match._territory._run_territory_step(0.0)


## Arms every slot's block timer and issues its first block. Idempotent: a slot
## that already holds its first block (issued when the countdown began, Bontago-
## 1pi.79) is left alone, so the bag is never advanced twice.
func _issue_first_blocks() -> void:
	for i: int in range(_slots.size()):
		# Bontago-mv0.10 follow-up: set the interval before issuing, not
		# after -- _issue_next_block() emits Events.feed_block_issued
		# synchronously, and net/MatchNet.gd's handler reads feed_time_left()
		# at that exact moment to replicate it, so a client's mirror is only
		# ever as accurate as what this slot's timer already says.
		_match._feed._feed_time_left[i] = _match.config.block_timer
		_match._feed._feed_expired[i] = false
		if _match._feed._held_shapes[i] == null:
			_match._feed._issue_next_block(i)


# --- Loading-screen ready gate (Bontago-1pi.32) -----------------------------

## Test/harness seam: arm the gate at every start_match() even headless. Production
## code never calls it; ui/LoadingScreen.gd arms through arm_loading_ready_gate().
func set_loading_gate_forced(forced: bool) -> void:
	_gate_forced = forced


## Called by ui/LoadingScreen.gd while it shows for a match (LOADING). Starts the
## host's min-display/ready clock; a client just starts waiting for the host's
## open message. Returns whether the gate is armed. See the DECISION above.
func arm_loading_ready_gate() -> bool:
	if _gate_armed:
		return true
	if _state != MatchAutoload.State.LOADING:
		return false
	if not _gate_forced and gate_suppressed_for_environment(DisplayServer.get_name(), AgentProbe.is_active()):
		return false
	if not _gate_armed:
		_gate_armed = true
		_gate_open_mirror = false
		_ready_gate.begin(_loading_tuning.ready_wait_max_s)
	return true


## Pure: a headless display or an agent-probe run never arms the gate on its own
## (nobody is there to press ready, and a probe tool would otherwise sit 5-60 s on
## the overlay). Bontago-1pi.32 review: the probe half mirrors game/Main.gd's
## staged-build condition.
static func gate_suppressed_for_environment(display_name: String, probe_active: bool) -> bool:
	return display_name == "headless" or probe_active


func is_loading_gate_armed() -> bool:
	return _gate_armed


## True while an armed gate has not opened yet -- on the host from its own rule,
## on a client from the host's open message. A client also stops waiting once the
## host's match has moved past the countdown (a missed message, a late join).
func loading_gate_blocking() -> bool:
	if not _gate_armed:
		return false
	# DECISION (fca.36.3): the gate exists only in the pre-play window LOADING..COUNTDOWN,
	# a set no other site shares, so it is not a Match predicate.
	var pre_play: bool = _state == MatchAutoload.State.LOADING
	pre_play = pre_play or _state == MatchAutoload.State.COUNTDOWN
	if not pre_play:
		return false
	return not (_ready_gate.is_open() if _match._is_host() else _gate_open_mirror)


## The peers the host waits for: connected peers holding a human slot (bots are
## auto-ready and never listed); offline/hot-seat the single local peer id, which
## stands for every local human. A client returns the host's last mirror.
func loading_required_peers() -> PackedInt32Array:
	if not _match._is_host():
		return _required_mirror
	var session: Variant = _loading_session()
	var result: PackedInt32Array = PackedInt32Array()
	if bool(session.is_offline()):
		for slot_item: PlayerSlot in _slots:
			if not slot_item.is_bot:
				result.append(int(session.local_peer_id()))
				break
		return result
	for peer_id: int in session.peer_ids():
		var slot_id: int = int(session.slot_of_peer(peer_id))
		if slot_id >= 0 and slot_id < _slots.size() and not _slots[slot_id].is_bot:
			result.append(peer_id)
	return result


## Required peers that already pressed ready (a client: the host's mirror).
func loading_ready_peers() -> PackedInt32Array:
	if not _match._is_host():
		return _ready_mirror
	return _ready_gate.ready_ids(loading_required_peers())


## Ready state of one slot for a player list: a bot is always ready; a human is
## ready once the peer holding it is.
func loading_slot_ready(slot_id: int) -> bool:
	var target: PlayerSlot = slot(slot_id)
	if target == null:
		return false
	if target.is_bot:
		return true
	var session: Variant = _loading_session()
	var peer_id: int = int(session.local_peer_id()) if bool(session.is_offline()) else int(session.peer_of_slot(slot_id))
	return peer_id >= 0 and loading_ready_peers().has(peer_id)


func _loading_session() -> Variant:
	return _match._net_provider if _match._net_provider != null else Net


func _reset_loading_gate() -> void:
	_gate_armed = false
	_gate_open_mirror = false
	_ready_mirror = PackedInt32Array()
	_required_mirror = PackedInt32Array()
	_published_ready = PackedInt32Array()
	_published_required = PackedInt32Array()
	_published_any = false
	loading_ready_refused = 0
	_ready_gate.begin(0.0)


## Host. Net already checked the sender is a seated peer; this checks the phase
## (an armed gate that has not opened), that the peer is one the gate waits for
## (a human slot's owner, not a spectator or a bot's seat) and ignores repeats.
func _on_loading_ready_intent(peer_id: int) -> void:
	if not _match._is_host():
		return
	if not loading_gate_blocking():
		loading_ready_refused += 1
		return
	if _ready_gate.is_ready(peer_id):
		return
	if not _ready_gate.mark_ready(peer_id, loading_required_peers()):
		loading_ready_refused += 1
		return
	_publish_loading_ready()


## Client: mirrors the host's sets. The host's own emit is ignored (it is the source).
func _on_loading_ready_changed(ready_ids: PackedInt32Array, required_ids: PackedInt32Array) -> void:
	if _match._is_host():
		return
	_ready_mirror = ready_ids
	_required_mirror = required_ids


func _on_loading_gate_opened() -> void:
	if _match._is_host():
		return
	_gate_open_mirror = true


## A peer joined or left: re-evaluate the required set (a leaver drops out at
## once; a joiner is waited for) and let the clients know.
func _on_loading_roster_changed(_peer_id: int, _slot_id: int, _extra: Variant) -> void:
	if _match._is_host() and loading_gate_blocking():
		_publish_loading_ready()


## Host. Ticks the gate from the countdown tick; true while it still blocks.
func _tick_loading_gate(delta: float) -> bool:
	if not _gate_armed or not _match._is_host() or _ready_gate.is_open():
		return false
	var required: PackedInt32Array = loading_required_peers()
	if _ready_gate.tick(delta, required):
		_publish_loading_ready()
		Events.loading_gate_opened.emit()
		return false
	_publish_loading_ready()
	return true


## Host. Publishes the current sets when they changed (the Net transport mirrors
## the signal to clients).
func _publish_loading_ready(force: bool = false) -> void:
	var required: PackedInt32Array = loading_required_peers()
	var ready_ids: PackedInt32Array = _ready_gate.ready_ids(required)
	if not force and _published_any and ready_ids == _published_ready and required == _published_required:
		return
	_published_any = true
	_published_ready = ready_ids
	_published_required = required
	Events.loading_ready_changed.emit(ready_ids, required)


## Host. The gate as a peer joining mid-countdown must see it: [ready peer ids,
## required peer ids, open] (Bontago-1pi.42). net/MatchNet.gd sends it inside the
## world replay, i.e. after the joiner's own start_match() -- the net_peer_joined
## handler above runs before MatchNet's replay, so its roster broadcast lands on the
## joiner ahead of net_match_start and is wiped by the reset. An unarmed gate (a
## headless host) counts as open, like _publish_loading_gate_start(). Who is
## required is unchanged: a joiner without a human seat never is.
func loading_gate_replay_args() -> Array:
	if not _match._is_host():
		return []
	if not _gate_armed:
		return [PackedInt32Array(), PackedInt32Array(), true]
	var required: PackedInt32Array = loading_required_peers()
	return [_ready_gate.ready_ids(required), required, _ready_gate.is_open()]


func _publish_loading_gate_start() -> void:
	if not _match._is_host():
		return
	if _gate_armed:
		_publish_loading_ready(true)
	else:
		Events.loading_gate_opened.emit()


# --- Match timer + sudden death (spec 2.8, M6 A3) ---------------------------

## Seconds left on the match timer, or 0.0 once it has run out or was never
## armed (config.match_timer_minutes == 0, "Off").
func match_timer_left() -> float:
	return _match_timer_left


## True only in State.SUDDEN_DEATH. ui/HUD.gd may read this later (M6 A3's
## own brief); MatchGifts._effective_special_frequency() reads it now, to
## ramp the gift chance only once sudden death has actually started.
func sudden_death_active() -> bool:
	return _state == MatchAutoload.State.SUDDEN_DEATH


## Ticked from Match._process()'s State.PLAYING branch. A no-op once the
## timer has reached 0.0 (whether it was ever armed or already ran out), so a
## match with config.match_timer_minutes == 0 -- timer "Off" -- never enters
## sudden death no matter how long it plays (this file's own regression test).
func _tick_match_timer(delta: float) -> void:
	if _match_timer_left <= 0.0:
		return
	# The territory tick that runs just before this one in the same frame may
	# already have ended the round; never finish (or tick) a second time.
	if _state != MatchAutoload.State.PLAYING:
		return
	_match_timer_left = maxf(_match_timer_left - delta, 0.0)
	var objective: ModeObjective = _match._territory._objective
	if objective != null and objective.is_timed():
		# Timed modes: the timer ends the round through the objective, with no
		# sudden death (Bontago-22y.11). Clients get the time left once a second.
		if _match_timer_left <= 0.0:
			# Bontago-1pi.11.28: an in-flight async solve applies before the
			# round-end outcome is read, so it equals the synchronous result.
			_match._territory.flush_pending()
			if _state != MatchAutoload.State.PLAYING:
				return
			_finish_match(objective.on_round_timer_end())
		else:
			var whole: int = int(ceil(_match_timer_left))
			if whole != _last_published_second and objective.replicates_state():
				_last_published_second = whole
				Events.mode_state_changed.emit(_build_mode_state(objective))
		return
	if _match_timer_left <= 0.0 and _match.config != null and _match.config.sudden_death:
		_begin_sudden_death()
	# Spec 2.8: "Sudden death: Off/On ... on if match timer is set" by
	# default, independently toggleable -- config.sudden_death == false with a
	# set timer means the timer simply becomes cosmetic once it hits zero
	# (this function's own doc header comment; also this package's plan
	# doc). Falling through here (no transition) is exactly that: the match
	# keeps running PLAYING under normal rules with no more timer.


## Seconds the match timer starts with: a timed mode's round_timer_minutes, else
## classic's match_timer_minutes (0 = off). Host-side, read at PLAYING start.
func _armed_timer_seconds() -> float:
	var objective: ModeObjective = _match._territory._objective
	if objective != null and objective.is_timed():
		return _match.config.round_timer_minutes * 60.0
	return _match.config.match_timer_minutes * 60.0 if _match.config.match_timer_minutes > 0 else 0.0


func _build_mode_state(objective: ModeObjective) -> Dictionary:
	var state: Dictionary = objective.mode_state()
	state["round_left"] = _match_timer_left
	return state


## Host: emits Events.mode_state_changed when the objective's state changed
## since the last publish (MatchNet replicates it). No-op for classic.
func publish_mode_state_if_changed() -> void:
	var objective: ModeObjective = _match._territory._objective
	if objective == null or not objective.replicates_state():
		return
	if objective.consume_state_dirty():
		Events.mode_state_changed.emit(_build_mode_state(objective))


## Client: mirrors the host's validated mode state for display; never decides
## an outcome (the match ends only via the replicated state/win events).
func apply_replicated_mode_state(state: Dictionary) -> void:
	var objective: ModeObjective = _match._territory._objective
	if objective == null:
		# Rejoin snapshot can arrive before the objective is built: keep the
		# latest and apply it once it exists (flush_pending_mode_state()).
		_pending_mode_state = state
		return
	if objective.mode_id() != int(state.get("mode_id", -1)):
		return
	objective.apply_mode_state(state)
	if objective is EliminationObjective:
		# A rejoining or late client learns who is out from the state itself.
		for slot_item: PlayerSlot in _slots:
			if (objective as EliminationObjective).is_slot_out(slot_item.slot_id):
				slot_item.home_flag_alive = false
	_match_timer_left = float(state.get("round_left", _match_timer_left))
	Events.mode_state_changed.emit(state)


## Client: applies a mode snapshot that arrived before the objective existed.
func flush_pending_mode_state() -> void:
	if _pending_mode_state.is_empty() or _match._territory._objective == null:
		return
	var pending: Dictionary = _pending_mode_state
	_pending_mode_state = {}
	apply_replicated_mode_state(pending)


## Current mode state for a late joiner/reconnect snapshot, or {} (classic or
## no objective).
func mode_state_snapshot() -> Dictionary:
	var objective: ModeObjective = _match._territory._objective
	if objective == null or not objective.replicates_state():
		return {}
	return _build_mode_state(objective)


func _begin_sudden_death() -> void:
	_sudden_death_elapsed = 0.0
	_last_shrink_radius = INF
	_set_state(MatchAutoload.State.SUDDEN_DEATH)


## Ticked from Match._process()'s new State.SUDDEN_DEATH branch, alongside
## the same three ticks State.PLAYING already runs (disconnect grace, feed,
## territory) -- spec 2.8's three bullets: the gift-chance ramp is
## MatchGifts._effective_special_frequency()'s own job (reads
## sudden_death_active()/`_sudden_death_elapsed` above), so this function
## only has to run the disk shrink and, once it has crumbled far enough, the
## radius-8 tiebreak.
func _tick_sudden_death(delta: float) -> void:
	if _match.config == null:
		return
	_sudden_death_elapsed += delta

	var tuning: TerritoryTuning = _match._territory_tuning
	var field_radius: float = _match.config.map_def().field_radius
	var interval: float = maxf(tuning.sudden_death_shrink_interval_s, 0.001)
	# Spec 2.8: "crumbles inward by 1 m every 10 s" -- recomputed from total
	# elapsed time rather than a second running accumulator, so a caller that
	# fast-forwards with one large delta (a test, a client that missed a few
	# frames) lands on exactly the same radius a real match reaches one frame
	# at a time.
	var steps: float = floor(_sudden_death_elapsed / interval)
	var shrink_radius: float = field_radius - steps * tuning.sudden_death_shrink_step_m

	if shrink_radius < _last_shrink_radius:
		_last_shrink_radius = shrink_radius
		_match._territory.shrink_to_radius(shrink_radius)

	if shrink_radius <= tuning.sudden_death_tiebreak_radius_m:
		_resolve_sudden_death_tiebreak()


## Spec 2.8: "If nobody has won when the disk has shrunk to a radius of 8,
## the player or team with the most territory wins." Guarded on _state still
## being SUDDEN_DEATH so a tiebreak already resolved (or a natural win landed
## the same tick) never calls _finish_match() a second time -- once this sets
## State.END, Match._process()'s match statement no longer reaches
## _tick_sudden_death() at all, so in practice this runs at most once, but the
## guard costs nothing and documents the invariant.
##
## DECISION (autoload/match/MatchLifecycle.gd, M6 A3): ties broken by lowest
## team id -- spec doesn't say, and an exact float tie between two teams'
## territory share is a vanishingly unlikely edge case not worth a second
## rule. `share > best_share` (strictly greater) rather than `>=` is what
## makes that deterministic: iterating team ids in ascending order, the first
## team to reach the current best share is the one that stays best on a tie.
func _resolve_sudden_death_tiebreak() -> void:
	if _state != MatchAutoload.State.SUDDEN_DEATH:
		return
	_match._territory.flush_pending()
	if _state != MatchAutoload.State.SUDDEN_DEATH:
		return
	var best_team: int = 0
	var best_share: float = -1.0
	for t: int in range(_match.config.team_count()):
		var share: float = _match._territory.territory_share(t)
		if share > best_share:
			best_share = share
			best_team = t
	_finish_match(best_team)


# --- Turn-based (spec 2.7, M6 B4) --------------------------------------------

## DECISION (autoload/match/MatchLifecycle.gd, M6 B4, per docs/M6_PLAN.md's B4
## section): turn_based and hot_seat are mutually exclusive in practice -- the
## lobby never offers hot_seat, and the CLI --hot-seat path never sets
## turn_based -- so nothing here resolves "both true" (advance_turn()'s own
## instant hand-off would just win, since it runs unconditionally once either
## flag is set). config.sanitize() does not need a cross-field rule for a
## combination no caller can reach.

## Called from MatchPlacement's two hot-seat advance_turn() sites, in the
## turn_based branch alongside them: arms the settle-wait instead of handing
## the turn over immediately. A no-op outside turn_based (callers only reach
## this from the turn_based branch, but the guard keeps the field itself
## authoritative about whether a wait is actually running).
func begin_turn_settle_wait() -> void:
	if _match.config == null or not _match.config.turn_based:
		return
	_turn_settle_wait_left = _match._territory_tuning.turn_based_max_settle_s


## Ticked from Match._process()'s State.PLAYING and State.SUDDEN_DEATH
## branches, only when config.turn_based (mirrors _tick_sudden_death()'s own
## call site pattern). Spec 2.7: "Physics settles completely (all bodies
## asleep, or after 6 s) before the next player's turn starts" -- hands the
## turn over the instant every tracked block is settled, or once the safety
## cap runs out, whichever comes first, so one block that never fully sleeps
## cannot stall the match forever.
func _tick_turn_based(delta: float) -> void:
	if _match.config == null or not _match.config.turn_based:
		return
	if _turn_settle_wait_left < 0.0:
		return
	if _match._registry != null and _match._registry.all_settled():
		_turn_settle_wait_left = -1.0
		advance_turn()
		return
	_turn_settle_wait_left = maxf(_turn_settle_wait_left - delta, 0.0)
	if _turn_settle_wait_left <= 0.0:
		_turn_settle_wait_left = -1.0
		advance_turn()


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


## Hot-seat and turn-based: hands the turn to the next slot. Called after a
## placement resolves (hot-seat: immediately; turn-based: once
## _tick_turn_based() decides the settle-wait is over), not by input.
func advance_turn() -> void:
	if not _match.config.is_sequential_play():
		return
	# Any settle-wait belonged to the outgoing turn. If the active slot was
	# eliminated mid-wait, MatchFeed._tick_feed() advances the turn here and
	# the stale wait must not fire a second advance_turn() once settled or
	# capped (Bontago-keo.10 review follow-up).
	_turn_settle_wait_left = -1.0
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


## Bontago-1pi.62: the names this host gave its bots so far, by bot ordinal. They
## persist across matches (play again) and are trimmed when a bot seat goes away.
var _host_bot_names: PackedStringArray = PackedStringArray()


## Host only: fills config.bot_names (distinct from each other and from every human
## seat's name), keeping the names handed out earlier while still valid.
func _assign_bot_names() -> void:
	var config: MatchConfig = _match.config
	var taken: PackedStringArray = PackedStringArray()
	var human_count: int = config.player_count - config.ai_count
	for i: int in range(human_count):
		var human_name: String = _peer_name_for_slot(i)
		if human_name != "":
			taken.append(human_name)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if config.rng_seed >= 0:
		rng.seed = config.rng_seed
	else:
		rng.randomize()
	# The lobby already named the bots (config.bot_names): reuse, never re-roll.
	var existing: PackedStringArray = config.bot_names if not config.bot_names.is_empty() else _host_bot_names
	_host_bot_names = BotNames.assign(existing, config.ai_count, taken, rng)
	config.bot_names = _host_bot_names.duplicate()


func _build_slots() -> void:
	_slots.clear()
	var map_def: MapDef = _match.config.map_def()
	for i: int in range(_match.config.player_count):
		var color: Color = SlotColors.wrapped_color(i, _match.config.player_colors)
		var home: Vector2 = PlayerSlot.home_position_for(i, _match.config.player_count, map_def)
		# Bontago-d5c (M5 P1): the trailing ai_count slots become bots; every
		# slot before that stays a human seat exactly as today. See
		# docs/M5_PLAN.md P1's own doc for why this is a one-line append.
		var is_bot: bool = i >= _match.config.player_count - _match.config.ai_count
		# Bontago-1pi.49: a human seat carries the name the host replicated for its
		# peer (Net.name_for_slot, already sanitised by the host); a bot, an
		# offline hot-seat seat or an empty seat keeps "Player N". Host and client
		# both build from the same roster, so MatchStats' results (host-built,
		# read from PlayerSlot.display_name) and every slot reader agree.
		var bot_ordinal: int = i - (_match.config.player_count - _match.config.ai_count)
		var seat_name: String = PlayerNames.label_for_slot(
			i, PlayerNames.bot_label(i, bot_ordinal, _match.config.bot_names), is_bot, _peer_name_for_slot(i)
		)
		var new_slot: PlayerSlot = PlayerSlot.new(i, _match.config.team_of_slot(i), seat_name, color, home)
		new_slot.is_bot = is_bot
		_slots.append(new_slot)

	_match._feed._held_shapes.resize(_slots.size())
	_match._feed._feed_time_left.resize(_slots.size())
	_match._feed._feed_expired.resize(_slots.size())
	_match._feed._feed_seq.resize(_slots.size())
	_match._feed._release_locked.resize(_slots.size())
	_disconnect_grace_left.resize(_slots.size())
	# Bontago-1pi.13: sizes MatchStats' per-slot arrays now that the new
	# match's slot count is known (reset() above cannot do this -- it runs
	# before _build_slots() on start_match()'s own call order).
	_match._stats.resize_for_slots(_slots.size())
	for i: int in range(_slots.size()):
		_match._feed._held_shapes[i] = null
		_match._feed._feed_time_left[i] = _match.config.block_timer
		_match._feed._feed_expired[i] = false
		_match._feed._feed_seq[i] = 0
		_match._feed._release_locked[i] = false
		_disconnect_grace_left[i] = -1.0


## Bontago-1pi.49: the replicated name of the human peer seated at `slot_id`, or ""
## when nobody holds it (a bot, an empty or hot-seat seat, a departed player) or
## the session double has no name roster. Offline (sandbox / hot-seat) there are no
## peers, so the local human on slot 0 goes by the name saved in Settings.
# DECISION: offline, only slot 0 (the local player; Net.local_slot() is 0) takes the
# saved name; further hot-seat humans share the keyboard and stay "Player N".
func _peer_name_for_slot(slot_id: int) -> String:
	var session: Variant = _loading_session()
	if session == null:
		return ""
	var peer_name: String = ""
	if session.has_method(&"name_for_slot"):
		peer_name = String(session.name_for_slot(slot_id))
	if peer_name == "" and slot_id == 0 and session.has_method(&"is_offline") and bool(session.is_offline()):
		# Bontago-1pi.100: the Steam persona wins when Steam is up.
		if session.has_method(&"resolve_local_name"):
			return String(session.resolve_local_name(Settings.player_name()))
		return Settings.player_name()
	return peer_name


## Bontago-1pi.49: copies each human seat's current roster name onto its slot. A
## seat nobody holds keeps the last name it had (a player who left mid-match is
## still named in the results); bots are never touched.
func refresh_slot_names() -> void:
	for slot_item: PlayerSlot in _slots:
		if slot_item.is_bot:
			continue
		var peer_name: String = _peer_name_for_slot(slot_item.slot_id)
		if peer_name != "":
			slot_item.display_name = peer_name


func _on_roster_names_changed(_roster: Array[Dictionary]) -> void:
	refresh_slot_names()


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
	var eliminated_any: bool = false
	for i: int in range(_disconnect_grace_left.size()):
		if _disconnect_grace_left[i] < 0.0:
			continue
		_disconnect_grace_left[i] -= delta
		if _disconnect_grace_left[i] > 0.0:
			continue
		_disconnect_grace_left[i] = -1.0
		_eliminate_slot(i)
		eliminated_any = true
	if eliminated_any and _match._territory._objective is EliminationObjective:
		_check_last_team_standing()


## The one elimination path, shared by a home flag lost to a hole (spec 2.2)
## and by a peer that never came back (docs/M3a_PLAN.md question 2), so the
## two cannot drift apart.
func _eliminate_slot(slot_id: int) -> void:
	var target: PlayerSlot = _slots[slot_id]
	if not target.home_flag_alive:
		return
	target.home_flag_alive = false
	var objective: ModeObjective = _match._territory._objective
	if objective is EliminationObjective:
		# Elimination judges a whole batch together (simultaneous home losses),
		# so the caller's _check_last_team_standing() runs after its loop.
		(objective as EliminationObjective).slot_eliminated(slot_id)
		Events.player_eliminated.emit(target.slot_id, target.team_id)
		return
	Events.player_eliminated.emit(target.slot_id, target.team_id)
	_check_last_team_standing()


func _check_last_team_standing() -> void:
	if not MatchAutoload.is_live(_state):
		return
	var elimination: ModeObjective = _match._territory._objective
	if elimination is EliminationObjective:
		_resolve_elimination(elimination as EliminationObjective)
		return
	var alive_teams: Dictionary = {}
	for slot_item: PlayerSlot in _slots:
		if slot_item.home_flag_alive:
			alive_teams[slot_item.team_id] = true
	if alive_teams.size() == 1:
		_finish_match(alive_teams.keys()[0])


## Elimination (Bontago-22y.8): the objective decides the outcome of the
## eliminations since the last call (last team standing, or the same-batch
## larger-share tiebreak) and the final state is published before the END.
func _resolve_elimination(objective: EliminationObjective) -> void:
	_match._territory.flush_pending()
	var shares: PackedFloat32Array = PackedFloat32Array()
	for team: int in range(_match.config.team_count()):
		shares.append(_match._territory.territory_share(team))
	var winning_team: int = objective.resolve(shares)
	publish_mode_state_if_changed()
	if winning_team != ModeObjective.NO_TEAM:
		_finish_match(winning_team)


func _finish_match(winning_team: int) -> void:
	var already_ended: bool = _state == MatchAutoload.State.END
	# Bontago-1pi.11.28: apply any in-flight solve before the results are built;
	# if that apply itself ended the match, it already published the outcome.
	_match._territory.flush_pending()
	if _state == MatchAutoload.State.END and not already_ended:
		return
	_set_state(MatchAutoload.State.END)
	Events.match_won.emit(winning_team)
	# Bontago-1pi.13: built after match_won so a listener that reacts to the
	# win first (ui/HUD.gd's show_winner()) and one that wants the fuller
	# payload (the results-screen UI worker) both see events in the same
	# order every match. _finish_match() only ever runs on the host (see
	# this function's own call sites: _check_last_team_standing() and
	# _resolve_sudden_death_tiebreak(), both reached only from Match._process's
	# `if not _is_host(): return`-gated ticks) -- a client's own copy never
	# calls this, and instead reaches State.END and its results payload
	# through EVENT_STATE_CHANGED and EVENT_MATCH_RESULTS respectively
	# (net/MatchNet.gd).
	var objective: ModeObjective = _match._territory._objective
	var mode_fields: Dictionary = {}
	if objective != null and objective.mode_id() != MatchConfig.GameMode.CLASSIC:
		mode_fields = objective.results_fields()
		mode_fields["mode_id"] = objective.mode_id()
		mode_fields["scores"] = Array(objective.scores())
	var results: Dictionary = _match._stats.build_results_payload(winning_team, mode_fields)
	Events.match_results_ready.emit(results)


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
