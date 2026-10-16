class_name BotController
extends Node
## One AI-driven seat (spec 1.8): each block it receives it builds a world snapshot, thinks
## (core/ai/BotThink, spread over physics ticks), decides what to do with a held special
## (core/ai/BotSpecialPlanner.plan_v2), and sends exactly one Match.request_place()/request_throw()
## per think-cycle -- the same authoritative entry points a human PlayerController uses.
##
## Host-gated like every autoload/match/ controller (`if not Net.is_host(): return`, true offline
## too), so a bare unit test or a bench scene needs no networking to exercise this. One instance per
## seat; a per-bot seeded RNG drives the reaction-delay jitter, the think and the aim noise.

## a large odd offset distinct from MatchFeed._build_bags()'s own
## per-slot bag stride (1000003) and MatchGifts' two RNG offsets (999983,
## 999979) -- this file's own per-system stream off the shared
## Match.config.rng_seed, so a fixed match seed reproduces this bot's own
## jitter/aim-noise/territory-sample draws without colliding with any other
## seeded system in the match (determinism is the reason for the separate stream).
const RNG_OFFSET: int = 777001

## the shipped Storm wind response the V2 evaluator reads (same resource StormEffect uses).
const STORM_TUNING: StormTuning = preload("res://config/weather/storm.tres")
## the wire fields (Events.breeze_gust_started) a listed gust must carry to be read.
const GUST_KEYS: Array[String] = ["x", "y", "z", "a", "r", "d", "s"]
## the shipped Breeze response the V2 evaluator reads for live gusts (same resource BreezeEffect uses).
const BREEZE_TUNING: BreezeTuning = preload("res://config/breeze/breeze.tres")

enum State { IDLE, ACTING, THINKING, RELEASE_WAIT }

## own seeded stream for the release-delay draw (a separate stream so the
## think/aim draws of _rng, and the decisions they make, are unchanged by the release timing).
const RELEASE_RNG_OFFSET: int = RNG_OFFSET + 1
const SLOT_SEED_STRIDE: int = 1000003

## Static per-physics-frame accounting of microseconds ALL V2 bots spent thinking, so eight
## bots cannot stack their budgets into one long frame (profile.think_frame_cap_us).
## the cap only limits work ahead of a bot's deadline schedule, never its share.
static var _think_frame: int = -1
static var _think_frame_used_us: int = 0

@export var tuning: BotTuning = preload("res://config/bots/bot_tuning.tres")
var _special_tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")
var _gift_config: GiftConfig = preload("res://config/gifts/gift_config.tres")
var _physics_tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")

var _slot_id: int = -1
var _difficulty: MatchConfig.AiDifficulty = MatchConfig.AiDifficulty.NORMAL
var _profile: BotDifficultyProfile = null
var _field: Field = null
var _registry: BlockRegistry = null

## DECISION: Match/Net are plain autoloads, and GUT
## cannot double one (see game/player/PlayerController.gd's matching DECISION), so
## every host/state read below goes through these seams instead of naming
## `Match`/`Net` directly. null means "the real one", which is what every
## shipped build uses; a test injects a double with set_match_provider()/
## set_net_provider().
var _match_provider: Variant = null
var _net_provider: Variant = null

## Seeded once at setup() off Match.config.rng_seed + RNG_OFFSET + a per-slot
## stride, per the determinism requirement -- never
## randi()/randf()'s global state. Drives the reaction-delay jitter (drawn
## once, below), the territory-point sampling and the aim-noise offset.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _release_rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Seconds left before a planned release is sent (State.RELEASE_WAIT).
var _release_wait_s: float = 0.0

## reaction_delay_s + a per-bot jitter drawn ONCE at setup() (not re-rolled
## every block), so this bot's own cadence is stable but different bots land
## on different frames (spec 1.8: "for multiple bots it spreads its thinking
## across several frames").
var _think_delay_s: float = 0.0
## Seconds left before this bot may start thinking again. Reset by
## Events.feed_block_issued for this slot.
var _countdown: float = 0.0

var _state: State = State.IDLE
## Bot V2: the snapshot the current think-cycle started from (read by the special planner).
var _special_view: BotWorldView = null
var _think: BotThink = null
var _think_frames_used: int = 0
## opt-in think cost report (BotThinkCostCollector.current(); null = off, then none of
## these is touched). Snapshot build / apply time, this tick's BotThink time, the bot's other THINKING-tick
## work, the think's start time and whether a finished record is waiting to be flushed at the tick's end.
var _cost_build_us: int = 0
var _cost_apply_us: int = 0
var _cost_other_us: int = 0
var _cost_begin_us: int = 0
var _cost_tick_think_us: int = -1
var _cost_pending: bool = false
## Physics frame this bot last ran a THINKING tick (same-frame re-ticks reset the shared count).
var _think_last_frame: int = -1
## THINKING ticks by which the current think must be decided, and ticks so far.
var _think_deadline_ticks: int = 0
var _think_ticks: int = 0
## the V2 probes' reused column-ray query (built on first use) and the physics
## space of the current THINKING tick (null outside one).
var _column_query: PhysicsRayQueryParameters3D = null
var _probe_space: PhysicsDirectSpaceState3D = null
var _candidates: Array[BotCandidate] = []


func _ready() -> void:
	Events.feed_block_issued.connect(_on_feed_block_issued)


## One instance drives exactly one bot slot on the host. Called once by
## whatever builds the match world (game/main/Main.gd's _build_match_world(), M5
## P5) right alongside HotSeat's own per-slot wiring.
func setup(slot_id: int, difficulty: MatchConfig.AiDifficulty, field: Field, registry: BlockRegistry) -> void:
	_slot_id = slot_id
	# a new bot never inherits the previous match's Reach the Sky base memory.
	BotThink.clear_strategy_memory(slot_id)
	# DECISION: setup() runs for every bot when a match world is built, so it is the match
	# start the report sees; the opt-in collector never carries match A's thinks into match B.
	var cost: BotThinkCostCollector = BotThinkCostCollector.current()
	if cost != null:
		cost.reset()
	_difficulty = difficulty
	_field = field
	_registry = registry
	_profile = _resolve_profile()
	_seed_rng()
	_think_delay_s = _profile.reaction_delay_s + _rng.randf() * tuning.think_phase_jitter_s
	_countdown = _think_delay_s
	_state = State.IDLE
	_candidates.clear()
	_think = null
	_think_last_frame = -1
	# A new bot (match or test) never inherits a previous run's frame accounting.
	_think_frame = -1
	_think_frame_used_us = 0


