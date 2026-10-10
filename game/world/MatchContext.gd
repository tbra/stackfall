class_name MatchContext
extends RefCounted
## The port world code (fields, specials, presenters, weather effects) uses to reach the running
## match without naming the Match or Net autoloads (docs/AUTOLOAD_DECOUPLING_PLAN.md, S1b, D1-D5).
##
## The base class is the null object: "no match, offline". autoload/match/MatchContextLive.gd
## forwards each method 1:1 to the real autoloads and is installed by Match._ready(). Tests install
## a FakeMatchContext and restore the previous one.
##
## DECISION (D3): has_authority() mirrors Match._is_host() (honours Match.set_net_provider) while
## net_*() mirror the real Net autoload (they ignore that provider), exactly as each call site
## behaved before. Never merge the two.

static var _installed: MatchContext = null
static var _null_context: MatchContext = null


## The installed context, else a lazily built null object.
static func current() -> MatchContext:
	if _installed != null:
		return _installed
	if _null_context == null:
		_null_context = MatchContext.new()
	return _null_context


## The installed context or null (tests save and restore with it).
static func installed() -> MatchContext:
	return _installed


## Null uninstalls.
static func install(context: MatchContext) -> void:
	_installed = context


# --- session (D3) -------------------------------------------------------------

func has_authority() -> bool:
	return true


func net_is_host() -> bool:
	return true


func net_is_client() -> bool:
	return false


func net_is_offline() -> bool:
	return true


func net_local_slot() -> int:
	return -1


func net_is_local_slot(_slot_id: int) -> bool:
	return false


# --- read model ---------------------------------------------------------------

func config() -> MatchConfig:
	return null


func physics_tuning() -> PhysicsTuning:
	return null


func state() -> int:
	return MatchPhase.State.LOBBY


func slot_count() -> int:
	return 0


func slot(_slot_id: int) -> PlayerSlot:
	return null


func slot_color(_slot_id: int, fallback: Color = Color.WHITE) -> Color:
	return fallback


func active_slot() -> int:
	return -1


func field() -> FieldBody:
	return null


## A BlockRegistry (kept as Node so this port stays out of the heavy world closure, D5/D8).
func registry() -> Node:
	return null


func blocks_parent() -> Node3D:
	return null


func raster() -> TerritoryRaster:
	return null


func cell_grid() -> CellGrid:
	return null


func qol_claim_radius() -> float:
	return 0.0


## Bontago-mp0.152: radius of the zone every goal beacon draws (null object: nothing).
func goal_zone_visual_radius() -> float:
	return 0.0


func glue_drops_left(_slot_id: int) -> int:
	return 0


func feed_timer_enabled() -> bool:
	return false


func feed_time_left(_slot_id: int) -> float:
	return 0.0


func has_weather() -> bool:
	return false


func weather_seed() -> int:
	return 0


func weather_event_index() -> int:
	return 0


func shared_clock_seconds() -> float:
	return 0.0


# --- host commands (Match re-validates each exactly as today) -------------------

func start_cat(_owner_slot: int, _position: Vector3, _effect: Resource) -> bool:
	return false


func end_cat(_activation_id: int) -> void:
	pass


func grant_glue_drops(_slot_id: int, _count: int) -> bool:
	return false


func convert_block_owner(_block: RigidBody3D, _new_slot: int) -> bool:
	return false


func spawn_special_projectile(_shape: BlockShape, _world_origin: Vector3, _basis: Basis,
		_owner_slot: int, _initial_velocity: Vector3, _orb_def: SpecialDef,
		_orb_tuning: SpecialTuning) -> RigidBody3D:
	return null


func punch_special_hole(_disk_pos: Vector2, _radius_m: float, _hole_open_s: float) -> void:
	pass


## Default (no match): the node is discarded; Live adds it under the Match autoload.
func add_match_child(node: Node) -> void:
	if node != null:
		node.queue_free()
