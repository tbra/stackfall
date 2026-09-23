extends GutTest
## game/DiscMirror.gd (Bontago-xtq.20, owner 2026-09-23 20:12: "the main
## light source is glaringly visible in the disc reflection") pushes
## mirror_max_luminance onto the shared TerritoryOverlay's material every
## frame, through that overlay's own public material() accessor -- not a
## dedicated push method on game/TerritoryOverlay.gd, which stays out of this
## package's file ownership (see DiscMirror.gd's own class doc). This is the
## one place that push is exercised end to end, through a real DiscMirror
## node's _process(); tests/unit/test_territory_overlay.gd separately pins
## the shader's own compiled-in default and its luminance-clamp math.

## Same shared-tiny-map trick test_field.gd already documents: a plain
## Field.new() against the full-size round_medium.tres map pays an ~11 s
## collision build for nothing here, since nothing below depends on the
## map's actual scale.
var _tiny_map: MapDef


func before_each() -> void:
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 6.0


## Builds a minimal live scene DiscMirror actually needs: a sibling Camera3D
## (camera_path) and a sibling Field (field_path), added to the tree in that
## order so both are already ready by the time the DiscMirror node itself is
## added (and runs its own _ready(), which resolves both paths and reads
## field.overlay()).
func _make_wired_mirror(visuals: TerritoryVisuals) -> Dictionary:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)

	var camera: Camera3D = Camera3D.new()
	camera.name = "Cam"
	world.add_child(camera)

	var field: Field = Field.new()
	field.name = "F"
	field.map_def = _tiny_map
	field.visuals = visuals
	world.add_child(field)

	var mirror: DiscMirror = DiscMirror.new()
	mirror.camera_path = NodePath("../Cam")
	mirror.field_path = NodePath("../F")
	mirror.visuals = visuals
	world.add_child(mirror)

	return {"mirror": mirror, "field": field, "camera": camera}


func test_process_pushes_mirror_max_luminance_onto_the_overlay_material() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.mirror_enabled = true
	visuals.mirror_max_luminance = 2.5
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror
	var field: Field = wired["field"] as Field

	mirror._process(0.016)

	assert_almost_eq(
		float(field.overlay().material().get_shader_parameter(&"mirror_max_luminance")),
		2.5, 0.0001,
		"DiscMirror._process() must push the current visuals.mirror_max_luminance every frame.",
	)


func test_process_pushes_an_updated_mirror_max_luminance_on_a_later_frame() -> void:
	# A live F4 edit (ui/TuningPanel.gd) changes visuals in place; the next
	# _process() tick must reflect it, not just the value at _ready() time.
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.mirror_enabled = true
	visuals.mirror_max_luminance = 1.0
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror
	var field: Field = wired["field"] as Field
	mirror._process(0.016)

	visuals.mirror_max_luminance = 3.75
	mirror._process(0.016)

	assert_almost_eq(
		float(field.overlay().material().get_shader_parameter(&"mirror_max_luminance")),
		3.75, 0.0001,
	)
