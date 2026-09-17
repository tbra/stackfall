class_name HUD
extends CanvasLayer
## Spec 2.10's HUD, scoped to what M2 needs (docs/M2_PLAN.md P4): timer ring,
## next-block preview, max height, per-player territory share, capture ring,
## and a hot-seat turn indicator. The minimap and presentation polish are M7.
##
## "Connects to Events only — no node paths out of ui/" (docs/M2_PLAN.md): it
## wires itself to the Events bus in _ready() and never walks the scene tree
## looking for collaborators. It reads the Match autoload for display data a
## signal payload doesn't carry (a slot's colour, a shape id's BlockShape,
## whether a slot is eliminated) but never decides anything — spawning a
## Block, validity, and the raster all stay Match's job.
##
## DECISION (ui/HUD.gd): every *gameplay-feel* number (durations, colors,
## hatch scale) already lives in GhostTuning (docs/M2_PLAN.md parks P4's HUD
## tunables there too). Pure screen-space drawing geometry for this
## placeholder layout — ring line width, background alpha, the preview's
## cell size in pixels — stays inline: M7 replaces this whole visual with
## real art, and CLAUDE.md's "no magic numbers" is about tunables that affect
## gameplay feel, not every pixel constant behind a first-pass debug HUD.


const SHARE_BAR_MAX_WIDTH: float = 120.0
const SHARE_BAR_HEIGHT: float = 14.0
const RING_LINE_WIDTH: float = 4.0
const RING_BACKGROUND_COLOR: Color = Color(1.0, 1.0, 1.0, 0.15)
const ELIMINATED_COLOR: Color = Color(0.4, 0.4, 0.4, 0.5)
const PREVIEW_CELL_PX: float = 8.0
const PREVIEW_CELL_MARGIN: float = 0.9

@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
## Fallback player colours for a slot Match cannot name — before a match
## starts, or in a HUD-only test with no Match behind it. An @export var
## rather than a const: a const's value has to resolve while the script is
## still being parsed, and the editor parses HUD.gd (through Main -> HotSeat)
## before it can load a .tres whose script is MatchConfig, which made the
## constant null and the parse fail.
@export var default_palette: MatchConfig = preload("res://config/match_defaults.tres")
## DECISION (ui/HUD.gd): a Variant test seam for the same reason
## PlayerController has one — GUT can't double a plain autoload, and P2's
## real Match hasn't landed on this branch yet. Defaults to the real
## autoload; tests overwrite it with a fake after add_child().
var match_provider: Variant = null

@onready var _turn_label: Label = %TurnLabel
@onready var _timer_ring: Control = %TimerRing
@onready var _shape_preview: Control = %ShapePreview
@onready var _height_label: Label = %HeightLabel
@onready var _shares_box: VBoxContainer = %SharesBox
@onready var _capture_ring: Control = %CaptureRing
@onready var _reject_label: Label = %RejectLabel
@onready var _winner_label: Label = %WinnerLabel

var _shapes_by_id: Dictionary = {}
var _active_slot: int = -1
var _active_color: Color = Color.WHITE
var _feed_progress: float = 1.0
var _next_shape: BlockShape = null
var _capture_color: Color = Color.WHITE
var _capture_progress: float = 0.0
var _reject_tween: Tween

var _share_rows: Array = []
var _share_bars: Array = []
var _share_labels: Array = []


