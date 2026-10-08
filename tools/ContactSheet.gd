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
## No written sheet exceeds MAX_SHEET_PX_W x MAX_SHEET_PX_H (2600x3000); when the shots do not fit
## they paginate into <run>_sheet_p1.png, _p2.png ... and every page path is printed (a single page
## keeps the plain <run>_sheet.png name).

const MAX_SHEET_WIDTH: int = 1280
const MAX_COLUMNS: int = 3
const GAP: int = 4
const BACKGROUND: Color = Color(0.1, 0.1, 0.1, 1.0)
const MAX_SHEET_PX_W: int = 2600
const MAX_SHEET_PX_H: int = 3000
const SHEET_SUFFIX: String = "_sheet.png"
const PAGE_INFIX: String = "_sheet_p"
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
	var base_dir: String = path.get_base_dir()
	var run: String = run_name(OS.get_cmdline_args())
	var pages: Array[Image] = build_pages(_thumbs, MAX_SHEET_WIDTH)
	var single_path: String = base_dir.path_join(run + SHEET_SUFFIX)
	if pages.size() > 1 and FileAccess.file_exists(single_path):
		DirAccess.remove_absolute(single_path)  # drop the stale one-page sheet
	var shown: PackedStringArray = PackedStringArray()
	for i: int in pages.size():
		var sheet_path: String = single_path if pages.size() == 1 else base_dir.path_join("%s%s%d.png" % [run, PAGE_INFIX, i + 1])
		err = pages[i].save_png(sheet_path)
		if err != OK:
			return err
		shown.append("%s size=%s" % [ProjectSettings.globalize_path(sheet_path) if sheet_path.begins_with("user://") or sheet_path.begins_with("res://") else sheet_path, pages[i].get_size()])
	print("CONTACT_SHEET %s frames=%s" % [" | ".join(shown), ", ".join(_names)])
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


## First page of build_pages: the whole sheet whenever it fits the 2600x3000 cap.
static func build(images: Array[Image], max_width: int = MAX_SHEET_WIDTH) -> Image:
	return build_pages(images, max_width)[0]


## Grid pages of `images` (row-major, up to MAX_COLUMNS wide), each no larger than
## MAX_SHEET_PX_W x MAX_SHEET_PX_H. Always returns at least one page.
static func build_pages(images: Array[Image], max_width: int = MAX_SHEET_WIDTH) -> Array[Image]:
	var pages: Array[Image] = []
	if images.is_empty():
		pages.append(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
		return pages
	max_width = clampi(max_width, 1, MAX_SHEET_PX_W)
	var columns: int = mini(images.size(), MAX_COLUMNS)
	var cell_w: int = maxi(1, int((max_width - GAP * (columns + 1)) / float(columns)))
	var max_cell_h: int = maxi(1, MAX_SHEET_PX_H - GAP * 2)
	var cells: Array[Image] = []
	var row_h: int = 1
	for image: Image in images:
		var cell: Image = _fit_width(image, cell_w)
		if cell.get_height() > max_cell_h:
			cell = _fit_height(cell, max_cell_h)
		cell.convert(Image.FORMAT_RGBA8)
		cells.append(cell)
		row_h = maxi(row_h, cell.get_height())
	var rows_per_page: int = maxi(1, int((MAX_SHEET_PX_H - GAP) / float(row_h + GAP)))
	var per_page: int = rows_per_page * columns
	var start: int = 0
	while start < cells.size():
		var count: int = mini(per_page, cells.size() - start)
		var used_columns: int = mini(columns, count)
		var rows: int = ceili(float(count) / float(columns))
		var sheet: Image = Image.create_empty(
				used_columns * cell_w + GAP * (used_columns + 1), rows * row_h + GAP * (rows + 1), false, Image.FORMAT_RGBA8)
		sheet.fill(BACKGROUND)
		for i: int in count:
			var cell: Image = cells[start + i]
			var origin: Vector2i = Vector2i(GAP + (i % columns) * (cell_w + GAP), GAP + (i / columns) * (row_h + GAP))
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), origin)
		pages.append(sheet)
		start += count
	return pages


static func _fit_width(image: Image, width: int) -> Image:
	var copy: Image = image.duplicate() as Image
	if copy.get_width() > width:
		var height: int = maxi(1, int(round(float(copy.get_height()) * float(width) / float(copy.get_width()))))
		copy.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return copy


static func _fit_height(image: Image, height: int) -> Image:
	var copy: Image = image.duplicate() as Image
	if copy.get_height() > height:
		var width: int = maxi(1, int(round(float(copy.get_width()) * float(height) / float(copy.get_height()))))
		copy.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return copy
