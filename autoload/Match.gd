class_name MatchAutoload
extends Node
## Match configuration and the host-side state machine (spec 3.7).
##
## Lobby -> Loading -> Countdown(3s) -> Playing -> (SuddenDeath) -> End -> Lobby.
## M2 implements Lobby, Loading, Countdown, Playing and End; SuddenDeath is
## M6.
##
## **This node is the authority.** Spec 3.4: "The host is authoritative, and
## only the host runs physics. Clients send intents. The host checks every
## intent before acting on it." Everything that decides an outcome lives here
## or in core/: the feed timers, the territory solve, the win check, and
## request_place(). Even in M2's hot-seat, where every player is local, the
## controllers do not spawn blocks themselves; they call request_place() and
## wait. M3a then only has to make request_place() reachable over an RPC,
## with no rule code to move.
##
## Signals are emitted on the Events bus rather than declared here, per
## CLAUDE.md's "use a global signal bus to decouple systems".
##
## Bontago-split.1 (pure refactor, no behaviour change): the state machine's
## rules used to all live directly on this Node. They now live in four
## RefCounted controllers under res://autoload/match/ -- MatchFeed (bags,
## held/next shapes, feed_seq, interval timers, the replicated feed mirror),
## MatchPlacement (request_place, pose validation, spawn/burn), MatchTerritory
## (territory build/solve, circles, elimination checks, the replicated
## territory mirror) and MatchLifecycle (the state machine itself, slots/
## teams, disconnect grace, hot-seat turns) -- each wired to this node via
## setup(self) in _ready() so none of them ever walks the scene tree to find
## it. This file keeps every existing public method (and the private/debug
## seams tests reach) as a one-line forward to whichever controller now owns
## the logic, so nothing outside autoload/match/ had to change.
##
## DECISION (autoload/Match.gd, Bontago-split.1): the class_name is
## `MatchAutoload`, not `Match` -- Godot 4.7 refuses `class_name Match` outright
## ("Class 'Match' hides an autoload singleton") since project.godot's
## [autoload] section already binds the global identifier `Match` to this
## script's singleton instance. `MatchAutoload` is the type every controller's
## `_match: MatchAutoload` field and `setup(match: MatchAutoload)` uses to stay
## statically typed (CLAUDE.md's "static typing everywhere"); the global name
## `Match` is untouched and still resolves to the autoload singleton
## everywhere it always has, so every existing `Match.foo()` call site outside
## this package is unaffected.

## Spec 3.7's states. The rules live in core/rules/MatchPhase.gd (Bontago-1pi.11.77.1, D4);
## the alias and the forwarding statics below keep every existing caller unchanged.
const State = MatchPhase.State


## LIVE = PLAYING, SUDDEN_DEATH (see MatchPhase.is_live).
static func is_live(state: int) -> bool:
	return MatchPhase.is_live(state)


static func is_replicating(state: int) -> bool:
	return MatchPhase.is_replicating(state)


static func is_resetting(state: int) -> bool:
	return MatchPhase.is_resetting(state)


static func is_in_progress(state: int) -> bool:
	return MatchPhase.is_in_progress(state)


static func is_pregame(state: int) -> bool:
	return MatchPhase.is_pregame(state)


static func is_lobby_or_end(state: int) -> bool:
	return MatchPhase.is_lobby_or_end(state)


static func is_start_transition(from_state: int, to_state: int) -> bool:
	return MatchPhase.is_start_transition(from_state, to_state)


## Spec 3.7: "Countdown(3s)". A fixed part of the state machine's shape, not a
## lobby setting (spec 2.8's table doesn't list it) — kept as a named constant
## here rather than in a Resource for the same reason
## BlockOrientations.ORIENTATION_COUNT is a const: it isn't tunable, it's the
## architecture (CLAUDE.md's "no magic numbers" targets tunables).
const COUNTDOWN_SECONDS: float = MatchConfig.COUNTDOWN_SECONDS_DEFAULT

## The config the running match was started with. A duplicate of whatever was
## handed to start_match(), never the shared config/match_defaults.tres.
var config: MatchConfig = null

var _physics_tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _block_feed_config: BlockFeedConfig = preload("res://config/block_feed.tres")
var _net_config: NetConfig = preload("res://config/net_config.tres")

## DECISION (autoload/Match.gd): Net is a plain autoload, and GUT cannot
## double one (see game/PlayerController.gd's matching DECISION), so every
## host gate below reads through this seam instead of naming `Net` directly.
## null means "the real Net", which is what every shipped build uses; a test
## injects a double with set_net_provider(). Net.is_host() is true offline
## too, so `if not _is_host(): return` changes nothing about M2's hot-seat.
var _net_provider: Variant = null

## Set by net/MatchNet.gd in its own _ready(). Match never calls rpc() and
## never names MatchNet as a global (the integrator registers that autoload
## after this one), so replication is a hook the membrane installs on itself:
## null means "not networked", which is exactly the M2 and single-player case.
var _replicator: Variant = null

