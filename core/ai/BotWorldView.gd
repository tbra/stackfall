class_name BotWorldView
extends RefCounted
## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3 step 1): one pure snapshot of everything a
## think-cycle reads, built once per piece from host state. No scene-tree access.
## The circle list comes from Match.circle_render_arrays(), which also contains
## every living home circle; those are stripped here (matched by home position
## and TerritoryTuning.home_radius) so `cx/cz/cr/cteam` hold block circles only.

const SHIPPED_TERRITORY_TUNING: TerritoryTuning = preload("res://config/territory_tuning.tres")
const SHIPPED_PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Position / radius slack when matching a render-list circle to a home flag.
const HOME_MATCH_TOLERANCE_M: float = 0.05
## Footprint-extent bound pads: one cube of reach and the unit-cube space diagonal.
const CUBE_PAD_CELLS: float = 1.0
const CUBE_DIAGONAL: float = 1.7320508
## A gust's sine envelope (BreezeField.envelope) peaks at this fraction of its life.
const GUST_PEAK_LIFE_FRACTION: float = 0.5

var slot_id: int = -1
var team_id: int = -1
var mode: int = MatchConfig.GameMode.CLASSIC
var field_radius: float = 0.0
## Bontago-1t5.42: radius of the still-solid disc (field_radius until a sudden-death shrink).
## field_radius stays the original so influence-circle caps are unchanged.
var live_radius: float = 0.0
var raster: TerritoryRaster = null
var grid: CellGrid = null
var territory_tuning: TerritoryTuning = SHIPPED_TERRITORY_TUNING
## Cube edge in metres (footprint sampling); not part of build() so tests may override.
var cube_size: float = SHIPPED_PHYSICS_TUNING.cube_size
var own_home: Vector2 = Vector2.ZERO
var has_home: bool = false
## Living home flags of the viewing bot team (own included, teammates too): chain roots.
var team_homes: PackedVector2Array = PackedVector2Array()
var goals: PackedVector2Array = PackedVector2Array()
var goal_zone_radius: float = 0.0
var enemy_homes: PackedVector2Array = PackedVector2Array()
var enemy_home_teams: PackedInt32Array = PackedInt32Array()
## Block circles only (home circles stripped).
var cx: PackedFloat32Array = PackedFloat32Array()
var cz: PackedFloat32Array = PackedFloat32Array()
var cr: PackedFloat32Array = PackedFloat32Array()
var cteam: PackedInt32Array = PackedInt32Array()
var held: BlockShape = null
var next_shape: BlockShape = null
var mode_goal: BotModeGoal = null
var specials: PackedVector2Array = PackedVector2Array()
var gifts: PackedVector2Array = PackedVector2Array()
## Bontago-1t5.44: enemy specials in flight, as predicted impact points (disk-local x/z) and their
## effect radii (m). Landed/armed specials stay in `specials`; these are risk terms only.
var incoming_points: PackedVector2Array = PackedVector2Array()
var incoming_radii: PackedFloat32Array = PackedFloat32Array()
## Active weather id (&"" = calm) and its current 0..1 intensity, plain data from MatchWeather.
var weather_id: StringName = &""
var weather_intensity: float = 0.0
## Height response of the active wind (WindField.height_factor); null when no wind blows
## (calm, rain, snow, ...), which keeps every wind term at exactly 0.
# DECISION (Bontago-1t5.46, replaces the 1t5.41 "direction and gusts ignored" note): the height
# response still decides how tip-prone a tall stack is, and the wind HEADING now only grades the
# fall-off-the-rim part of it (BotEvaluator.downwind_rim_factor): a piece with open disc downwind
# of it is unchanged, one near the rim on the downwind side is graded worse. The Storm heading is
# its seeded base heading (WindField.base_angle of the event seed): the host's live +/- veer is
# not readable from the controller (the effect's clock is private), so it is left out.
var wind_tuning: StormTuning = null
## Storm heading as a unit vector in disk-local x/z; ZERO when no Storm blows or it is unknown.
var wind_dir: Vector2 = Vector2.ZERO
## Bontago-1t5.46: the live Breeze gusts (host list, BreezeEffect.gusts()) as plain parallel data in
## disk-local space; empty when none blows. `gust_center` is (disk x, height above the disc
## surface, disk z), `gust_heading` a unit vector, `gust_power` 0..1 (see gust_power()).
## `breeze_tuning` is the height response the gust pushes with; null while no gust is listed.
var breeze_tuning: BreezeTuning = null
var gust_center: PackedVector3Array = PackedVector3Array()
var gust_radius: PackedFloat32Array = PackedFloat32Array()
var gust_heading: PackedVector2Array = PackedVector2Array()
var gust_power_values: PackedFloat32Array = PackedFloat32Array()
## Bontago-1t5.53b: snapshot of the cubes near the own towers (game/BotStackProbe.gd); BotThink's STACK
## phase analyses it. null = no tower statics: every site keeps its old score.
var stack: BotStack = null


