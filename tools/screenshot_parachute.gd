extends Node
## Bontago-mp0.139: off-screen evidence for the procedural gift parachute. One
## real sandbox match, one real crate (MatchGifts._spawn_crate_at), three
## captures: the canopy inflating just after the drop starts, the open canopy
## mid-descent, and the canopy collapsing just after landing. Derived from
## screenshot_volcano_model.gd. Windowed run, quits after saving:
##
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path <checkout> res://tools/screenshot_parachute.tscn -- --agent-probe

const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_TICKS: int = 90
const SPAWN_POINT: Vector2 = Vector2(0.0, 6.0)
## Frames (physics ticks) after the spawn at which the inflating shot is taken.
const DEPLOY_SHOT_TICKS: int = 18
## Seconds of descent fast-forwarded before the mid-air shot.
const DESCENT_SKIP_S: float = 3.0
const MID_AIR_SETTLE_TICKS: int = 75
## Seconds fast-forwarded to just before landing, then the collapse shot delay.
const LANDING_MARGIN_S: float = 0.05
const COLLAPSE_SHOT_TICKS: int = 40
const CAMERA_DISTANCE_M: float = 7.0
const CAMERA_LIFT_M: float = 1.4
const CAMERA_FOV: float = 55.0
## Aim point above the riser: halfway between the crate and the canopy top.
const LOOK_ABOVE_RISER_M: float = 0.4
const CAMERA_AZIMUTH: Vector3 = Vector3(0.55, 0.0, 0.83)


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(SETTLE_TICKS)

	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._spawn_crate_at(SPAWN_POINT)
	var crate: GiftCrate = Match._gifts._crates[gift_id]["node"] as GiftCrate
	await _wait(DEPLOY_SHOT_TICKS)
	await _shoot(crate, "parachute_1_deploying.png")

	Match._gifts.tick_host(DESCENT_SKIP_S)
	await _wait(MID_AIR_SETTLE_TICKS)
	await _shoot(crate, "parachute_2_descending.png")

	var config: GiftConfig = Match._gifts._gift_config
	var remaining_s: float = config.drop_height_m / config.fall_speed_m_s - float(Match._gifts.gift_state(gift_id)["elapsed"])
	Match._gifts.tick_host(maxf(remaining_s - LANDING_MARGIN_S, 0.0))
	Match._gifts.tick_host(LANDING_MARGIN_S * 2.0)
	await _wait(COLLAPSE_SHOT_TICKS)
	await _shoot(crate, "parachute_3_collapsing.png")
	get_tree().quit()


func _shoot(crate: GiftCrate, file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	# A crate claimed on landing is freed; its canopy lives on in the container.
	var chute: GiftParachute = crate.parachute() if is_instance_valid(crate) 		else Match._gifts._container.get_node_or_null("Parachute") as GiftParachute
	var focus: Vector3 = chute.global_position + Vector3(0.0, LOOK_ABOVE_RISER_M, 0.0)
	var image: Image = await _render_large_shot(focus)
	var path: String = OUTPUT_DIR + file_name
	ContactSheet.save_capture(image, path)
	print("SCREENSHOT parachute saved=%s size=%s phase=%s" % [
		ProjectSettings.globalize_path(path), image.get_size(), ParachuteAnim.Phase.keys()[chute.phase()]])


## A fresh Camera3D in a SubViewport that shares the live World3D, so the
## capture is CAPTURE_SIZE regardless of the OS-clamped probe window.
func _render_large_shot(focus: Vector3) -> Image:
	var source: Camera3D = get_viewport().get_camera_3d()
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = source.near
	camera.far = source.far
	camera.environment = source.environment
	sub.add_child(camera)
	add_child(sub)
	camera.look_at_from_position(focus + CAMERA_AZIMUTH.normalized() * CAMERA_DISTANCE_M + Vector3(0.0, CAMERA_LIFT_M, 0.0), focus)
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	return image


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