var _field: Field = null
var _registry: BlockRegistry = null
var _blocks_parent: Node3D = null
## Sandbox may tune the cone projection or pause it for diagnostics. New
## matches use the owner-approved top-height cone projection by default.
## (Value 0 was the removed linear per-block model, Bontago-1pi.111; the
## remaining values keep their numbers.)
const SANDBOX_TERRITORY_CONE: int = 1
const SANDBOX_TERRITORY_PAUSED: int = 2
const DEFAULT_TERRITORY_MODE: int = SANDBOX_TERRITORY_CONE
const DEFAULT_CONE_ANGLE_DEGREES: float = InfluenceCircle.CONE_HALF_ANGLE_DEGREES
var _sandbox_territory_mode: int = DEFAULT_TERRITORY_MODE
var _sandbox_cone_angle: float = DEFAULT_CONE_ANGLE_DEGREES
var _sandbox_cone_height_source: int = SandboxConeExperiment.HEIGHT_TOP
var _sandbox_cone_base_mode: int = SandboxConeExperiment.BASE_ADDITIVE
var _sandbox_territory_profile_enabled: bool = false
var _territory_cache_enabled: bool = true

## Bontago-split.1: the four controllers this file forwards to. Built and
## wired in _ready() rather than at field-declaration time, so each one's
## setup(self) can hand back a fully-constructed Match reference.
var _feed: MatchFeed = null
var _placement: MatchPlacement = null
var _territory: MatchTerritory = null
var _lifecycle: MatchLifecycle = null

## M4 P1b: gift-crate spawn/claim/expire and the per-slot pending-special
## array. See autoload/match/MatchGifts.gd's own header for the split.
var _gifts: MatchGifts = null

## Bontago-1pi.13: per-slot match statistics and the results-screen payload
## builder. See autoload/match/MatchStats.gd's own header for the split and
## the full results payload contract.
var _stats: MatchStats = null

## Bontago-22y.10: host-scheduled weather events. See autoload/match/MatchWeather.gd.
var _weather: MatchWeather = null
var _cat: CatController = null
var _gift_fx: GiftFxPresenter = null
var _cat_serial: int = 0

## The MatchContext port world code reads (game/world/MatchContext.gd). Installed first thing in
## _ready(); uninstalled on PREDELETE so a freed Match never leaves a dangling static.
var _context: MatchContextLive = null


## The live port; world setup points that already receive Match hand it on (WeatherEffect.bind).
func context() -> MatchContext:
	return _context


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _context != null and MatchContext.installed() == _context:
			MatchContext.install(null)


func _ready() -> void:
	_context = MatchContextLive.new(self)
	MatchContext.install(_context)
	_feed = MatchFeed.new()
	_placement = MatchPlacement.new()
	_territory = MatchTerritory.new()
	_lifecycle = MatchLifecycle.new()
	_gifts = MatchGifts.new()
	_stats = MatchStats.new()
	_weather = MatchWeather.new()
	_feed.setup(self)
	_placement.setup(self)
	_territory.setup(self)
	_lifecycle.setup(self)
	_gifts.setup(self)
	_stats.setup(self)
	_weather.setup(self)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	# Bontago-1pi.85.8: one presenter owns every per-gift client visual
	# (Paintball splash, Black hole disc, ...); it subscribes to
	# Events.special_triggered itself.
	_gift_fx = GiftFxPresenter.new()
	_gift_fx.name = "GiftFxPresenter"
	add_child(_gift_fx)
	Events.match_state_changed.connect(_on_cat_match_state_changed)


func active_cat() -> CatController:
	return _cat if is_instance_valid(_cat) else null


func start_cat(owner_slot: int, position: Vector3, effect: CatEffect) -> bool:
	if not _is_host() or state() != State.PLAYING or effect == null or field() == null:
		return false
	if owner_slot < 0 or owner_slot >= slot_count() or not position.is_finite():
		return false
	if blocks_parent() == null or blocks_parent().get_child_count() >= effect.max_active_blocks:
		return false
	var point: Vector2 = field().disk_local_from_world(position)
	if not field().map_def.shape_contains(point):
		return false
	if active_cat() != null:
		end_cat(_cat.activation_id)
	_cat_serial += 1
	_cat = CatController.new()
	_cat.configure(_cat_serial, owner_slot,
		field().world_from_disk_local(point, effect.body_radius_m),
		effect.duration_s, effect.speed_mps, effect.target_range_m,
		effect.body_radius_m, effect.push_impulse, true)
	add_child(_cat)
	Events.cat_started.emit(_cat_serial, owner_slot, _cat.global_position, effect.duration_s)
	return true


func set_cat_target(slot_id: int, point: Vector3) -> bool:
	var cat: CatController = active_cat()
	if not _is_host() or cat == null or cat.owner_slot != slot_id or not is_live(state()):
		return false
	return cat.set_target(point)


func apply_replicated_cat_start(id: int, slot_id: int, position: Vector3, duration: float) -> bool:
	if _is_host() or id <= _cat_serial or slot_id < 0 or slot_id >= slot_count():
		return false
	if not position.is_finite() or not is_finite(duration) or duration <= 0.0:
		return false
	if active_cat() != null:
		_cat.queue_free()
	_cat_serial = id
	var effect: CatEffect = (load("res://config/specials/cat.tres") as SpecialDef).effect as CatEffect
	_cat = CatController.new()
	_cat.configure(id, slot_id, position, duration, effect.speed_mps,
		effect.target_range_m, effect.body_radius_m, effect.push_impulse, false)
	add_child(_cat)
	Events.cat_started.emit(id, slot_id, position, duration)
	return true


