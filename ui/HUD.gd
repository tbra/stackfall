class_name HUD
extends CanvasLayer
## Spec 2.10's HUD, scoped to what M2/Bontago-mv0.9 need: a timer ring around
## the held-block preview, a separate next-block preview, max height,
## per-player territory share, capture ring, a LOCKED indicator, and a
## hot-seat turn indicator. Bontago-1en.16 (M4 P2b-ii) adds a small pending-
## special queue indicator beside the next-shape preview. The minimap and
## presentation polish are M7.
##
## Bontago-mv0.9: outside hot-seat there is no "turn" — every slot plays at
## once (spec 2.4 "[ORIGINAL target]") — so this HUD shows **the local
## player's own status** instead of a turn banner. `_active_slot` doubles as
## "whichever slot this HUD's widgets currently read": in hot-seat it is
## whoever's turn it is (set_active_slot(), wired off Events.turn_changed);
## outside hot-seat it is the local slot (set_local_slot(), also wired off
## Events.turn_changed since net/MatchNet.gd already substitutes the local
## slot into that signal there — see its own DECISION), and
## game/Sandbox.gd calls set_local_slot() directly when its debug hotkey
## cycles which slot it is driving. The gate is Match.config.hot_seat
## (_hot_seat_active()); config == null (no match running yet, or a bare
## HUD-only test) behaves like real-time play, matching every other
## HUD codepath that reads Match's config the same way.
##
## "Connects to Events only — no node paths out of ui/" (docs/M2_PLAN.md): it
## wires itself to the Events bus in _ready() and never walks the scene tree
## looking for collaborators. It reads the Match autoload for display data a
## signal payload doesn't carry (a slot's colour, name, or a shape id's
## BlockShape, whether a slot is eliminated, whether its release is locked)
## but never decides anything — spawning a Block, validity, and the raster
## all stay Match's job.
##
## DECISION (ui/HUD.gd): every *gameplay-feel* number (durations, colors,
## hatch scale) already lives in GhostTuning (docs/M2_PLAN.md parks P4's HUD
## tunables there too). Pure screen-space drawing geometry for this
## placeholder layout — ring line width, background alpha, the preview's
## cell size in pixels — stays inline: M7 replaces this whole visual with
## real art, and CLAUDE.md's "no magic numbers" is about tunables that affect
## gameplay feel, not every pixel constant behind a first-pass debug HUD.
##
## DECISION (ui/HUD.gd, Bontago-mv0.9): the held/next previews stay the
## existing flat 2D icon draw (BlockShape.cells projected to screen space)
## rather than a mesh thumbnail rendered through a SubViewport +
## BlockFactory.build_visual_only(). The assignment allows either "mesh
## thumbnails ... or the existing icon approach — reuse what HUD.tscn
## already has"; a SubViewport per preview is real M7-grade art (its own
## camera rig, lighting, and a second render pass per HUD per frame) for a
## placeholder HUD everything else here explicitly defers to M7.


const SHARE_BAR_MAX_WIDTH: float = 120.0
const SHARE_BAR_HEIGHT: float = 14.0
const RING_LINE_WIDTH: float = 4.0
const RING_BACKGROUND_COLOR: Color = Color(1.0, 1.0, 1.0, 0.15)
const ELIMINATED_COLOR: Color = Color(0.4, 0.4, 0.4, 0.5)
## Bontago-mv0.9: a distinct grey from ELIMINATED_COLOR (same idea, different
## meaning) for the release-locked ring/label, so a locked-but-not-eliminated
## slot never reads as "this player is out".
const LOCKED_COLOR: Color = Color(0.75, 0.75, 0.75, 0.9)
const PREVIEW_CELL_PX: float = 8.0
const PREVIEW_CELL_MARGIN: float = 0.9