func _resolve_profile() -> BotDifficultyProfile:
	return tuning.profile_for(_difficulty)


## Test seam for the Match autoload; null restores the real one.
func set_match_provider(provider: Variant) -> void:
	_match_provider = provider


## Test seam for the Net autoload; null restores the real one.
func set_net_provider(provider: Variant) -> void:
	_net_provider = provider


func _seed_rng() -> void:
	var match_ref: Variant = _match()
	var config: MatchConfig = match_ref.config if match_ref != null else null
	if config != null and config.rng_seed >= 0:
		_rng.seed = config.rng_seed + RNG_OFFSET + _slot_id * SLOT_SEED_STRIDE
		_release_rng.seed = config.rng_seed + RELEASE_RNG_OFFSET + _slot_id * SLOT_SEED_STRIDE
	else:
		_release_rng.randomize()
		# BlockBag._init()'s identical convention for rng_seed < 0
		# ("randomize" mode) -- explicit rather than relying on _rng's own
		# construction-time seed (review fix, RandomNumberGenerator
		# is not guaranteed random at construction across engine versions).
		_rng.randomize()


func _match() -> Variant:
	return _match_provider if _match_provider != null else Match


func _session() -> Variant:
	return _net_provider if _net_provider != null else Net


func _physics_process(delta: float) -> void:
	if _slot_id < 0 or not _session().is_host():
		return
	var match_ref: Variant = _match()
	if not MatchAutoload.is_live(match_ref.state() as MatchAutoload.State):
		return
	var cost: BotThinkCostCollector = BotThinkCostCollector.current()
	var tick_start_us: int = Time.get_ticks_usec() if cost != null else 0
	_cost_tick_think_us = -1
	match _state:
		State.IDLE:
			_tick_idle(delta)
		State.ACTING:
			_tick_acting()
		State.RELEASE_WAIT:
			_tick_release_wait(delta)
		State.THINKING:
			_tick_thinking()
	if cost != null:
		_flush_cost(cost, Time.get_ticks_usec() - tick_start_us)


## books this tick's time (the whole tick is a bot frame; its share outside BotThink
## joins the think's "other" work) and, when the think finished in it, hands the record over.
func _flush_cost(cost: BotThinkCostCollector, tick_us: int) -> void:
	cost.record_frame(_slot_id, tick_us)
	if _cost_tick_think_us >= 0:
		_cost_other_us += maxi(tick_us - _cost_tick_think_us, 0)
	if not _cost_pending:
		return
	_cost_pending = false
	if _think == null:
		return
	var record: Dictionary = _think.stats_record()
	if record.is_empty():
		return
	record["build_us"] = _cost_build_us
	record["apply_us"] = _cost_apply_us
	record["other_us"] = _cost_other_us
	record["ticks"] = _think_ticks
	record["latency_us"] = Time.get_ticks_usec() - _cost_begin_us
	cost.record_think(_slot_id, record)