func apply_replicated_cat_state(id: int, position: Vector3, velocity: Vector3,
		point: Vector3, remaining: float) -> void:
	var cat: CatController = active_cat()
	if not _is_host() and cat != null and cat.activation_id == id and is_finite(remaining):
		cat.apply_snapshot(position, velocity, point, remaining)


func end_cat(id: int) -> void:
	var cat: CatController = active_cat()
	if cat == null or cat.activation_id != id:
		return
	cat.queue_free()
	_cat = null
	Events.cat_ended.emit(id)


func _on_cat_match_state_changed(_old: int, next: int) -> void:
	if is_resetting(next):
		var cat: CatController = active_cat()
		if cat != null:
			end_cat(cat.activation_id)


# --- Test/debug seams (Bontago-split.1) --------------------------------------
#
# tests/ and tools/ reach several of these directly (by grep of
# `Match\._` and `Match\.debug_`): _held_shapes (index-assigned), _raster and
# _solver (read, then a method called on the returned object), _territory_
# tuning (unchanged -- see above, never moved off Match), and the private
# methods below. Each forwards to the controller that now owns the field or
# method, and — since Array/Object are reference types in GDScript — an
# index-assignment through a get-only property still mutates the controller's
# own storage, exactly as before the split.

var _held_shapes: Array[BlockShape]:
	get:
		return _feed._held_shapes
	set(value):
		_feed._held_shapes = value

var _raster: TerritoryRaster:
	get: return _territory._raster

var _solver: TerritorySolver:
	get: return _territory._solver


func _resolve_outcome(initial_result: PlacementRules.Result, auto_drop: bool, relocated: Vector2) -> Dictionary:
	return _placement._resolve_outcome(initial_result, auto_drop, relocated)


func _finish_match(winning_team: int) -> void:
	_lifecycle._finish_match(winning_team)


func _check_home_flags(opened: PackedInt32Array) -> void:
	_territory._check_home_flags(opened)


func _check_home_flags_v2() -> void:
	_territory._check_home_flags_v2()


func _collect_circles() -> Array[InfluenceCircle]:
	return _territory._collect_circles()


## M4 P1b: MatchGifts.claim_or_expire_gifts() runs right after the raster
## updates (the plan's own "hooked into the existing _run_territory_step(),
## right after the raster updates"), by appending it to this forward rather
## than editing autoload/match/MatchTerritory.gd, which this package does not
## own.
func _run_territory_step(delta: float) -> void:
	_territory._run_territory_step(delta)
	_gifts.claim_or_expire_gifts(delta)


## Gift flight and landed expiry use physics time, independent of territory solve cadence.
func _physics_process(delta: float) -> void:
	var probe_gifts: int = PerfProbe.start()
	if _is_host() and _lifecycle != null and is_live(state()):
		_gifts.tick_host(delta)
	elif not _is_host() and _lifecycle != null and is_live(state()):
		_gifts.tick_client(delta)
	PerfProbe.stop(&"gifts", probe_gifts)
	# Bontago-22y.10: no-op unless a weather schedule is running.
	var probe_weather: int = PerfProbe.start()
	_weather.tick(delta)
	PerfProbe.stop(&"weather", probe_weather)


func debug_unlock_slot(slot_id: int) -> void:
	_feed.debug_unlock_slot(slot_id)


# --- Lifecycle --------------------------------------------------------------

## Hands Match the world it drives. Called once by Main after the scene is
## built, so nothing here ever walks the scene tree looking for its
## collaborators (CLAUDE.md). `registry` is game/BlockRegistry.gd, which
## tracks live blocks and their settled state; `blocks_parent` is where new
## blocks are added.
func register_world(field: Field, registry: Node, blocks_parent: Node3D) -> void:
	_field = field
	_registry = registry as BlockRegistry
	_blocks_parent = blocks_parent
	if _registry != null:
		# Spec 3.4: only the host simulates. A client's registry must not hand
		# out net_ids of its own — the host's are the only ones that mean
		# anything — and must not run the settled rule over frozen bodies.
		_registry.set_host_authority(_is_host())


## The BlockRegistry and the node new blocks are added under, for
## net/MatchNet.gd's replicated spawns. Nothing else should reach for these:
## rules go through request_place().
func registry() -> BlockRegistry:
	return _registry if is_instance_valid(_registry) else null


func convert_block_owner(block: Block, new_slot: int) -> bool:
	if not _is_host() or block == null or new_slot < 0 or new_slot >= slot_count() or registry() == null:
		return false
	return _registry.convert_owner(block, new_slot, slot(new_slot).color)


func apply_replicated_block_owner(net_id: int, new_slot: int) -> bool:
	if _is_host() or new_slot < 0 or new_slot >= slot_count() or registry() == null:
		return false
	return _registry.apply_replicated_owner(net_id, new_slot, slot(new_slot).color)


func blocks_parent() -> Node3D:
	return _blocks_parent if is_instance_valid(_blocks_parent) else null


## Validity-guarded: Main frees its world without unregistering it, so
## between one match world's teardown and the next register_world() these
## accessors would otherwise hand out a freed node (seen when
## ui/SandboxPanel.gd and game/PlayerController.gd read them from _ready()).
func field() -> Field:
	return _field if is_instance_valid(_field) else null


## Test seam for the Net autoload (see _net_provider). Passing null restores
## the real Net.
func set_net_provider(provider: Variant) -> void:
	_net_provider = provider


