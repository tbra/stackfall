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

var slot_id: int = -1
var team_id: int = -1
var mode: int = MatchConfig.GameMode.CLASSIC
var field_radius: float = 0.0
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