func _ready() -> void:
	match_provider = Match
	_shapes_by_id = _load_shapes_by_id()
	_timer_ring.draw.connect(_on_timer_ring_draw)
	_shape_preview.draw.connect(_on_shape_preview_draw)
	_capture_ring.draw.connect(_on_capture_ring_draw)
	_reject_label.modulate.a = 0.0
	_winner_label.visible = false
	_capture_ring.visible = false

	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.territory_share_changed.connect(_on_territory_share_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.match_won.connect(_on_match_won)
	Events.player_eliminated.connect(_on_player_eliminated)


func _process(_delta: float) -> void:
	if match_provider == null or _active_slot < 0:
		return
	set_feed_progress(match_provider.feed_progress(_active_slot))
	set_height(match_provider.max_height_for_slot(_active_slot))


# --- Public API (docs/M2_PLAN.md — "implement exactly") ---------------------

func set_active_slot(slot_id: int, color: Color) -> void:
	_active_slot = slot_id
	_active_color = color
	var eliminated: bool = _is_slot_eliminated(slot_id)
	_turn_label.text = (
		"Player %d — eliminated" % (slot_id + 1) if eliminated else "Player %d's turn" % (slot_id + 1)
	)
	_turn_label.modulate = ELIMINATED_COLOR if eliminated else color
	_timer_ring.queue_redraw()
	_shape_preview.queue_redraw()


func set_next_shape(shape: BlockShape) -> void:
	_next_shape = shape
	_shape_preview.queue_redraw()


## fraction runs 1 -> 0 as the slot's block timer counts down; drives the
## timer ring's radial fill.
func set_feed_progress(fraction: float) -> void:
	_feed_progress = clampf(fraction, 0.0, 1.0)
	_timer_ring.queue_redraw()


func set_height(meters: float) -> void:
	_height_label.text = "Height: %.2f m" % meters


func set_territory_shares(shares: PackedFloat32Array) -> void:
	_ensure_share_row_count(shares.size())
	for i: int in range(shares.size()):
		_update_share_row(i, shares[i])


func set_capture(team_id: int, progress: float, color: Color) -> void:
	_capture_progress = clampf(progress, 0.0, 1.0)
	_capture_color = color
	_capture_ring.visible = team_id >= 0 and _capture_progress > 0.0
	_capture_ring.queue_redraw()


func show_reject(reason: StringName) -> void:
	_reject_label.text = "Rejected: %s" % String(reason).replace("_", " ")
	_reject_label.modulate.a = 1.0
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_tween = create_tween()
	_reject_tween.tween_interval(ghost_tuning.hud_reject_message_duration)
	_reject_tween.tween_property(_reject_label, ^"modulate:a", 0.0, ghost_tuning.hud_reject_fade_duration)


func show_winner(team_id: int, color: Color) -> void:
	_winner_label.text = "Team %d wins!" % (team_id + 1)
	_winner_label.modulate = color
	_winner_label.visible = true


# --- Events reactions --------------------------------------------------------

func _on_turn_changed(slot_id: int) -> void:
	set_active_slot(slot_id, _color_for_slot(slot_id))


func _on_feed_block_issued(slot_id: int, _shape_id: StringName, next_shape_id: StringName) -> void:
	if slot_id != _active_slot:
		return
	set_next_shape(_shapes_by_id.get(next_shape_id) as BlockShape)


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	# DECISION (ui/HUD.gd): M2 is hot-seat only, one player acts at a time, so
	# every rejection is shown as if it's about whoever's turn it is. A
	## per-viewer HUD for simultaneous multiplayer is M3's problem.
	if slot_id != _active_slot:
		return
	show_reject(reason)


func _on_territory_share_changed(shares: PackedFloat32Array) -> void:
	set_territory_shares(shares)


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	set_capture(team_id, progress, _color_for_slot(team_id) if team_id >= 0 else Color.WHITE)


func _on_match_won(team_id: int) -> void:
	show_winner(team_id, _color_for_slot(team_id))


## The turn banner already reads home_flag_alive, but it is only rebuilt on
## turn_changed, so an elimination that lands mid-turn would sit invisible
## until the turn passed. Repainting it here is the whole reaction.
func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	if slot_id != _active_slot:
		return
	set_active_slot(_active_slot, _active_color)


# --- Helpers -----------------------------------------------------------------

## Spec M2 owner decision 3: no dedicated Events signal exists for "home flag
## lost", so — like PlayerController — the HUD reads the already-documented
## PlayerSlot.home_flag_alive straight off Match.slot() instead of inventing
## a signal on a contract this package doesn't own.
func _is_slot_eliminated(slot_id: int) -> bool:
	if match_provider == null:
		return false
	var slot: PlayerSlot = match_provider.slot(slot_id)
	return slot != null and not slot.home_flag_alive


func _color_for_slot(slot_id: int) -> Color:
	if match_provider != null:
		var slot: PlayerSlot = match_provider.slot(slot_id)
		if slot != null:
			return slot.color
	if slot_id >= 0 and slot_id < default_palette.player_colors.size():
		return default_palette.player_colors[slot_id]
	return Color.WHITE


func _ensure_share_row_count(count: int) -> void:
	while _share_rows.size() < count:
		var row: HBoxContainer = HBoxContainer.new()
		var bar_bg: ColorRect = ColorRect.new()
		bar_bg.custom_minimum_size = Vector2(SHARE_BAR_MAX_WIDTH, SHARE_BAR_HEIGHT)
		bar_bg.color = RING_BACKGROUND_COLOR
		var bar_fill: ColorRect = ColorRect.new()
		bar_fill.custom_minimum_size = Vector2(0.0, SHARE_BAR_HEIGHT)
		bar_bg.add_child(bar_fill)
		var label: Label = Label.new()
		row.add_child(bar_bg)
		row.add_child(label)
		_shares_box.add_child(row)
		_share_rows.append(row)
		_share_bars.append(bar_fill)
		_share_labels.append(label)
	while _share_rows.size() > count:
		var last: int = _share_rows.size() - 1
		(_share_rows[last] as Node).queue_free()
		_share_rows.remove_at(last)
		_share_bars.remove_at(last)
		_share_labels.remove_at(last)


func _update_share_row(i: int, share: float) -> void:
	var eliminated: bool = _is_slot_eliminated(i)
	var color: Color = ELIMINATED_COLOR if eliminated else _color_for_slot(i)
	var bar: ColorRect = _share_bars[i]
	bar.color = color
	bar.custom_minimum_size = Vector2(SHARE_BAR_MAX_WIDTH * clampf(share, 0.0, 1.0), SHARE_BAR_HEIGHT)
	var label: Label = _share_labels[i]
	label.text = "P%d: %.0f%%%s" % [i + 1, share * 100.0, "  (out)" if eliminated else ""]


## Events.feed_block_issued names the next shape by id; the preview needs the
## resource. BlockShape.load_all_shapes() is the project's one directory scan.
func _load_shapes_by_id() -> Dictionary:
	var shapes: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		shapes[shape.id] = shape
	return shapes


# --- Drawing (ring/preview Controls have no script of their own; connecting
# to their `draw` signal lets HUD.gd draw into them without a second file) --

func _on_timer_ring_draw() -> void:
	var size: Vector2 = _timer_ring.size
	var radius: float = minf(size.x, size.y) * 0.5 - RING_LINE_WIDTH
	var center: Vector2 = size * 0.5
	_timer_ring.draw_arc(center, radius, 0.0, TAU, 48, RING_BACKGROUND_COLOR, RING_LINE_WIDTH)
	if _feed_progress > 0.0:
		_timer_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _feed_progress, 48, _active_color, RING_LINE_WIDTH
		)