## Installed by net/MatchNet.gd. `replicator` must answer replicate_spawn(),
## replicate_match_event() and replicate_match_start(); null turns replication
## off, which is the single-player and unit-test case.
func set_replicator(replicator: Variant) -> void:
	_replicator = replicator


## net/MatchNet.gd, or null in a build with no networking. This is how a
## scene node reaches the membrane without naming an autoload the integrator
## registers after this one — and without a get_node("/root/...") path
## (CLAUDE.md).
func replicator() -> Variant:
	return _replicator


## True on the host **and offline** (Net.is_host()'s contract), so every gate
## written against it leaves M2's single-PC behaviour exactly as it was.
func _is_host() -> bool:
	if _net_provider != null:
		return bool(_net_provider.is_host())
	return Net.is_host()


func start_match(match_config: MatchConfig) -> void:
	var previous_cat: CatController = active_cat()
	if previous_cat != null:
		end_cat(previous_cat.activation_id)
	_cat_serial = 0
	_sandbox_territory_mode = DEFAULT_TERRITORY_MODE
	_sandbox_cone_angle = DEFAULT_CONE_ANGLE_DEGREES
	_sandbox_cone_height_source = SandboxConeExperiment.HEIGHT_TOP
	_sandbox_cone_base_mode = SandboxConeExperiment.BASE_ADDITIVE
	_territory_cache_enabled = true
	# Bontago-8or.30: a forced-special drawer (Sandbox / gift demo) must not
	# leak into a later real match. Sandbox installs its drawer after start,
	# so resetting here for every non-sandbox start is safe; the weighted
	# drawer is re-installed lazily at the first claim (_roster_ready reset).
	if match_config == null or not match_config.sandbox:
		_gifts.set_special_drawer(_gifts._default_special_drawer)
	_lifecycle.start_match(match_config)


func abort_match() -> void:
	var previous_cat: CatController = active_cat()
	if previous_cat != null:
		end_cat(previous_cat.activation_id)
	_cat_serial = 0
	_lifecycle.abort_match()


func state() -> State:
	return _lifecycle.state()


## Seconds left in the countdown, or 0.0 outside State.COUNTDOWN.
func countdown_remaining() -> float:
	return _lifecycle.countdown_remaining()


## Bontago-mp0.27: pause/resume the countdown's run-down (loading hand-off).
func set_countdown_held(held: bool) -> void:
	_lifecycle.set_countdown_held(held)


## Seconds left on the match timer (spec 2.8), 0.0 when off or run out.
func match_timer_left() -> float:
	return _lifecycle.match_timer_left()


## True only in State.SUDDEN_DEATH (spec 2.8).
func sudden_death_active() -> bool:
	return _lifecycle.sudden_death_active()


## Spec 3.4: "The host is authoritative ... only the host runs physics." Every
## clock that decides something — the countdown, the feed timers and their
## auto-drops, the 10 Hz territory solve, the win check and the disconnect
## grace — runs here and only on the host. A client's copy of Match is a
## read model: it holds the slots, the config and a mirror raster so its HUD
## and its ghost's territory tint are right, and it is driven entirely by
## net/MatchNet.gd's replicated events.
func _process(delta: float) -> void:
	if not _is_host():
		_feed._tick_client_display(delta)
		return
	match _lifecycle._state:
		State.COUNTDOWN:
			_lifecycle._tick_countdown(delta)
			# Bontago-mp0.27. # DECISION: while Main holds the countdown for the
			# loading screen, the loading readiness gate still needs its first
			# applied territory result, which is otherwise only solved in PLAYING
			# (it used to arrive during the old unconditional 3 s). Solve the
			# empty field then; with no hold nothing changes.
			if _lifecycle.is_countdown_held():
				_territory._tick_territory(delta)
		State.PLAYING:
			_lifecycle._tick_disconnect_grace(delta)
			_feed._tick_feed(delta)
			if _sandbox_territory_mode != SANDBOX_TERRITORY_PAUSED:
				var probe_territory: int = PerfProbe.start()
				_territory._tick_territory(delta)
				PerfProbe.stop(&"territory", probe_territory)
			_lifecycle._tick_match_timer(delta)
			# DECISION (autoload/Match.gd, M6 B4): a no-op unless
			# config.turn_based, so hot-seat and free-for-all matches pay
			# nothing extra here (mirrors _tick_match_timer's own
			# config.match_timer_minutes == 0 no-op).
			_lifecycle._tick_turn_based(delta)
			# Bontago-1pi.13: match_duration() accumulates only across the two
			# "live" states (is_live()), mirroring every
			# other per-state tick call above.
			_stats._tick(delta)
		State.SUDDEN_DEATH:
			# Spec 2.8 sudden death (M6 A3): normal play continues -- the same
			# three ticks PLAYING runs -- plus the gift ramp / disk shrink /
			# radius-8 tiebreak schedule in MatchLifecycle.
			_lifecycle._tick_disconnect_grace(delta)
			_feed._tick_feed(delta)
			if _sandbox_territory_mode != SANDBOX_TERRITORY_PAUSED:
				var probe_territory: int = PerfProbe.start()
				_territory._tick_territory(delta)
				PerfProbe.stop(&"territory", probe_territory)
			_lifecycle._tick_sudden_death(delta)
			_lifecycle._tick_turn_based(delta)
			_stats._tick(delta)
		_:
			pass