func _on_feed_block_issued(slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	if slot_id != _slot_id:
		return
	# A new piece is in hand (whether following this bot's own placement or
	# an unrelated auto-drop) -- any candidates already gathered were scored
	# against the old shape and must not carry over.
	_countdown = clamp_reaction_s(
		_think_delay_s, _feed_time_left(), tuning.timer_plan_margin_s, tuning.timer_min_think_s
	)
	_think = null
	# DECISION: a freshly fed gift piece is spent after the
	# short gift_use_delay_s, not the full reaction delay -- a queued gift may
	# be released before the next ordinary boundary (spec 1.4 gift exception).
	var match_ref: Variant = _match()
	if match_ref.has_method("held_special") and StringName(match_ref.held_special(_slot_id)) != &"":
		_countdown = minf(_countdown, tuning.gift_use_delay_s)
	_state = State.IDLE
	_candidates.clear()


# --- IDLE: wait for the reaction delay, the release lock and a held shape ---

func _tick_idle(delta: float) -> void:
	_countdown = maxf(_countdown - delta, 0.0)
	if _countdown > 0.0:
		return
	var match_ref: Variant = _match()
	var slot: PlayerSlot = match_ref.slot(_slot_id)
	if slot == null or not slot.home_flag_alive:
		# DECISION (game/bots/BotController.gd): an eliminated slot may still be
		# fed a block (MatchFeed does not itself stop on elimination), but
		# request_place() always refuses it (home_flag_alive gate) -- skip
		# the whole think/ACT cycle rather than spend every frame
		# sampling candidates for a request that can never succeed.
		return
	if bool(match_ref.is_release_locked(_slot_id)):
		return
	if match_ref.held_shape(_slot_id) == null:
		return
	# QoL gift slot: a bot spends a slotted gift as soon as
	# it can; the resulting feed event restarts the (short) gift think delay.
	if match_ref.has_method("gift_slot_head") and StringName(match_ref.gift_slot_head(_slot_id)) != &"":
		if bool(match_ref.request_use_gift_slot(_slot_id)):
			return
	_candidates.clear()
	_begin_thinking(match_ref)


# --- THINKING (Bot V2): BotThink.step() slices spread over the ticks before the decision deadline ---

## Builds the pure world snapshot for this piece and starts a BotThink on it.
func _begin_thinking(match_ref: Variant) -> void:
	var shape: BlockShape = match_ref.held_shape(_slot_id)
	var raster: TerritoryRaster = match_ref.raster()
	if shape == null or raster == null:
		return
	var slots: Array[PlayerSlot] = []
	for i: int in range(int(match_ref.slot_count())):
		var slot_item: PlayerSlot = match_ref.slot(i)
		if slot_item != null:
			slots.append(slot_item)
	var next_shape: BlockShape = null
	if match_ref.has_method("next_shape"):
		next_shape = match_ref.next_shape(_slot_id) as BlockShape
	var cost: BotThinkCostCollector = BotThinkCostCollector.current()
	var begin_us: int = Time.get_ticks_usec() if cost != null else 0
	var view: BotWorldView = BotWorldView.build(
		_slot_id, int(match_ref.team_of(_slot_id)), match_ref.circle_render_arrays(), slots, raster,
		_goal_positions(), raster.tuning().goal_zone_radius,
		shape, next_shape, _mode_goal(match_ref), _active_special_positions(), _landed_gift_positions(match_ref)
	)
	var built_us: int = Time.get_ticks_usec() if cost != null else 0
	_apply_weather(view, match_ref)
	_apply_gravity_and_gifts(view, match_ref)
	_apply_live_radius(view, match_ref)
	_apply_incoming_specials(view, match_ref)
	_apply_stack(view, match_ref)
	_special_view = view
	_think = BotThink.new(view, _profile, _rng)
	_think.collect_stats = cost != null
	_cost_pending = false
	if cost != null:
		var end_us: int = Time.get_ticks_usec()
		_cost_build_us = built_us - begin_us
		_cost_apply_us = end_us - built_us
		_cost_other_us = 0
		_cost_begin_us = begin_us
	_think.tuning = tuning
	_think.cell_probe = _probe_cell
	_think_frames_used = 0
	_think_ticks = 0
	_think_deadline_ticks = think_deadline_ticks()
	_state = State.THINKING


## The snapshot of the cubes near the own towers (BotStackProbe); BotThink's STACK phase
## analyses it in slices. Sources: the tallest `stack_site_count` own circles at least `stack_min_height_m`
## high (the tower-top sites BotCandidateGen offers) and the Reach the Sky tower. Without a registry or a
## source the view keeps `stack == null` and the think is exactly the old one.
func _apply_stack(view: BotWorldView, match_ref: Variant) -> void:
	if _registry == null or _field == null:
		return
	var gen: BotGenTuning = BotCandidateGen.SHIPPED_TUNING
	var tops: Array[Dictionary] = []
	for i: int in view.indices_of_team(view.team_id):
		var top: float = view.top_height(i)
		if top >= gen.stack_min_height_m:
			tops.append({"point": Vector2(view.cx[i], view.cz[i]), "top": top})
	tops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["top"] as float) > (b["top"] as float))
	var centres: PackedVector2Array = PackedVector2Array()
	for entry: Dictionary in tops.slice(0, maxi(gen.stack_site_count, 0)):
		centres.append(entry["point"] as Vector2)
	if view.mode_goal != null and view.mode_goal.has_tower:
		centres.append(view.mode_goal.tower_origin)
	if view.mode == MatchConfig.GameMode.REACH_THE_SKY:
		_append_uncovered_towers(view, tops, centres, gen)
	view.stack = BotStackProbe.build(
		_registry, _field, centres, BotEvaluator.stack_tuning, view.cube_size,
		func(slot: int) -> int: return int(match_ref.team_of(slot))
	)


## Reach the Sky only. The tallest circles can all belong to one toppled pile, which would leave
## a sound stack elsewhere out of the snapshot (so it could never be chosen as the base). Tall own circles
## farther than the snapshot radius from every source so far become sources too (tallest first, at most
## `stack_site_count` more); a bot with one cluster of blocks gets exactly the old sources.
func _append_uncovered_towers(
	view: BotWorldView, tops: Array[Dictionary], centres: PackedVector2Array, gen: BotGenTuning
) -> void:
	var radius: float = BotEvaluator.stack_tuning.snapshot_radius_m
	var added: int = 0
	for entry: Dictionary in tops:
		if added >= maxi(gen.stack_site_count, 0):
			break
		var point: Vector2 = entry["point"] as Vector2
		var covered: bool = false
		for centre: Vector2 in centres:
			if centre.distance_to(point) <= radius:
				covered = true
				break
		if not covered:
			centres.append(point)
			added += 1


## after the sudden-death shrink, the view's live radius is the surviving disc.
func _apply_live_radius(view: BotWorldView, match_ref: Variant) -> void:
	if match_ref.has_method("sudden_death_active") and bool(match_ref.sudden_death_active()):
		var live: float = BotWorldView.live_radius_from_raster(view.raster, view.grid)
		if live > 0.0:
			view.live_radius = minf(live, view.field_radius)


## live gravity in the Field's local frame (magnitude g * gravity_multiplier) and the match's
## gifts flag, for BotStability's tilted-disc shift and gift allowance.
func _apply_gravity_and_gifts(view: BotWorldView, match_ref: Variant) -> void:
	if _field != null:
		var gravity_base: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
		var world_gravity: Vector3 = Vector3.DOWN * gravity_base * _physics_tuning.gravity_multiplier
		view.gravity_local = _field.global_transform.basis.orthonormalized().inverse() * world_gravity
	var config: Variant = match_ref.get("config") if match_ref is Object else null
	if config is MatchConfig:
		view.gifts_enabled = (config as MatchConfig).gifts_enabled


## copies the live weather (host) into the view; only a Storm blows wind.
## also the Storm heading (seeded base heading, disk-local) and the live Breeze gusts.
func _apply_weather(view: BotWorldView, match_ref: Variant) -> void:
	if not match_ref.has_method("weather"):
		return
	var weather: Object = match_ref.weather() as Object
	if weather == null:
		return
	view.weather_id = weather.active_id()
	view.weather_intensity = float(weather.active_intensity())
	if view.weather_id == WeatherIds.STORM:
		view.wind_tuning = STORM_TUNING
		view.wind_dir = _storm_heading(weather)
	_apply_gusts(view, weather)


