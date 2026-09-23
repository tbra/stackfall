class_name BotController
extends Node
## One AI-driven seat (spec 2.9): samples placement candidates inside its own
## territory, scores them (core/ai/BotPlacementScorer.gd), decides what to do
## with a held special (core/ai/BotSpecialPlanner.gd), and sends exactly one
## Match.request_place()/request_throw() per completed think-cycle -- the
## same authoritative entry points a human PlayerController uses, never a
## shortcut into rules internals (docs/M5_PLAN.md, "What the existing code
## already gives this milestone").
##
## docs/M5_PLAN.md P1 (Bontago-d5c): this is the interface-stub package.
## `BotPlacementScorer`/`BotSpecialPlanner` still answer trivially (first
## candidate, never throw) -- P2/P3 rewrite only their bodies. This file's
## job is the real cadence/gating/candidate-generation machinery every later
## package relies on: host-gated, time-sliced GENERATING (a bounded number of
## support + stability raycasts per physics frame), a per-bot seeded RNG for
## the reaction-delay jitter and the aim-noise perturbation, and one request
## per cycle.
##
## Host-gated the same way every autoload/match/ controller already is (`if
## not Net.is_host(): return`, true offline too), so a bare unit test or a
## bench scene needs no networking to exercise this -- the same shape
## game/HotSeat.gd already establishes for a human controller (one instance
## per seat).

## Bontago-d5c: a large odd offset distinct from MatchFeed._build_bags()'s own
## per-slot bag stride (1000003) and MatchGifts' two RNG offsets (999983,
## 999979) -- this file's own per-system stream off the shared
## Match.config.rng_seed, so a fixed match seed reproduces this bot's own
## jitter/aim-noise/territory-sample draws without colliding with any other
## seeded system in the match (see docs/M5_PLAN.md's "Known risks:
## Determinism").
const RNG_OFFSET: int = 777001

enum State { IDLE, GENERATING, ACTING }

@export var tuning: BotTuning = preload("res://config/bot_tuning.tres")

var _slot_id: int = -1
var _difficulty: MatchConfig.AiDifficulty = MatchConfig.AiDifficulty.NORMAL
var _profile: BotDifficultyProfile = null
var _field: Field = null
var _registry: BlockRegistry = null

## DECISION (game/BotController.gd): Match/Net are plain autoloads, and GUT
## cannot double one (see game/PlayerController.gd's matching DECISION), so
## every host/state read below goes through these seams instead of naming
## `Match`/`Net` directly. null means "the real one", which is what every
## shipped build uses; a test injects a double with set_match_provider()/
## set_net_provider().
var _match_provider: Variant = null
var _net_provider: Variant = null

## Seeded once at setup() off Match.config.rng_seed + RNG_OFFSET + a per-slot
## stride, per docs/M5_PLAN.md's determinism requirement -- never
## randi()/randf()'s global state. Drives the reaction-delay jitter (drawn
## once, below), the territory-point sampling and the aim-noise offset.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## reaction_delay_s + a per-bot jitter drawn ONCE at setup() (not re-rolled
## every block), so this bot's own cadence is stable but different bots land
## on different frames (spec 2.9: "for multiple bots it spreads its thinking
## across several frames").
var _think_delay_s: float = 0.0
## Seconds left before this bot may start GENERATING again. Reset by
## Events.feed_block_issued for this slot.
var _countdown: float = 0.0

var _state: State = State.IDLE
var _candidates: Array[BotCandidate] = []
var _generation_frames_used: int = 0


func _ready() -> void:
	Events.feed_block_issued.connect(_on_feed_block_issued)