@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
## Bontago-d04: durations for the "Special queued: <name>" claim toast below
## (see config/GiftConfig.gd's own "-- Claim feedback --" section for why
## these live there rather than in ghost_tuning above).
@export var gift_config: GiftConfig = preload("res://config/gift_config.tres")
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
@onready var _next_shape_preview: Control = %NextShapePreview
@onready var _special_indicator: Label = %SpecialIndicator
@onready var _locked_label: Label = %LockedLabel
@onready var _height_label: Label = %HeightLabel
@onready var _shares_box: VBoxContainer = %SharesBox
@onready var _capture_ring: Control = %CaptureRing
@onready var _reject_label: Label = %RejectLabel
@onready var _winner_label: Label = %WinnerLabel
@onready var _gift_toast_label: Label = %GiftToastLabel

var _shapes_by_id: Dictionary = {}
## Whichever slot this HUD's widgets currently read: the hot-seat active
## slot, or (outside hot-seat) the local player's slot. See the class
## doc comment above.
var _active_slot: int = -1
var _active_color: Color = Color.WHITE
var _feed_progress: float = 1.0
## What `_active_slot` is holding right now — drawn inside the timer ring,
## since the ring counts down toward that block's placement deadline.
var _held_shape: BlockShape = null
## What the bag deals `_active_slot` after the held block — drawn in the
## separate next-block preview beside the ring.
var _next_shape: BlockShape = null
var _locked: bool = false
var _capture_color: Color = Color.WHITE
var _capture_progress: float = 0.0
var _reject_tween: Tween
var _gift_toast_tween: Tween

var _share_rows: Array = []
var _share_bars: Array = []
var _share_labels: Array = []