## the active Storm's base heading (WindField.base_angle of the event seed, the value
## StormEffect and the presentation also derive; the slow +/- veer is not readable here) as a disk-local
## unit vector; ZERO when the weather object exposes no seed.
func _storm_heading(weather: Object) -> Vector2:
	if not weather.has_method("seed_value") or not weather.has_method("event_index"):
		return Vector2.ZERO
	var angle: float = WindField.base_angle(WindField.event_seed(int(weather.seed_value()), int(weather.event_index())))
	return _disk_heading(Vector2(cos(angle), sin(angle)))


## copies the host's live Breeze gusts (BreezeEffect.gusts(): wire fields plus "age")
## into the view in disk-local space; the view's gust power is BotWorldView.gust_power().
func _apply_gusts(view: BotWorldView, weather: Object) -> void:
	if not weather.has_method("breeze"):
		return
	var breeze: Object = weather.breeze() as Object
	if breeze == null or not breeze.has_method("gusts"):
		return
	var gusts: Array = breeze.gusts() as Array
	for entry: Variant in gusts:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var gust: Dictionary = entry
		if not gust.has_all(GUST_KEYS):
			continue
		var power: float = BotWorldView.gust_power(float(gust["s"]), float(gust.get("age", 0.0)), float(gust["d"]))
		var world_centre: Vector3 = Vector3(float(gust["x"]), float(gust["y"]), float(gust["z"]))
		var local_centre: Vector3 = _field.to_local(world_centre) if _field != null else world_centre
		var heading: Vector2 = _disk_heading(BreezeField.heading(float(gust["a"])))
		view.add_gust(local_centre, float(gust["r"]), heading, power)
	if not view.gust_power_values.is_empty():
		view.breeze_tuning = BREEZE_TUNING


## a world x/z direction as a unit vector in disk-local x/z (the field's own
## rotation undone, like Field.disk_local_from_world does for points).
func _disk_heading(world_dir: Vector2) -> Vector2:
	if _field == null:
		return world_dir
	var local: Vector3 = _field.global_transform.basis.inverse() * Vector3(world_dir.x, 0.0, world_dir.y)
	return Vector2(local.x, local.z).normalized()


## THINKING ticks after the release boundary by which a think is decided
## (BotDifficultyProfile.generation_ticks; every tier shares Hard's 14 ticks).
func think_deadline_ticks() -> int:
	# The tier's profile when none is resolved yet (a controller built without setup).
	var active: BotDifficultyProfile = _profile if _profile != null else tuning.profile_for(_difficulty)
	var ticks: int = active.generation_ticks(tuning.max_generation_frames)
	return clamp_think_ticks(
		ticks, _feed_time_left(), tuning.timer_plan_margin_s, int(Engine.physics_ticks_per_second)
	)


## seconds left on this slot's block timer; -1.0 when the match exposes none.
func _feed_time_left() -> float:
	var match_ref: Variant = _match()
	if match_ref.has_method("feed_time_left") and not bool(match_ref.has_method("timer_paused") and match_ref.timer_paused(_slot_id)):
		return float(match_ref.feed_time_left(_slot_id))
	return -1.0


## the reaction delay cut so the bot still has min_think_s of think time and the plan
## lands margin_s before the auto-drop. Unchanged (and exact) while the timer is long enough or unknown
## (time_left < 0).
static func clamp_reaction_s(delay_s: float, time_left_s: float, margin_s: float, min_think_s: float) -> float:
	if time_left_s < 0.0:
		return delay_s
	return minf(delay_s, maxf(time_left_s - margin_s - min_think_s, 0.0))


## the think deadline (physics ticks) cut to the time left before the margin; >= 1.
static func clamp_think_ticks(ticks: int, time_left_s: float, margin_s: float, ticks_per_s: int) -> int:
	if time_left_s < 0.0:
		return ticks
	return mini(ticks, maxi(floori((time_left_s - margin_s) * float(ticks_per_s)), 1))


## Bot V2: the held special planned against this piece's world snapshot and
## its chain graph (built here, only when a special is actually held).
func _plan_special_v2(held_special_id: StringName) -> BotSpecialPlanner.BotSpecialAction:
	return BotSpecialPlanner.plan_v2(
		held_special_id,
		_special_view,
		BotChains.build(_special_view),
		_profile,
		tuning,
		_territory_sample_points(),
		_throw_range_m(),
		black_hole_pull_radius_m(),
		_special_effect_radius_m(held_special_id)
	)


## Effect radius (m) of a placed special, read from its shipped SpecialDef effect (area/base/hole/
## splash radius, or the explosion blast radius); 0.0 when unknown (planner then does not cap).
func _special_effect_radius_m(special_id: StringName) -> float:
	var def: SpecialDef = SpecialDef.find_by_id(special_id)
	if def == null or def.effect == null:
		return 0.0
	for property: String in ["base_radius_m", "hole_radius_m", "splash_radius_m", "radius_m"]:
		var value: Variant = def.effect.get(property)
		if value is float and float(value) > 0.0:
			return float(value)
	var blast: ExplosionTuning = def.effect.get("blast") as ExplosionTuning
	return blast.radius_m if blast != null else 0.0


func _tick_thinking() -> void:
	var match_ref: Variant = _match()
	if _think == null or match_ref.held_shape(_slot_id) == null:
		_state = State.IDLE
		_think = null
		_candidates.clear()
		return
	var frame: int = Engine.get_physics_frames()
	# The same bot ticking twice in one engine frame means the caller ticks manually (tests,
	# benches); treat that as a new frame so the accounting cannot stall for good.
	if frame != _think_frame or _think_last_frame == frame:
		_think_frame = frame
		_think_frame_used_us = 0
	_think_last_frame = frame
	_think_ticks += 1
	var ticks_left: int = _think_deadline_ticks - _think_ticks + 1
	var start_us: int = Time.get_ticks_usec()
	_probe_space = _field.direct_space() if _field != null else null
	var finished: bool = true
	if ticks_left <= 1:
		# The deadline tick: whatever is left runs now (the schedule keeps it about one slice).
		_think.complete(_probe)
	else:
		finished = _think.step(_think_slice_us(ticks_left), _probe)
	_probe_space = null
	var think_us: int = Time.get_ticks_usec() - start_us
	_think_frame_used_us += think_us
	if _think.collect_stats:
		_cost_tick_think_us = think_us
	_think_frames_used += 1
	if not finished and _think_frames_used >= tuning.max_generation_frames:
		_think.finish_early()
		finished = true
	if finished:
		_cost_pending = _think.collect_stats
		_candidates = _think.candidates()
		_begin_release_wait()