# --- Slots and teams --------------------------------------------------------

func slot_count() -> int:
	return _lifecycle.slot_count()


func slot(slot_id: int) -> PlayerSlot:
	return _lifecycle.slot(slot_id)


## The colour of `slot_id`: the live PlayerSlot.color, else the config palette,
## else `fallback` (SlotColors.resolve owns the order, Bontago-1pi.86 D1).
func slot_color(slot_id: int, fallback: Color = Color.WHITE) -> Color:
	var live: PlayerSlot = slot(slot_id) if _lifecycle != null else null
	var palette: PackedColorArray = config.player_colors if config != null else MatchConfig.default_player_colors()
	return SlotColors.resolve(slot_id, live.color if live != null else null, palette, fallback)


func team_of(slot_id: int) -> int:
	return _lifecycle.team_of(slot_id)


## Hot-seat: the slot whose turn it is. Outside hot-seat this is the local
## player's slot, and every slot acts at once.
func active_slot() -> int:
	return _lifecycle.active_slot()


## Hot-seat: hands the turn to the next slot. Called after a placement
## resolves, not by input.
func advance_turn() -> void:
	_lifecycle.advance_turn()


# --- Block feed (spec 2.4, 3.7) ---------------------------------------------

## The shape `slot_id` is holding right now, or null between blocks.
func held_shape(slot_id: int) -> BlockShape:
	return _feed.held_shape(slot_id)


## What the HUD's next-block preview shows for `slot_id`.
func next_shape(slot_id: int) -> BlockShape:
	return _feed.next_shape(slot_id)


## M4 P1b/P2b: the oldest pending special `slot_id` is holding from a claimed
## gift crate, or &"" for none (spec 2.6: "your next fed block becomes a
## special") -- a peek, not a pop. P2c reads this from its own
## _spawn_block() extension and pops via pop_pending_special() where
## MatchGifts.on_feed_block_issued()'s unconditional clear used to run. See
## autoload/match/MatchGifts.gd for the placeholder id the default drawer
## hands out.
func held_special(slot_id: int) -> StringName:
	return _gifts.held_special(slot_id)


## Presentation peek (Bontago-59o.13): the gift queued as `slot_id`'s next
## piece, or &"" for none. See MatchGifts.next_special().
func next_special(slot_id: int) -> StringName:
	return _gifts.next_special(slot_id)


## M4 P2b (Bontago-csc): dequeues and returns `slot_id`'s oldest pending
## special, or &"" if its queue is empty. See MatchGifts.pop_pending_special().
func pop_pending_special(slot_id: int) -> StringName:
	return _gifts.pop_pending_special(slot_id)


## M4 P2b: how many specials `slot_id` currently has queued (capped at
## GiftConfig.max_pending_specials). ui/HUD.gd's queued-count indicator
## (Bontago-1en.16, not this package) is the only consumer today.
func pending_special_count(slot_id: int) -> int:
	return _gifts.pending_special_count(slot_id)


## Glue's activation grants future successful drops; MatchPlacement will
## consume a charge once each later drop is accepted.
func grant_glue_drops(slot_id: int, count: int) -> bool:
	return _gifts.grant_glue_drops(slot_id, count)


func glue_drops_left(slot_id: int) -> int:
	return _gifts.glue_drops_left(slot_id)


func glue_revision(slot_id: int) -> int:
	return _gifts.glue_revision(slot_id)


func apply_replicated_glue_charges(slot_id: int, count: int, revision: int) -> bool:
	return _gifts.apply_replicated_glue_charges(slot_id, count, revision)


func consume_glue_drop(slot_id: int) -> bool:
	return _gifts.consume_glue_drop(slot_id)


## M4 P2b: installs the real weighted special-type draw P2c wires in once
## config/specials/ exists; the default (MatchGifts._default_special_drawer)
## always returns MatchGifts.PENDING_SPECIAL_ID. See
## MatchGifts.set_special_drawer().
func set_special_drawer(drawer: Callable) -> void:
	_gifts.set_special_drawer(drawer)


## Bontago-1en.24: game/Sandbox.gd's F9 hotkey turning back "off" -- reinstalls
## whatever drawer a real match would be running (the weighted SpecialDef
## pick, or the shipped placeholder). See MatchGifts.restore_default_special_
## drawer().
func restore_default_special_drawer() -> void:
	_gifts.restore_default_special_drawer()


## Bontago-1en.24: game/Sandbox.gd's F9 sandbox_force_special hotkey and
## `--force-special=` -- appends `special_id` straight onto `slot_id`'s
## pending queue with no crate needed, host-only and sandbox-only. See
## MatchGifts.debug_queue_special() for the full contract (the cap, the
## DEBUG_GIFT_ID sentinel on Events.gift_claimed).
func debug_queue_special(slot_id: int, special_id: StringName) -> bool:
	return _gifts.debug_queue_special(slot_id, special_id)