static func build(
	slot_id_value: int,
	team_id_value: int,
	circles: Dictionary,
	slots: Array[PlayerSlot],
	raster_value: TerritoryRaster,
	goals_value: PackedVector2Array,
	goal_zone_radius_value: float,
	held_value: BlockShape,
	next_shape_value: BlockShape,
	mode_goal_value: BotModeGoal,
	specials_value: PackedVector2Array,
	gifts_value: PackedVector2Array
) -> BotWorldView:
	var view: BotWorldView = BotWorldView.new()
	view.slot_id = slot_id_value
	view.team_id = team_id_value
	view.raster = raster_value
	view.grid = raster_value.grid() if raster_value != null else null
	if raster_value != null and raster_value.tuning() != null:
		view.territory_tuning = raster_value.tuning()
	view.field_radius = view.grid.field_radius if view.grid != null else 0.0
	view.live_radius = view.field_radius
	view.goals = goals_value
	view.goal_zone_radius = goal_zone_radius_value
	view.held = held_value
	view.next_shape = next_shape_value
	view.mode_goal = mode_goal_value
	if mode_goal_value != null:
		view.mode = mode_goal_value.mode
	view.specials = specials_value
	view.gifts = gifts_value
	var living_homes: PackedVector2Array = PackedVector2Array()
	for slot_item: PlayerSlot in slots:
		if slot_item == null:
			continue
		if slot_item.slot_id == slot_id_value:
			view.own_home = slot_item.home_position
			view.has_home = true
		elif slot_item.team_id != team_id_value:
			if slot_item.home_flag_alive:
				view.enemy_homes.append(slot_item.home_position)
				view.enemy_home_teams.append(slot_item.team_id)
		if slot_item.home_flag_alive:
			living_homes.append(slot_item.home_position)
			if slot_item.team_id == team_id_value:
				view.team_homes.append(slot_item.home_position)
	view._copy_block_circles(circles, living_homes)
	return view


## Bontago-1t5.44: records one enemy special in flight by its predicted impact point.
func add_incoming_special(impact: Vector2, radius: float) -> void:
	if radius <= 0.0:
		return
	incoming_points.append(impact)
	incoming_radii.append(radius)


## Bontago-1t5.44: ballistic landing of a body at disk-local `pos` / `height` above the disc
## surface moving at `vel` (x/z) and `vy`, under `gravity` (m/s^2, > 0). Returns (x, z, seconds to
## impact). A non-positive gravity or a body already at/below the surface returns its own point at 0.
static func ballistic_impact(pos: Vector2, height: float, vel: Vector2, vy: float, gravity: float) -> Vector3:
	if gravity <= 0.0 or height <= 0.0 and vy <= 0.0:
		return Vector3(pos.x, pos.y, 0.0)
	var t: float = (vy + sqrt(maxf(vy * vy + 2.0 * gravity * maxf(height, 0.0), 0.0))) / gravity
	var hit: Vector2 = pos + vel * t
	return Vector3(hit.x, hit.y, t)


## Bontago-1t5.46: records one live Breeze gust (disk-local `center` = x, height above the disc
## surface, z; `heading` a unit x/z vector). Gusts with no power are skipped.
func add_gust(center: Vector3, radius: float, heading: Vector2, power: float) -> void:
	if power <= 0.0 or radius <= 0.0:
		return
	gust_center.append(center)
	gust_radius.append(radius)
	gust_heading.append(heading)
	gust_power_values.append(power)


## Bontago-1t5.46: how hard a gust can still push a piece that lands later, 0..1. Its envelope
## rises to a peak at half its life, so a young gust counts as its peak (it is about to blow
## hardest) and an old one as its current, fading envelope; an expired gust counts as 0.
static func gust_power(strength: float, age_s: float, duration_s: float) -> float:
	if duration_s <= 0.0 or age_s >= duration_s:
		return 0.0
	var envelope: float = 1.0
	if age_s > duration_s * GUST_PEAK_LIFE_FRACTION:
		envelope = BreezeField.envelope(age_s, duration_s)
	return clampf(strength, 0.0, 1.0) * envelope


## Copies the render list, dropping one home circle per living home.
func _copy_block_circles(circles: Dictionary, living_homes: PackedVector2Array) -> void:
	var xs: PackedFloat32Array = circles.get("xs", PackedFloat32Array()) as PackedFloat32Array
	var zs: PackedFloat32Array = circles.get("zs", PackedFloat32Array()) as PackedFloat32Array
	var radii: PackedFloat32Array = circles.get("radii", PackedFloat32Array()) as PackedFloat32Array
	var teams: PackedInt32Array = circles.get("teams", PackedInt32Array()) as PackedInt32Array
	var home_unmatched: Array[bool] = []
	home_unmatched.resize(living_homes.size())
	home_unmatched.fill(true)
	for i: int in range(mini(xs.size(), mini(zs.size(), teams.size()))):
		var radius: float = radii[i] if i < radii.size() else 0.0
		if _strip_as_home(Vector2(xs[i], zs[i]), radius, living_homes, home_unmatched):
			continue
		cx.append(xs[i])
		cz.append(zs[i])
		cr.append(radius)
		cteam.append(teams[i])