## this tick's think slice. The deadline share (BotThink's remaining-work
## estimate over the ticks left, this one included, less the tier's think_reserve_frames) always
## runs; while the shared per-frame cap (think_frame_cap_us, all V2 bots together) has room the
## bot may work ahead up to its think_budget_us. The cap no longer skips a bot's tick: that only
## pushed decisions late. Until this process has measured every costly stage
## (BotThink.has_cost_estimate) the share is the tier's think_budget_us.
func _think_slice_us(ticks_left: int) -> int:
	var deadline_share_us: int = _profile.think_budget_us
	if _think.has_cost_estimate():
		var planned_ticks: int = maxi(ticks_left - maxi(_profile.think_reserve_frames, 0), 1)
		deadline_share_us = ceili(float(_think.remaining_work_us()) / float(planned_ticks))
	var room_us: int = mini(_profile.think_budget_us, _profile.think_frame_cap_us - _think_frame_used_us)
	return maxi(deadline_share_us, room_us)


## BotThink's physics probe: {hit, height} straight down at a disk-local point.
func _probe(xz: Vector2) -> Dictionary:
	var hit: Dictionary = _column_hit(xz)
	if hit.is_empty():
		return {"hit": false, "height": 0.0}
	return {"hit": true, "height": _field.to_local(hit["position"] as Vector3).y}


## The per-bottom-cube probe: like `_probe` plus `body`, the
## instance id of the block collider hit (1 for the disc or a miss).
func _probe_cell(xz: Vector2) -> Dictionary:
	var hit: Dictionary = _column_hit(xz)
	if hit.is_empty():
		return {"hit": false, "height": 0.0, "body": -1}
	var block: Block = hit.get("collider") as Block
	return {
		"hit": true,
		"height": _field.to_local(hit["position"] as Vector3).y,
		"body": block.get_instance_id() if block != null else -1,
	}


## Field.raycast_disk_column's exact ray (map_def.cell_wake_height down to
## tuning.kill_plane_y, bodies only, PLACEMENT_QUERY_MASK, nothing excluded) through one reused
## query object: the V2 probes fire up to seven rays per site. The end points are
## world_from_disk_local's own transform (Node3D.to_global is global_transform * point), and the
## physics space is looked up once per THINKING tick. {} on a miss or with no physics.
func _column_hit(xz: Vector2) -> Dictionary:
	if _field == null:
		return {}
	var space: PhysicsDirectSpaceState3D = _probe_space if _probe_space != null else _field.direct_space()
	if space == null:
		return {}
	if _column_query == null:
		_column_query = PhysicsRayQueryParameters3D.new()
		_column_query.collide_with_bodies = true
		_column_query.collide_with_areas = false
		_column_query.collision_mask = Field.PLACEMENT_QUERY_MASK
	var xform: Transform3D = _field.global_transform
	_column_query.from = xform * Vector3(xz.x, _field.map_def.cell_wake_height, xz.y)
	_column_query.to = xform * Vector3(xz.x, _field.tuning.kill_plane_y, xz.y)
	return space.intersect_ray(_column_query)


## Disk-local positions of every landed gift plus every airborne one (at its predicted landing
## point) that lands within BotEvalTuning.air_gift_horizon_s, for the world view.
func _landed_gift_positions(match_ref: Variant) -> PackedVector2Array:
	var positions: PackedVector2Array = PackedVector2Array()
	if not match_ref.has_method("gift_states"):
		return positions
	for state: Dictionary in match_ref.gift_states():
		var phase: int = int(state.get("phase", -1))
		if phase == MatchGifts.LANDED:
			positions.append(state.get("position", Vector2.ZERO))
		elif phase == MatchGifts.FALLING and _gift_eta_s(state) <= BotEvaluator.tuning.air_gift_horizon_s:
			positions.append(state.get("position", Vector2.ZERO))
	return positions


## Seconds until a falling gift lands: its remaining straight-line fall at the configured speed.
func _gift_eta_s(state: Dictionary) -> float:
	var origin: Vector3 = state.get("origin", Vector3.ZERO)
	var landing: Vector3 = state.get("landing", Vector3.ZERO)
	var speed: float = maxf(_gift_config.fall_speed_m_s, 0.001)
	return maxf(origin.distance_to(landing) / speed - float(state.get("elapsed", 0.0)), 0.0)


## every enemy special still in flight (armed, untriggered, not landed, moving)
## becomes a predicted impact point + radius in the view's incoming-special list. Own-team throws
## are ignored. Nothing happens without a field.
func _apply_incoming_specials(view: BotWorldView, match_ref: Variant) -> void:
	if _field == null:
		return
	var eval_tuning: BotEvalTuning = BotEvaluator.tuning
	var gravity_base: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	# gravity expressed in the Field's local frame, so a tilted disc predicts right.
	var local_gravity: Vector3 = _field.global_transform.basis.orthonormalized().inverse() * (Vector3.DOWN * gravity_base)
	var gravity_down_local: float = -local_gravity.y
	for node: Node in get_tree().get_nodes_in_group(SpecialBehavior.GROUP):
		var behavior: SpecialBehavior = node as SpecialBehavior
		if behavior == null or behavior.is_triggered() or behavior.has_landed():
			continue
		var block: Block = behavior.get_parent() as Block
		if block == null or block.owner_slot < 0 or block.freeze:
			continue
		if int(match_ref.team_of(block.owner_slot)) == view.team_id:
			continue
		var local_pos: Vector3 = _field.to_local(block.global_position)
		var local_vel: Vector3 = _field.to_local(block.global_position + block.linear_velocity) - local_pos
		# DECISION: "airborne" = moving along the Field's local vertical above the
		# resting threshold. A special sliding on the disc has ~0 vertical speed, so it is not
		# incoming (has_landed() is never set for needs_landing=false effects). Cost: a throw's
		# apex frame (|vy| below the threshold) is missed for a moment.
		if absf(local_vel.y) < eval_tuning.incoming_min_speed_mps:
			continue
		var impact: Vector3 = BotWorldView.ballistic_impact(
			Vector2(local_pos.x, local_pos.z), local_pos.y, Vector2(local_vel.x, local_vel.z),
			local_vel.y, gravity_down_local * block.gravity_scale
		)
		var radius: float = _special_effect_radius_m(_behavior_special_id(behavior))
		if radius <= 0.0:
			radius = eval_tuning.incoming_default_radius_m
		view.add_incoming_special(Vector2(impact.x, impact.y), radius)


