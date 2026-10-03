class_name SnowCaps
extends RefCounted
## Scene side of snow geometry (Bontago-22y.6): the node helpers the
## SnowCapBuilder commits through, on the host (with colliders) and on
## clients (without).
##
## Block visuals sit under a plain Node3D ("SnowCap"), never as a direct
## MeshInstance3D child of the Block: BlockRegistry's height credit reads the
## direct MeshInstance3D children, and snow must not raise a tower's height.
## The colliders are direct CollisionShape3D children (a body only collides
## with direct children), tagged with LUMP_META so "which cells does this
## block have" readers here skip them; they are ConvexPolygonShape3D, never
## BoxShape3D, so box-only readers (Block release tilt, PerchingBirds) ignore
## them too. Disc drifts are grouped per region: one mesh and one
## StaticBody3D child of the Field per region.

const CAP_NAME: StringName = &"SnowCap"
const CAP_MESH_NAME: StringName = &"SnowCapMesh"
const DISC_CAP_PREFIX: String = "SnowDiscCap"
const DISC_BODY_PREFIX: String = "SnowDiscBody"
const DISC_COVER_NAME: StringName = &"SnowDiscCover"
## A cover set to level 0 keeps drawing while it fades out (Bontago-mp0.97)
## under this name, so disc_cover() no longer reports it.
const DISC_COVER_FADING_NAME: StringName = &"SnowDiscCoverFading"
const LUMP_META: StringName = &"snow_lump"
const CAP_SHADER: Shader = preload("res://shaders/weather/snow_cap.gdshader")
const DISC_CAP_SHADER: Shader = preload("res://shaders/weather/snow_drift.gdshader")
## Collision margin of a snow shape when no tuning is at hand (clearing).
const DEFAULT_MARGIN_M: float = 0.004
## Region ids pack (x, y) region coordinates; the grid is far smaller.
const REGION_STRIDE: int = 4096

static var _material: ShaderMaterial = null
static var _material_tuning: SnowTuning = null
static var _disc_material: ShaderMaterial = null
static var _disc_material_tuning: SnowTuning = null


## Disc drift domes: same look, but the dome fades in over its lowest
## disc_drift_rim_fade_m so it blends into the disc snow layer instead of
## showing a circle outline (the collider is unchanged).
static func disc_cap_material(tuning: SnowTuning) -> ShaderMaterial:
	if _disc_material == null or _disc_material_tuning != tuning:
		var material: ShaderMaterial = cap_material(tuning).duplicate() as ShaderMaterial
		material.shader = DISC_CAP_SHADER
		material.set_shader_parameter(&"rim_fade_height", tuning.disc_drift_rim_fade_m)
		material.set_shader_parameter(&"rim_fade_base", tuning.cap_lift_m)
		material.set_shader_parameter(&"light_gain", tuning.cover_light_gain)
		material.set_shader_parameter(&"dim", tuning.disc_drift_dim)
		# A drift reads as the pale-lavender middle tone of the disc snow.
		material.set_shader_parameter(&"snow_color", tuning.cover_tone_mid_color)
		material.set_shader_parameter(&"shade_color", tuning.snow_shade_color)
		_disc_material = material
		_disc_material_tuning = tuning
	return _disc_material


static func cap_material(tuning: SnowTuning) -> ShaderMaterial:
	if _material == null or _material_tuning != tuning:
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = CAP_SHADER
		material.set_shader_parameter(&"snow_color", tuning.snow_color)
		material.set_shader_parameter(&"shade_color", tuning.snow_shade_color)
		material.set_shader_parameter(&"rim_color", tuning.snow_rim_color)
		material.set_shader_parameter(&"rim_strength", tuning.snow_rim_strength)
		_material = material
		_material_tuning = tuning
	return _material


static func cube_size_of(block: Node3D) -> float:
	var typed: Block = block as Block
	if typed != null and typed.tuning != null:
		return typed.tuning.cube_size
	return 1.0


## Canonical cell centres (block-local) from the block's own cell colliders.
static func block_cells(block: Node3D) -> PackedVector3Array:
	var centers: PackedVector3Array = PackedVector3Array()
	for child: Node in block.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision == null or collision.has_meta(LUMP_META) or not (collision.shape is BoxShape3D):
			continue
		centers.append(collision.position)
	return SnowGeometry.canonical_cells(centers, cube_size_of(block))


static func block_patch_edge(cube_size: float, tuning: SnowTuning) -> float:
	return cube_size * tuning.block_patch_fill


static func disc_patch_edge(grid: CellGrid, tuning: SnowTuning) -> float:
	return grid.cell_size * tuning.disc_patch_cells


