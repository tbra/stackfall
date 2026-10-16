class_name MenuBackdrop
extends Control
## Main menu / lobby reskin:
## the flat "paper-cut" half of the split background (docs/art_mockups/
## 10-main-menu-layered-pastel.png, 11-lobby-layered-pastel.png) -- a banded
## sky, a layered concentric sun, pill-shaped cloud strata and apricot/mint
## ground bands, all drawn with _draw() so no image asset is needed (hard
## constraint in the brief). Sits full-rect behind everything else; the live
## 3D diorama (ui/MenuDiorama.gd) is reframed into the right third on top of
## it as its own small framed island.
##
## Every color, count and layout fraction it draws from is a
## config/ui/MenuVisualTuning.gd export (CLAUDE.md "No magic numbers"); this
## script holds no tunables of its own, only the drawing routine, matching
## ui/MenuDiorama.gd's existing "build everything in _ready()/_draw(), no
## companion .tscn children" convention.

@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")
## UI reskin P1: false keeps only the render-budget holding below and draws
## nothing, for screens whose backdrop is not drawn here (the main menu shows a static image node).
## The lobby keeps the paper-cut art until its own package.
@export var draw_art: bool = true


## ("main menu uses 95% of my gpu"). Root cause: the
## match world (Field disc, Skybox, SSR, shadows, glow, reflection probe, disc
## mirror: ~400k prims) kept rendering uncapped, at monitor refresh, behind this
## full-screen opaque backdrop. Menu/lobby screens now hold a render budget: the
## root viewport skips 3D and Engine.max_fps is capped. Reference counted
## because the lobby is added before the menu's queue_free() runs.
static var _budget_holders: int = 0
static var _saved_max_fps: int = 0
static var _saved_disable_3d: bool = false
## the in-match cap decided by game/main/Main.gd (-1 = none decided, so
## the cap saved on menu entry is restored). Main is the single place that decides it;
## this class only arbitrates menu vs match, so a preset change made while a menu is
## open cannot leave the match cap behind in the menu (or the menu cap in the match).
static var _match_cap: int = -1
static var _menu_cap: int = 0

## (the menu is a picture). Measured at menu, options and
## lobby: root disable_3d was already true (no 3D pass), but 12 world scripts (Skybox, birds,
## Field, BlockRegistry, CameraRig, CloudShadows, HorizonIslands, ...) kept running _process behind
## it. DECISION: while a menu holds the budget the world nodes Main registers go
## PROCESS_MODE_DISABLED (gated by the same menu_disable_world_3d switch) and get their previous
## mode back on the last release. Restoration happens when the menu leaves the tree, i.e. at the
## end of the frame in which Main frees it, before the match world is next processed.
static var _dormant_nodes: Array[Node] = []
static var _dormant_saved: Dictionary = {}
static var _dormant_active: bool = false
static var _dormant_wanted: bool = false
## Main's "a match, sandbox or tutorial world is live" predicate. DECISION: a menu backdrop can
## outlive a world start (the CLI --sandbox path leaves the MainMenu up), so dormancy is
## re-evaluated every frame against it and never freezes a live world.
static var _world_live: Callable = Callable()

var _holds_budget: bool = false

const IMAGE_NODE_NAME: String = "BackdropImage"
const MENU_TUNING_PATH: String = "res://config/ui/main_menu_tuning.tres"
## The image picked this launch (empty until the first menu/lobby asks); shared so the lobby
## keeps the menu's backdrop. Only the chosen file is ever loaded.
static var _chosen_path: String = ""


## Pure pick: the entry of `paths` at `roll` (0..1, exclusive of 1); "" for an empty list.
static func pick_path(paths: PackedStringArray, roll: float) -> String:
	if paths.is_empty():
		return ""
	return paths[clampi(int(roll * float(paths.size())), 0, paths.size() - 1)]


static func chosen_path() -> String:
	if _chosen_path.is_empty():
		var menu_tuning: MainMenuTuning = load(MENU_TUNING_PATH) as MainMenuTuning
		if menu_tuning != null:
			_chosen_path = pick_path(menu_tuning.backdrop_paths, randf())
	return _chosen_path


