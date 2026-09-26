class_name GoalFlag
extends HomeFlag
## A goal flag (spec 2.2, 2.3): one in the center by default, 1-5 in setup,
## extras placed symmetrically at 0.4 * field_radius.
##
## Extends HomeFlag because a goal flag is the same beacon (socket, ring and
## crystal, M7 P8) at a larger scale in a neutral color; what it adds is spec
## 2.3's capture display, "a radial progress ring appears on each goal flag
## while someone is capturing it". That capture ring is a second, separate
## flat annulus arc lying on the disk (distinct from the beacon's own always-
## on Ring mesh above it), rebuilt only when the progress it shows actually
## moves.
##
## Visual only: who is capturing and how far along they are is WinChecker's
## answer, arriving through Events.goal_capture_progress and
## Field.set_capture_progress().

## Smallest change in progress that is worth rebuilding the arc mesh for. One
## ring segment is 1 / capture_ring_segments of a turn, so anything finer than
## that cannot change a single triangle.
const PROGRESS_EPSILON: float = 0.001

var _ring: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _capture_team: int = -1
var _capture_progress: float = 0.0
var _drawn_progress: float = -1.0


func _ready() -> void:
	# DECISION (game/GoalFlag.gd, Bontago-xtq.33): the goal beacon's neutral
	# color and scale now come from BeaconVisualTuning (neutral_color,
	# goal_scale_factor) instead of TerritoryVisuals (goal_flag_color,
	# goal_flag_scale), which this file was the only reader of for those two
	# purposes -- TerritoryVisuals.goal_flag_color keeps its own, unrelated
	# fallback uses in Field.gd/TerritoryOverlay.gd untouched.
	_color = beacon_visuals.neutral_color
	super()
	_build_ring()


func banner_scale() -> float:
	return beacon_visuals.goal_scale_factor


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = &"CaptureRing"
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.emission_enabled = true
	_ring.material_override = _ring_material
	_ring.position = Vector3(0.0, visuals.capture_ring_lift, 0.0)
	_ring.visible = false
	add_child(_ring)


## Spec 2.3's capture display. `progress` runs 0..1 over
## TerritoryTuning.capture_hold; team_id -1 or progress 0 hides the ring.
func set_capture(team_id: int, progress: float, color: Color) -> void:
	_capture_team = team_id
	_capture_progress = clampf(progress, 0.0, 1.0)
	if _ring == null:
		return
	if _capture_team < 0 or _capture_progress <= 0.0:
		_ring.visible = false
		_drawn_progress = 0.0
		return
	_ring_material.albedo_color = color
	_ring_material.emission = color
	_ring_material.emission_energy_multiplier = visuals.capture_ring_emission
	_ring.visible = true
	if absf(_capture_progress - _drawn_progress) >= PROGRESS_EPSILON:
		_ring.mesh = _build_arc(_capture_progress)
		_drawn_progress = _capture_progress


func capture_team() -> int:
	return _capture_team


func capture_progress() -> float:
	return _capture_progress


func ring_visible() -> bool:
	return _ring != null and _ring.visible


## The arc currently drawn, or null before the first capture.
func ring_mesh() -> Mesh:
	return _ring.mesh if _ring != null else null


## An annulus arc covering `progress` of a full turn, starting at +z and
## running clockwise seen from above, so it fills the way a clock hand does.
func _build_arc(progress: float) -> ArrayMesh:
	var segments: int = maxi(visuals.capture_ring_segments, 3)
	var used: int = maxi(int(ceil(progress * float(segments))), 1)
	var outer: float = visuals.capture_ring_radius
	var inner: float = maxf(outer - visuals.capture_ring_thickness, 0.001)
	var sweep: float = TAU * progress

	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for i: int in range(used):
		var a0: float = sweep * float(i) / float(used)
		var a1: float = sweep * float(i + 1) / float(used)
		var d0: Vector3 = Vector3(sin(a0), 0.0, cos(a0))
		var d1: Vector3 = Vector3(sin(a1), 0.0, cos(a1))
		var o0: Vector3 = d0 * outer
		var o1: Vector3 = d1 * outer
		var i0: Vector3 = d0 * inner
		var i1: Vector3 = d1 * inner
		vertices.append_array([i0, o0, o1, i0, o1, i1])
	for _v: int in range(vertices.size()):
		normals.append(Vector3.UP)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh_out: ArrayMesh = ArrayMesh.new()
	mesh_out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh_out