## The special id a behaviour was bound with (&"" when unknown).
func _behavior_special_id(behavior: SpecialBehavior) -> StringName:
	var def: SpecialDef = behavior.get(&"_def") as SpecialDef
	return def.id if def != null else &""


func _field_radius() -> float:
	if _field == null or _field.map_def == null:
		return 0.0
	return _field.map_def.field_radius


func _home_position() -> Vector2:
	var slot: PlayerSlot = _match().slot(_slot_id)
	return slot.home_position if slot != null else Vector2.ZERO


## The straight-down raycast Field.raycast_down_disk_local() uses (map_def.cell_wake_height down to
## tuning.kill_plane_y), keeping the hit's disk-local height. `{}` only with no Field or physics
## world; a genuine miss reports `"hit": false` with the disk-surface fallback height 0.0. Only a
## support estimate: MatchPlacement.request_place() is the sole authority on legality.
func _raycast_support_height(local_xz: Vector2) -> Dictionary:
	if _field == null:
		return {}
	var space: PhysicsDirectSpaceState3D = _field.direct_space()
	if space == null:
		return {}
	var hit: Dictionary = _field.raycast_disk_column(space, local_xz)
	if hit.is_empty():
		return {"height": 0.0, "collider": null, "hit": false}
	var local_hit: Vector3 = _field.to_local(hit["position"] as Vector3)
	return {"height": local_hit.y, "collider": hit.get("collider"), "hit": true, "position": hit["position"]}


# --- ACTING: one frame, exactly one request per completed think-cycle ------

## the plan is ready; hold the release for a seeded random delay (this bot's
## own stream), cut so it lands release_safety_margin_s before the block timer's expiry. A
## gift piece (gift_use_delay_s) and a zero range release at once.
func _begin_release_wait() -> void:
	_release_wait_s = _draw_release_delay()
	_state = State.RELEASE_WAIT if _release_wait_s > 0.0 else State.ACTING


func _draw_release_delay() -> float:
	var lo: float = maxf(tuning.release_delay_min_s, 0.0)
	var hi: float = maxf(tuning.release_delay_max_s, lo)
	var delay: float = _release_rng.randf_range(lo, hi)
	var match_ref: Variant = _match()
	if match_ref.has_method("held_special") and StringName(match_ref.held_special(_slot_id)) != &"":
		return 0.0
	if match_ref.has_method("feed_time_left"):
		var time_left: float = float(match_ref.feed_time_left(_slot_id))
		delay = minf(delay, maxf(time_left - tuning.release_safety_margin_s, 0.0))
	return delay


func _tick_release_wait(delta: float) -> void:
	var match_ref: Variant = _match()
	if match_ref.held_shape(_slot_id) == null:
		_state = State.IDLE
		_candidates.clear()
		return
	_release_wait_s -= delta
	if _release_wait_s <= 0.0:
		_state = State.ACTING


func _tick_acting() -> void:
	_state = State.IDLE
	var match_ref: Variant = _match()
	var held_special_id: StringName = StringName(match_ref.held_special(_slot_id))
	if held_special_id != &"" and _special_view != null:
		# chain-aware targeting off this think's snapshot.
		var action: BotSpecialPlanner.BotSpecialAction = _plan_special_v2(held_special_id)
		if action.should_throw:
			_apply_rejection_backoff(_send_throw(action))
			return
		if not action.should_place_ordinarily:
			return
		if action.has_place_target:
			# A placed-special heuristic picked an intended disk-local target: send the think's
			# candidate nearest to it (aim noise, height resample and the request are unchanged).
			_apply_rejection_backoff(_send_best_placement(action.place_target))
			return
	# Gifts are a BotThink score term, so an ordinary placement follows.
	_apply_rejection_backoff(_send_best_placement())


## Review fix (MINOR): an outright-rejected request_place()/
## request_throw() (anything but PlacementRules.REASON_OK -- e.g.
## REASON_CONTESTED after another block landed on the sampled spot between
## THINKING and ACTING) must not spend every following physics frame
## retrying the exact same rejected cycle -- with no backoff, _tick_idle()'s
## own countdown gate reads 0.0 the very next frame (nothing resets it short
## of a fresh Events.feed_block_issued) and thinking restarts immediately.
## `reason` is `PlacementRules.REASON_OK` (StringName "") both when a request
## actually succeeded and when `_send_best_placement()`/`_send_throw()` sent
## nothing at all (empty candidates, null best, null `_field`) -- neither
## case needs a backoff, only a genuine non-OK reason from a request that was
## actually sent does.
func _apply_rejection_backoff(reason: StringName) -> void:
	if reason != PlacementRules.REASON_OK:
		_countdown = tuning.rejection_backoff_s


