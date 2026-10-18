class_name PaintballSling
extends Node3D
## Paintball activation visual. The thrown body shows only the loaded glob; the slingshot is a
## separate, purely visual copy left at the launch point that plays the release clip (band snaps
## forward), holds briefly, then shrinks and fades out. Every peer builds it from the replicated
## gift spawn (GiftFxPresenter.on_gift_block_spawned), so there is no RPC and no physics.
##
## Built by GiftFxPresenter.spawn_paintball_sling; this file uses engine types only so it stays out
## of the autoload layer cycle.
## Smallest playback speed treated as non-zero.
const MIN_SPEED: float = 0.0001

var _age: float = 0.0
var _release_s: float = 0.0
var _hold_s: float = 0.0
var _fade_s: float = 0.0
var _meshes: Array[MeshInstance3D] = []


## Pure: fade progress 0..1 `age_s` after the launch. 0 through the release and hold, then
## rises linearly to 1 over `fade_s`; 1 at once when `fade_s` is not positive and the hold is over.
static func fade_progress(age_s: float, release_s: float, hold_s: float, fade_s: float) -> float:
	var fade_start: float = maxf(release_s, 0.0) + maxf(hold_s, 0.0)
	if age_s < fade_start:
		return 0.0
	if fade_s <= 0.0:
		return 1.0
	return clampf((age_s - fade_start) / fade_s, 0.0, 1.0)


## Hides every mesh of `visual` that is not part of the glob node (`glob_name`). Returns whether
## the glob node exists; when it does not the visual is left untouched (no separable blob).
static func strip_to_glob(visual: Node, glob_name: StringName) -> bool:
	var glob: Node = visual.find_child(String(glob_name), true, false)
	if glob == null:
		return false
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visible = glob.is_ancestor_of(mesh)
	return true


## Hides the glob node's meshes' opposite: the slingshot copy shows everything except the glob.
static func hide_glob(visual: Node, glob_name: StringName) -> void:
	var glob: Node = visual.find_child(String(glob_name), true, false)
	if glob == null:
		return
	for mesh: Node in glob.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).visible = false


## Starts the release clip on `visual` (the slingshot copy, already a child) and the hold/fade timers.
func begin(visual: Node3D, clip_name: StringName, speed_scale: float, hold_s: float, fade_s: float) -> void:
	_hold_s = hold_s
	_fade_s = fade_s
	for mesh: Node in visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mesh as MeshInstance3D)
	var players: Array[Node] = visual.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var player: AnimationPlayer = players[0] as AnimationPlayer
		if player.has_animation(clip_name):
			var clip: Animation = player.get_animation(clip_name)
			clip.loop_mode = Animation.LOOP_NONE
			player.speed_scale = speed_scale
			player.play(clip_name)
			_release_s = clip.length / maxf(speed_scale, MIN_SPEED)


func _process(delta: float) -> void:
	_age += delta
	var progress: float = fade_progress(_age, _release_s, _hold_s, _fade_s)
	if progress >= 1.0:
		queue_free()
		return
	scale = Vector3.ONE * (1.0 - progress)
	for mesh: MeshInstance3D in _meshes:
		mesh.transparency = progress
