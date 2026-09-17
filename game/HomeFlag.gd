class_name HomeFlag
extends Node3D
## A player's home flag (spec 2.2): "Each player's home flag sits at
## 0.85 * field_radius, spaced evenly around the edge."
##
## Visual only. The home *circle* the flag anchors is an InfluenceCircle built
## by the match from the same MapDef.home_flag_position(), and whether the flag
## is still standing is PlayerSlot.home_flag_alive — no rule lives here.
##
## The flag is built from meshes rather than an art asset because M2 has no art
## yet; M7 replaces the body of _build() and nothing else.

@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")

var _slot_id: int = -1
var _color: Color = Color.WHITE
var _pole: MeshInstance3D = null
var _banner: MeshInstance3D = null
var _banner_material: StandardMaterial3D = null


func _ready() -> void:
	_build()
	_apply_color()


func _build() -> void:
	var height: float = visuals.flag_pole_height

	_pole = MeshInstance3D.new()
	_pole.name = &"Pole"
	var pole_mesh: CylinderMesh = CylinderMesh.new()
	pole_mesh.top_radius = visuals.flag_pole_radius
	pole_mesh.bottom_radius = visuals.flag_pole_radius
	pole_mesh.height = height
	_pole.mesh = pole_mesh
	var pole_material: StandardMaterial3D = StandardMaterial3D.new()
	pole_material.albedo_color = visuals.flag_pole_color
	_pole.material_override = pole_material
	_pole.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(_pole)

	var size: Vector2 = visuals.flag_banner_size * banner_scale()
	_banner = MeshInstance3D.new()
	_banner.name = &"Banner"
	var banner_mesh: QuadMesh = QuadMesh.new()
	banner_mesh.size = size
	_banner.mesh = banner_mesh
	_banner_material = StandardMaterial3D.new()
	_banner_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_banner_material.emission_enabled = true
	_banner.material_override = _banner_material
	# Hangs from the top of the pole, offset so the pole is its left edge.
	_banner.position = Vector3(size.x * 0.5, height - size.y * 0.5, 0.0)
	add_child(_banner)


## How much bigger than TerritoryVisuals.flag_banner_size this flag's banner
## is. GoalFlag overrides it.
func banner_scale() -> float:
	return 1.0


## Which slot this flag belongs to, and the color it flies. The color comes
## from MatchConfig.player_colors by way of Field.place_flags().
func set_slot(slot_id: int, color: Color) -> void:
	_slot_id = slot_id
	_color = color
	_apply_color()


func slot_id() -> int:
	return _slot_id


func color() -> Color:
	return _color


func _apply_color() -> void:
	if _banner_material == null:
		return
	_banner_material.albedo_color = _color
	_banner_material.emission = _color
	_banner_material.emission_energy_multiplier = visuals.flag_emission