func _ready() -> void:
	match_provider = Match
	_shapes_by_id = _load_shapes_by_id()
	_timer_ring.draw.connect(_on_timer_ring_draw)
	_shape_preview.draw.connect(_on_shape_preview_draw)
	_next_shape_preview.draw.connect(_on_next_shape_preview_draw)
	_capture_ring.draw.connect(_on_capture_ring_draw)
	_reject_label.modulate.a = 0.0
	_gift_toast_label.modulate.a = 0.0
	_winner_label.visible = false
	_capture_ring.visible = false
	_locked_label.visible = false
	_special_indicator.visible = false

	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.territory_share_changed.connect(_on_territory_share_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.match_won.connect(_on_match_won)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_claimed.connect(_on_gift_claimed)


func _process(_delta: float) -> void:
	if match_provider == null or _active_slot < 0:
		return
	set_feed_progress(match_provider.feed_progress(_active_slot))
	var tower_m: float = match_provider.max_height_for_slot(_active_slot)
	var held: GhostPreview = get_tree().get_first_node_in_group(GhostPreview.LOCAL_HELD_GROUP) as GhostPreview
	if held != null and held.get_shape() != null:
		set_tower_and_block_height(tower_m, held.height_above_surface())
	else:
		set_height(tower_m)
	set_locked(bool(match_provider.is_release_locked(_active_slot)))
	_refresh_special_indicator()


# --- Public API (docs/M2_PLAN.md — "implement exactly"; Bontago-mv0.9 adds
# set_local_slot/set_held_shape/set_locked) -----------------------------------

## Hot-seat only: whoever's turn it is right now. Shows the "Player N's
## turn" wording — the one place in the game a "turn" still exists (spec
## Part 4 M2: hot-seat is a test harness, not the shipped cadence).
func set_active_slot(slot_id: int, color: Color) -> void:
	_active_slot = slot_id
	_active_color = color
	var eliminated: bool = _is_slot_eliminated(slot_id)
	var display_name: String = _name_for_slot(slot_id)
	_turn_label.text = (
		"%s — eliminated" % display_name if eliminated else "%s's turn" % display_name
	)
	_turn_label.modulate = ELIMINATED_COLOR if eliminated else color
	_timer_ring.queue_redraw()
	_shape_preview.queue_redraw()


## Real-time play and sandbox: points every per-slot widget (turn label sans
## "turn" wording, timer ring, held/next previews, LOCKED state) at
## `slot_id` without implying anyone is "taking a turn". Called from
## Events.turn_changed outside hot-seat (net/MatchNet.gd already substitutes
## the local slot into that signal there) and from game/Sandbox.gd whenever
## its debug hotkey cycles which slot it is driving.
func set_local_slot(slot_id: int) -> void:
	_active_slot = slot_id
	_active_color = _color_for_slot(slot_id)
	var eliminated: bool = _is_slot_eliminated(slot_id)
	var display_name: String = _name_for_slot(slot_id)
	_turn_label.text = "%s — eliminated" % display_name if eliminated else display_name
	_turn_label.modulate = ELIMINATED_COLOR if eliminated else _active_color
	_timer_ring.queue_redraw()
	_shape_preview.queue_redraw()
	_next_shape_preview.queue_redraw()


func set_held_shape(shape: BlockShape) -> void:
	_held_shape = shape
	_shape_preview.queue_redraw()


func set_next_shape(shape: BlockShape) -> void:
	_next_shape = shape
	_next_shape_preview.queue_redraw()


## Spec 2.4/2.5's release-locked state (Match.is_release_locked): the held
## piece may be aimed but not released again until the interval boundary.
## Greys the ring out and shows the LOCKED label; a no-op call when nothing
## changed, matching set_capture's shape.
func set_locked(locked: bool) -> void:
	if _locked == locked:
		return
	_locked = locked
	_locked_label.visible = locked
	_timer_ring.queue_redraw()


## fraction runs 1 -> 0 as the slot's block timer counts down; drives the
## timer ring's radial fill.
func set_feed_progress(fraction: float) -> void:
	_feed_progress = clampf(fraction, 0.0, 1.0)
	_timer_ring.queue_redraw()


func set_height(meters: float) -> void:
	_height_label.text = "Height: %.2f m" % meters


## Bontago-mv0.35 (owner: "there is still a maximum height the block cannot
## be raised"): the old single "Height" readout is the slot's tallest
## *placed* structure (Match.max_height_for_slot()), which does not move
## while the held block is wheeled up -- and the follow camera keeps the
## ghost fixed at screen centre -- so raising looked capped. While a local
## block is held the label names both numbers explicitly.
func set_tower_and_block_height(tower_meters: float, block_meters: float) -> void:
	_height_label.text = "Tower: %.2f m   Block: %.1f m" % [tower_meters, block_meters]


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


## Bontago-d04: the local player's own claim feedback beside the pending-
## special indicator (_refresh_special_indicator() above) -- same fade shape
## as show_reject() (a hold, then a fade), but its own durations
## (GiftConfig.claim_toast_visible_duration_s/claim_toast_fade_duration_s)
## since a claim toast and a rejection message read very differently and
## shouldn't be forced to share one timing.
func show_gift_toast(special_id: StringName) -> void:
	_gift_toast_label.text = "Special queued: %s" % _special_display_name(special_id)
	_gift_toast_label.modulate = Color(_active_color.r, _active_color.g, _active_color.b, 1.0)
	if _gift_toast_tween != null and _gift_toast_tween.is_valid():
		_gift_toast_tween.kill()
	_gift_toast_tween = create_tween()
	_gift_toast_tween.tween_interval(gift_config.claim_toast_visible_duration_s)
	_gift_toast_tween.tween_property(_gift_toast_label, ^"modulate:a", 0.0, gift_config.claim_toast_fade_duration_s)


# --- Events reactions --------------------------------------------------------

## Bontago-mv0.9: in hot-seat this really is a turn changing hands
## (Match.advance_turn()); outside hot-seat net/MatchNet.gd's own
## EVENT_TURN_CHANGED handler already substitutes this instance's local slot
## before re-emitting the signal (see its DECISION), so either way `slot_id`
## is exactly the slot this HUD should now read — the gate below only picks
## which wording it shows.
func _on_turn_changed(slot_id: int) -> void:
	if _hot_seat_active():
		set_active_slot(slot_id, _color_for_slot(slot_id))
	else:
		set_local_slot(slot_id)


func _on_feed_block_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName) -> void:
	if slot_id != _active_slot:
		return
	set_held_shape(_shapes_by_id.get(shape_id) as BlockShape)
	set_next_shape(_shapes_by_id.get(next_shape_id) as BlockShape)


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	# DECISION (ui/HUD.gd): one HUD instance shows exactly one slot's status
	# — whoever's turn it is in hot-seat, or the local slot otherwise (see
	# the class doc comment) — so every rejection for any other slot is
	# silently ignored here. A per-viewer HUD for simultaneous multiplayer is
	# already what _active_slot picks out; nothing else changes.
	if slot_id != _active_slot:
		return
	show_reject(reason)


