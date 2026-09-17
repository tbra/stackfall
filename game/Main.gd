extends Node3D
## The playable M2 build: a hot-seat match on one PC (spec Part 4 M2).
##
## This is the one file nobody but the integrator owns (docs/M2_PLAN.md), and
## it is deliberately thin. It builds no rules and runs no ticks of its own:
## every M2 system self-wires through the Events bus, so all Main does is hand
## the pieces to each other once, in the right order.
##
## **Wiring order matters.** Match.register_world() must happen before
## start_match(), because start_match() configures the BlockRegistry and clears
## the blocks container. Field.place_flags() and Field.set_overlay_source() must
## happen after start_match(), because only then do Match.config (sanitized) and
## Match.raster() exist.
##
## **Ticks** (docs/M2_PLAN.md integration order, step 3) are all accumulators,
## never Timer nodes, and none of them live here:
##   - 10 Hz (TerritoryTuning.solve_hz): Match._tick_territory runs the solver,
##     the raster and the win check, then emits territory_updated,
##     hole_cells_changed, goal_capture_progress, territory_share_changed and
##     match_won.
##   - 5 Hz (TerritoryTuning.raster_upload_hz): TerritoryOverlay rebuilds its
##     ImageTexture from the raster Field handed it here.
##   - every physics frame: Field drains its hole backlog at
##     TerritoryTuning.max_cell_toggles_per_frame and wakes the blocks above
##     the cells that changed; BlockRegistry re-evaluates the settled rule.
##
## M3 replaces this scene's start-a-match-immediately behaviour with a lobby;
## nothing here assumes a transport, and nothing branches on is_server().

## Default lobby settings for the hot-seat build. start_match() duplicates and
## sanitizes it, so the resource on disk is never mutated.
@export var match_config: MatchConfig = preload("res://config/match_defaults.tres")
## Spec Part 4 M2 accepts on "two players take turns on one PC", so the M2
## build starts a two-player hot-seat match. Both live in MatchConfig rather
## than as literals here (CLAUDE.md: no magic numbers).
@export var player_count: int = 2

@onready var _field: Field = $Field
@onready var _blocks_container: Node3D = $BlocksContainer
@onready var _registry: BlockRegistry = $BlockRegistry
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _hot_seat: HotSeat = $HotSeat


func _ready() -> void:
	print(_boot_line())
	_hot_seat.set_camera_rig(_camera_rig)
	Match.register_world(_field, _registry, _blocks_container)
	Match.start_match(_build_config())

	var config: MatchConfig = Match.config
	_field.place_flags(config.player_count, config.player_colors, config.goal_flag_count)
	_field.set_overlay_source(Match.raster(), config.player_colors)


## The lobby settings M3 will collect from a real lobby screen. Hot-seat and
## the player count are the only overrides; everything else is whatever
## config/match_defaults.tres says.
func _build_config() -> MatchConfig:
	var config: MatchConfig = match_config.duplicate(true) as MatchConfig
	config.player_count = player_count
	config.hot_seat = true
	return config


## One-line report of the settings M0 is required to get right (spec 3.1, 3.5).
func _boot_line() -> String:
	var version: String = str(Engine.get_version_info().get("string", "unknown"))
	var physics_engine: String = str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var ticks: int = Engine.physics_ticks_per_second
	var interpolated: bool = bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	return "Stackfall boot | godot %s | renderer %s | physics %s | %d Hz | interpolation %s" % [
		version, renderer, physics_engine, ticks, interpolated,
	]