## One instance drives exactly one bot slot on the host. Called once by
## whatever builds the match world (game/Main.gd's _build_match_world(), M5
## P5) right alongside HotSeat's own per-slot wiring.
func setup(slot_id: int, difficulty: MatchConfig.AiDifficulty, field: Field, registry: BlockRegistry) -> void:
	_slot_id = slot_id
	_difficulty = difficulty
	_field = field
	_registry = registry
	_profile = tuning.profile_for(difficulty)
	_seed_rng()
	_think_delay_s = _profile.reaction_delay_s + _rng.randf() * tuning.think_phase_jitter_s
	_countdown = _think_delay_s
	_state = State.IDLE
	_candidates.clear()
	_generation_frames_used = 0


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
		_rng.seed = config.rng_seed + RNG_OFFSET + _slot_id * 1000003
	else:
		# BlockBag._init()'s identical convention for rng_seed < 0
		# ("randomize" mode) -- explicit rather than relying on _rng's own
		# construction-time seed (review fix, Bontago-d5c.2: RandomNumberGenerator
		# is not guaranteed random at construction across engine versions).
		_rng.randomize()


func _match() -> Variant:
	return _match_provider if _match_provider != null else Match


func _is_host() -> bool:
	if _net_provider != null:
		return bool(_net_provider.is_host())
	return Net.is_host()


func _physics_process(delta: float) -> void:
	if _slot_id < 0 or not _is_host():
		return
	var match_ref: Variant = _match()
	if int(match_ref.state()) != int(MatchAutoload.State.PLAYING):
		return
	match _state:
		State.IDLE:
			_tick_idle(delta)
		State.GENERATING:
			_tick_generating()
		State.ACTING:
			_tick_acting()