func _on_territory_share_changed(shares: PackedFloat32Array) -> void:
	set_territory_shares(shares)


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	set_capture(team_id, progress, _color_for_slot(team_id) if team_id >= 0 else Color.WHITE)


func _on_match_won(team_id: int) -> void:
	show_winner(team_id, _color_for_slot(team_id))


## The status label already reads home_flag_alive, but it is only rebuilt on
## turn_changed/set_local_slot, so an elimination that lands in between would
## sit invisible until the next one. Repainting it here is the whole
## reaction, through whichever of the two the hot-seat gate currently picks.
func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	if slot_id != _active_slot:
		return
	if _hot_seat_active():
		set_active_slot(_active_slot, _active_color)
	else:
		set_local_slot(_active_slot)


## Bontago-1en.16: an instant refresh for the local slot the moment it claims
## a crate, rather than waiting up to one frame for _process()'s poll below.
## _refresh_special_indicator() re-reads Match itself (not the signal's own
## special_id) so this handler and the per-frame poll can never disagree about
## what the queue currently holds.
func _on_gift_claimed(_gift_id: int, slot_id: int, special_id: StringName) -> void:
	if slot_id != _active_slot:
		return
	_refresh_special_indicator()
	show_gift_toast(special_id)


# --- Helpers -----------------------------------------------------------------

## Bontago-mv0.9: whether Events.turn_changed still means "it is this slot's
## turn" (set_active_slot(), "Player N's turn" wording) rather than "this is
## the local slot" (set_local_slot(), no turn wording). config == null (no
## match built yet, or a bare HUD-only test with no FakeMatch.config set)
## behaves like real-time play, matching every other read of Match.config
## elsewhere in this file (_color_for_slot, _is_slot_eliminated).
func _hot_seat_active() -> bool:
	if match_provider == null:
		return false
	var running_config: Variant = match_provider.config
	return running_config != null and bool(running_config.hot_seat)


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


## Bontago-mv0.9: PlayerSlot.display_name when Match has built one, otherwise
## the same "Player N" fallback set_active_slot always used — pre-match (no
## slots exist yet) and in a bare HUD-only test with no FakeMatch.slots_by_id
## entry.
func _name_for_slot(slot_id: int) -> String:
	if match_provider != null:
		var slot: PlayerSlot = match_provider.slot(slot_id)
		if slot != null and not slot.display_name.is_empty():
			return slot.display_name
	return "Player %d" % (slot_id + 1)


## Bontago-1en.16 (docs/M4_P2_PACKAGES.md P2b-ii): the pending-special queue
## indicator, next to the next-shape preview. Reads `_active_slot` the exact
## same way the previews do (set_active_slot/set_local_slot both drive it, so
## this follows hot-seat's acting slot or the local slot outside hot-seat,
## whichever _active_slot currently is) rather than tracking a slot of its
## own. No dedicated "a special was consumed at spawn" signal exists yet
## (P2c, not landed on this branch) so, like set_feed_progress/set_height/
## set_locked above, _process() polls it every frame; _on_gift_claimed()
## above only shortcuts the wait for the specific claim case.
func _refresh_special_indicator() -> void:
	if match_provider == null or _active_slot < 0:
		_special_indicator.visible = false
		return
	var count: int = int(match_provider.pending_special_count(_active_slot))
	if count <= 0:
		_special_indicator.visible = false
		return
	var head_id: StringName = match_provider.held_special(_active_slot)
	_special_indicator.text = _special_display_text(head_id, count)
	_special_indicator.modulate = _active_color
	_special_indicator.visible = true


