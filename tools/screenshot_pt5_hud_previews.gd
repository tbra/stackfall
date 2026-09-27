extends Node
## Windowed off-screen capture for Bontago-1pi.5 (owner playtest: "Held/next
## previews should be grouped and moved to the bottom left corner, some of
## the blocks are rendered oddly in the previews as well"). Not part of the
## running game (CLAUDE.md); run as:
##   godot --windowed --position 10000,10000 --path . --scene res://tools/screenshot_pt5_hud_previews.tscn
##
## Two pieces of evidence in one windowed boot (probe-ceiling discipline,
## docs/AGENT_WORKFLOW.md): (1) a full-HUD screenshot with a non-square
## held/next shape pair and a live territory-share list, showing the grouped
## %HeldNextPanel sitting in the bottom-left corner clear of both the
## top-left per-player cluster and the bottom-right minimap; (2) a contact
## sheet, one tile per config/blocks/*.tres BlockShape, each rendered through
## the real %ShapePreview control and cropped straight off the rendered
## frame, showing every shape centered and fully in frame after the
## AABB-centering fix in ui/HUD.gd's _draw_iso_shape().

const GROUPED_PANEL_OUTPUT: String = "res://feedback/pt5-grouped-panel.png"
const CONTACT_SHEET_OUTPUT: String = "res://feedback/pt5-preview-contact-sheet.png"
const TILE_SIZE: int = 140
const TILE_MARGIN: int = 10
const TILES_PER_ROW: int = 4
const BACKDROP_COLOR: Color = Color(0.1, 0.1, 0.12, 1.0)


func _ready() -> void:
	var hud: HUD = (load("res://ui/HUD.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(hud)
	await get_tree().process_frame
	await get_tree().process_frame

	await _capture_grouped_panel(hud)
	await _capture_preview_contact_sheet(hud)
	get_tree().quit()


## Capture 1: a representative, visibly non-square held/next pair (an L4 and
## a bar4), plus a 3-row territory share list, so this frame proves both the
## grouped bottom-left panel's position and its lack of overlap with the
## other HUD clusters at once.
func _capture_grouped_panel(hud: HUD) -> void:
	hud.set_local_slot(0)
	hud.set_held_shape(load("res://config/blocks/L4.tres"))
	hud.set_next_shape(load("res://config/blocks/bar4.tres"))
	hud.set_territory_shares(PackedFloat32Array([0.4, 0.3, 0.3]))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var full: Image = get_viewport().get_texture().get_image()
	full.save_png(GROUPED_PANEL_OUTPUT)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(GROUPED_PANEL_OUTPUT), full.get_width(), full.get_height(),
	])


## Capture 2: every BlockShape the bag can deal, rendered one at a time
## through the held-shape preview and cropped into a grid so a reviewer can
## eyeball every shape's centering/framing at once without a second windowed
## run per shape.
func _capture_preview_contact_sheet(hud: HUD) -> void:
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	shapes.sort_custom(func(a: BlockShape, b: BlockShape) -> bool: return String(a.id) < String(b.id))

	var rows: int = int(ceil(float(shapes.size()) / float(TILES_PER_ROW)))
	var sheet: Image = Image.create(TILES_PER_ROW * TILE_SIZE, rows * TILE_SIZE, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKDROP_COLOR)

	var preview: Control = hud._shape_preview
	for i: int in range(shapes.size()):
		var shape: BlockShape = shapes[i]
		hud.set_held_shape(shape)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var frame: Image = get_viewport().get_texture().get_image()
		# DECISION (Bontago-1pi.5, root cause found after the first run
		# produced blank tiles): Control.global_position/size are in the
		# viewport's *logical* size (get_viewport().get_visible_rect().size),
		# but get_viewport().get_texture().get_image() reads back the actual
		# *physical* swapchain image, which can be a different (and
		# non-uniformly scaled per axis, under a stretch mode that fills an
		# arbitrary window/monitor size) resolution -- cropping with the raw
		# logical-space rect silently read the wrong pixels. Scaling by
		# physical/logical per axis maps the Control's rect into the same
		# space `frame` is actually in.
		var logical_size: Vector2 = get_viewport().get_visible_rect().size
		var physical_size: Vector2 = Vector2(frame.get_width(), frame.get_height())
		var to_physical: Vector2 = physical_size / logical_size
		var rect: Rect2i = Rect2i(
			Vector2i(preview.global_position * to_physical), Vector2i(preview.size * to_physical)
		)
		var crop: Image = frame.get_region(rect)
		crop.convert(Image.FORMAT_RGBA8)
		var tile_inner: int = TILE_SIZE - TILE_MARGIN * 2
		crop.resize(tile_inner, tile_inner)

		var col: int = i % TILES_PER_ROW
		var row: int = i / TILES_PER_ROW
		var dest: Vector2i = Vector2i(col * TILE_SIZE + TILE_MARGIN, row * TILE_SIZE + TILE_MARGIN)
		sheet.blit_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), dest)
		print("SCREENSHOT tile shape=%s preview_rect=%s" % [shape.id, rect])

	sheet.save_png(CONTACT_SHEET_OUTPUT)
	print("SCREENSHOT saved=%s size=%dx%d shapes=%d" % [
		ProjectSettings.globalize_path(CONTACT_SHEET_OUTPUT), sheet.get_width(), sheet.get_height(), shapes.size(),
	])