func _on_feed_block_issued(slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	if slot_id != _slot_id:
		return
	# A new piece is in hand (whether following this bot's own placement or
	# an unrelated auto-drop) -- any candidates already gathered were scored
	# against the old shape and must not carry over.
	_countdown = _think_delay_s
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
		# DECISION (game/BotController.gd): an eliminated slot may still be
		# fed a block (MatchFeed does not itself stop on elimination), but
		# request_place() always refuses it (home_flag_alive gate) -- skip
		# the whole GENERATING/ACTING cycle rather than spend every frame
		# sampling candidates for a request that can never succeed.
		return
	if bool(match_ref.is_release_locked(_slot_id)):
		return
	if match_ref.held_shape(_slot_id) == null:
		return
	_candidates.clear()
	_generation_frames_used = 0
	_state = State.GENERATING


# --- GENERATING: up to profile.candidates_per_frame candidates per frame ---

func _tick_generating() -> void:
	var match_ref: Variant = _match()
	var shape: BlockShape = match_ref.held_shape(_slot_id)
	if shape == null:
		_state = State.IDLE
		_candidates.clear()
		return
	var team_id: int = int(match_ref.team_of(_slot_id))
	var orientations: Array[int] = BotPlacementScorer.flattest_orientations(shape, _profile.candidate_count)
	if orientations.is_empty():
		orientations = [0]
	var budget: int = _profile.candidates_per_frame
	for i: int in range(budget):
		if _candidates.size() >= _profile.candidate_count:
			break
		var orientation_index: int = orientations[_candidates.size() % orientations.size()]
		_generate_one_candidate(team_id, shape, orientation_index)
	_generation_frames_used += 1
	if _candidates.size() >= _profile.candidate_count or _generation_frames_used >= tuning.max_generation_frames:
		_state = State.ACTING


func _generate_one_candidate(team_id: int, shape: BlockShape, orientation_index: int) -> void:
	var match_ref: Variant = _match()
	var origin: Vector2 = _sample_territory_point(team_id)
	var hit: Dictionary = _raycast_support_height(origin)
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	candidate.orientation_index = orientation_index
	candidate.support_height = float(hit.get("height", 0.0))
	var basis: Basis = BlockOrientations.get_basis(orientation_index)
	# Bontago-d5c.8 (M5 P3b-ii, BotCandidate.shape_height producer): pure
	# geometry off shape.cells/basis, independent of grid/terrain, so this is
	# set regardless of whether a CellGrid is available below (a bare unit
	# test with no cell_grid() still gets a real shape_height).
	candidate.shape_height = _shape_height_cubes(shape.cells, basis)
	var grid: CellGrid = match_ref.cell_grid()
	if grid != null:
		# Review fix (Bontago-d5c.2, nit): the real PhysicsTuning.cube_size,
		# read off _field the same way BlockFactory/GhostPreview do (both
		# take a PhysicsTuning and read .cube_size off it), not a duplicate
		# local literal that could silently drift from the shipped value.
		candidate.footprint_cells = PlacementRules.footprint_cells(
			shape.cells, basis, origin, _field.tuning.cube_size, grid
		)
		_fire_stability_raycasts(candidate, candidate.footprint_cells, grid)
	candidate.on_top_of_own_stack = _is_own_block(hit.get("collider"), team_id)
	_candidates.append(candidate)


## Bontago-d5c.8 (M5 P3b-ii): the oriented shape's own height above its own
## pivot, in cube units -- e.g. a pillar lying flat is 1, standing on end is
## 3 (BotCandidate.shape_height's own doc). `basis` is always one of
## BlockOrientations' 24 axis-aligned rotations (same guarantee
## BotPlacementScorer._flat_footprint_coverage() relies on), so every
## transformed cell's own y lands on, or within float rounding of, an
## integer -- round() before taking the span keeps that exact rather than
## accumulating rotation error over repeated calls.
func _shape_height_cubes(cells: Array[Vector3i], basis: Basis) -> float:
	if cells.is_empty():
		return 0.0
	var min_height: float = INF
	var max_height: float = -INF
	for cell: Vector3i in cells:
		var transformed_height: float = round((basis * Vector3(cell)).y)
		min_height = minf(min_height, transformed_height)
		max_height = maxf(max_height, transformed_height)
	return max_height - min_height + 1.0


## Disk-local point inside this bot's own territory (uniform-in-disk
## sampling, Match.raster()/cell_grid().team_at() -- docs/M5_PLAN.md P1),
## retried up to tuning.max_territory_sample_attempts times before falling
## back to the slot's own home position.
func _sample_territory_point(team_id: int) -> Vector2:
	var match_ref: Variant = _match()
	var grid: CellGrid = match_ref.cell_grid()
	var raster: TerritoryRaster = match_ref.raster()
	if grid != null and raster != null:
		var radius: float = _field_radius()
		if radius > 0.0:
			for _attempt: int in range(tuning.max_territory_sample_attempts):
				var angle: float = _rng.randf() * TAU
				var dist: float = sqrt(_rng.randf()) * radius
				var candidate_xz: Vector2 = Vector2(cos(angle), sin(angle)) * dist
				var cell: Vector2i = grid.world_to_cell(candidate_xz)
				if raster.team_at(cell.x, cell.y) == team_id:
					return candidate_xz
	return _home_position()


func _field_radius() -> float:
	if _field == null or _field.map_def == null:
		return 0.0
	return _field.map_def.field_radius


func _home_position() -> Vector2:
	var slot: PlayerSlot = _match().slot(_slot_id)
	return slot.home_position if slot != null else Vector2.ZERO


## The same straight-down raycast Field.raycast_down_disk_local() already
## uses (map_def.cell_wake_height down to tuning.kill_plane_y), except this
## keeps the hit's disk-local height instead of discarding it
## (docs/M5_PLAN.md P1: "the same technique... just keeping the hit height").
## Returns `{}` only when there is no Field/no physics world to query at all
## (a bare unit test with no Field wired); a genuine miss (nothing directly
## below, e.g. a hole or the rim) still returns a disk-surface fallback
## height of 0.0 -- this raycast is only ever used for the bot's own scoring
## estimate, never the placement's actual legality gate (MatchPlacement.
## request_place() runs its own raycast_down_disk_local() and is the only
## authority on whether a point is valid).
func _raycast_support_height(local_xz: Vector2) -> Dictionary:
	if _field == null or not _field.is_inside_tree():
		return {}
	var world: World3D = _field.get_world_3d()
	if world == null:
		return {}
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return {}
	var start: Vector3 = _field.world_from_disk_local(local_xz, _field.map_def.cell_wake_height)
	var end: Vector3 = _field.world_from_disk_local(local_xz, _field.tuning.kill_plane_y)
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, end)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(params)
	if hit.is_empty():
		return {"height": 0.0, "collider": null}
	var local_hit: Vector3 = _field.to_local(hit["position"] as Vector3)
	return {"height": local_hit.y, "collider": hit.get("collider")}