## "Special ×N" once a second one is queued (N > 1); just the head id's
## display name otherwise (decision: matches the next-shape preview, which
## also never shows a bare count for a single item).
func _special_display_text(head_id: StringName, count: int) -> String:
	var display_name: String = _special_display_name(head_id)
	if count > 1:
		return "%s ×%d" % [display_name, count]
	return display_name


## MatchGifts.PENDING_SPECIAL_ID is the placeholder every claim draws until
## P2c installs the real weighted SpecialDef pick (autoload/match/
## MatchGifts.gd's own DECISION) -- shown as the generic "Special" rather than
## its literal id ("special_pending".capitalize() would misleadingly read
## "Special Pending"). A real special's id is shown as its own
## String.capitalize() (snake_case -> Title Case), e.g. "jumping_bean" ->
## "Jumping Bean" -- placeholder art only, M7 replaces this with real icons.
func _special_display_name(head_id: StringName) -> String:
	if head_id == MatchGifts.PENDING_SPECIAL_ID or head_id == &"":
		return "Special"
	return String(head_id).capitalize()


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
		# Bontago-mv0.9: greys out while release-locked (spec 2.4/2.5) instead
		# of the active player's colour, so "the interval hasn't come around
		# again yet" reads distinctly from "counting down normally".
		var ring_color: Color = LOCKED_COLOR if _locked else _active_color
		_timer_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _feed_progress, 48, ring_color, RING_LINE_WIDTH
		)


## Draws `shape`'s cells centered in `control`, tinted `color`. Shared by the
## held-block preview (inside the timer ring) and the next-block preview
## (beside it) so the two can never draw differently by accident.
func _draw_shape_preview(control: Control, shape: BlockShape, color: Color) -> void:
	if shape == null:
		return
	var center: Vector2 = control.size * 0.5
	# DECISION (ui/HUD.gd): projects each cube's (x, y) offset — a front
	# elevation — rather than the top-down (x, z) footprint, so tall shapes
	# (bar4, pillar) read as tall in the small preview instead of collapsing
	# to a single square; flat shapes that only vary in (x, z) (square4,
	# slab6) collapse to one row here, a fair trade for a placeholder icon.
	for cell: Vector3i in shape.cells:
		var pos: Vector2 = center + Vector2(cell.x, -cell.y) * PREVIEW_CELL_PX - Vector2.ONE * PREVIEW_CELL_PX * 0.5
		var rect: Rect2 = Rect2(pos, Vector2.ONE * PREVIEW_CELL_PX * PREVIEW_CELL_MARGIN)
		control.draw_rect(rect, color)


func _on_shape_preview_draw() -> void:
	_draw_shape_preview(_shape_preview, _held_shape, _active_color)


func _on_next_shape_preview_draw() -> void:
	# Bontago-mv0.9: drawn at reduced opacity so the held preview (inside the
	# timer ring, full colour) reads as "current" and this one as "up next".
	var next_color: Color = _active_color
	next_color.a *= 0.6
	_draw_shape_preview(_next_shape_preview, _next_shape, next_color)


func _on_capture_ring_draw() -> void:
	var size: Vector2 = _capture_ring.size
	var radius: float = minf(size.x, size.y) * 0.5 - RING_LINE_WIDTH
	var center: Vector2 = size * 0.5
	_capture_ring.draw_arc(center, radius, 0.0, TAU, 48, RING_BACKGROUND_COLOR, RING_LINE_WIDTH)
	if _capture_progress > 0.0:
		_capture_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _capture_progress, 48, _capture_color, RING_LINE_WIDTH
		)