func _strip_as_home(point: Vector2, radius: float, living_homes: PackedVector2Array, home_unmatched: Array[bool]) -> bool:
	if absf(radius - territory_tuning.home_radius) > HOME_MATCH_TOLERANCE_M:
		return false
	for h: int in range(living_homes.size()):
		if home_unmatched[h] and living_homes[h].distance_to(point) <= HOME_MATCH_TOLERANCE_M:
			home_unmatched[h] = false
			return true
	return false


## Bontago-1t5.42: live playable radius from the raster (no Match accessor exposes the shrink
## radius). MatchTerritory.shrink_to_radius punches every cell whose centre lies beyond the radius
## as a permanent hole, so the farthest non-hole in-disk cell centre is the live radius
## (cell-quantised; a natural hole on the rim only makes it smaller, i.e. conservative).
## Returns the live radius, or the grid's original extent (farthest in-disk cell centre) when no
## shrink is visible: DECISION: on non-circular maps (CellGrid shape test) the farthest cell of the
## carved shape is below field_radius with nothing shrunk, so "shrunk" means live < that original
## extent, never live < field_radius; unshrunk maps then report the full field_radius.
## DECISION: cached per (raster, content_revision) so every bot's think in one solve step shares
## one scan (the revision bumps on any raster change, no hole-only counter exists); the original
## extent is cached per grid. Only call while sudden death is active.
static var _scan_raster_id: int = 0
static var _scan_revision: int = -1
static var _scan_live: float = 0.0
static var _extent_grid_id: int = 0
static var _extent_value: float = 0.0
static var scan_count: int = 0


static func live_radius_from_raster(raster_value: TerritoryRaster, grid_value: CellGrid) -> float:
	if raster_value == null or grid_value == null:
		return 0.0
	var raster_id: int = raster_value.get_instance_id()
	var revision: int = raster_value.content_revision()
	if raster_id != _scan_raster_id or revision != _scan_revision:
		_scan_raster_id = raster_id
		_scan_revision = revision
		_scan_live = _scan_live_radius(raster_value, grid_value)
	var extent: float = _original_extent(grid_value)
	if _scan_live >= extent:
		return grid_value.field_radius
	return _scan_live


static func _scan_live_radius(raster_value: TerritoryRaster, grid_value: CellGrid) -> float:
	scan_count += 1
	var best_sq: float = 0.0
	for index: int in grid_value.in_disk_cells():
		var xy: Vector2i = grid_value.cell_coords(index)
		if raster_value.is_hole(xy.x, xy.y):
			continue
		best_sq = maxf(best_sq, grid_value.index_center(index).length_squared())
	return sqrt(best_sq)


static func _original_extent(grid_value: CellGrid) -> float:
	var grid_id: int = grid_value.get_instance_id()
	if grid_id != _extent_grid_id:
		_extent_grid_id = grid_id
		var best_sq: float = 0.0
		for index: int in grid_value.in_disk_cells():
			best_sq = maxf(best_sq, grid_value.index_center(index).length_squared())
		_extent_value = sqrt(best_sq)
	return _extent_value


## True only for an actual shrink: live radius below the original by more than
## BotEvalTuning.shrink_epsilon_m (not at sudden-death t=0, where live == field_radius).
func is_shrunk() -> bool:
	return live_radius > 0.0 and live_radius < field_radius - BotEvaluator.tuning.shrink_epsilon_m


## Upper bound (m) of how far any footprint cell centre lies from the candidate origin, whatever
## the orientation (rotation about the pivot keeps lengths); -1 when no held shape is known.
func footprint_extent_m() -> float:
	if _extent_cached:
		return _extent_m
	_extent_cached = true
	_extent_m = -1.0
	if held == null or held.cells.is_empty() or grid == null:
		return _extent_m
	var pivot: Vector3 = held.bottom_center()
	var far: float = 0.0
	for cell: Vector3i in held.cells:
		far = maxf(far, (Vector3(cell) - pivot).length())
	# + one cube diagonal for the cell's own corners, + one grid cell for centre quantisation.
	_extent_m = (far + CUBE_PAD_CELLS) * cube_size * CUBE_DIAGONAL + grid.cell_size
	return _extent_m


var _extent_cached: bool = false
var _extent_m: float = -1.0


func circle_count() -> int:
	return cx.size()


## Height of circle `i`'s highest point above the disk, inverted from
## InfluenceCircle.radius_for_height (r = base + slope * h); 0 at or below the base.
func top_height(i: int) -> float:
	return maxf(cr[i] - territory_tuning.influence_base, 0.0) / InfluenceCircle.cone_slope()


func indices_of_team(team: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(cteam.size()):
		if cteam[i] == team:
			out.append(i)
	return out


## Enemy home flags plus every enemy block-circle centre: what BotPlacementScorer's
## risk and elimination terms read as "where the enemy is".
func enemy_circle_centers() -> PackedVector2Array:
	var centers: PackedVector2Array = enemy_homes.duplicate()
	for i: int in range(cteam.size()):
		if cteam[i] != team_id:
			centers.append(Vector2(cx[i], cz[i]))
	return centers
