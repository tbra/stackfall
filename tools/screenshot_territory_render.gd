extends Node
## Windowed screenshot harness for Bontago-cmc.5 (smooth, circle-derived
## territory rendering). Not part of the running game (CLAUDE.md). Run:
##   godot --path . --scene res://tools/screenshot_territory_render.gd
##
## Builds an 8-player sandbox match on the small map (tightest home-flag
## packing, so two adjacent players' circles meet with the fewest
## placements) and walks slots 0 and 1 toward each other with the same
## "half the reach per step" pattern tools/screenshot_main.gd already uses,
## until their circles overlap into a contested band and (TerritoryTuning.
## hole_delay later) a temporary hole. Saves:
##   user://territory_wide.png         the whole disk: every player's smooth
##                                      circle-derived border + rim, the
##                                      contested band, the hole, and the
##                                      central goal disc.
##   user://territory_zoom.png         a closer shot centred on the
##                                      slot 0 / slot 1 contested band.
##   user://territory_crop_nearest.png a 6x nearest-filtered crop of a clean
##                                      (uncontested) circle boundary near
##                                      slot 2's home, to compare against the
##                                      pre-cmc.5 raster crop
##                                      (implementer-O-crop-blue-nearest.png)
##                                      for an apples-to-apples smoothness
##                                      check.
##   user://territory_crop_smooth.png  the same region, bilinear-resized
##                                      instead, for a "how it actually
##                                      reads" reference alongside the
##                                      nearest crop.
##   user://territory_crop_contested.png a 6x nearest crop of the slot 0/1
##                                      contested band itself (the rim, the
##                                      shimmer and the hole up close).

const OUTPUT_WIDE: String = "user://territory_wide.png"
const OUTPUT_ZOOM: String = "user://territory_zoom.png"
const OUTPUT_CROP_NEAREST: String = "user://territory_crop_nearest.png"
const OUTPUT_CROP_SMOOTH: String = "user://territory_crop_smooth.png"
const OUTPUT_CROP_CONTESTED: String = "user://territory_crop_contested.png"