## M4 P1b DECISION: "the feed issues a new window" is Events.feed_block_issued
## -- see MatchGifts.on_feed_block_issued()'s own DECISION for the full
## reasoning. Connected once in _ready(); this is the one call site both the
## gift-spawn roll and the held-special clear share.
func _on_feed_block_issued(slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	_gifts.on_feed_block_issued(slot_id)


## Seconds left on the slot's block timer (spec 2.8: 3-12 s, default 6).
func feed_time_left(slot_id: int) -> float:
	return _feed.feed_time_left(slot_id)


## feed_time_left / config.block_timer, 1 -> 0, for the HUD's timer ring.
func feed_progress(slot_id: int) -> float:
	return _feed.feed_progress(slot_id)


## Bontago-1pi.18.1 (QoL experiments): blocks queued for `slot_id` (0 when the
## backlog toggle is off), and whether its block timer is paused by the pause toggle.
func qol_backlog_count(slot_id: int) -> int:
	return _feed.backlog_count(slot_id)


func qol_timer_paused(slot_id: int) -> bool:
	return _feed.timer_paused(slot_id)


## Bontago-1pi.18.6: the goal claim radius in force, in meters: the very value
## MatchTerritory feeds capture (WinChecker.claim_at), so the beacon's ground ring
## (GoalFlag.set_claim_ring) cannot disagree with it. 0.0 when the toggle is off or
## no match config exists yet. Reads Match.config.qol, so host and client agree.
func qol_claim_radius() -> float:
	if _territory == null or config == null:
		return 0.0
	return _territory._claim_radius()


## Bontago-1pi.18.2 (QoL gift slot): the gift `slot_id` could spend now (&"" if none), how many wait, and the host-validated use.
func gift_slot_head(slot_id: int) -> StringName:
	return _gifts.gift_slot_head(slot_id)


func gift_slot_count(slot_id: int) -> int:
	return _gifts.gift_slot_count(slot_id)


func gift_slot_contents(slot_id: int) -> Array[StringName]:
	return _gifts.gift_slot_contents(slot_id)


func gift_slot_enabled() -> bool:
	return _gifts.gift_slot_capacity() > 0


func request_use_gift_slot(slot_id: int) -> bool:
	return _gifts.request_use_gift_slot(slot_id)


func apply_replicated_gift_slot(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName) -> void:
	_gifts.apply_replicated_gift_slot(slot_id, contents, activated, carrier_id)


## Client side of Events.qol_feed_changed (net/MatchNet.gd).
func apply_replicated_qol(slot_id: int, backlog: int, paused: bool) -> void:
	_feed.apply_replicated_qol(slot_id, backlog, paused)


## Whether _tick_feed() is currently decrementing timers (Bontago-mv0.8:
## true for every real match). ui/SandboxPanel.gd shows this as the timer's
## "running"/"paused" state.
func feed_timer_enabled() -> bool:
	return _feed.feed_timer_enabled()


## game/Sandbox.gd's sandbox_toggle_timer hotkey. A no-op call outside
## sandbox is harmless (every real match starts true and nothing else in the
## shipped game ever calls this), but nothing stops a caller from flipping it
## — this file does not gate it on config.sandbox, the same way
## set_process(false) in the test harness is trusted rather than re-checked.
func set_feed_timer_enabled(enabled: bool) -> void:
	_feed.set_feed_timer_enabled(enabled)


## Sandbox switch over the live host territory solve: cone settings or paused.
## Normal matches start in DEFAULT_TERRITORY_MODE.
func set_sandbox_territory_mode(
	mode: int,
	angle_degrees: float = DEFAULT_CONE_ANGLE_DEGREES,
	height_source: int = SandboxConeExperiment.HEIGHT_TOP,
	base_mode: int = SandboxConeExperiment.BASE_ADDITIVE
) -> void:
	if mode < SANDBOX_TERRITORY_CONE or mode > SANDBOX_TERRITORY_PAUSED:
		return
	_sandbox_territory_mode = mode
	_sandbox_cone_angle = angle_degrees
	_sandbox_cone_height_source = height_source
	_sandbox_cone_base_mode = base_mode


func sandbox_territory_mode() -> int:
	return _sandbox_territory_mode


func sandbox_territory_paused() -> bool:
	return _sandbox_territory_mode == SANDBOX_TERRITORY_PAUSED


# --- The one authoritative entry point (spec 3.4) ---------------------------

## Every placement in the game goes through here, local or remote. See
## autoload/match/MatchPlacement.gd's request_place() for the full contract
## (origin/orientation/free_quat/auto_drop/feed_seq, burn-on-reject, the M3a
## RPC wrapping and the -1 feed_seq sentinel for trusted local callers).
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int = -1
) -> StringName:
	return _placement.request_place(slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq)


## Spec 2.5's throw: releases a pending special with velocity instead of
## dropping it in place. See MatchPlacement.request_throw() for the full
## contract (guard order, REASON_NOT_A_SPECIAL, the never-burns refusal, the
## throw_max_speed clamp and continuous_cd).
func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int = -1
) -> StringName:
	return _placement.request_throw(slot_id, origin, orientation_index, free_quat, velocity, feed_seq)


## Bontago-1pi.134: host-side last aim (unit camera forward) of a slot; the forced release at
## timer expiry throws a held throwable gift along it. See MatchPlacement.note_aim().
func note_aim(slot_id: int, forward: Vector3) -> void:
	_placement.note_aim(slot_id, forward)


func noted_aim(slot_id: int) -> Vector3:
	return _placement.noted_aim(slot_id)


