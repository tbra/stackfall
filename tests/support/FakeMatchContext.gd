class_name FakeMatchContext
extends MatchContext
## Test double for the MatchContext port (docs/AUTOLOAD_DECOUPLING_PLAN.md, S1b): one public
## `<name>_value` field per read, `<command>_calls` per command. Install with
## MatchContext.install(fake) and restore the previous one (MatchContext.installed()) in after_each.

var has_authority_value: bool = true
var net_is_host_value: bool = true
var net_is_client_value: bool = false
var net_is_offline_value: bool = true
var net_local_slot_value: int = -1
var config_value: MatchConfig = null
var physics_tuning_value: PhysicsTuning = null
var state_value: int = MatchPhase.State.LOBBY
var slot_count_value: int = 0
var active_slot_value: int = -1
var field_value: FieldBody = null
var registry_value: Node = null
var blocks_parent_value: Node3D = null
var raster_value: TerritoryRaster = null
var cell_grid_value: CellGrid = null
var qol_claim_radius_value: float = 0.0
var feed_timer_enabled_value: bool = false
var has_weather_value: bool = false
var weather_seed_value: int = 0
var weather_event_index_value: int = 0
var shared_clock_seconds_value: float = 0.0
var net_is_local_slot_value: bool = false
var slot_by_id: Dictionary = {}
var slot_color_by_id: Dictionary = {}
var glue_drops_by_slot: Dictionary = {}
var feed_time_by_slot: Dictionary = {}
var start_cat_result: bool = false
var grant_glue_drops_result: bool = false
var convert_block_owner_result: bool = false
var spawn_projectile_result: RigidBody3D = null
var add_match_child_adopts: bool = false

var start_cat_calls: Array[Dictionary] = []
var end_cat_calls: Array[Dictionary] = []
var grant_glue_drops_calls: Array[Dictionary] = []
var convert_block_owner_calls: Array[Dictionary] = []
var spawn_special_projectile_calls: Array[Dictionary] = []
var punch_special_hole_calls: Array[Dictionary] = []
var add_match_child_calls: Array[Dictionary] = []


func has_authority() -> bool:
	return has_authority_value

func net_is_host() -> bool:
	return net_is_host_value

func net_is_client() -> bool:
	return net_is_client_value

func net_is_offline() -> bool:
	return net_is_offline_value

func net_local_slot() -> int:
	return net_local_slot_value

func config() -> MatchConfig:
	return config_value

func physics_tuning() -> PhysicsTuning:
	return physics_tuning_value

func state() -> int:
	return state_value

func slot_count() -> int:
	return slot_count_value

func active_slot() -> int:
	return active_slot_value

func field() -> FieldBody:
	return field_value

func registry() -> Node:
	return registry_value

func blocks_parent() -> Node3D:
	return blocks_parent_value

func raster() -> TerritoryRaster:
	return raster_value

func cell_grid() -> CellGrid:
	return cell_grid_value

func qol_claim_radius() -> float:
	return qol_claim_radius_value

func feed_timer_enabled() -> bool:
	return feed_timer_enabled_value

func has_weather() -> bool:
	return has_weather_value

func weather_seed() -> int:
	return weather_seed_value

func weather_event_index() -> int:
	return weather_event_index_value

func shared_clock_seconds() -> float:
	return shared_clock_seconds_value


func net_is_local_slot(_slot_id: int) -> bool:
	return net_is_local_slot_value


func slot(slot_id: int) -> PlayerSlot:
	return slot_by_id.get(slot_id, null) as PlayerSlot


func slot_color(slot_id: int, fallback: Color = Color.WHITE) -> Color:
	return slot_color_by_id.get(slot_id, fallback) as Color


func glue_drops_left(slot_id: int) -> int:
	return int(glue_drops_by_slot.get(slot_id, 0))


func feed_time_left(slot_id: int) -> float:
	return float(feed_time_by_slot.get(slot_id, 0.0))


func start_cat(owner_slot: int, position: Vector3, effect: Resource) -> bool:
	start_cat_calls.append({"owner_slot": owner_slot, "position": position, "effect": effect})
	return start_cat_result


func end_cat(activation_id: int) -> void:
	end_cat_calls.append({"activation_id": activation_id})


func grant_glue_drops(slot_id: int, count: int) -> bool:
	grant_glue_drops_calls.append({"slot_id": slot_id, "count": count})
	return grant_glue_drops_result


func convert_block_owner(block: RigidBody3D, new_slot: int) -> bool:
	convert_block_owner_calls.append({"block": block, "new_slot": new_slot})
	return convert_block_owner_result


func spawn_special_projectile(shape: BlockShape, world_origin: Vector3, basis: Basis,
		owner_slot: int, initial_velocity: Vector3, orb_def: SpecialDef,
		orb_tuning: SpecialTuning) -> RigidBody3D:
	spawn_special_projectile_calls.append({"shape": shape, "world_origin": world_origin, "basis": basis,
			"owner_slot": owner_slot, "initial_velocity": initial_velocity, "orb_def": orb_def,
			"orb_tuning": orb_tuning})
	return spawn_projectile_result


func punch_special_hole(disk_pos: Vector2, radius_m: float, hole_open_s: float) -> void:
	punch_special_hole_calls.append({"disk_pos": disk_pos, "radius_m": radius_m, "hole_open_s": hole_open_s})


## Records the node; frees it unless the test sets add_match_child_adopts (then the test owns it).
func add_match_child(node: Node) -> void:
	add_match_child_calls.append({"node": node})
	if node != null and not add_match_child_adopts:
		node.queue_free()