## Footprint-corner raycasts (spec 2.9's stability factor, P2's own scoring):
## fires up to profile.stability_raycast_count of them -- sampled at the
## footprint's own cell centers, since PlacementRules.footprint_cells()
## already gives a pure, terrain-independent list of covered grid cells --
## and tallies into `candidate.corner_support_hits` how many landed within
## tuning.stability_contact_tolerance_m of `candidate.support_height` (the
## same origin-point sample every candidate is scored against), i.e. how much
## of the footprint is actually in flush contact rather than hovering over a
## gap or a lower stack (core/ai/BotPlacementScorer.gd's own `_stability_
## term()` is the consumer). Leaves `corner_support_hits` at its -1 ("not
## measured") default only when `cells` is empty -- no ray is ever fired for
## an empty footprint.
func _fire_stability_raycasts(candidate: BotCandidate, cells: PackedInt32Array, grid: CellGrid) -> void:
	var count: int = mini(_profile.stability_raycast_count, cells.size())
	if count <= 0:
		return
	var hits: int = 0
	for i: int in range(count):
		var hit: Dictionary = _raycast_support_height(grid.index_center(cells[i]))
		var height: float = float(hit.get("height", 0.0))
		if absf(height - candidate.support_height) <= tuning.stability_contact_tolerance_m:
			hits += 1
	candidate.corner_support_hits = hits


func _is_own_block(collider: Variant, team_id: int) -> bool:
	var block: Block = collider as Block
	if block == null:
		return false
	return int(_match().team_of(block.owner_slot)) == team_id


# --- ACTING: one frame, exactly one request per completed think-cycle ------

func _tick_acting() -> void:
	_state = State.IDLE
	var match_ref: Variant = _match()
	var held_special_id: StringName = StringName(match_ref.held_special(_slot_id))
	if held_special_id != &"":
		var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
			held_special_id,
			_home_position(),
			_territory_sample_points(),
			_enemy_circle_centers(),
			_active_special_positions(),
			_difficulty,
			tuning
		)
		if action.should_throw:
			_apply_rejection_backoff(_send_throw(action))
			return
		if not action.should_place_ordinarily:
			# Neither throws nor places -- nothing to do this cycle. A default
			# BotSpecialAction (e.g. an EASY profile's both-flags-false gate)
			# never reaches this branch (should_place_ordinarily is always
			# true then); core/ai/BotSpecialPlanner.gd's Bomb heuristic is the
			# one path that does (should_throw already handled above, so this
			# is reached only when a special neither throws nor places).
			return
		if action.has_place_target:
			# Bontago-d5c.8 (M5 P3b-ii): a placed-special heuristic already
			# picked an intended disk-local target (e.g. Rocket aiming near
			# the densest enemy cluster) -- honour it by sending whichever
			# already-generated candidate landed nearest that target, instead
			# of BotPlacementScorer.pick_best()'s own general-purpose scoring
			# (which would happily steer a Rocket away from the enemy risk it
			# was aimed at). Aim noise, the noisy-point height resample and
			# the request itself are unchanged -- only which candidate is
			# chosen differs.
			_apply_rejection_backoff(_send_best_placement(action.place_target))
			return
	_apply_rejection_backoff(_send_best_placement())


## Review fix (Bontago-d5c.2, MINOR): an outright-rejected request_place()/
## request_throw() (anything but PlacementRules.REASON_OK -- e.g.
## REASON_CONTESTED after another block landed on the sampled spot between
## GENERATING and ACTING) must not spend every following physics frame
## retrying the exact same rejected cycle -- with no backoff, _tick_idle()'s
## own countdown gate reads 0.0 the very next frame (nothing resets it short
## of a fresh Events.feed_block_issued) and GENERATING restarts immediately.
## `reason` is `PlacementRules.REASON_OK` (StringName "") both when a request
## actually succeeded and when `_send_best_placement()`/`_send_throw()` sent
## nothing at all (empty candidates, null best, null `_field`) -- neither
## case needs a backoff, only a genuine non-OK reason from a request that was
## actually sent does.
func _apply_rejection_backoff(reason: StringName) -> void:
	if reason != PlacementRules.REASON_OK:
		_countdown = tuning.rejection_backoff_s


