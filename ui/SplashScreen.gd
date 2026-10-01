class_name SplashScreen
extends CanvasLayer
## In-engine SlopShop intro. The engine shows the matching empty background
## during loading; then four blocks land on successive jingle beats, the
## wordmark slams in, and the complete mark keeps punching with later beats.
## Keyboard, gamepad, and mouse can skip at any time.

signal finished

const IMAGE_PATH: String = "res://assets/ui/slopshop_intro_bg.png"
const PIECES_PATH: String = "res://assets/ui/slopshop_intro_pieces.png"
const WORDMARK_PATH: String = "res://assets/ui/slopshop_intro_wordmark.png"
const JINGLE_PATH: String = "res://assets/ui/slopshop_jingle.mp3"
const SETTING_BG_COLOR: String = "application/boot_splash/bg_color"
const SPLASH_LAYER: int = 128
const DESIGN_SIZE: Vector2 = Vector2(1280.0, 720.0)
const BLOCK_SCALE: float = 0.45
const WORDMARK_SCALE: float = 0.34
const DROP_SECONDS: float = 0.46
const WORDMARK_DROP_SECONDS: float = 0.48
## The 8.81-second owner jingle has a regular pulse and a stronger middle.
## Contacts land on audible accents; the last five hits keep the mark alive.
const BLOCK_CONTACTS: Array[float] = [0.78, 1.58, 2.38, 3.18]
const WORDMARK_CONTACT: float = 3.70
const LATE_BEATS: Array[float] = [4.62, 5.42, 6.22, 7.02, 7.82]
const BLOCK_POSITIONS: Array[Vector2] = [
	Vector2(632.0, 424.0), Vector2(626.0, 335.0),
	Vector2(638.0, 263.0), Vector2(663.0, 181.0),
]
## The generated sheet has four isolated alpha islands with unequal widths.
## Cropping at quarter boundaries picks up a sliver of the preceding piece.
const BLOCK_REGIONS: Array[Rect2] = [
	Rect2(55.0, 0.0, 420.0, 724.0), Rect2(585.0, 0.0, 550.0, 724.0),
	Rect2(1200.0, 0.0, 412.0, 724.0), Rect2(1725.0, 0.0, 406.0, 724.0),
]
const BLOCK_COLORS: Array[Color] = [
	Color("#4ea7ff"), Color("#ffd05e"),
	Color("#69dfb5"), Color("#ff806b"),
]

var _player: AudioStreamPlayer
var _stage: Node2D
var _blocks: Array[Sprite2D] = []
var _wordmark: Sprite2D
var _flash: ColorRect
var _flash_tween: Tween
var _done: bool = false


static func should_show(headless: bool, user_args: PackedStringArray) -> bool:
	return not headless and user_args.is_empty()


static func should_show_now() -> bool:
	return should_show(DisplayServer.get_name() == "headless", OS.get_cmdline_user_args())


func _ready() -> void:
	layer = SPLASH_LAYER
	var background: ColorRect = ColorRect.new()
	background.color = ProjectSettings.get_setting(SETTING_BG_COLOR, Color.BLACK) as Color
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var plate: TextureRect = TextureRect.new()
	plate.texture = load(IMAGE_PATH) as Texture2D
	plate.set_anchors_preset(Control.PRESET_FULL_RECT)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	_stage = Node2D.new()
	add_child(_stage)
	_layout_stage()
	get_viewport().size_changed.connect(_layout_stage)
	_create_logo_layers()
	_flash = ColorRect.new()
	_flash.color = Color.WHITE
	_flash.modulate.a = 0.0
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)

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
	_schedule_sequence()


func _layout_stage() -> void:
	if _stage == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var factor: float = minf(viewport_size.x / DESIGN_SIZE.x, viewport_size.y / DESIGN_SIZE.y)
	_stage.scale = Vector2.ONE * factor
	_stage.position = (viewport_size - DESIGN_SIZE * factor) * 0.5


func _create_logo_layers() -> void:
	var sheet: Texture2D = load(PIECES_PATH) as Texture2D
	for index in range(4):
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = BLOCK_REGIONS[index]
		var block: Sprite2D = Sprite2D.new()
		block.texture = atlas
		block.position = BLOCK_POSITIONS[index]
		block.scale = Vector2.ONE * BLOCK_SCALE
		block.visible = false
		_stage.add_child(block)
		_blocks.append(block)
	_wordmark = Sprite2D.new()
	_wordmark.texture = load(WORDMARK_PATH) as Texture2D
	_wordmark.position = Vector2(640.0, 548.0)
	_wordmark.scale = Vector2.ONE * WORDMARK_SCALE
	_wordmark.visible = false
	_stage.add_child(_wordmark)


func _schedule_sequence() -> void:
	for index in range(BLOCK_CONTACTS.size()):
		_schedule_at(BLOCK_CONTACTS[index] - DROP_SECONDS, _drop_block.bind(index))
	_schedule_at(WORDMARK_CONTACT - WORDMARK_DROP_SECONDS, _slam_wordmark)
	for index in range(LATE_BEATS.size()):
		_schedule_at(LATE_BEATS[index], _pulse_logo.bind(index))


func _schedule_at(seconds: float, action: Callable) -> void:
	var trigger: Tween = create_tween()
	trigger.tween_interval(seconds)
	trigger.tween_callback(action)