func _enter_tree() -> void:
	if _holds_budget:
		return
	_holds_budget = true
	_budget_holders += 1
	if _budget_holders == 1:
		_saved_max_fps = Engine.max_fps
		var viewport: Viewport = get_viewport()
		if viewport != null:
			_saved_disable_3d = viewport.disable_3d
	_apply_budget()


func _exit_tree() -> void:
	if not _holds_budget:
		return
	_holds_budget = false
	_budget_holders = maxi(_budget_holders - 1, 0)
	if _budget_holders == 0:
		Engine.max_fps = _match_cap if _match_cap >= 0 else _saved_max_fps
		var viewport: Viewport = get_viewport()
		if viewport != null:
			viewport.disable_3d = _saved_disable_3d
		_set_world_dormant(false)


## Main registers the always-present world roots here (replaces any earlier list, restoring it).
static func set_dormant_world(nodes: Array[Node], world_live: Callable = Callable()) -> void:
	_set_world_dormant(false)
	_dormant_nodes = nodes.duplicate()
	_world_live = world_live


static func _refresh_dormancy() -> void:
	var live: bool = _world_live.is_valid() and bool(_world_live.call())
	_set_world_dormant(_budget_holders > 0 and not live and _dormant_wanted)


static func _set_world_dormant(dormant: bool) -> void:
	if dormant == _dormant_active:
		return
	_dormant_active = dormant
	for node: Node in _dormant_nodes:
		if not is_instance_valid(node):
			continue
		if dormant:
			_dormant_saved[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED
		elif _dormant_saved.has(node):
			node.process_mode = _dormant_saved[node] as Node.ProcessMode
	if not dormant:
		_dormant_saved.clear()


static func budget_holders() -> int:
	return _budget_holders


## Called by game/main/Main.gd whenever it decides the in-match cap (0 = uncapped). While a
## menu holds the budget the menu cap stays in force and the match cap takes effect on
## the last menu exit; otherwise it applies immediately.
static func set_match_cap(cap: int) -> void:
	_match_cap = maxi(cap, 0)
	if _budget_holders == 0:
		Engine.max_fps = _match_cap
	else:
		Engine.max_fps = _menu_effective_cap()


static func clear_match_cap() -> void:
	_match_cap = -1


static func _menu_effective_cap() -> int:
	# DECISION: an existing lower player/tool/match cap wins over the menu cap.
	var base: int = _match_cap if _match_cap >= 0 else _saved_max_fps
	if _menu_cap <= 0:
		return base
	return _menu_cap if base <= 0 else mini(_menu_cap, base)


func _apply_budget() -> void:
	_menu_cap = tuning.menu_max_fps
	if _menu_cap > 0:
		Engine.max_fps = _menu_effective_cap()
	var viewport: Viewport = get_viewport()
	if viewport != null and tuning.menu_disable_world_3d:
		viewport.disable_3d = true
	# Dormancy itself starts on this backdrop's first _process frame, never inside the tree-entry
	# call, so a world started in the same frame (CLI --sandbox, test fixtures) is already live.
	_dormant_wanted = tuning.menu_disable_world_3d


func _process(_delta: float) -> void:
	_refresh_dormancy()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_apply_image()


## Sets the random launch backdrop on the sibling BackdropImage node (menu and lobby scenes).
func _apply_image() -> void:
	var parent: Node = get_parent()
	var image: TextureRect = parent.get_node_or_null(IMAGE_NODE_NAME) as TextureRect if parent != null else null
	if image == null:
		return
	var path: String = chosen_path()
	if not path.is_empty():
		image.texture = load(path) as Texture2D


func _draw() -> void:
	if not draw_art:
		return
	var size: Vector2 = get_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_sky(size)
	_draw_sun(size)
	_draw_clouds(size)
	_draw_ground_bands(size)


func _draw_sky(size: Vector2) -> void:
	var band_count: int = tuning.backdrop_sky_band_count
	var band_height: float = size.y / float(band_count)
	for i: int in range(band_count):
		var t: float = float(i) / float(band_count - 1)
		var color: Color = tuning.backdrop_sky_top_color.lerp(tuning.backdrop_sky_horizon_color, t)
		var rect: Rect2 = Rect2(0.0, band_height * float(i), size.x, band_height + 1.0)
		draw_rect(rect, color, true)


## Draws the sun as [member MenuVisualTuning.backdrop_sun_ring_count] concentric
## filled circles, largest (the pale halo) first, smallest (the orange core)
## last, lerping through 3 stops -- halo -> ring -> core -- instead of
## alternating 2 flat colors (review r1, item 7: "orange core, peach rings,
## pale halo, not yellow").
func _draw_sun(size: Vector2) -> void:
	var ring_count: int = tuning.backdrop_sun_ring_count
	if ring_count <= 0:
		return
	var center: Vector2 = Vector2(
		size.x * tuning.backdrop_sun_pos_x_fraction,
		size.y * tuning.backdrop_sun_pos_y_fraction
	)
	var outer_radius: float = minf(size.x, size.y) * tuning.backdrop_sun_radius_fraction
	for k: int in range(ring_count, 0, -1):
		var radius: float = outer_radius * (float(k) / float(ring_count))
		var t: float = 1.0 - float(k) / float(ring_count)
		var color: Color
		if t < 0.5:
			color = tuning.backdrop_sun_halo_color.lerp(tuning.backdrop_sun_ring_color, t * 2.0)
		else:
			color = tuning.backdrop_sun_ring_color.lerp(tuning.backdrop_sun_color, (t - 0.5) * 2.0)
		draw_circle(center, radius, color)


## Pill-shaped cloud strata, spaced evenly across the sky at a fixed height
## band with a small alternating vertical offset.
func _draw_clouds(size: Vector2) -> void:
	var count: int = tuning.backdrop_cloud_count
	if count <= 0:
		return
	var cloud_height: float = size.y * tuning.backdrop_cloud_height_fraction
	var cloud_width: float = size.x * tuning.backdrop_cloud_width_fraction
	var base_y: float = size.y * tuning.backdrop_cloud_base_y_fraction
	for i: int in range(count):
		var t: float = (float(i) + 0.5) / float(count)
		var offset_y: float = cloud_height * tuning.backdrop_cloud_offset_fraction if i % 2 == 0 else 0.0
		var rect: Rect2 = Rect2(
			size.x * t - cloud_width * 0.5,
			base_y + offset_y,
			cloud_width,
			cloud_height
		)
		var pill: StyleBoxFlat = StyleBoxFlat.new()
		pill.bg_color = tuning.backdrop_cloud_color
		# DECISION (review finding #4): cloud_height * 0.5 is pure geometry (a
		# fully-rounded pill's corner radius is half its own height, by
		# definition of "pill shape"), not an independent tunable, so it stays
		# a literal here rather than becoming a MenuVisualTuning export. Same
		# for the two `* 0.5` centering terms above (rect.x, cloud_width).
		pill.set_corner_radius_all(int(cloud_height * 0.5))
		pill.shadow_color = Color(0.22, 0.32, 0.36, 0.16)
		pill.shadow_size = int(tuning.card_shadow_size_px * 0.5)
		pill.shadow_offset = Vector2(0.0, tuning.card_offset_px * 0.5)
		draw_style_box(pill, rect)


func _draw_ground_bands(size: Vector2) -> void:
	var band_height: float = size.y * tuning.ground_band_height_fraction
	_draw_paper_band(size, size.y - band_height * 2.8, tuning.card_cream_color)
	_draw_paper_band(size, size.y - band_height * 1.9, tuning.ground_band_apricot_color)
	_draw_paper_band(size, size.y - band_height, tuning.ground_band_mint_color)


func _draw_paper_band(size: Vector2, top: float, color: Color) -> void:
	var edge: PackedVector2Array = PackedVector2Array()
	for i: int in range(33):
		var t: float = float(i) / 32.0
		edge.append(Vector2(t * size.x, top - sin(t * PI) * size.y * tuning.ground_band_height_fraction * 0.5))
	var polygon: PackedVector2Array = edge.duplicate()
	polygon.append(Vector2(size.x, size.y))
	polygon.append(Vector2(0.0, size.y))
	draw_colored_polygon(polygon, color)
	draw_polyline(edge, color.darkened(0.12), tuning.card_offset_px * 0.5, true)