## `place_target_override` is null for an ordinary think-cycle (score every
## generated candidate with BotPlacementScorer.pick_best(), spec 2.9's normal
## height/goal-progress/stability/risk formula); a Vector2 when a placed-
## special heuristic already picked an intended disk-local target
## (BotSpecialPlanner.BotSpecialAction.place_target, Bontago-d5c.8's own
## _tick_acting DECISION) -- then the candidate whose own `origin` is nearest
## that target is sent instead, honouring the special's own intent (e.g.
## Rocket aiming at a cluster) over the general-purpose scorer, which would
## otherwise steer away from exactly the risk the special was aimed at.
## Everything past candidate selection (aim noise, the noisy-point height
## resample, the request itself) is identical either way.
func _send_best_placement(place_target_override: Variant = null) -> StringName:
	if _candidates.is_empty() or _field == null:
		return PlacementRules.REASON_OK
	var match_ref: Variant = _match()
	var team_id: int = int(match_ref.team_of(_slot_id))
	var best: BotCandidate = null
	if place_target_override != null:
		best = _pick_candidate_nearest_to(place_target_override as Vector2)
	else:
		best = BotPlacementScorer.pick_best(
			_candidates,
			match_ref.raster(),
			match_ref.cell_grid(),
			team_id,
			_goal_positions(),
			_enemy_circle_centers(),
			_active_special_positions(),
			tuning,
			_field_radius()
		)
	if best == null:
		return PlacementRules.REASON_OK
	var noisy_origin: Vector2 = best.origin + _aim_noise_offset()
	# Review fix (Bontago-d5c.2, MAJOR): best.support_height was sampled at
	# the pre-noise origin -- the aim-noise offset can legitimately land the
	# request over a different (e.g. taller) collider than the one the
	# candidate was scored against, so the height must be resampled at the
	# actual noisy point the request is about to use, never the stale
	# pre-noise sample.
	var hit: Dictionary = _raycast_support_height(noisy_origin)
	var world_origin: Vector3 = _field.world_from_disk_local(noisy_origin, float(hit.get("height", 0.0)))
	return StringName(match_ref.request_place(
		_slot_id, world_origin, best.orientation_index, Quaternion.IDENTITY, false, int(match_ref.feed_seq(_slot_id))
	))


## Bontago-d5c.8 (M5 P3b-ii): the already-generated candidate whose `origin`
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


func _send_throw(action: BotSpecialPlanner.BotSpecialAction) -> StringName:
	if _field == null:
		return PlacementRules.REASON_OK
	var match_ref: Variant = _match()
	var noisy_origin: Vector2 = action.throw_origin + _aim_noise_offset()
	var world_origin: Vector3 = _field.world_from_disk_local(noisy_origin, 0.0)
	# DECISION (game/BotController.gd, Bontago-d5c.10 item C): core/ai/
	# BotSpecialPlanner.gd's own _ballistic_velocity() builds `throw_velocity`
	# in disk-local axes (x, y=up, z -- see that file's own doc comment on the
	# function), never world space; MatchPlacement.request_throw() applies
	# `velocity` to the spawned RigidBody3D verbatim (world space, only
	# clamped to throw_max_speed -- see that file's own doc comment on
	# request_throw()), so a level Field happened to make the two spaces
	# coincide, but a tilted disk (SPECIALS_ONLY, spec 2.1/2.7/3.5) would then
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
	return StringName(match_ref.request_throw(
		_slot_id, world_origin, 0, Quaternion.IDENTITY, world_velocity, int(match_ref.feed_seq(_slot_id))
	))


