class_name SplashScreen
extends CanvasLayer
## Bontago-59o.1: in-engine SlopShop splash shown right after the engine boot
## splash (which cannot play audio). Displays the same image on the same
## background colour (no flash), plays the studio jingle at the saved
## master/music volume and emits `finished` when the jingle ends or the player
## skips it (ui_accept, ui_cancel -- keyboard and gamepad -- or a mouse click).
## The image pops into place, then gently rocks until the jingle ends.
## Game/Main.gd shows the main menu on `finished`.

signal finished

const IMAGE_PATH: String = "res://assets/ui/slopshop_splash.png"
const JINGLE_PATH: String = "res://assets/ui/slopshop_jingle.mp3"
const SETTING_BG_COLOR: String = "application/boot_splash/bg_color"
## The layer sits above every menu/overlay Main can create.
const SPLASH_LAYER: int = 128
const INTRO_SECONDS: float = 0.55
const SETTLE_SECONDS: float = 0.36
const IDLE_HALF_CYCLE_SECONDS: float = 1.25
const SPARKLE_FADE_SECONDS: float = 0.45

var _player: AudioStreamPlayer
var _image: TextureRect
var _entrance_tween: Tween
var _idle_tween: Tween
var _done: bool = false


## True for interactive launches only: not headless, and no `--` user args
## (--hot-seat, --sandbox, --host, --headless-host, --join, ... all skip it).
static func should_show(headless: bool, user_args: PackedStringArray) -> bool:
	return not headless and user_args.is_empty()


static func should_show_now() -> bool:
	return should_show(DisplayServer.get_name() == "headless", OS.get_cmdline_user_args())


func _ready() -> void:
	layer = SPLASH_LAYER
	var bg: ColorRect = ColorRect.new()
	bg.color = ProjectSettings.get_setting(SETTING_BG_COLOR, Color.BLACK) as Color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_image = TextureRect.new()
	_image.texture = load(IMAGE_PATH) as Texture2D
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_start_animation()
	_add_sparkles()

	var stream: AudioStream = load(JINGLE_PATH) as AudioStream
	if stream == null:
		finish.call_deferred()
		return
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = Settings.master_volume_db() + Settings.music_volume_db()
	_player.finished.connect(finish)
	add_child(_player)
	_player.play()


func _start_animation() -> void:
	# The pivot is the viewport centre so the baked artwork, including its
	# lettering, bounces as one studio mark rather than sliding off screen.
	_image.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	_image.modulate.a = 0.0
	_image.scale = Vector2(0.84, 0.84)
	_image.rotation = deg_to_rad(-3.0)
	_entrance_tween = create_tween().set_parallel(true)
	_entrance_tween.tween_property(_image, "modulate:a", 1.0, INTRO_SECONDS * 0.7)
	_entrance_tween.tween_property(_image, "scale", Vector2(1.045, 1.045), INTRO_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_entrance_tween.tween_property(_image, "rotation", deg_to_rad(1.5), INTRO_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entrance_tween.chain().tween_property(_image, "scale", Vector2.ONE, SETTLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_entrance_tween.parallel().tween_property(_image, "rotation", 0.0, SETTLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_entrance_tween.finished.connect(_start_idle_motion)


func _start_idle_motion() -> void:
	if _done:
		return
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_image, "scale", Vector2(1.025, 1.025), IDLE_HALF_CYCLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_image, "rotation", deg_to_rad(-1.2), IDLE_HALF_CYCLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.chain().tween_property(_image, "scale", Vector2.ONE, IDLE_HALF_CYCLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.parallel().tween_property(_image, "rotation", deg_to_rad(1.2), IDLE_HALF_CYCLE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _add_sparkles() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var positions: Array[Vector2] = [
		Vector2(0.34, 0.21), Vector2(0.64, 0.18), Vector2(0.31, 0.39),
		Vector2(0.69, 0.42), Vector2(0.40, 0.57), Vector2(0.61, 0.56),
	]
	var colors: Array[Color] = [
		Color("#7ecbff"), Color("#ffe27a"), Color("#ff977f"),
		Color("#79e9bb"), Color("#ffe27a"), Color("#7ecbff"),
	]
	for index in range(positions.size()):
		var sparkle: ColorRect = ColorRect.new()
		sparkle.color = colors[index]
		sparkle.size = Vector2(9.0, 9.0)
		sparkle.position = positions[index] * viewport_size
		sparkle.pivot_offset = sparkle.size * 0.5
		sparkle.rotation = PI * 0.25
		sparkle.modulate.a = 0.0
		sparkle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(sparkle)
		var origin: Vector2 = sparkle.position
		var twinkle: Tween = create_tween().set_loops()
		twinkle.tween_interval(0.32 + float(index) * 0.28)
		twinkle.tween_property(sparkle, "modulate:a", 0.8, SPARKLE_FADE_SECONDS)
		twinkle.parallel().tween_property(sparkle, "position", origin + Vector2(0.0, -12.0), SPARKLE_FADE_SECONDS * 2.0)
		twinkle.tween_property(sparkle, "modulate:a", 0.0, SPARKLE_FADE_SECONDS)
		twinkle.tween_property(sparkle, "position", origin, 0.01)


func _unhandled_input(event: InputEvent) -> void:
	if _is_skip_event(event):
		get_viewport().set_input_as_handled()
		finish()


static func _is_skip_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
		return true
	var click: InputEventMouseButton = event as InputEventMouseButton
	return click != null and click.pressed


## Idempotent: emits `finished` once, then frees the overlay.
func finish() -> void:
	if _done:
		return
	_done = true
	if _player != null:
		_player.stop()
	finished.emit()
	queue_free()