## the disk-local pose `request_place` is sent for a piece whose pivot (bottom_center) is
## at `pivot_xz` over a support at `support_y`: the pivot raised so the ROTATED shape's lowest corner rests on
## the support. Pure seam so tests use exactly the send conversion.
static func spawn_pose(
	shape: BlockShape, orientation_index: int, pivot_xz: Vector2, support_y: float, physics: PhysicsTuning
) -> Vector3:
	var basis: Basis = BlockOrientations.get_basis(orientation_index)
	var lift: float = -shape.rotated_bottom_offset(basis, physics.cube_size, physics.cube_margin)
	return Vector3(pivot_xz.x, support_y + lift, pivot_xz.y)


## the support height the piece rests on when its pivot is at `pivot_xz`: the highest ray
## hit under its real bottom cubes (spawn frame, outermost first, at most stability_raycast_count rays,
## once per decision), which is where the host lift puts it; `fallback_y` (the pivot ray) when no cube ray
## hits. DECISION: the cap is the tier's own ray count (Hard 9), so no new tunable.
func _highest_cube_support(shape: BlockShape, orientation_index: int, pivot_xz: Vector2, fallback_y: float) -> float:
	return highest_cube_support(
		shape, orientation_index, pivot_xz, fallback_y, _physics_tuning.cube_size, _profile.stability_raycast_count,
		_raycast_support_height
	)


## Pure seam of _highest_cube_support: `ray(xz) -> {hit, height}` is the support ray (Field raycast in the game).
static func highest_cube_support(
	shape: BlockShape, orientation_index: int, pivot_xz: Vector2, fallback_y: float, cube_size: float,
	max_rays: int, ray: Callable
) -> float:
	var info: BotStatics.OrientationInfo = BotStatics.orientation_info(shape, orientation_index)
	var at: BotCandidate = BotCandidate.new()
	at.origin = pivot_xz
	var points: PackedVector2Array = BotStatics.contact_probe_points(at, info, cube_size, max_rays)
	var highest: float = fallback_y
	var any_hit: bool = false
	for point: Vector2 in points:
		var cube_hit: Dictionary = ray.call(point) as Dictionary
		if not bool(cube_hit.get("hit", false)):
			continue
		var height: float = float(cube_hit.get("height", 0.0))
		if not any_hit or height > highest:
			highest = height
			any_hit = true
	return highest


## `place_target_override` is null for an ordinary think-cycle (the BotThink pick, revalidated); a
## Vector2 when a placed-special heuristic picked an intended disk-local target
## (BotSpecialAction.place_target): the think's candidate nearest to it is sent instead. Everything
## past candidate selection (aim noise, the noisy-point height resample, the request) is identical.
func _send_best_placement(place_target_override: Variant = null) -> StringName:
	if _candidates.is_empty() or _field == null:
		return PlacementRules.REASON_OK
	var match_ref: Variant = _match()
	var best: BotCandidate = null
	if place_target_override != null:
		best = _pick_candidate_nearest_to(place_target_override as Vector2)
	elif _think != null:
		best = _think.revalidate()
	if best == null:
		return PlacementRules.REASON_OK
	var noisy_origin: Vector2 = best.origin + _aim_noise_offset()
	# Review fix (MAJOR): best.support_height was sampled at
	# the pre-noise origin -- the aim-noise offset can legitimately land the
	# request over a different (e.g. taller) collider than the one the
	# candidate was scored against, so the height must be resampled at the
	# actual noisy point the request is about to use, never the stale
	# pre-noise sample.
	var held: BlockShape = match_ref.held_shape(_slot_id)
	var hit: Dictionary = _raycast_support_height(noisy_origin)
	var support_y: float = float(hit.get("height", 0.0))
	if held != null:
		support_y = _highest_cube_support(held, best.orientation_index, noisy_origin, support_y)
	# `request_place` takes the bottom-centre PIVOT of the unrotated shape (as the
	# human ghost sends it), so raise it until the ROTATED shape's lowest corner sits on the support;
	# without this a lying piece spawns inside the disc and falls through it.
	var world_origin: Vector3 = _field.world_from_disk_local(noisy_origin, support_y)
	if held != null:
		var pose: Vector3 = spawn_pose(held, best.orientation_index, noisy_origin, support_y, _physics_tuning)
		world_origin = _field.world_from_disk_local(Vector2(pose.x, pose.z), pose.y)
	var reason: StringName = StringName(match_ref.request_place(
		_slot_id, world_origin, best.orientation_index, Quaternion.IDENTITY, false, int(match_ref.feed_seq(_slot_id))
	))
	return reason


## M5 P3b-ii: the already-generated candidate whose `origin`
## is disk-local nearest `target` -- _send_best_placement()'s own selection
## when a placed-special heuristic supplied a `place_target`. Assumes
## `_candidates` is non-empty; its only caller already checked that.
func _pick_candidate_nearest_to(target: Vector2) -> BotCandidate:
	var best: BotCandidate = _candidates[0]
	var best_dist_sq: float = best.origin.distance_squared_to(target)
	for i: int in range(1, _candidates.size()):
		var candidate: BotCandidate = _candidates[i]
		var dist_sq: float = candidate.origin.distance_squared_to(target)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = candidate
	return best


## b: this map's host throw range (GiftAim.range_scale of the field radius),
## so the bomb heuristic releases from where the fixed trajectory lands on the target.
func _throw_range_m() -> float:
	var radius: float = _field_radius()
	if radius <= 0.0:
		return 0.0
	return GiftAim.flat_range(
		_special_tuning,
		GiftAim.range_scale(radius, _special_tuning),
		float(ProjectSettings.get_setting("physics/3d/default_gravity")) * _physics_tuning.gravity_multiplier
	)