const PLAYER_COUNT: int = 8
## One step past the minimum (see the class doc's math): slot 0 and slot 1's
## home circles alone (radius 6, home-flag chord ~19.5 m apart on the small
## map) don't touch, so each walks a couple of single-cube steps toward the
## other, half the new circle's own reach per step so every intermediate
## point stays inside the territory the previous step just claimed.
const TOWER_STEPS: int = 4
const SETTLE_FRAMES: int = 45
## >= TerritoryTuning.hole_delay (0.75 s) at 60 Hz, plus margin so the
## contested band has actually opened into a hole, not just started timing.
const HOLE_WAIT_FRAMES: int = 120
const PLACE_HEIGHT: float = 0.55
const CROP_SIZE: int = 90
const CROP_SCALE: int = 6

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _small_map: MapDef = preload("res://config/maps/round_small.tres")


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var field: Field = main.get_node("Field") as Field
	var camera_rig: CameraRig = main.get_node("CameraRig") as CameraRig
	field.map_def = _small_map
	camera_rig.map_def = _small_map
	# DECISION (tools/screenshot_territory_render.gd): Main.gd's default
	# (menu) _ready() path is still live -- this harness never passes
	# --hot-seat/--sandbox, so nothing suppresses it -- and it attaches a
	# real PlayerController once Match reaches PLAYING, which calls
	# CameraRig.set_follow_position() every frame for its own ghost (spec
	# 1.5's block-locked camera). That fought this script's own framing every
	# single frame (found by logging CameraRig._target: it snapped back
	# toward the live ghost within one wait() call). Duplicating the tuning
	# resource (never mutating the shared .tres) and turning follow_block off
	# restores the legacy free-orbit mode, where only an explicit call moves
	# _target -- a screenshot-harness-only choice with no gameplay effect.
	camera_rig.tuning = camera_rig.tuning.duplicate() as CameraTuning
	camera_rig.tuning.follow_block = false
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = PLAYER_COUNT
	config.hot_seat = false
	config.ai_count = 0
	config.sandbox = true
	config.map_size = MapDef.MapSize.SMALL
	config.rng_seed = 4242

	Match.register_world(field, main.get_node("BlockRegistry"), main.get_node("BlocksContainer"))
	Match.start_match(config)
	field.place_flags(config.player_count, config.player_colors, config.goal_flag_count)
	field.set_overlay_source(Match.raster(), config.player_colors)

	await _wait(int(3.5 * Engine.physics_ticks_per_second))
	print("SCREENSHOT state=%d" % Match.state())

	var home0: Vector2 = Match.slot(0).home_position
	var home1: Vector2 = Match.slot(1).home_position
	var dir0: Vector2 = (home1 - home0).normalized()
	var dir1: Vector2 = -dir0
	var reach: float = _tuning.influence_base + _tuning.influence_k * _physics.cube_size

	for step: int in range(TOWER_STEPS):
		var distance: float = _tuning.home_radius - _physics.cube_size + float(step) * reach * 0.5
		_place(field, 0, home0 + dir0 * distance)
		_place(field, 1, home1 + dir1 * distance)
		await _wait(SETTLE_FRAMES)

	await _wait(HOLE_WAIT_FRAMES)

	camera_rig.set_follow_position(Vector3.ZERO)
	camera_rig._target = Vector3.ZERO
	camera_rig._distance = _small_map.field_radius * 1.6
	camera_rig._update_transform()
	await _wait(30)
	await RenderingServer.frame_post_draw
	var wide: Image = get_viewport().get_texture().get_image()
	wide.save_png(OUTPUT_WIDE)
	print("SCREENSHOT wide saved=%s size=%dx%d overlay_circles=%d" % [
		ProjectSettings.globalize_path(OUTPUT_WIDE), wide.get_width(), wide.get_height(),
		field.overlay().circle_count()
	])

	# A clean (uncontested) circle boundary near slot 2's home, straight out
	# from the flag at the home circle's own rim, cropped and blown up 6x
	# nearest -- the same comparison implementer-O's package C screenshots
	# made against the raster route.
	var camera: Camera3D = camera_rig.get_camera()
	var home2: Vector2 = Match.slot(2).home_position
	# The *inward* rim (toward the disk centre, not the outward/off-disk
	# side) so the crop target reliably projects well inside the viewport
	# regardless of which direction the player's home happens to face on
	# screen.
	var edge_disk: Vector2 = home2 - home2.normalized() * _tuning.home_radius
	var edge_world: Vector3 = field.world_from_disk_local(edge_disk, 0.0)
	var screen_pos: Vector2 = camera.unproject_position(edge_world)
	var max_x: int = maxi(wide.get_width() - CROP_SIZE, 0)
	var max_y: int = maxi(wide.get_height() - CROP_SIZE, 0)
	var rect_x: int = clampi(int(screen_pos.x) - CROP_SIZE / 2, 0, max_x)
	var rect_y: int = clampi(int(screen_pos.y) - CROP_SIZE / 2, 0, max_y)
	var crop_rect: Rect2i = Rect2i(rect_x, rect_y, CROP_SIZE, CROP_SIZE).intersection(
		Rect2i(Vector2i.ZERO, wide.get_size())
	)
	var crop_nearest: Image = wide.get_region(crop_rect)
	crop_nearest.resize(
		crop_nearest.get_width() * CROP_SCALE, crop_nearest.get_height() * CROP_SCALE, Image.INTERPOLATE_NEAREST
	)
	crop_nearest.save_png(OUTPUT_CROP_NEAREST)
	var crop_smooth: Image = wide.get_region(crop_rect)
	crop_smooth.resize(
		crop_smooth.get_width() * CROP_SCALE, crop_smooth.get_height() * CROP_SCALE, Image.INTERPOLATE_CUBIC
	)
	crop_smooth.save_png(OUTPUT_CROP_SMOOTH)
	print("SCREENSHOT crop rect=%s saved=%s and %s" % [crop_rect, OUTPUT_CROP_NEAREST, OUTPUT_CROP_SMOOTH])

	# Zoomed shot: the midpoint between slot 0 and slot 1's frontiers, close
	# enough to read the curve, the rim, the contested shimmer and the hole.
	var midpoint_world: Vector3 = field.world_from_disk_local((home0 + home1) * 0.5, 0.0)
	camera_rig.set_follow_position(midpoint_world)
	camera_rig._target = midpoint_world
	camera_rig._distance = 14.0
	camera_rig._update_transform()
	await _wait(30)
	await RenderingServer.frame_post_draw
	var zoom: Image = get_viewport().get_texture().get_image()
	zoom.save_png(OUTPUT_ZOOM)
	print("SCREENSHOT zoom saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(OUTPUT_ZOOM), zoom.get_width(), zoom.get_height()
	])

	# The contested band itself (slot 0/1's shared boundary): the zoom
	# camera is already centred on it, so crop straight out of that frame.
	var mid_x: int = zoom.get_width() / 2
	var mid_y: int = zoom.get_height() / 2
	var contested_rect: Rect2i = Rect2i(mid_x - 60, mid_y - 60, 120, 120).intersection(
		Rect2i(Vector2i.ZERO, zoom.get_size())
	)
	var contested_crop: Image = zoom.get_region(contested_rect)
	contested_crop.resize(
		contested_crop.get_width() * CROP_SCALE, contested_crop.get_height() * CROP_SCALE, Image.INTERPOLATE_NEAREST
	)
	contested_crop.save_png(OUTPUT_CROP_CONTESTED)
	print("SCREENSHOT contested crop saved=%s" % OUTPUT_CROP_CONTESTED)

	get_tree().quit()


func _place(field: Field, slot_id: int, disk_pos: Vector2) -> void:
	var spot: Vector3 = field.world_from_disk_local(disk_pos, PLACE_HEIGHT)
	Match._held_shapes[slot_id] = _cube
	Match.request_place(slot_id, spot, 0, Quaternion.IDENTITY, false)


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