func _on_shape_preview_draw() -> void:
	if _next_shape == null:
		return
	var center: Vector2 = _shape_preview.size * 0.5
	# DECISION (ui/HUD.gd): projects each cube's (x, y) offset — a front
	# elevation — rather than the top-down (x, z) footprint, so tall shapes
	# (bar4, pillar) read as tall in the small preview instead of collapsing
	# to a single square; flat shapes that only vary in (x, z) (square4,
	# slab6) collapse to one row here, a fair trade for a placeholder icon.
	for cell: Vector3i in _next_shape.cells:
		var pos: Vector2 = center + Vector2(cell.x, -cell.y) * PREVIEW_CELL_PX - Vector2.ONE * PREVIEW_CELL_PX * 0.5
		var rect: Rect2 = Rect2(pos, Vector2.ONE * PREVIEW_CELL_PX * PREVIEW_CELL_MARGIN)
		_shape_preview.draw_rect(rect, _active_color)


func _on_capture_ring_draw() -> void:
	var size: Vector2 = _capture_ring.size
	var radius: float = minf(size.x, size.y) * 0.5 - RING_LINE_WIDTH
	var center: Vector2 = size * 0.5
	_capture_ring.draw_arc(center, radius, 0.0, TAU, 48, RING_BACKGROUND_COLOR, RING_LINE_WIDTH)
	if _capture_progress > 0.0:
		_capture_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _capture_progress, 48, _capture_color, RING_LINE_WIDTH
		)