## Field-local frame of the disc drift centred on `cell`.
## With `tuning` the frame's X axis points along the wind, so drifts lie
## downwind of what shelters them.
static func disc_patch_frame(grid: CellGrid, cell: int, tuning: SnowTuning = null) -> Transform3D:
	var center: Vector2 = grid.index_center(cell)
	var basis: Basis = Basis.IDENTITY
	if tuning != null:
		var wind: Vector2 = Vector2.from_angle(deg_to_rad(tuning.cover_wind_angle_deg))
		basis = Basis(Vector3(wind.x, 0.0, wind.y), Vector3.UP, Vector3(-wind.y, 0.0, wind.x))
	return Transform3D(basis, Vector3(center.x, 0.0, center.y))


static func disc_region(grid: CellGrid, cell: int, tuning: SnowTuning) -> int:
	var coords: Vector2i = grid.cell_coords(cell)
	var size: int = maxi(tuning.disc_region_cells, 1)
	return (coords.y / size) * REGION_STRIDE + coords.x / size


static func disc_cap_name(region: int) -> StringName:
	return StringName("%s%d" % [DISC_CAP_PREFIX, region])


static func disc_body_name(region: int) -> StringName:
	return StringName("%s%d" % [DISC_BODY_PREFIX, region])


# --- Commit helpers -------------------------------------------------------------------

## Replaces the snow mesh under `holder` (removed when `vertices` is empty).
static func apply_mesh(holder: Node3D, cap_name: StringName, vertices: PackedVector3Array, normals: PackedVector3Array, tuning: SnowTuning, disc: bool = false) -> void:
	var cap: Node3D = holder.get_node_or_null(NodePath(String(cap_name))) as Node3D
	if vertices.is_empty():
		if cap != null:
			holder.remove_child(cap)
			cap.free()
		return
	if cap == null:
		cap = Node3D.new()
		cap.name = cap_name
		holder.add_child(cap)
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.name = CAP_MESH_NAME
		cap.add_child(instance)
	var mesh_instance: MeshInstance3D = cap.get_node(NodePath(String(CAP_MESH_NAME))) as MeshInstance3D
	mesh_instance.mesh = SnowGeometry.build_mesh(vertices, normals)
	if disc:
		var material: ShaderMaterial = disc_cap_material(tuning)
		_match_disc_lighting(material, holder, tuning)
		mesh_instance.material_override = material
	else:
		mesh_instance.material_override = cap_material(tuning)


## Copies the disc surface's own lighting numbers (sun desaturation, sky
## ambient) onto the drift material, so a drift is lit like the disc snow
## layer it sits in.
static func _match_disc_lighting(material: ShaderMaterial, holder: Node3D, tuning: SnowTuning) -> void:
	var field: Field = holder as Field
	var overlay: TerritoryOverlay = field.overlay() if field != null else null
	var disc: ShaderMaterial = overlay.material() if overlay != null else null
	if disc == null:
		return
	var desaturate: Variant = disc.get_shader_parameter(&"disk_diffuse_desaturate")
	var ambient: Variant = disc.get_shader_parameter(&"disk_ambient_scale")
	if desaturate is float:
		material.set_shader_parameter(&"diffuse_desaturate", desaturate)
	if ambient is float:
		material.set_shader_parameter(&"ambient_ao", float(ambient) * tuning.cover_ambient_factor)


## Makes `owner`'s snow colliders exactly `hulls` (one convex shape each,
## reusing existing shapes). Returns the collider count.
static func apply_colliders(owner: Node, hulls: Array[PackedVector3Array], margin: float = DEFAULT_MARGIN_M) -> int:
	var existing: Array[CollisionShape3D] = lump_colliders(owner)
	for index: int in range(hulls.size()):
		if index < existing.size():
			var shape: ConvexPolygonShape3D = existing[index].shape as ConvexPolygonShape3D
			if shape.points != hulls[index]:
				shape.points = hulls[index]
			continue
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.name = "SnowLump%d" % index
		collision.set_meta(LUMP_META, true)
		var convex: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
		convex.margin = margin
		convex.points = hulls[index]
		collision.shape = convex
		owner.add_child(collision)
	for index: int in range(hulls.size(), existing.size()):
		owner.remove_child(existing[index])
		existing[index].free()
	return hulls.size()


## The static body of disc region `region`, created on demand.
static func disc_region_body(field: Node3D, region: int, create: bool) -> StaticBody3D:
	var body_name: StringName = disc_body_name(region)
	var body: StaticBody3D = field.get_node_or_null(NodePath(String(body_name))) as StaticBody3D
	if body == null and create:
		body = StaticBody3D.new()
		body.name = body_name
		field.add_child(body)
	return body