func _send_throw(action: BotSpecialPlanner.BotSpecialAction) -> StringName:
	if _field == null:
		return PlacementRules.REASON_OK
	var match_ref: Variant = _match()
	var noisy_origin: Vector2 = action.throw_origin + _aim_noise_offset()
	var world_origin: Vector3 = _field.world_from_disk_local(noisy_origin, 0.0)
	# DECISION (game/bots/BotController.gd item C): core/ai/
	# BotSpecialPlanner.gd's own _ballistic_velocity() builds `throw_velocity`
	# in disk-local axes (x, y=up, z -- see that file's own doc comment on the
	# function), never world space; MatchPlacement.request_throw() applies
	# `velocity` to the spawned RigidBody3D verbatim (world space, only
	# clamped to throw_max_speed -- see that file's own doc comment on
	# request_throw()), so a level Field happened to make the two spaces
	# coincide, but a tilted disk (SPECIALS_ONLY, spec 1.7/1.2/2.7) would then
	# throw a Bomb along the FLAT disk's axes instead of the bot's own tilted
	# one. Rotating through Field.global_transform.basis (a pure rotation,
	# tilt has no scale) converts the planner's disk-local direction into the
	# same world-space vector request_throw() expects, exactly like
	# MatchPlacement._burn_block()'s own `_match._field.global_transform.basis
	# * Vector3(outward.x, 0.0, outward.y)` conversion of a disk-local
	# direction into world space -- the same pattern, reused rather than
	# reinvented. A pure rotation preserves length, so the planner's own
	# `special_throw_speed_mps` speed survives the conversion unchanged.
	var world_velocity: Vector3 = _field.global_transform.basis * action.throw_velocity
	# the host derives the throw from a unit aim only (client speed is never
	# trusted), so the bot sends its planned direction, not a speed-scaled velocity.
	# the host (GiftAim.throw_velocity) adds the loft itself, so send the flat
	# camera-style forward (planner's horizontal heading), not the loft-included ballistic direction.
	var flat_forward: Vector3 = Vector3(world_velocity.x, 0.0, world_velocity.z)
	if flat_forward.length_squared() <= 0.0:
		flat_forward = world_velocity
	# remembered so a refused/backed-off throw still leaves the host an aim for
	# the expiry throw of this gift.
	if match_ref.has_method(&"note_aim"):
		match_ref.note_aim(_slot_id, flat_forward.normalized())
	return StringName(match_ref.request_throw(
		_slot_id, world_origin, 0, Quaternion.IDENTITY, flat_forward.normalized(), int(match_ref.feed_seq(_slot_id))
	))


## Random aiming error (spec 1.8), drawn from the same per-bot seeded RNG as
## the reaction-delay jitter and the territory sampling -- applied to the
## chosen candidate's origin *before* the request goes out, so
## PlacementRules.validate_point() still gets the final word (a noisy aim can
## legitimately land the bot in a worse, even invalid, spot).
func _aim_noise_offset() -> Vector2:
	var angle: float = _rng.randf() * TAU
	var radius: float = _rng.randf() * _profile.aim_noise_m
	return Vector2(cos(angle), sin(angle)) * radius


## the active mode's goal context, or null when the match
## provider has none (test fakes, Classic).
func _mode_goal(match_ref: Variant) -> BotModeGoal:
	if not match_ref.has_method("bot_mode_goal"):
		return null
	return match_ref.bot_mode_goal(_slot_id) as BotModeGoal


func _goal_positions() -> PackedVector2Array:
	var match_ref: Variant = _match()
	var config: MatchConfig = match_ref.config
	if config == null:
		return PackedVector2Array()
	return PlayerSlot.goal_positions_for(config.effective_goal_flag_count(), config.map_def())


## item F: every other special currently ticking on the disk
## (`game/gifts/specials/SpecialBehavior.GROUP`, its own scene-tree group -- see
## that file's own header comment), converted to a disk-local point through
## `_field.disk_local_from_world()`, the same conversion Field's own
## raycast_down_disk_local() uses. Fed to the world snapshot
## (spec 1.8's risk term: don't stack a new block, or aim a special, on top of one
## already armed and ticking). A behaviour is always added as a child of its
## owning Block (autoload/match/MatchPlacement.gd's `_arm_special_behavior()`:
## `block.add_child(behavior)`) -- read generically as `Node3D` rather than
## the concrete `Block` type, so a test fixture that stands in for "a
## Block-like Node3D" (any parented Node3D with a `global_position`) does not
## need to construct a real, physics-backed Block.
## item 2 (review fix): a triggered special's SpecialBehavior
## node lingers in the group until its Block is actually freed (game/gifts/specials/
## SpecialBehavior.gd's own is_triggered() doc: it flips once, on trigger(),
## and nothing here removes the node from GROUP before then), so a spent
## special (already exploded/landed) must not still count as "live" for
## _tick_acting()'s risk term or BotSpecialPlanner's own chain-avoidance --
## skip it before it is ever converted to a position.
##
## item 3 (review fix): get_nodes_in_group() iteration order is
## not part of any contract (Godot's own docs: insertion order into the
## group's internal list, not spatial or otherwise stable across runs), so
## sorting the result removes any dependence on it for the consumer that
## reads this list (the snapshot), so a bot's choices depend only on
## its own seeded RNG stream, not on however many other specials happened to
## spawn first. Vector2's own `<` (x, then y) is exactly sort()'s default
## ordering.
func _active_special_positions() -> PackedVector2Array:
	var positions: PackedVector2Array = PackedVector2Array()
	if _field == null:
		return positions
	for node: Node in get_tree().get_nodes_in_group(SpecialBehavior.GROUP):
		var behavior: SpecialBehavior = node as SpecialBehavior
		if behavior == null:
			continue
		if behavior.is_triggered():
			continue
		var owner_node: Node3D = behavior.get_parent() as Node3D
		if owner_node == null:
			continue
		positions.append(_field.disk_local_from_world(owner_node.global_position))
	positions.sort()
	return positions


## Pull radius (m) read from the shipped Black hole SpecialDef so the bot's scoring
## cannot drift from the real effect. 0.0 if the def or its effect
## is missing, which makes the planner skip the special.
static func black_hole_pull_radius_m() -> float:
	var def: SpecialDef = SpecialDef.find_by_id(&"black_hole")
	var effect: BlackHoleEffect = def.effect as BlackHoleEffect if def != null else null
	return effect.pull_radius_m if effect != null else 0.0


func _territory_sample_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for candidate: BotCandidate in _candidates:
		points.append(candidate.origin)
	if points.is_empty():
		points.append(_home_position())
	return points