## M4 P4-SPAWN: a special effect's own runtime projectile spawn (e.g.
## Volcano's lava orbs), not a player intent. See
## MatchPlacement.spawn_special_projectile() for the full contract
## (host-only, no feed/rules check, continuous_cd threshold).
func spawn_special_projectile(
	shape: BlockShape,
	world_origin: Vector3,
	basis: Basis,
	owner_slot: int,
	initial_velocity: Vector3,
	orb_def: SpecialDef,
	orb_tuning: SpecialTuning
) -> Block:
	return _placement.spawn_special_projectile(shape, world_origin, basis, owner_slot, initial_velocity, orb_def, orb_tuning)


## Whether a pose can be evaluated at all. See MatchPlacement.is_pose_well_formed().
func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	return _placement.is_pose_well_formed(origin, orientation_index, free_quat)


## Dry run of request_place()'s territory check, for the ghost's valid/red/
## hatched tint (spec 2.5). See MatchPlacement.preview_placement().
func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	return _placement.preview_placement(slot_id, origin, orientation_index, free_quat)


## Blocks this instance has spawned since the match started. The M3a
## acceptance harness asserts this equals the sum of accepted intents plus
## auto-drops (docs/archive/M3a_PLAN.md).
func blocks_spawned() -> int:
	return _placement.blocks_spawned()


## The value an intent for `slot_id` must quote to be accepted right now. It
## advances on every consumed block, so exactly one intent can spend any one
## held block (docs/archive/M3a_PLAN.md, "Never duplicated, never lost").
func feed_seq(slot_id: int) -> int:
	return _feed.feed_seq(slot_id)


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): whether `slot_id`'s
## currently held piece may be released right now. See MatchFeed.is_release_locked().
func is_release_locked(slot_id: int) -> bool:
	return _feed.is_release_locked(slot_id)


## Where a slot's block goes when its timer expires and the host has never
## heard a cursor from it. See MatchPlacement.default_ghost_origin().
func default_ghost_origin(slot_id: int) -> Vector3:
	return _placement.default_ghost_origin(slot_id)


# --- Disconnects (docs/archive/M3a_PLAN.md question 2) ------------------------------

func on_peer_left(slot_id: int) -> void:
	_lifecycle.on_peer_left(slot_id)


func on_peer_rejoined(slot_id: int) -> void:
	_lifecycle.on_peer_rejoined(slot_id)


## Seconds left before `slot_id` is eliminated for being gone, or -1 when its
## peer is connected. The lobby and the HUD read this; nothing else.
func disconnect_grace_left(slot_id: int) -> float:
	return _lifecycle.disconnect_grace_left(slot_id)


# --- Territory and the win check (spec 2.2, 2.3, 3.3) -----------------------

## The live raster. Never mutate it from outside Match.
func raster() -> TerritoryRaster:
	return _territory.raster()


## The groups from the last solve, parallel to the raster.
func groups() -> TerritoryGroups:
	return _territory.groups()


## Bontago-1t5.3: mode goal context for a bot slot (see MatchTerritory.bot_mode_goal()).
func bot_mode_goal(slot_id: int) -> BotModeGoal:
	return _territory.bot_mode_goal(slot_id)


func cell_grid() -> CellGrid:
	return _territory.cell_grid()


## Fraction of the disk a team owns, 0..1.
func territory_share(team_id: int) -> float:
	return _territory.territory_share(team_id)


## The winning team, or -1.
func winner_team() -> int:
	return _territory.winner_team()


## Bontago-22y.10: the weather controller (net/WeatherNet.gd, the HUD cue and
## tests read it; rules never do).
func weather() -> MatchWeather:
	return _weather


# --- Match statistics + results (spec 3.7, Bontago-1pi.13) ------------------

## Per-slot stats and the results-payload builder. See
## autoload/match/MatchStats.gd's own header for the full contract; the
## results-screen UI worker (Bontago-1pi.6) reads Events.match_results_ready
## rather than reaching in here directly, but net/MatchNet.gd's replication
## and this file's own tests need the object itself.
func stats() -> MatchStats:
	return _stats


## Tallest point any of this slot's settled blocks reaches above the disk, in
## meters. Spec 2.10's HUD shows it as a number.
func max_height_for_slot(slot_id: int) -> float:
	return _registry.max_height_for_slot(slot_id) if _registry != null else 0.0


## The analytic circle list the last territory step built (host only),
## cached so net/MatchNet.gd's replicate_territory() can ship the identical
## list to clients. See MatchTerritory.circle_render_arrays().
func circle_render_arrays() -> Dictionary:
	return _territory.circle_render_arrays()


## core/net/CircleWire.gd's quantization bounds for this match's map. Host
## (encoding, net/MatchNet.gd's replicate_territory()) and client (decoding,
## the same file's net_territory()) must use the identical numbers, so this
## is the one place both read them from — the same MatchConfig/NetConfig/
## TerritoryTuning resources a version-matched build already shares.
func circle_wire_xz_bound() -> float:
	return _net_config.position_bounds(config.map_def()).size.x * 0.5


func circle_wire_radius_max() -> float:
	return _territory_tuning.influence_max_fraction * config.map_def().field_radius


## M4 P5-HOLE: a special effect's own hole, independent of contest. See
## MatchTerritory.punch_special_hole() for the full contract (host-only,
## no-op under HoleMode.OFF, disk-local world_pos, home-flag elimination).
func punch_special_hole(world_pos: Vector2, radius_m: float, hole_open_s: float) -> void:
	_territory.punch_special_hole(world_pos, radius_m, hole_open_s)


