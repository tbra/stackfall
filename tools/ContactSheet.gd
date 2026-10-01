class_name ContactSheet
extends RefCounted
## Screenshot contact sheet: judging visuals takes one small image instead of
## several large ones (Bontago-fca.8). Static helpers only.
## Opt-in hook for tools/screenshot_*.gd: replace `image.save_png(path)` with
## `ContactSheet.save_capture(image, path)`. In probe mode (AgentProbe) every
## capture also refreshes <run>_sheet.png next to the captures; otherwise it is
## a plain save. Cells are unlabelled here (Image has no text drawing); the
## sheet is row-major in capture order and the names are printed. The Python
## tools/contact_sheet.py makes labelled sheets from existing PNGs.

const MAX_SHEET_WIDTH: int = 1280
const MAX_COLUMNS: int = 3
const GAP: int = 4
const BACKGROUND: Color = Color(0.1, 0.1, 0.1, 1.0)
const SHEET_SUFFIX: String = "_sheet.png"
const FALLBACK_NAME: String = "capture"

static var _thumbs: Array[Image] = []
static var _names: PackedStringArray = PackedStringArray()


## Saves `image` to `path`; in probe mode also rewrites the run's sheet.
static func save_capture(image: Image, path: String) -> Error:
	var err: Error = image.save_png(path)
	if err != OK or not AgentProbe.is_active():
		return err
	var cell: int = int(MAX_SHEET_WIDTH / 2.0)
	_thumbs.append(_fit_width(image, cell))
	_names.append(path.get_file())
	var sheet_path: String = path.get_base_dir().path_join(run_name(OS.get_cmdline_args()) + SHEET_SUFFIX)
	var sheet: Image = build(_thumbs, MAX_SHEET_WIDTH)
	err = sheet.save_png(sheet_path)
	if err == OK:
		print("CONTACT_SHEET %s size=%s frames=%s" % [ProjectSettings.globalize_path(sheet_path) if sheet_path.begins_with("user://") or sheet_path.begins_with("res://") else sheet_path, sheet.get_size(), ", ".join(_names)])
	return err


## Basename of the scene on the command line (tools/screenshot_fog.tscn -> screenshot_fog).
static func run_name(cmdline_args: PackedStringArray) -> String:
	for arg: String in cmdline_args:
		if arg.ends_with(".tscn"):
			return arg.get_file().get_basename()
	return FALLBACK_NAME


static func reset() -> void:
	_thumbs.clear()
	_names.clear()


## Grid of `images` (row-major, up to MAX_COLUMNS wide) no wider than max_width.
static func build(images: Array[Image], max_width: int = MAX_SHEET_WIDTH) -> Image:
	if images.is_empty():
		return Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	var columns: int = mini(images.size(), MAX_COLUMNS)
	var rows: int = ceili(float(images.size()) / float(columns))
	var cell_w: int = maxi(1, int((max_width - GAP * (columns + 1)) / float(columns)))
	var cells: Array[Image] = []
	var row_h: int = 1
	for image: Image in images:
		var cell: Image = _fit_width(image, cell_w)
		cells.append(cell)
		row_h = maxi(row_h, cell.get_height())
	var sheet: Image = Image.create_empty(
			columns * cell_w + GAP * (columns + 1), rows * row_h + GAP * (rows + 1), false, Image.FORMAT_RGBA8)
	sheet.fill(BACKGROUND)
	for i: int in cells.size():
		var cell: Image = cells[i]
		cell.convert(Image.FORMAT_RGBA8)
		var origin: Vector2i = Vector2i(GAP + (i % columns) * (cell_w + GAP), GAP + (i / columns) * (row_h + GAP))
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), origin)
	return sheet


static func _fit_width(image: Image, width: int) -> Image:
	var copy: Image = image.duplicate() as Image
	if copy.get_width() > width:
		var height: int = maxi(1, int(round(float(copy.get_height()) * float(width) / float(copy.get_width()))))
		copy.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return copy