func _drop_block(index: int) -> void:
	if _done:
		return
	var block: Sprite2D = _blocks[index]
	var destination: Vector2 = BLOCK_POSITIONS[index]
	block.position = destination + Vector2(-65.0 if index % 2 == 0 else 65.0, -475.0)
	block.rotation = deg_to_rad(-16.0 if index % 2 == 0 else 16.0)
	block.scale = Vector2.ONE * BLOCK_SCALE * 0.9
	block.visible = true
	var drop: Tween = create_tween().set_parallel(true)
	drop.tween_property(block, "position", destination, DROP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(block, "rotation", 0.0, DROP_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(block, "scale", Vector2.ONE * BLOCK_SCALE, DROP_SECONDS)
	drop.finished.connect(_block_impact.bind(index))


func _block_impact(index: int) -> void:
	if _done:
		return
	var block: Sprite2D = _blocks[index]
	var destination: Vector2 = BLOCK_POSITIONS[index]
	block.scale = Vector2(BLOCK_SCALE * 1.16, BLOCK_SCALE * 0.78)
	var rebound: Tween = create_tween().set_parallel(true)
	rebound.tween_property(block, "position", destination + Vector2(0.0, -24.0), 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	rebound.tween_property(block, "scale", Vector2(BLOCK_SCALE * 0.92, BLOCK_SCALE * 1.08), 0.13)
	rebound.chain().tween_property(block, "position", destination, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	rebound.parallel().tween_property(block, "scale", Vector2.ONE * BLOCK_SCALE, 0.18)
	_impact(destination + Vector2(0.0, 35.0), BLOCK_COLORS[index], 0.25, 10)


func _slam_wordmark() -> void:
	if _done:
		return
	var destination: Vector2 = Vector2(640.0, 548.0)
	_wordmark.position = destination + Vector2(0.0, 215.0)
	_wordmark.scale = Vector2(WORDMARK_SCALE * 1.3, WORDMARK_SCALE * 0.65)
	_wordmark.modulate.a = 0.0
	_wordmark.visible = true
	var slam: Tween = create_tween().set_parallel(true)
	slam.tween_property(_wordmark, "position", destination, WORDMARK_DROP_SECONDS).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	slam.tween_property(_wordmark, "scale", Vector2(WORDMARK_SCALE * 1.06, WORDMARK_SCALE * 0.88), WORDMARK_DROP_SECONDS)
	slam.tween_property(_wordmark, "modulate:a", 1.0, 0.12)
	slam.finished.connect(_wordmark_impact)


func _wordmark_impact() -> void:
	if _done:
		return
	var settle: Tween = create_tween()
	settle.tween_property(_wordmark, "scale", Vector2(WORDMARK_SCALE * 0.96, WORDMARK_SCALE * 1.08), 0.15)
	settle.tween_property(_wordmark, "scale", Vector2.ONE * WORDMARK_SCALE, 0.17)
	_impact(Vector2(640.0, 530.0), Color("#fff0bb"), 0.45, 24)


func _pulse_logo(beat_index: int) -> void:
	if _done or not _wordmark.visible:
		return
	var pulse: Tween = create_tween()
	pulse.tween_property(_wordmark, "scale", Vector2.ONE * WORDMARK_SCALE * 1.10, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.tween_property(_wordmark, "scale", Vector2.ONE * WORDMARK_SCALE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for index in range(_blocks.size()):
		var block: Sprite2D = _blocks[index]
		var kick: Tween = create_tween().set_parallel(true)
		kick.tween_property(block, "position", BLOCK_POSITIONS[index] + Vector2(0.0, -14.0), 0.12)
		kick.tween_property(block, "rotation", deg_to_rad(5.0 if (index + beat_index) % 2 == 0 else -5.0), 0.12)
		kick.chain().tween_property(block, "position", BLOCK_POSITIONS[index], 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		kick.parallel().tween_property(block, "rotation", 0.0, 0.22)
	_impact(Vector2(640.0, 330.0), BLOCK_COLORS[beat_index % 4], 0.12, 8)


func _impact(center: Vector2, color: Color, flash_alpha: float, shard_count: int) -> void:
	_flash.color = color
	_flash.modulate.a = flash_alpha
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.23)
	var ring: Line2D = Line2D.new()
	ring.width = 4.0
	ring.default_color = color
	for point_index in range(33):
		var angle: float = TAU * float(point_index) / 32.0
		ring.add_point(Vector2.from_angle(angle) * 38.0)
	ring.position = center
	ring.scale = Vector2.ONE * 0.2
	_stage.add_child(ring)
	var ring_tween: Tween = create_tween().set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector2.ONE * 2.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring, "modulate:a", 0.0, 0.42)
	ring_tween.finished.connect(ring.queue_free)
	for index in range(shard_count):
		var shard: Polygon2D = Polygon2D.new()
		shard.polygon = PackedVector2Array([Vector2(-6.0, -3.0), Vector2(8.0, 0.0), Vector2(-6.0, 3.0)])
		shard.color = color
		var angle: float = TAU * float(index) / float(shard_count) + float(index % 3) * 0.09
		shard.position = center
		shard.rotation = angle
		_stage.add_child(shard)
		var distance: float = 65.0 + float(index % 4) * 18.0
		var fly: Tween = create_tween().set_parallel(true)
		fly.tween_property(shard, "position", center + Vector2.from_angle(angle) * distance, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		fly.tween_property(shard, "modulate:a", 0.0, 0.45)
		fly.tween_property(shard, "rotation", angle + 2.0, 0.45)
		fly.finished.connect(shard.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if _is_skip_event(event):
		get_viewport().set_input_as_handled()
		finish()


static func _is_skip_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
		return true
	var click: InputEventMouseButton = event as InputEventMouseButton
	return click != null and click.pressed


func finish() -> void:
	if _done:
		return
	_done = true
	if _player != null:
		_player.stop()
	finished.emit()
	queue_free()