static func remove_node(parent: Node, node_name: StringName) -> void:
	if not is_instance_valid(parent):
		return
	var node: Node = parent.get_node_or_null(NodePath(String(node_name)))
	if node != null:
		parent.remove_child(node)
		node.free()


# --- Clearing and queries ---------------------------------------------------------------

static func clear_block(block: Node3D) -> void:
	if not is_instance_valid(block):
		return
	var empty: Array[PackedVector3Array] = []
	remove_node(block, CAP_NAME)
	apply_colliders(block, empty)


## Removes every disc drift mesh/body and the disc cover.
static func clear_disc(field: Node3D) -> void:
	if not is_instance_valid(field):
		return
	for child: Node in field.get_children():
		var child_name: String = String(child.name)
		if child_name.begins_with(DISC_CAP_PREFIX) or child_name.begins_with(DISC_BODY_PREFIX) or child.name == DISC_COVER_NAME or child.name == DISC_COVER_FADING_NAME:
			field.remove_child(child)
			child.free()


## The snow colliders currently on `owner` (in order).
static func lump_colliders(owner: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	if not is_instance_valid(owner):
		return out
	for child: Node in owner.get_children():
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision != null and collision.has_meta(LUMP_META):
			out.append(collision)
	return out


static func disc_bodies(field: Node) -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	if not is_instance_valid(field):
		return out
	for child: Node in field.get_children():
		if child is StaticBody3D and String(child.name).begins_with(DISC_BODY_PREFIX):
			out.append(child as StaticBody3D)
	return out


static func disc_collider_count(field: Node) -> int:
	var total: int = 0
	for body: StaticBody3D in disc_bodies(field):
		total += lump_colliders(body).size()
	return total


## Every disc drift mesh instance under `field`.
static func disc_cap_meshes(field: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if not is_instance_valid(field):
		return out
	for child: Node in field.get_children():
		if String(child.name).begins_with(DISC_CAP_PREFIX):
			var instance: MeshInstance3D = cap_mesh(field, child.name)
			if instance != null:
				out.append(instance)
	return out


## The snow mesh under `holder` (a block or the field), or null.
static func cap_mesh(holder: Node, cap_name: StringName) -> MeshInstance3D:
	if not is_instance_valid(holder):
		return null
	var cap: Node = holder.get_node_or_null(NodePath(String(cap_name)))
	if cap == null:
		return null
	return cap.get_node_or_null(NodePath(String(CAP_MESH_NAME))) as MeshInstance3D


## Sets the visual disc cover to `level`. Visual only. Level 0 melts it away:
## the cover fades out (SnowTuning.cover_ease_s per level) and frees itself;
## a new level before then revives it.
static func set_disc_cover(field: Field, seed_value: int, level: int, tuning: SnowTuning, blocks_source: Callable = Callable()) -> void:
	if not is_instance_valid(field):
		return
	var cover: SnowDiscCover = field.get_node_or_null(NodePath(String(DISC_COVER_NAME))) as SnowDiscCover
	var fading: SnowDiscCover = field.get_node_or_null(NodePath(String(DISC_COVER_FADING_NAME))) as SnowDiscCover
	if level <= 0:
		if cover != null:
			cover.set_level(0)
			if cover.is_faded_out():
				field.remove_child(cover)
				cover.free()
			else:
				cover.set_retiring(true)
				cover.name = DISC_COVER_FADING_NAME
		return
	if cover == null and fading != null:
		fading.name = DISC_COVER_NAME
		fading.set_retiring(false)
		cover = fading
	if cover == null:
		cover = SnowDiscCover.new()
		cover.name = DISC_COVER_NAME
		cover.configure(field, seed_value, tuning)
		field.add_child(cover)
	if blocks_source.is_valid():
		cover.set_blocks_source(blocks_source)
	cover.set_level(level)


## The live cover (null when none, or when it is only fading out).
static func disc_cover(field: Node) -> SnowDiscCover:
	if not is_instance_valid(field):
		return null
	return field.get_node_or_null(NodePath(String(DISC_COVER_NAME))) as SnowDiscCover


## The cover that is melting away after its level hit 0 (null when none).
static func fading_disc_cover(field: Node) -> SnowDiscCover:
	if not is_instance_valid(field):
		return null
	return field.get_node_or_null(NodePath(String(DISC_COVER_FADING_NAME))) as SnowDiscCover
