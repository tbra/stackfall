extends Node
## The one reusable off-screen capture tool: renders a shot list into the AgentProbe SubViewport at each
## requested size, saves PNGs, prints one SHOT_SAVED / SHOT_FAILED line per shot and (optionally) a labelled,
## paginated contact sheet per size. Targets and setup keys: tools/shot_targets.gd.
##
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path <checkout> res://tools/shot.tscn -- --agent-probe --out=<dir> \
##     --render-size=1280x720,1920x1080 [--sheet] \
##     (--target=lobby --kind=hosted --seats=8 --style=cards | --shots=<json file or inline json>)
##
## Examples (flags describe one shot; --shots=<file> lists many, the flags being their defaults):
##   --target=main_menu                          --target=options --tab=audio
##   --target=sandbox --overlays=f4 --f4-tab=physics --sky=cycle --time=0.5 --cam=30,-35,40
##   --target=match --watch --bots=4 --mode=ctf --follow=1 --frames=600 --speed=4 --hud=0
##   --shots=shots.json --sheet   (a JSON array of objects with the same keys)
## Deterministic parity captures (the sky rebuild's recipe). The ENGINE flag --fixed-fps 60 goes before
## --path, so TIME advances a fixed step per frame; --pin-sky-time=<s>[,<drift_s>] pins the sky and cloud
## clocks, --weather=<id>:<intensity> snaps the weather ceiling, --rng-seed=<n> fixes the match seed:
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy --fixed-fps 60 ##     --path <checkout> res://tools/shot.tscn -- --agent-probe --out=<dir> --render-size=1280x720 ##     --target=match --bots=0 --seats=1 --hud=0 --sky=cycle --pin-sky-time=100,50 --rng-seed=1 ##     [--weather=storm:0.5]
## Compare two captures: godot --headless -s tools/image_diff.gd -- a.png b.png ##   [--max-mean=<n> --max-over8=<n> --max-over1=<n> --diff-out=<png>]
## --sky takes cycle (the running cycle), sunset, dawn or night (the cycle locked at that sky's phase).
## Exit code 0 when every shot saved, 1 when any shot or the arguments failed. Never resizes the OS window.

const FAIL_EXIT_CODE: int = 1
const LABEL_FONT_SIZE: int = 15
const LABEL_BG: Color = Color(0.1, 0.1, 0.1, 1.0)
const LABEL_FG: Color = Color(0.92, 0.92, 0.92, 1.0)
const LABEL_PAD: Vector2 = Vector2(4.0, 2.0)
const LABEL_FRAMES: int = 2

var _out: String = ""
var _vp: SubViewport = null
var _main: Node = null
var _scene: Node = null
var _failures: int = 0
## Per size: [{name, file}] of the saved shots, for the contact sheet.
var _saved: Dictionary = {}


func _ready() -> void:
	var parsed: Dictionary = ShotTargets.parse_args(OS.get_cmdline_user_args())
	if not str(parsed["error"]).is_empty():
		_exit_failed(str(parsed["error"]))
		return
	_out = str(parsed["out"])
	DirAccess.make_dir_recursive_absolute(_out)
	var shots: Array[Dictionary] = []
	shots.assign(parsed["shots"])
	if _wants_debug(shots):
		DebugMode.set_override_for_test(true)
	for size: Vector2i in parsed["sizes"]:
		await _run_size(size, shots)
	if bool(parsed["sheet"]):
		await _build_sheets(parsed["sizes"])
	await _teardown()
	print("SHOT_DONE saved=%d failed=%d out=%s" % [_saved_count(), _failures, _out])
	Sfx.quit_tree(FAIL_EXIT_CODE if _failures > 0 else 0)


func _wants_debug(shots: Array[Dictionary]) -> bool:
	for shot: Dictionary in shots:
		if not (shot["overlays"] as PackedStringArray).is_empty() or bool(shot["watch"]) or int(shot["style"]) != 0:
			return true
	return false


func _run_size(size: Vector2i, shots: Array[Dictionary]) -> void:
	_saved[size] = []
	for shot: Dictionary in shots:
		var error: String = await _run_shot(size, shot)
		if error.is_empty():
			var file: String = ShotTargets.file_name(shot, size)
			var image: Image = _vp.get_texture().get_image()
			if image == null or image.is_empty():
				error = "empty viewport image"
			elif image.save_png(_out.path_join(file)) != OK:
				error = "could not save %s" % file
			else:
				(_saved[size] as Array).append({"name": str(shot["name"]), "file": file})
				print("SHOT_SAVED ", _out.path_join(file), " ", image.get_size())
		if not error.is_empty():
			_failures += 1
			printerr("SHOT_FAILED ", shot["name"], " ", size.x, "x", size.y, ": ", error)
		await _after_shot(shot)
	await _teardown()


