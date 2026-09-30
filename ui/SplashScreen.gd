class_name SplashScreen
extends CanvasLayer
## Bontago-59o.1: in-engine SlopShop splash shown right after the engine boot
## splash (which cannot play audio). Displays the same image on the same
## background colour (no flash), plays the studio jingle at the saved
## master/music volume and emits `finished` when the jingle ends or the player
## skips it (ui_accept, ui_cancel -- keyboard and gamepad -- or a mouse click).
## Game/Main.gd shows the main menu on `finished`.

signal finished

const IMAGE_PATH: String = "res://assets/ui/slopshop_splash.png"
const JINGLE_PATH: String = "res://assets/ui/slopshop_jingle.mp3"
const SETTING_BG_COLOR: String = "application/boot_splash/bg_color"
## The layer sits above every menu/overlay Main can create.
const SPLASH_LAYER: int = 128

var _player: AudioStreamPlayer
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
	var image: TextureRect = TextureRect.new()
	image.texture = load(IMAGE_PATH) as Texture2D
	image.set_anchors_preset(Control.PRESET_FULL_RECT)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)

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