## Random aiming error (spec 2.9), drawn from the same per-bot seeded RNG as
## the reaction-delay jitter and the territory sampling -- applied to the
## chosen candidate's origin *before* the request goes out, so
## PlacementRules.validate_point() still gets the final word (a noisy aim can
## legitimately land the bot in a worse, even invalid, spot).
func _aim_noise_offset() -> Vector2:
	var angle: float = _rng.randf() * TAU
	var radius: float = _rng.randf() * _profile.aim_noise_m
	return Vector2(cos(angle), sin(angle)) * radius


func _goal_positions() -> PackedVector2Array:
	var match_ref: Variant = _match()
	var config: MatchConfig = match_ref.config
	if config == null:
		return PackedVector2Array()
	return PlayerSlot.goal_positions_for(config.goal_flag_count, config.map_def())


## Bontago-d5c.10 (item F): "where the enemy is" -- every other team's home
## flag, PLUS the disk-local center of every one of that team's own live
## influence circles.
##
## DECISION (game/BotController.gd, Bontago-d5c.10): the circle source is
## `Match.circle_render_arrays()` (forwarded from autoload/match/
## MatchTerritory.gd's own method of the same name), which already exists on
## the autoload/ this package does not own -- no new accessor was added
## there. It is the *render* list (home-anchored, connected-group circles
## only, already capped at TerritoryTuning.max_circles, each tagged with its
## own `teams[i]`), not every raw per-block circle MatchTerritory ever builds
## internally, which is exactly "the centers of that team's live influence
## circles" the brief asks for and cheap enough to call every ACTING tick (it
## is already recomputed at most once per territory solve, not on demand).
func _enemy_circle_centers() -> PackedVector2Array:
	var match_ref: Variant = _match()
	var own_team: int = int(match_ref.team_of(_slot_id))
	var centers: PackedVector2Array = PackedVector2Array()
	for i: int in range(int(match_ref.slot_count())):
		if int(match_ref.team_of(i)) == own_team:
			continue
		var slot: PlayerSlot = match_ref.slot(i)
		if slot != null:
			centers.append(slot.home_position)
	var circle_arrays: Dictionary = match_ref.circle_render_arrays()
	var xs: PackedFloat32Array = circle_arrays.get("xs", PackedFloat32Array()) as PackedFloat32Array
	var zs: PackedFloat32Array = circle_arrays.get("zs", PackedFloat32Array()) as PackedFloat32Array
	var teams: PackedInt32Array = circle_arrays.get("teams", PackedInt32Array()) as PackedInt32Array
	for i: int in range(teams.size()):
		if teams[i] == own_team:
			continue
		centers.append(Vector2(xs[i], zs[i]))
	return centers


## Bontago-d5c.10 (item F): every other special currently ticking on the disk
## (`game/specials/SpecialBehavior.GROUP`, its own scene-tree group -- see
## that file's own header comment), converted to a disk-local point through
## `_field.disk_local_from_world()`, the same conversion Field's own
## raycast_down_disk_local() uses. Fed to both BotSpecialPlanner.plan() and
## BotPlacementScorer.pick_best() as `active_special_positions` (spec 2.9's
## risk term: don't stack a new block, or aim a special, on top of one
## already armed and ticking). A behaviour is always added as a child of its
## owning Block (autoload/match/MatchPlacement.gd's `_arm_special_behavior()`:
## `block.add_child(behavior)`) -- read generically as `Node3D` rather than
## the concrete `Block` type, so a test fixture that stands in for "a
## Block-like Node3D" (any parented Node3D with a `global_position`) does not
## need to construct a real, physics-backed Block.
func _active_special_positions() -> PackedVector2Array:
	var positions: PackedVector2Array = PackedVector2Array()
	if _field == null:
		return positions
	for node: Node in get_tree().get_nodes_in_group(SpecialBehavior.GROUP):
		var behavior: SpecialBehavior = node as SpecialBehavior
		if behavior == null:
			continue
		var owner_node: Node3D = behavior.get_parent() as Node3D
		if owner_node == null:
			continue
		positions.append(_field.disk_local_from_world(owner_node.global_position))
	return positions


func _territory_sample_points() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for candidate: BotCandidate in _candidates:
		points.append(candidate.origin)
	if points.is_empty():
		points.append(_home_position())
	return points