## Sets up one shot and leaves the viewport rendered for the capture ("" = ready).
func _run_shot(size: Vector2i, shot: Dictionary) -> String:
	if str(shot["target"]) == ShotTargets.TARGET_SCENE:
		await _teardown()
		_vp = AgentProbe.make_viewport(self, size)
		var packed: PackedScene = load(str(shot["path"])) as PackedScene
		if packed == null:
			return "cannot load %s" % shot["path"]
		_scene = packed.instantiate()
		_vp.add_child(_scene)
		await ShotTargets.settle(self, ShotTargets.BOOT_FRAMES)
		var error: String = await ShotTargets.finish_setup(self, _vp, _scene, shot)
		await RenderingServer.frame_post_draw
		return error
	if _main == null or _vp == null or _vp.size != size:
		await _teardown()
		_vp = AgentProbe.make_viewport(self, size)
		_main = (load(ShotTargets.MAIN_SCENE) as PackedScene).instantiate()
		_vp.add_child(_main)
		await ShotTargets.settle(self, ShotTargets.BOOT_FRAMES)
		await get_tree().create_timer(ShotTargets.STARTUP_WAIT_S).timeout
	var setup_error: String = await ShotTargets.setup(self, _vp, _main, shot)
	await RenderingServer.frame_post_draw
	return setup_error


func _after_shot(shot: Dictionary) -> void:
	if _main != null and str(shot["target"]) != ShotTargets.TARGET_SCENE:
		await ShotTargets.return_to_menu(self, _main)


func _teardown() -> void:
	if _main != null:
		await ShotTargets.return_to_menu(self, _main)
		_main.queue_free()
		_main = null
	if _scene != null:
		_scene.queue_free()
		_scene = null
	if _vp != null:
		_vp.queue_free()
		_vp = null
		await get_tree().process_frame
		await get_tree().process_frame


func _saved_count() -> int:
	var total: int = 0
	for size: Variant in _saved:
		total += (_saved[size] as Array).size()
	return total


# --- contact sheets ------------------------------------------------------------------------------------

func _build_sheets(sizes: Array) -> void:
	var label_vp: SubViewport = SubViewport.new()
	var bg: ColorRect = ColorRect.new()
	bg.color = LABEL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", LABEL_FG)
	label.position = LABEL_PAD
	bg.add_child(label)
	label_vp.add_child(bg)
	label_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(label_vp)
	for size: Vector2i in sizes:
		var items: Array = _saved.get(size, [])
		if not items.is_empty():
			await _sheet_for_size(size, items, label_vp, label)
	label_vp.queue_free()


func _sheet_for_size(size: Vector2i, items: Array, label_vp: SubViewport, label: Label) -> void:
	var layout: Dictionary = ShotTargets.sheet_layout(items.size(), size)
	var columns: int = int(layout["columns"])
	var cell_w: int = int(layout["cell_w"])
	var thumb_h: int = int(layout["thumb_h"])
	var row_h: int = int(layout["row_h"])
	var per_page: int = int(layout["per_page"])
	var gap: int = ShotTargets.SHEET_GAP
	label_vp.size = Vector2i(cell_w, ShotTargets.SHEET_LABEL_HEIGHT)
	for page: int in int(layout["pages"]):
		var chunk: Array = items.slice(page * per_page, (page + 1) * per_page)
		var rows: int = ceili(float(chunk.size()) / float(columns))
		var cols: int = mini(columns, chunk.size())
		var sheet: Image = Image.create_empty(
				cols * cell_w + gap * (cols + 1), rows * row_h + gap * (rows + 1), false, Image.FORMAT_RGBA8)
		sheet.fill(LABEL_BG)
		for i: int in chunk.size():
			var item: Dictionary = chunk[i]
			var thumb: Image = Image.load_from_file(_out.path_join(str(item["file"])))
			thumb.convert(Image.FORMAT_RGBA8)
			thumb.resize(cell_w, thumb_h, Image.INTERPOLATE_LANCZOS)
			label.text = str(item["name"])
			await ShotTargets.settle(self, LABEL_FRAMES)
			await RenderingServer.frame_post_draw
			var bar: Image = label_vp.get_texture().get_image()
			bar.convert(Image.FORMAT_RGBA8)
			var origin: Vector2i = Vector2i(gap + (i % columns) * (cell_w + gap), gap + (i / columns) * (row_h + gap))
			sheet.blit_rect(bar, Rect2i(Vector2i.ZERO, bar.get_size()), origin)
			sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), origin + Vector2i(0, ShotTargets.SHEET_LABEL_HEIGHT))
		var path: String = _out.path_join("sheet_%dx%d_p%d.png" % [size.x, size.y, page + 1])
		if sheet.save_png(path) != OK:
			_failures += 1
			printerr("SHOT_FAILED sheet ", path, ": could not save")
			return
		print("SHOT_SHEET ", path, " ", sheet.get_size())


func _exit_failed(message: String) -> void:
	printerr("SHOT_FAILED ", message)
	Sfx.quit_tree(FAIL_EXIT_CODE)