# --- The client's read model (spec 3.4) -------------------------------------
#
# Everything below is called only by net/MatchNet.gd, only on a client, and
# decides nothing: it writes the host's answers into this instance's copy of
# the match so the HUD, the ghost tint and the block feed preview are right.
# Each one is idempotent, because a reliable channel can still deliver a state
# the client already reached on its own.

## Mirrors the host's state machine. Re-emits match_state_changed only on a
## real change, so a client that already moved itself (the countdown it ran
## locally, say) does not emit twice.
func apply_replicated_state_change(new_state: int) -> void:
	_lifecycle.apply_replicated_state_change(new_state)


func apply_replicated_countdown(seconds_left: int) -> void:
	_lifecycle.apply_replicated_countdown(seconds_left)


## The host issued `slot_id` a block. See MatchFeed.apply_replicated_feed()
## for the full contract (host_feed_seq/host_feed_time_left/host_is_locked).
func apply_replicated_feed(
	slot_id: int,
	shape_id: StringName,
	next_shape_id: StringName,
	host_feed_seq: int,
	host_feed_time_left: float = -1.0,
	host_is_locked: bool = false
) -> void:
	_feed.apply_replicated_feed(slot_id, shape_id, next_shape_id, host_feed_seq, host_feed_time_left, host_is_locked)


func apply_replicated_turn(slot_id: int) -> void:
	_lifecycle.apply_replicated_turn(slot_id)


func apply_replicated_elimination(slot_id: int) -> void:
	_lifecycle.apply_replicated_elimination(slot_id)


## Bontago-22y.11: client mirror of the host's mode-objective state, and the
## host's snapshot of it for a reconnecting peer ({} when there is none).
func apply_replicated_mode_state(state: Dictionary) -> void:
	_lifecycle.apply_replicated_mode_state(state)


func mode_state_snapshot() -> Dictionary:
	return _lifecycle.mode_state_snapshot()


## M4 P1b/P2b: net/MatchNet.gd's net_match_event() mirrors for the three gift
## events. A client only ever builds/frees the crate visual and (for a claim)
## keeps held_special()/pending_special_count() accurate -- it never spawns,
## claims or expires anything itself. See autoload/match/MatchGifts.gd's own
## client-read-model section.
func apply_replicated_gift_spawned(gift_id: int, position: Vector2) -> void:
	_gifts.apply_replicated_spawn(gift_id, position)


func gift_state(gift_id: int) -> Dictionary:
	return _gifts.gift_state(gift_id)


func gift_states() -> Array[Dictionary]:
	return _gifts.gift_states()


func apply_replicated_gift_flight(gift_id: int, origin: Vector3, landing: Vector3) -> void:
	_gifts.apply_replicated_flight(gift_id, origin, landing)


func apply_replicated_gift_landed(gift_id: int, landing: Vector3) -> void:
	_gifts.apply_replicated_landing(gift_id, landing)


## `special_id` is the third EVENT_GIFT_CLAIMED wire argument (Orchestrator
## amendment 1) -- net/MatchNet.gd's wire check has already rejected a
## malformed one before this is ever called.
func apply_replicated_gift_claimed(gift_id: int, slot_id: int, special_id: StringName) -> void:
	_gifts.apply_replicated_claim(gift_id, slot_id, special_id)


func apply_replicated_gift_expired(gift_id: int) -> void:
	_gifts.apply_replicated_expire(gift_id)


## Bontago-1en.21: net/MatchNet.gd's EVENT_SPECIAL_CONSUMED dispatch calls
## this before re-emitting Events.special_consumed -- the spend-side
## counterpart of apply_replicated_gift_claimed() above. `special_id` is the
## wire argument net/MatchNet.gd's own _special_id_wire_ok() has already
## checked before this is ever called.
##
## DECISION (autoload/Match.gd, Bontago-1en.21): this package's own brief did
## not list autoload/Match.gd among its owned files, but net/MatchNet.gd's
## dispatch needs an entry point on the same _authority() surface every other
## apply_replicated_* call already uses (see the three siblings directly
## above) -- reaching into Match._gifts directly from net/MatchNet.gd would
## break that established forwarding convention instead. This is a one-line,
## additive, same-shape stub with no risk of colliding with another
## package's edits to this file.
func apply_replicated_special_consumed(slot_id: int, special_id: StringName) -> void:
	_gifts.apply_replicated_special_consumed(slot_id, special_id)


## Writes one territory payload into the mirror raster. See
## MatchTerritory.apply_replicated_territory() for the full contract
## (circle_*/goal_*/argmax_mode defaults for pre-existing call sites).
func apply_replicated_territory(
	cells: PackedInt32Array,
	owners: PackedByteArray,
	states: PackedByteArray,
	full: bool,
	circle_xs: PackedFloat32Array = PackedFloat32Array(),
	circle_zs: PackedFloat32Array = PackedFloat32Array(),
	circle_radii: PackedFloat32Array = PackedFloat32Array(),
	circle_teams: PackedInt32Array = PackedInt32Array(),
	goal_positions: PackedVector2Array = PackedVector2Array(),
	goal_radii: PackedFloat32Array = PackedFloat32Array(),
	argmax_mode: bool = false
) -> void:
	_territory.apply_replicated_territory(
		cells, owners, states, full,
		circle_xs, circle_zs, circle_radii, circle_teams,
		goal_positions, goal_radii, argmax_mode
	)
