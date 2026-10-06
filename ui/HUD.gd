class_name HUD
extends CanvasLayer
## Spec 2.10's HUD, scoped to what M2/Bontago-mv0.9 need: a timer ring around
## the held-block preview, a separate next-block preview, max height,
## per-player territory share, capture ring, a greyed locked ring, and a
## hot-seat turn indicator. Bontago-1en.16 (M4 P2b-ii) adds a small pending-
## special queue indicator beside the next-shape preview. M7 P5 adds the
## live minimap (ui/Minimap.gd); Bontago-mp0.3.3 restyles the whole HUD
## toward docs/art_mockups/08-cel-shaded-home-beacons.png (per-player
## diamond+bar rows top-left, a numeral in the timer ring top-center, a
## circular minimap bottom-right) and rebuilds the minimap as a 2D draw off
## the live TerritoryRaster instead of a 3D camera (see ui/Minimap.gd's own
## class doc for why). Bontago-1pi.5 (owner playtest: "Held/next previews
## should be grouped and moved to the bottom left corner") moves the
## held-shape and next-shape cards off the top edge into one grouped
## %HeldNextPanel in the bottom-left corner (clear of both the top-left
## per-player cluster and the bottom-right minimap). Bontago-35f replaces
## the procedural cube drawing with pre-rendered actual mesh thumbnails.
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


## Bontago-mp0.3.3 (owner review 2026-09-26: "bar ~22-25% of screen width"):
## 300px is 23.4% of the 1280px reference width tools/capture_mockup08.tscn
## and every other fixed HUD offset in this file already assume.
const SHARE_BAR_MAX_WIDTH: float = 200.0
const SHARE_BAR_HEIGHT: float = 14.0
## Bontago-mp0.3.3 (owner review 2026-09-26: "thicker ring (~8 px)").
const RING_LINE_WIDTH: float = 8.0
const RING_BACKGROUND_COLOR: Color = Color(1.0, 1.0, 1.0, 0.15)
## Bontago-mp0.3.3: the bold numeral drawn in the middle of the timer ring
## (mockup 08's "6"), pure screen-space geometry like every other constant in
## this section (this file's own pre-M7 DECISION above). Owner review
## 2026-09-26 grew the ring itself to ~84-96px; the numeral grows with it.
const TIMER_NUMERAL_FONT_SIZE: int = 34
## Bontago-mp0.3.3 (owner review 2026-09-26: "subtle drop shadow"), shared by
## the timer ring's disc.
const DROP_SHADOW_OFFSET: Vector2 = Vector2(2.0, 3.0)
const DROP_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.35)
const ELIMINATED_COLOR: Color = Color(0.4, 0.4, 0.4, 0.5)
## Locked but still playing must remain distinct from eliminated.
const LOCKED_COLOR: Color = Color(0.75, 0.75, 0.75, 0.9)
@export var ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
## Bontago-d04: durations for the "Special queued: <name>" claim toast below
## (see config/GiftConfig.gd's own "-- Claim feedback --" section for why
## these live there rather than in ghost_tuning above).
@export var gift_config: GiftConfig = preload("res://config/gift_config.tres")
## The action whose bound glyph the gift slot card shows (PlayerController spends the slot on it).
const GIFT_SLOT_ACTION: StringName = &"use_gift_slot"
const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")
## Gap between the gift card's border and its icon/glyph (screen-space geometry, see the DECISION above).
const GIFT_CARD_INSET_PX: float = 6.0
const GIFT_CARD_ICON_GLYPH_GAP_PX: float = 2.0
## Fallback player colours for a slot Match cannot name — before a match
## starts, or in a HUD-only test with no Match behind it. An @export var
## rather than a const: a const's value has to resolve while the script is
## still being parsed, and the editor parses HUD.gd (through Main -> HotSeat)
## before it can load a .tres whose script is MatchConfig, which made the
## constant null and the parse fail.
@export var default_palette: MatchConfig = preload("res://config/match_defaults.tres")
## M7 P5 (docs/M7_PLAN.md): the minimap's camera framing and the reskinned
## panels' colours — see config/HUDVisualTuning.gd's own class doc for why
## this is the one Resource this file adds (everything else here stays the
## pre-M7 "pure screen-space geometry is inline" DECISION above).
@export var hud_visual_tuning: HUDVisualTuning = preload("res://config/hud_visual_tuning.tres")
## DECISION (ui/HUD.gd): a Variant test seam for the same reason
## PlayerController has one — GUT can't double a plain autoload, and P2's
## real Match hasn't landed on this branch yet. Defaults to the real
## autoload; tests overwrite it with a fake after add_child().
var match_provider: Variant = null
## Bontago-1pi.49: where a human seat's replicated name comes from, anything
## answering name_for_slot(slot_id) -> String. Null means the real Net autoload.
var name_provider: Variant = null

@onready var _turn_label: Label = %TurnLabel
@onready var _timer_ring: Control = %TimerRing
@onready var _shape_preview: Control = %ShapePreview
@onready var _next_shape_preview: Control = %NextShapePreview
@onready var _next_label: Label = $HeldNextPanel/HeldNextRow/NextColumn/NextLabel
@onready var _held_label: Label = $HeldNextPanel/HeldNextRow/HeldColumn/HeldLabel
@onready var _special_indicator: Label = %SpecialIndicator
@onready var _height_label: Label = %HeightLabel
@onready var _shares_box: VBoxContainer = %SharesBox
@onready var _status_pill: VBoxContainer = %StatusPill
@onready var _capture_ring: Control = %CaptureRing
@onready var _reject_label: Label = %RejectLabel
## Bontago-mp0.124: feedback pictograms (config/hud_feedback_icon_table.tres)
## beside held height, the capture ring and the reject/relocated message.
@onready var _capture_icon: TextureRect = %CaptureIcon
@onready var _reject_icon: TextureRect = %RejectIcon
@export var feedback_icons: HudFeedbackIconTable = preload("res://config/hud_feedback_icon_table.tres")
@onready var _winner_label: Label = %WinnerLabel
@onready var _gift_toast_label: Label = %GiftToastLabel
## Bontago-mp0.3.3 (mockup 08 restyle): the next-shape card's own backing
## panel, and the live minimap. Added as new HUD.tscn nodes; every
## pre-existing %UniqueName above keeps the exact same path it always had.
## The M7 P5 status/shares boxy backing panels (StatusPanel/SharesPanel) are
## gone -- feedback/graphics_feedback.md + Bontago-mp0.2 ("top-left HUD
## unreadable"): mockup 08 has no panel behind the top-left readouts at all,
## just outlined text and slim bars (see _apply_text_outline() below).
@onready var _next_shape_card: Panel = %NextShapeCard
## Bontago-mp0.3.3 (owner review 2026-09-27): the held-shape icon's own
## labeled card, styled the same as _next_shape_card -- previously an
## unlabeled flat icon floating loose beside the timer ring, which the
## review correctly read as a stray leftover glyph.
@onready var _held_shape_card: Panel = %HeldShapeCard
## Bontago-1pi.5 (owner playtest: "Held/next previews should be grouped and
## moved to the bottom left corner"): the outer frame around both
## %HeldShapeCard and %NextShapeCard (ui/HUD.tscn's HeldNextRow), styled the
## same as those two inner cards so the group reads as one panel rather than
## two loose cards -- DECISION: keeps the inner cards' own borders too
## (nested, not replaced) rather than stripping their styling now that
## they're grouped, since a Panel with no stylebox override at all would fall
## back to the engine's default gray theme box, which reads worse than a
## slightly nested double border in the same palette.
@onready var _held_next_panel: Panel = %HeldNextPanel
@onready var _minimap: Minimap = %Minimap
@onready var _top_left_backplate: Panel = %TopLeftBackplate
@onready var _top_left_cluster: VBoxContainer = $TopLeftCluster

var _shapes_by_id: Dictionary = {}
## Placeholder id for a queued gift whose def id is unknown (icon falls back).
const GENERIC_GIFT_ID: StringName = &"gift"
var _preview_textures: Dictionary[StringName, Texture2D] = {}
## Whichever slot this HUD's widgets currently read: the hot-seat active
## slot, or (outside hot-seat) the local player's slot. See the class
## doc comment above.
var _active_slot: int = -1
var _active_color: Color = Color.WHITE
## Timer numeral shown while a QoL experiment has the block timer paused.
const QOL_PAUSED_TEXT: String = "||"
var _feed_progress: float = 1.0
## Bontago-1pi.18.1 (QoL experiments): queued-block count and "timer paused"
## flag for the active slot; both stay 0/false unless an experiment is on.
var _qol_backlog: int = 0
var _qol_paused: bool = false
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
## Bontago-1pi.68: the ellipsized player-name label of each row, parallel to _share_labels
## (which now holds only the mode-specific value text).
var _share_name_labels: Array = []
## Last values fed to the rows, so a mode-state or roster change can repaint them.
var _last_shares: PackedFloat32Array = PackedFloat32Array()
var _mode_state: Dictionary = {}
## Bontago-mp0.3.3: the small team-colored diamond glyph drawn beside each
## player's share bar (mockup 08), parallel to _share_rows/_share_bars/
## _share_labels above.
var _share_glyphs: Array = []
## Seconds left on the active slot's block timer, drawn as the bold numeral
## inside the timer ring (mockup 08's "6"). -1 until the first _process()
## poll (or a test's direct set_feed_seconds() call) has a real value, so a
## bare HUD-only instance draws no numeral at all.
var _feed_seconds_left: float = -1.0
## M7 P5: last MapDef pushed to the minimap, so repeated territory_share_changed
## ticks (every placement) don't re-frame its camera when the map hasn't
## actually changed.
var _last_map_def: MapDef = null
## Bontago-1pi.11.6: change-gates for the per-frame _process() polls.
var _last_gift_states: Array[Dictionary] = []
var _last_height_text: String = ""
var _last_special_signature: Array = []
## Bontago-22y.7: live per-team score line for timed modes (Capture the Flag),
## built in code under the status pill so HUD.tscn and classic stay unchanged.
var _mode_score_label: Label = null
## Bontago-mp0.27: big centred 3-2-1 label, built in code (no scene edit).
## Driven by the host's replicated countdown (Match.countdown_remaining()),
## never by a local timer, so clients stay in step with the host.
var _countdown_label: Label = null
var _countdown_was_active: bool = false
var _go_left_s: float = 0.0

## Bontago-1pi.18.2 (QoL gift slot): a third card beside HELD/NEXT, built in
## code and shown only while the experiment has a gift waiting. Styled with the
## same helpers as the HELD/NEXT cards.
var _gift_slot_column: VBoxContainer = null
var _gift_slot_label: Label = null
var _gift_slot_preview: Control = null
var _gift_slot_id: StringName = &""
var _gift_slot_panel_base_right: float = 0.0
## Space the extra column adds to the HELD/NEXT panel (card width plus row separation).
var _gift_slot_extra_width: float = 0.0
## Bontago-1pi.18.7: the use_gift_slot binding drawn along the card's bottom edge
## (one InputGlyph for the active device family) and what it was built from.
var _gift_slot_glyph_row: HBoxContainer = null
var _gift_slot_glyph: InputGlyph = null
var _gift_slot_glyph_signature: String = ""



func _ready() -> void:
	match_provider = Match
	_shapes_by_id = _load_shapes_by_id()
	_timer_ring.draw.connect(_on_timer_ring_draw)
	_shape_preview.draw.connect(_on_shape_preview_draw)
	_next_shape_preview.draw.connect(_on_next_shape_preview_draw)
	_capture_ring.draw.connect(_on_capture_ring_draw)
	_reject_label.modulate.a = 0.0
	_setup_feedback_icons()
	_gift_toast_label.modulate.a = 0.0
	_winner_label.visible = false
	_capture_ring.visible = false
	_special_indicator.visible = false

	# Bontago-mp0.3.3 (mockup 08 restyle): no boxy panel behind the top-left
	# readouts (feedback/graphics_feedback.md, Bontago-mp0.2) -- every label
	# there gets a soft outline instead, so it stays legible directly over a
	# bright sky. The next-shape and held-shape cards are the readouts that
	# do keep a backing panel (see _style_panel()'s own doc).
	# DECISION: persistent readouts share one cream/ink card family;
	# team color is reserved for the share fill, glyph and countdown arc.
	_style_panel(_top_left_backplate)
	_style_panel(_held_next_panel)
	_style_panel(_next_shape_card, true)
	_style_panel(_held_shape_card, true)
	_build_gift_slot_column()
	# Bontago-1pi.68 (owner playtest 2026-10-04): the status pill keeps only the
	# locked/special/toast rows; the name header, tower/block line and
	# experiments line are gone from the HUD.
	_turn_label.visible = false
	_height_label.visible = false
	for label: Label in [
		_turn_label, _height_label, _special_indicator,
		_gift_toast_label, _reject_label,
	]:
		label.add_theme_color_override("font_color", hud_visual_tuning.ink_color)
	_height_label.add_theme_color_override("font_color", hud_visual_tuning.muted_ink_color)
	_held_label.add_theme_color_override("font_color", hud_visual_tuning.muted_ink_color)
	_next_label.add_theme_color_override("font_color", hud_visual_tuning.muted_ink_color)
	for outlined: Label in [_turn_label, _height_label, _special_indicator, _gift_toast_label, _held_label, _next_label]:
		_apply_text_outline(outlined)
	# Bontago-mp0.3.3 (owner review 2026-09-26: "row gap ~12 px"). The status
	# labels above sit in %StatusPill, a VBoxContainer nested right under
	# %SharesBox inside their shared %TopLeftCluster (ui/HUD.tscn) -- both
	# stack directly under however many player rows currently exist, so
	# nothing here floats independent of row count (the earlier "orphaned
	# mid-left text" bug).
	_shares_box.add_theme_constant_override("separation", 12)
	_top_left_cluster.resized.connect(_resize_top_left_backplate)
	_resize_top_left_backplate()

	_build_countdown_label()
	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	Events.territory_share_changed.connect(_on_territory_share_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.mode_state_changed.connect(_on_mode_state_changed)
	Events.match_results_ready.connect(_on_match_results_ready)
	Events.match_won.connect(_on_match_won)
	Events.match_state_changed.connect(_on_match_state_changed_glue)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.gift_flight_spawned.connect(_on_gift_state_changed)
	Events.gift_landed.connect(_on_gift_state_changed)
	Events.gift_expired.connect(_on_gift_state_changed)
	Events.input_device_changed.connect(_on_input_device_changed)


func _build_countdown_label() -> void:
	_countdown_label = Label.new()
	_countdown_label.name = "CountdownLabel"
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.add_theme_font_size_override("font_size", hud_visual_tuning.countdown_font_size)
	_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_countdown_label.add_theme_color_override("font_outline_color", hud_visual_tuning.countdown_outline_color)
	_countdown_label.add_theme_constant_override("outline_size", hud_visual_tuning.countdown_font_size / maxi(hud_visual_tuning.countdown_outline_divisor, 1))
	_countdown_label.visible = false
	add_child(_countdown_label)


## Whole seconds of the host's countdown left, or 0 outside it. A provider
## without the method (tests' FakeMatch) means no countdown.
func _countdown_seconds_left() -> int:
	if match_provider == null or not match_provider.has_method(&"countdown_remaining"):
		return 0
	return int(ceil(float(match_provider.countdown_remaining())))


func _update_countdown_label(delta: float) -> void:
	var left: int = _countdown_seconds_left()
	if left > 0:
		_countdown_was_active = true
		_go_left_s = 0.0
		_countdown_label.text = str(left)
		_countdown_label.visible = true
		return
	if _countdown_was_active:
		_countdown_was_active = false
		# Only a countdown that ran into PLAYING says Go; an abort just hides.
		if match_provider.has_method(&"state") and int(match_provider.state()) != MatchAutoload.State.PLAYING:
			_countdown_label.visible = false
			return
		_go_left_s = hud_visual_tuning.countdown_go_hold_s
		_countdown_label.text = hud_visual_tuning.countdown_go_text
		_countdown_label.visible = true
		return
	if _go_left_s > 0.0:
		_go_left_s -= delta
	if _go_left_s <= 0.0:
		_countdown_label.visible = false


func _process(delta: float) -> void:
	_update_countdown_label(delta)
	# Bontago-mp0.3.3 (owner review 2026-09-26: "the minimap must match what
	# the player sees -- rotate it with the camera yaw"). DECISION (ui/HUD.gd):
	# reads Viewport.get_camera_3d() (whichever Camera3D currently has
	# `current = true`) rather than a node path into game/CameraRig.gd or a
	# new Events signal -- this package owns ui/HUD.gd and ui/Minimap.gd only,
	# not game/CameraRig.gd or autoload/Events.gd (see the assignment's file
	# ownership), and Viewport.get_camera_3d() is a generic engine query, not
	# a hardcoded path into Main.tscn's node tree, so it does not reintroduce
	# the deep-node-path pattern the class doc's "connects to Events only"
	# DECISION warns against. Runs unconditionally (before the active-slot
	# gate below) so the minimap keeps tracking the camera even between
	# active-slot changes; a null camera (tests, no 3D scene) leaves
	# Minimap's basis at whatever it last was (its own no-op guard).
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var basis: Basis = camera.global_transform.basis
		var forward: Vector3 = -basis.z
		var right: Vector3 = basis.x
		_minimap.set_camera_basis(Vector2(right.x, right.z), Vector2(forward.x, forward.z))
	_update_gift_markers()
	if match_provider == null or _active_slot < 0:
		return
	set_feed_progress(match_provider.feed_progress(_active_slot))
	if match_provider.has_method(&"qol_backlog_count"):
		var paused_now: bool = bool(match_provider.qol_timer_paused(_active_slot))
		if paused_now != _qol_paused:
			_qol_paused = paused_now
			_timer_ring.queue_redraw()
		_qol_backlog = int(match_provider.qol_backlog_count(_active_slot))
	# Bontago-mp0.3.3: the timer ring's numeral (mockup 08's "6"). Guarded by
	# has_method() the same way _update_minimap()'s raster() read is --
	# tests/unit/support/FakeMatch.gd (and any other Variant double) has no
	# feed_time_left(), and a bare HUD-only instance should draw no numeral
	# at all rather than error.
	if match_provider.has_method(&"feed_time_left"):
		set_feed_seconds(float(match_provider.feed_time_left(_active_slot)))
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
	# DECISION (Bontago-1pi.68): the name header is gone except in hot-seat, where
	# the "<name>'s turn" banner is the only turn indicator there is.
	_turn_label.visible = true
	_pull_current_shapes(slot_id)
	_refresh_special_indicator()
	_timer_ring.queue_redraw()
	_shape_preview.queue_redraw()


## Real-time play and sandbox: points every per-slot widget (turn label sans
## "turn" wording, timer ring, held/next previews, locked state) at
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
	_turn_label.visible = false
	_pull_current_shapes(slot_id)
	_refresh_special_indicator()
	_timer_ring.queue_redraw()
	_shape_preview.queue_redraw()
	_next_shape_preview.queue_redraw()


## Bontago-mp0.3.3 (owner review 2026-09-26: "It must show the actual
## upcoming/held block for the local player ... If it's genuinely empty at
## capture time in sandbox, find out why"). ROOT CAUSE: the held/next
## previews previously only ever updated from Events.feed_block_issued
## (_on_feed_block_issued() below), which fires once, the moment Match first
## feeds a slot -- almost always *before* this HUD instance's set_local_slot/
## set_active_slot ever runs (game/Sandbox.gd/net/MatchNet.gd wire the local
## slot in only after Match.start_match() has already fed it), so the signal
## this HUD needed had already fired and gone by the time anyone was
## listening for it: `_held_shape`/`_next_shape` stayed at their `null`
## default for the rest of the match. Calling this from both set_active_slot()
## and set_local_slot() pulls whatever `match_provider` is holding for
## `slot_id` *right now*, independent of signal timing, and every later
## Events.feed_block_issued tick still keeps it current as before.
func _pull_current_shapes(slot_id: int) -> void:
	if match_provider == null:
		return
	set_held_shape(match_provider.held_shape(slot_id))
	set_next_shape(match_provider.next_shape(slot_id))


func set_held_shape(shape: BlockShape) -> void:
	_held_shape = shape
	_shape_preview.queue_redraw()


func set_next_shape(shape: BlockShape) -> void:
	_next_shape = shape
	_next_shape_preview.queue_redraw()


## Spec 2.4/2.5's release-locked state (Match.is_release_locked): the held
## piece may be aimed but not released again until the interval boundary.
## Greys the ring out (Bontago-1pi.92: no LOCKED text, owner 2026-10-06 "locked
## text still exists, get rid of it"); a no-op call when nothing changed,
## matching set_capture's shape.
func set_locked(locked: bool) -> void:
	if _locked == locked:
		return
	_locked = locked
	_timer_ring.queue_redraw()


## fraction runs 1 -> 0 as the slot's block timer counts down; drives the
## timer ring's radial fill.
func set_feed_progress(fraction: float) -> void:
	var clamped: float = clampf(fraction, 0.0, 1.0)
	if is_equal_approx(clamped, _feed_progress):
		return
	_feed_progress = clamped
	_timer_ring.queue_redraw()


## Bontago-mp0.3.3: seconds left on the block timer, shown as the bold
## numeral inside the timer ring (mockup 08's "6"). A negative value (the
## -1.0 default, or a caller's own choice) draws no numeral at all.
func set_feed_seconds(seconds: float) -> void:
	if is_equal_approx(seconds, _feed_seconds_left):
		return
	_feed_seconds_left = seconds
	_timer_ring.queue_redraw()


## Bontago-mp0.124: sizes the three pictograms from the table. The held-height
## icon only shows while a block is held (set_tower_and_block_height); the reject
## icon sits centred above the message and is hidden until a message plays.
func _setup_feedback_icons() -> void:
	var px: float = float(feedback_icons.icon_px)
	# DECISION (Bontago-1pi.80): the held-height icon is gone from the HUD; with the
	# height text hidden it was a label-less icon that carried no information.
	_capture_icon.texture = feedback_icons.icon_for(HudFeedbackIconTable.Feedback.CAPTURE)
	_capture_icon.offset_left = -px * 0.5
	_capture_icon.offset_right = px * 0.5
	_capture_icon.offset_top = -px * 0.5
	_capture_icon.offset_bottom = px * 0.5
	_reject_icon.offset_left = -px * 0.5
	_reject_icon.offset_right = px * 0.5
	_reject_icon.offset_bottom = _reject_label.offset_top
	_reject_icon.offset_top = _reject_label.offset_top - px
	_reject_icon.modulate.a = 0.0


## Shows `feedback`'s pictogram with the message and fades it with the label.
func _play_reject_icon(feedback: HudFeedbackIconTable.Feedback, fade_s: float) -> void:
	_reject_icon.texture = feedback_icons.icon_for(feedback)
	_reject_icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_reject_tween.parallel().tween_property(_reject_icon, ^"modulate:a", 0.0, fade_s)


func set_height(meters: float) -> void:
	_set_height_text("Height: %.2f m" % meters)


## Bontago-mv0.35 (owner: "there is still a maximum height the block cannot
## be raised"): the old single "Height" readout is the slot's tallest
## *placed* structure (Match.max_height_for_slot()), which does not move
## while the held block is wheeled up -- and the follow camera keeps the
## ghost fixed at screen centre -- so raising looked capped. While a local
## block is held the label names both numbers explicitly.
func set_tower_and_block_height(tower_meters: float, block_meters: float) -> void:
	_set_height_text("Tower: %.2f m   Block: %.1f m" % [tower_meters, block_meters])


## Bontago-1pi.11.6: only touches the Label (which re-lays out text) on change.
func _set_height_text(text: String) -> void:
	if text == _last_height_text:
		return
	_last_height_text = text
	_height_label.text = text


func set_territory_shares(shares: PackedFloat32Array) -> void:
	_last_shares = shares
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
	# DECISION (ui/HUD.gd, Bontago-xtq.23): explicit full-white modulate, not
	# just the alpha channel show_reject() alone used to touch -- show_relocated()
	# below tints this same label a distinct colour, and without resetting the
	# whole modulate here a reject message right after a relocated one would
	# stay tinted instead of reading as its own, distinct message.
	_reject_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_tween = create_tween()
	_reject_tween.tween_interval(ghost_tuning.hud_reject_message_duration)
	_reject_tween.tween_property(_reject_label, ^"modulate:a", 0.0, ghost_tuning.hud_reject_fade_duration)
	_play_reject_icon(HudFeedbackIconTable.Feedback.REJECTED, ghost_tuning.hud_reject_fade_duration)


## Bontago-xtq.23 (owner playtest 2026-09-24, "if I'm hovering over another
## player's area I get the rejected message but the block still drops more or
## less in place"): a manual click over enemy territory is correctly refused
## (show_reject() above, nothing spawns) -- the "drops more or less in place"
## half of the report is a *separate*, later event: the interval boundary
## still auto-drops that same held piece, and PlacementRules.
## closest_valid_point() relocates it into the player's own territory, often
## only a couple of metres from the spot they were just refused at. Until now
## nothing distinguished that forced auto-drop from silence, so it read as
## "the rejected placement still happened". Reuses show_reject()'s own label/
## tween shape (hold, then fade) but its own wording, colour (the same bluish-
## white as GhostTuning.auto_drop_flash_color, tying it visually to the
## auto-drop flash game/GhostPreview.play_auto_drop_flash() already plays for
## this same event) and durations (hud_relocated_message_duration/
## hud_relocated_fade_duration), so tuning the reject message never silently
## detunes this one.
func show_relocated() -> void:
	_reject_label.text = "Relocated into your territory"
	var tint: Color = ghost_tuning.auto_drop_flash_color
	_reject_label.modulate = Color(tint.r, tint.g, tint.b, 1.0)
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_tween = create_tween()
	_reject_tween.tween_interval(ghost_tuning.hud_relocated_message_duration)
	_reject_tween.tween_property(_reject_label, ^"modulate:a", 0.0, ghost_tuning.hud_relocated_fade_duration)
	_play_reject_icon(HudFeedbackIconTable.Feedback.RELOCATED, ghost_tuning.hud_relocated_fade_duration)


## DECISION (ui/HUD.gd, Bontago-1pi.5): a separate results screen (built
## elsewhere) now owns the "who won" announcement, so this in-HUD banner must
## no longer appear. Keeps computing/storing the text and tint (harmless, and
## a cheap seam for a future results-screen consumer that might want to read
## %WinnerLabel's text instead of duplicating this formatting) but no longer
## flips `visible` -- Events.match_won -> _on_match_won() -> show_winner()
## still fires every time exactly as before, it just no longer has any
## on-screen effect. %WinnerLabel itself is left in ui/HUD.tscn rather than
## deleted so a future revert or the results-screen work doesn't need to
## re-add the node.
func show_winner(team_id: int, color: Color) -> void:
	_winner_label.text = "Team %d wins!" % _team_number(team_id)
	_winner_label.modulate = color
	_winner_label.visible = false


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
	_refresh_special_indicator()


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	# DECISION (ui/HUD.gd): one HUD instance shows exactly one slot's status
	# — whoever's turn it is in hot-seat, or the local slot otherwise (see
	# the class doc comment) — so every rejection for any other slot is
	# silently ignored here. A per-viewer HUD for simultaneous multiplayer is
	# already what _active_slot picks out; nothing else changes.
	if slot_id != _active_slot:
		return
	show_reject(reason)


## Bontago-xtq.23: same per-viewer-HUD filter as _on_placement_rejected() above
## -- every other slot's own relocation is none of this instance's business.
## `point` (the disk-local landing spot) is not shown; the message text alone
## already says everything this placeholder HUD needs to (M7 owns richer art).
func _on_placement_relocated(slot_id: int, _point: Vector2) -> void:
	if slot_id != _active_slot:
		return
	show_relocated()


func _on_territory_share_changed(shares: PackedFloat32Array) -> void:
	set_territory_shares(shares)
	_update_minimap()


## Pure formatting of a replicated mode state: "1: 3.5  2: 1.0   2:05", or ""
## when the state has no scores. Static so tests need no scene.
##
## Lobby rework (Bontago-1pi.53): `team_numbers` is MatchConfig.team_numbers of a
## match whose lobby teams were host-resolved (dense team id -> the number the
## team had in the lobby); empty = the legacy "team id + 1" label.
static func mode_score_text(state: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var scores: Array = state.get("scores", []) as Array
	if scores.is_empty():
		return ""
	if int(state.get("mode_id", -1)) == MatchConfig.GameMode.DOMINATION:
		return domination_text(state, team_numbers)
	var parts: PackedStringArray = PackedStringArray()
	# Reach the Sky scores are record heights in meters (Bontago-22y.9).
	var unit: String = " m" if int(state.get("mode_id", -1)) == MatchConfig.GameMode.REACH_THE_SKY else ""
	var elimination: bool = int(state.get("mode_id", -1)) == MatchConfig.GameMode.ELIMINATION
	for team: int in range(scores.size()):
		if elimination:
			parts.append("%d: %s" % [ResultsScreen.team_number_in(team_numbers, team), ResultsScreen.survivor_text(int(scores[team]))])
		else:
			parts.append("%d: %s%s" % [ResultsScreen.team_number_in(team_numbers, team), String.num(float(scores[team]), 1), unit])
	var text: String = "  ".join(parts)
	var left: int = int(ceil(float(state.get("round_left", 0.0))))
	if left > 0:
		text += "   %d:%02d" % [left / 60, left % 60]
	return text


## Bontago-1pi.25.1: Domination territory race, "Leading: 2 (41%)   9:32" (ties
## list every leader). The per-team bars above already show each share, so this
## only adds the leader and the time left. Pure.
static func domination_text(state: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var scores: Array = state.get("scores", []) as Array
	if scores.is_empty():
		return ""
	var best: float = -INF
	for value: Variant in scores:
		best = maxf(best, float(value))
	var leaders: PackedStringArray = PackedStringArray()
	for team: int in range(scores.size()):
		if float(scores[team]) >= best - DominationObjective.TIE_EPSILON:
			leaders.append(str(ResultsScreen.team_number_in(team_numbers, team)))
	var text: String = "Leading: %s (%.0f%%)" % [" & ".join(leaders), maxf(best, 0.0) * 100.0]
	var left: int = int(ceil(float(state.get("round_left", 0.0))))
	if left > 0:
		text += "   %d:%02d" % [left / 60, left % 60]
	return text


## Bontago-1pi.68: what the row value shows for `team` in this mode state: Capture
## the Flag the team's hold time in seconds, Reach the Sky its record height in
## meters, every other mode the territory `share` as a percent. Pure.
static func row_value_text(state: Dictionary, team: int, share: float) -> String:
	var scores: Array = state.get("scores", []) as Array
	var mode_id: int = int(state.get("mode_id", -1))
	if team >= 0 and team < scores.size():
		if mode_id == MatchConfig.GameMode.CAPTURE_THE_FLAG:
			return "%s s" % String.num(float(scores[team]), 1)
		if mode_id == MatchConfig.GameMode.REACH_THE_SKY:
			return "%s m" % String.num(float(scores[team]), 1)
	return "%.0f%%" % (share * 100.0)


## Bontago-1pi.68: the line under the rows. CTF and Reach the Sky now put their score
## in the rows, so only the round clock ("3:29", empty when untimed) is left of it;
## Domination and Elimination keep their existing summary line. Pure.
## DECISION: the clock stays (a separate small line) so timed modes do not lose their
## time left; only the per-team numbers moved into the rows.
static func mode_status_text(state: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var mode_id: int = int(state.get("mode_id", -1))
	if mode_id != MatchConfig.GameMode.CAPTURE_THE_FLAG and mode_id != MatchConfig.GameMode.REACH_THE_SKY:
		return mode_score_text(state, team_numbers)
	if (state.get("scores", []) as Array).is_empty():
		return ""
	var left: int = int(ceil(float(state.get("round_left", 0.0))))
	if left <= 0:
		return ""
	return "%d:%02d" % [left / 60, left % 60]


func _on_mode_state_changed(state: Dictionary) -> void:
	_mode_state = state
	set_territory_shares(_last_shares)
	var text: String = mode_status_text(state, _resolved_team_numbers())
	if _mode_score_label == null:
		if text.is_empty():
			return
		_mode_score_label = Label.new()
		_mode_score_label.add_theme_font_size_override("font_size", 14)
		_mode_score_label.add_theme_color_override("font_color", hud_visual_tuning.ink_color)
		_height_label.get_parent().add_child(_mode_score_label)
	_mode_score_label.text = text
	_mode_score_label.visible = not text.is_empty()


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	_minimap.set_capture(team_id, progress)
	set_capture(team_id, progress, _color_for_team(team_id) if team_id >= 0 else Color.WHITE)


## A shared win (CTF tie) replaces the sole-winner text, from the payload's
## winners list. Single-winner payloads leave show_winner()'s text untouched.
func _on_match_results_ready(results: Dictionary) -> void:
	# Bontago-1pi.23: the results screen owns the end of a match; the whole HUD
	# (previews, stats, timer ring, countdown, minimap) steps aside so nothing
	# draws over its card.
	visible = false
	var shared: String = ResultsScreen.shared_winners_text(results, _resolved_team_numbers())
	if not shared.is_empty():
		_winner_label.text = shared


func _on_match_won(team_id: int) -> void:
	show_winner(team_id, _color_for_team(team_id))


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
##
## Bontago-keo.17 (owner decision "b"): Events.gift_claimed's second argument
## is the RESOLVED RECIPIENT slot -- the one teammate nearest the crate, not
## every teammate. This HUD toast is still a team-wide notification (a
## teammate should see "your team claimed a special" even on the frame they
## don't hold it), so both sides of the comparison go through
## _team_of_slot(): the active slot's own team against the recipient's team.
func _on_gift_claimed(_gift_id: int, slot_id: int, special_id: StringName) -> void:
	_update_gift_markers()
	if slot_id == _active_slot and match_provider != null:
		set_next_shape(match_provider.next_shape(slot_id))
	if _team_of_slot(_active_slot) != _team_of_slot(slot_id):
		return
	_refresh_special_indicator()
	show_gift_toast(special_id)


func _on_gift_state_changed(_gift_id: int, _position: Variant = null, _landing: Variant = null) -> void:
	_update_gift_markers()


func _update_gift_markers() -> void:
	if match_provider != null and match_provider.has_method(&"gift_states"):
		# Bontago-1pi.11.6: _process() polls this every frame; skip the
		# minimap's duplicate + redraw unless a crate actually changed.
		var states: Array[Dictionary] = match_provider.gift_states()
		if states == _last_gift_states:
			return
		_last_gift_states = states.duplicate(true)
		_minimap.set_gift_states(states)


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


## M7 P5: forwards the running match's MapDef to the minimap (docs/M7_PLAN.md
## "P5 -- HUD minimap + reskin", "no new signal needed" — Events.
## territory_share_changed already fires once the match's territory state
## exists, which is after MatchConfig is set). Null-safe the same way
## _hot_seat_active()/_team_of_slot() are: match_provider == null or no config
## yet (pre-match, or a bare HUD-only test with no FakeMatch.config set) just
## leaves the minimap in its initial hidden/disabled state. Only pushes
## set_map_def() when the map actually changed, so this doesn't re-frame the
## minimap on every placement's territory-share tick.
##
## Bontago-mp0.3.3: also forwards the live TerritoryRaster/player colors/home
## positions every tick (Minimap.set_match_state(), cheap reference stores —
## see its own doc), guarded by has_method(&"raster") the same way
## set_feed_seconds()'s feed_time_left() read is: the real Match autoload has
## raster(), tests/unit/support/FakeMatch.gd does not, and a bare HUD-only
## instance should just leave the minimap showing whatever it already had
## rather than error.
func _update_minimap() -> void:
	if match_provider == null:
		return
	var running_config: Variant = match_provider.config
	if running_config == null:
		return
	var map_def: MapDef = running_config.map_def()
	if map_def != _last_map_def:
		_last_map_def = map_def
		_minimap.set_map_def(map_def)
	if not match_provider.has_method(&"raster"):
		return
	var raster: TerritoryRaster = match_provider.raster()
	var homes: PackedVector2Array = PackedVector2Array()
	var count: int = int(running_config.player_count)
	for i: int in range(count):
		var slot: PlayerSlot = match_provider.slot(i)
		homes.append(slot.home_position if slot != null else Vector2.ZERO)
	_minimap.set_goal_positions(PlayerSlot.goal_positions_for(running_config.effective_goal_flag_count(), map_def))
	# Lobby rework (Bontago-1pi.53): territory and goal colours are per TEAM
	# (territory_colors()); the home beacons stay per SLOT (player_colors).
	_minimap.set_match_state(raster, running_config.territory_colors(), homes, running_config.player_colors)
	_update_gift_markers()


## M7 P5 / Bontago-mp0.3.3: the one StyleBoxFlat a reskinned HUD panel uses,
## built from hud_visual_tuning so ui/HUD.tscn itself holds no colour
## literals (mirrors ui/Minimap.gd's own panel styling for the minimap's
## frame/backdrop). Only the next-shape and held-shape cards use this now --
## mockup 08's top-left readouts are plain outlined text
## (_apply_text_outline() below), not a panel.
func _style_panel(panel: Panel, inner: bool = false) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = hud_visual_tuning.inner_surface_color if inner else hud_visual_tuning.surface_color
	style.border_color = hud_visual_tuning.surface_border_color
	style.set_border_width_all(int(hud_visual_tuning.panel_border_width_px))
	style.set_corner_radius_all(int(hud_visual_tuning.panel_corner_radius_px))
	panel.add_theme_stylebox_override("panel", style)


func _resize_top_left_backplate() -> void:
	var padding: float = hud_visual_tuning.card_padding_px
	_top_left_backplate.size = Vector2(
		maxf(_top_left_cluster.size.x, _top_left_cluster.get_combined_minimum_size().x) + padding * 2.0,
		_top_left_cluster.get_combined_minimum_size().y + padding * 2.0
	)
	# Bontago-1pi.80: the status rows (locked/special/toast/mode score) live
	# outside the stats box, stacked just below it.
	_status_pill.position = Vector2(
		_top_left_cluster.position.x, _top_left_backplate.position.y + _top_left_backplate.size.y + padding
	)


## Bontago-mp0.3.3 (mockup 08 restyle; Bontago-mp0.2 "top-left HUD
## unreadable"): a soft dark outline behind a label's text instead of a
## backing panel, so it stays legible directly over a bright sunset sky.
func _apply_text_outline(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 4)


## Spec M2 owner decision 3: no dedicated Events signal exists for "home flag
## lost", so — like PlayerController — the HUD reads the already-documented
## PlayerSlot.home_flag_alive straight off Match.slot() instead of inventing
## a signal on a contract this package doesn't own.
func _is_slot_eliminated(slot_id: int) -> bool:
	if match_provider == null:
		return false
	var slot: PlayerSlot = match_provider.slot(slot_id)
	return slot != null and not slot.home_flag_alive


## Bontago-keo.17: null-safe mirror of config/MatchConfig.gd's team_of_slot()
## for _on_gift_claimed()'s team-membership check -- config == null (no match
## built yet, or a bare HUD-only test with no FakeMatch.config set) falls back
## to "every slot is its own team", the same TeamMode.OFF behaviour
## team_of_slot() itself returns.
func _team_of_slot(slot_id: int) -> int:
	if match_provider == null:
		return slot_id
	var running_config: Variant = match_provider.config
	if running_config == null:
		return slot_id
	return int(running_config.team_of_slot(slot_id))


## Lobby rework (Bontago-1pi.53): the number a team shows in labels -- the one it
## had in the lobby once the host resolved the picks, else team id + 1 (the legacy
## "Team 1/Team 2" numbering). Null-safe like _team_of_slot() above.
func _team_number(team_id: int) -> int:
	if match_provider == null:
		return team_id + 1
	var running_config: Variant = match_provider.config
	if running_config == null:
		return team_id + 1
	return int(running_config.team_number_for(team_id))


## MatchConfig.team_numbers when the lobby teams are host-resolved, else empty
## (labels fall back to team id + 1). For the static score formatters above.
func _resolved_team_numbers() -> PackedInt32Array:
	if match_provider == null:
		return PackedInt32Array()
	var running_config: Variant = match_provider.config
	if running_config == null or not bool(running_config.teams_resolved()):
		return PackedInt32Array()
	return running_config.team_numbers


## Colour of TEAM `team_id` (goal capture ring, winner banner, share bars). With
## host-resolved lobby teams a team shows territory_colors()[team] (its lowest
## slot's colour); otherwise team id t is slot t, exactly the old
## _color_for_slot(team_id) read.
func _color_for_team(team_id: int) -> Color:
	if match_provider != null:
		var running_config: Variant = match_provider.config
		if running_config != null and bool(running_config.teams_resolved()):
			var colors: PackedColorArray = running_config.territory_colors()
			if team_id >= 0 and team_id < colors.size():
				return colors[team_id]
	return _color_for_slot(team_id)


## Whether team `team_id` is out. Resolved lobby teams: every slot of the team has
## lost its home flag (team ids no longer equal slot ids); otherwise the old
## "slot t is team t" read.
func _is_team_eliminated(team_id: int) -> bool:
	if match_provider == null:
		return false
	var running_config: Variant = match_provider.config
	if running_config == null or not bool(running_config.teams_resolved()):
		return _is_slot_eliminated(team_id)
	var found: bool = false
	for slot_id: int in range(int(running_config.player_count)):
		if int(running_config.team_of_slot(slot_id)) != team_id:
			continue
		found = true
		if not _is_slot_eliminated(slot_id):
			return false
	return found


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
##
## Bontago-1pi.49: a human seat's replicated roster name wins over the slot's own
## label (the host never copies roster names onto its PlayerSlots, so its slots
## still read "Player N"); bots keep their slot label.
func _name_for_slot(slot_id: int) -> String:
	var peer_name: String = String(_names().name_for_slot(slot_id))
	if match_provider != null:
		var slot: PlayerSlot = match_provider.slot(slot_id)
		if slot != null:
			return PlayerNames.label_for_slot(slot_id, slot.display_name, slot.is_bot, peer_name)
	return PlayerNames.label_for_slot(slot_id, "", false, peer_name)


## Bontago-1pi.68: the display name of the row for team `team_id`: the roster name of
## its slot, or every member's name joined with " & " in a team match. Falls back
## to the slot of the same number with no config (team t is slot t).
func _name_for_team(team_id: int) -> String:
	if match_provider != null:
		var running_config: Variant = match_provider.config
		if running_config != null:
			var members: PackedStringArray = PackedStringArray()
			for slot_id: int in range(int(running_config.player_count)):
				if int(running_config.team_of_slot(slot_id)) == team_id:
					members.append(_name_for_slot(slot_id))
			if not members.is_empty():
				return " & ".join(members)
	return _name_for_slot(team_id)


func _names() -> Variant:
	return name_provider if name_provider != null else Net


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
	_refresh_gift_slot()
	if match_provider == null or _active_slot < 0:
		_last_special_signature = []
		_set_glue_active(false)
		_special_indicator.visible = false
		_set_gift_icons(&"", &"")
		_held_label.text = "HELD"
		_next_label.text = "NEXT"
		return
	var count: int = int(match_provider.pending_special_count(_active_slot))
	var head_id: StringName = match_provider.held_special(_active_slot)
	var glue_charges: int = 0
	if match_provider.has_method(&"glue_drops_left"):
		glue_charges = int(match_provider.glue_drops_left(_active_slot))
	# Bontago-1pi.11.6: nothing below depends on anything but these inputs.
	var next_id: StringName = _next_gift_id_for(count, head_id)
	var signature: Array = [_active_slot, _active_color, count, head_id, next_id, glue_charges, _qol_backlog]
	if signature == _last_special_signature:
		return
	_last_special_signature = signature
	_set_gift_icons(head_id, next_id)
	_set_glue_active(glue_charges > 0)
	_held_label.text = "HELD: %s" % _special_display_name(head_id) if head_id != &"" else "HELD"
	_next_label.text = "NEXT GIFT" if count > (1 if head_id != &"" else 0) else "NEXT"
	if _qol_backlog > 0:
		_next_label.text += " +%d" % _qol_backlog
	if count <= 0 and glue_charges <= 0:
		_special_indicator.visible = false
		return
	var pending_text: String = _special_display_text(head_id, count) if count > 0 else ""
	var glue_text: String = "Glue ×%d" % glue_charges if glue_charges > 0 else ""
	_special_indicator.text = "%s · %s" % [pending_text, glue_text] if count > 0 and glue_charges > 0 else pending_text + glue_text
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


## Bontago-mp0.3.3 (mockup 08): one row per player, a small team-colored
## diamond glyph (the shared SlotDiamond) beside a slim rounded
## territory-share bar. Bontago-1pi.80: each bar is ONE ui/ShareBar.gd control
## drawing its track, the team-colored fill inside it and a sheen. Replaces
## the old boxy SharesPanel background entirely (Bontago-mp0.2).
func _ensure_share_row_count(count: int) -> void:
	while _share_rows.size() < count:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var glyph: SlotDiamond = SlotDiamond.create(Color.WHITE)

		var bar: ShareBar = ShareBar.new()
		bar.configure(hud_visual_tuning)

		var name_label: Label = Label.new()
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", hud_visual_tuning.ink_color)
		_apply_text_outline(name_label)
		name_label.custom_minimum_size = Vector2(hud_visual_tuning.hud_row_name_width_px, 0.0)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label: Label = Label.new()
		# Bontago-mp0.3.3 (owner review 2026-09-26: "percent label optional/
		# small ... with a text shadow").
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", hud_visual_tuning.ink_color)

		row.add_child(glyph)
		row.add_child(name_label)
		row.add_child(bar)
		row.add_child(label)
		_shares_box.add_child(row)
		_share_rows.append(row)
		_share_bars.append(bar)
		_share_labels.append(label)
		_share_name_labels.append(name_label)
		_share_glyphs.append(glyph)
	while _share_rows.size() > count:
		var last: int = _share_rows.size() - 1
		(_share_rows[last] as Node).queue_free()
		_share_rows.remove_at(last)
		_share_bars.remove_at(last)
		_share_labels.remove_at(last)
		_share_name_labels.remove_at(last)
		_share_glyphs.remove_at(last)


func _update_share_row(i: int, share: float) -> void:
	var eliminated: bool = _is_team_eliminated(i)
	var color: Color = ELIMINATED_COLOR if eliminated else _color_for_team(i)
	var bar: ShareBar = _share_bars[i]
	bar.fill_color = color
	bar.fraction = share
	var label: Label = _share_labels[i]
	label.text = "%s%s" % [row_value_text(_mode_state, i, share), "  (out)" if eliminated else ""]
	var name_label: Label = _share_name_labels[i]
	name_label.text = _name_for_team(i)
	name_label.tooltip_text = name_label.text
	var glyph: SlotDiamond = _share_glyphs[i]
	glyph.set_color(color)


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
	# Bontago-mp0.3.3 (owner review 2026-09-26: "subtle drop shadow"): a soft
	# offset dark disc behind everything else, then the dark disc itself
	# (mockup 08) instead of a bare transparent circle, so the countdown
	# numeral below always has contrast against a bright sky.
	_timer_ring.draw_circle(center + DROP_SHADOW_OFFSET, radius - RING_LINE_WIDTH * 0.5, DROP_SHADOW_COLOR)
	_timer_ring.draw_circle(center, radius - RING_LINE_WIDTH * 0.5, hud_visual_tuning.panel_background_color)
	_timer_ring.draw_arc(center, radius, 0.0, TAU, 48, RING_BACKGROUND_COLOR, RING_LINE_WIDTH)
	if _feed_progress > 0.0:
		# Bontago-mv0.9: greys out while release-locked (spec 2.4/2.5) instead
		# of the active player's colour, so "the interval hasn't come around
		# again yet" reads distinctly from "counting down normally".
		#
		# DECISION (ui/HUD.gd, owner review 2026-09-26: "mockup shows a
		# red/blue two-tone ring -- use player colours as you see fit"):
		# mockup 08's two-tone ring reads as a *shared spectator* HUD showing
		# both players' timers on one ring; this HUD is per-viewer (its own
		# class doc: "shows the local player's own status", one _active_slot
		# at a time), so there is only ever one player's colour to draw here.
		# The remaining-time arc stays that one active player's own colour
		# over the dark RING_BACKGROUND_COLOR track -- the direct one-player
		# equivalent of the mockup's two-tone idea.
		var ring_color: Color = LOCKED_COLOR if (_locked or _qol_paused) else _active_color
		_timer_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _feed_progress, 48, ring_color, RING_LINE_WIDTH
		)
	if _feed_seconds_left >= 0.0:
		_draw_timer_numeral(center)


## Bontago-mp0.3.3: the bold numeral inside the timer ring (mockup 08's "6"),
## ceil()'d the same way a countdown reads to a player (still shows "1" for
## the last fraction of a second, not "0").
func _draw_timer_numeral(center: Vector2) -> void:
	var text: String = QOL_PAUSED_TEXT if _qol_paused else str(int(ceil(_feed_seconds_left)))
	var font: Font = _timer_ring.get_theme_default_font()
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TIMER_NUMERAL_FONT_SIZE).x
	var baseline: Vector2 = center + Vector2(-text_width * 0.5, TIMER_NUMERAL_FONT_SIZE * 0.35)
	_timer_ring.draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TIMER_NUMERAL_FONT_SIZE, 3, Color.BLACK
	)
	_timer_ring.draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TIMER_NUMERAL_FONT_SIZE, Color.WHITE
	)


func _on_shape_preview_draw() -> void:
	_draw_static_shape(_shape_preview, _held_shape, _active_color)


func _on_next_shape_preview_draw() -> void:
	_draw_static_shape(_next_shape_preview, _next_shape, _active_color)


## DECISION: bake actual meshes once; runtime previews only draw cached,
## player-tinted images, without per-cell painter ordering or a 3D viewport.
func _preview_texture(shape: BlockShape) -> Texture2D:
	if shape == null:
		return null
	if not _preview_textures.has(shape.id):
		var path: String = "res://assets/ui/block_previews/%s.png" % shape.id
		_preview_textures[shape.id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _preview_textures[shape.id]


## Bontago-59o.13: gift ids currently shown by the held/next previews
## (&"" = ordinary block). A gift draws SpecialDef.preview_icon_for() (the
## generic gift icon when the def has none) instead of the shape image.
var _held_gift_id: StringName = &""
var _next_gift_id: StringName = &""


func held_gift_icon() -> Texture2D:
	return SpecialDef.preview_icon_for(_held_gift_id) if _held_gift_id != &"" else null


func next_gift_icon() -> Texture2D:
	return SpecialDef.preview_icon_for(_next_gift_id) if _next_gift_id != &"" else null


## The next piece is a gift iff more is queued than the held piece accounts
## for; the id is the queue head (falls back to a generic placeholder id).
func _next_gift_id_for(count: int, head_id: StringName) -> StringName:
	if count <= (1 if head_id != &"" else 0):
		return &""
	var next_id: StringName = &""
	if match_provider.has_method(&"next_special"):
		next_id = match_provider.next_special(_active_slot)
	return next_id if next_id != &"" else GENERIC_GIFT_ID


## Bontago-sen.3: while Glue charges remain, the held/next previews wear a
## glue overlay (tint plus drips) drawn over the block image.
const GLUE_PREVIEW_COLOR: Color = Color(0.55, 0.95, 0.25, 0.4)
const GLUE_DRIP_COLOR: Color = Color(0.55, 0.95, 0.25, 0.85)
const GLUE_DRIP_COUNT: int = 3
const GLUE_DRIP_WIDTH_FRACTION: float = 0.1
const GLUE_DRIP_LENGTH_FRACTION: float = 0.22
var _glue_active: bool = false


## Bontago-sen.8: leaving a match (lobby/end) drops the overlay at once and
## forces the next refresh to re-read the charges.
func _on_match_state_changed_glue(_from_state: int, to_state: int) -> void:
	if to_state != Match.State.END:
		visible = true
	if to_state == Match.State.LOADING or to_state == Match.State.COUNTDOWN:
		prime_pregame_widgets()
	if to_state == Match.State.LOBBY or to_state == Match.State.END:
		_last_special_signature = []
		_set_glue_active(false)


## Bontago-1pi.84: the player-stat rows and minimap otherwise fill in only on
## the first territory_share_changed, which the solver emits once play begins, so
## the countdown showed an empty stats panel and no minimap. Called on
## LOADING/COUNTDOWN (the HUD is loaded behind the Ready screen): builds one
## zero-share row per team and pushes the map/raster/homes to the minimap.
func prime_pregame_widgets() -> void:
	if match_provider == null:
		return
	var running_config: Variant = match_provider.config
	if running_config == null:
		return
	var shares: PackedFloat32Array = PackedFloat32Array()
	shares.resize(int(running_config.team_count()))
	set_territory_shares(shares)
	_update_minimap()


func glue_preview_active() -> bool:
	return _glue_active


func _set_glue_active(active: bool) -> void:
	if active == _glue_active:
		return
	_glue_active = active
	_shape_preview.queue_redraw()
	_next_shape_preview.queue_redraw()


func _draw_glue_overlay(control: Control) -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, control.size)
	control.draw_rect(rect, GLUE_PREVIEW_COLOR)
	var drip_width: float = control.size.x * GLUE_DRIP_WIDTH_FRACTION
	var drip_length: float = control.size.y * GLUE_DRIP_LENGTH_FRACTION
	for i: int in range(GLUE_DRIP_COUNT):
		var x: float = control.size.x * (float(i) + 0.5) / float(GLUE_DRIP_COUNT)
		control.draw_rect(Rect2(x - drip_width * 0.5, control.size.y - drip_length * (1.0 + 0.4 * float(i % 2)), drip_width, drip_length * (1.0 + 0.4 * float(i % 2))), GLUE_DRIP_COLOR)


func _set_gift_icons(held_id: StringName, next_id: StringName) -> void:
	if held_id != _held_gift_id:
		_held_gift_id = held_id
		_shape_preview.queue_redraw()
	if next_id != _next_gift_id:
		_next_gift_id = next_id
		_next_shape_preview.queue_redraw()


func _build_gift_slot_column() -> void:
	var row: HBoxContainer = _held_next_panel.get_node("HeldNextRow") as HBoxContainer
	_gift_slot_column = VBoxContainer.new()
	_gift_slot_column.add_theme_constant_override("separation", _next_shape_card.get_parent().get_theme_constant("separation"))
	_gift_slot_label = Label.new()
	_gift_slot_label.text = "GIFT"
	_gift_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gift_slot_label.add_theme_font_size_override("font_size", _held_label.get_theme_font_size("font_size"))
	_gift_slot_label.add_theme_color_override("font_color", hud_visual_tuning.muted_ink_color)
	var card: Panel = Panel.new()
	card.custom_minimum_size = _held_shape_card.custom_minimum_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_panel(card, true)
	# Bontago-1pi.18.7: the icon sits above a strip reserved for the bound-key glyph, so
	# the badge never covers the gift art. Same left inset/width as the HELD/NEXT icons.
	var glyph_strip_px: float = InputGlyph.GLYPH_HEIGHT_PX
	_gift_slot_preview = Control.new()
	_gift_slot_preview.position = Vector2(_shape_preview.position.x, GIFT_CARD_INSET_PX)
	_gift_slot_preview.size = Vector2(
		_shape_preview.size.x,
		card.custom_minimum_size.y - GIFT_CARD_INSET_PX * 2.0 - glyph_strip_px - GIFT_CARD_ICON_GLYPH_GAP_PX
	)
	_gift_slot_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gift_slot_preview.draw.connect(_on_gift_slot_preview_draw)
	card.add_child(_gift_slot_preview)
	_gift_slot_glyph_row = HBoxContainer.new()
	_gift_slot_glyph_row.name = "GlyphRow"
	_gift_slot_glyph_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_gift_slot_glyph_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gift_slot_glyph_row.anchor_left = 0.0
	_gift_slot_glyph_row.anchor_right = 1.0
	_gift_slot_glyph_row.anchor_top = 1.0
	_gift_slot_glyph_row.anchor_bottom = 1.0
	_gift_slot_glyph_row.offset_top = -(GIFT_CARD_INSET_PX + glyph_strip_px)
	_gift_slot_glyph_row.offset_bottom = -GIFT_CARD_INSET_PX
	card.add_child(_gift_slot_glyph_row)
	_gift_slot_column.add_child(_gift_slot_label)
	_gift_slot_column.add_child(card)
	_gift_slot_column.visible = false
	row.add_child(_gift_slot_column)
	_gift_slot_panel_base_right = _held_next_panel.offset_right
	_gift_slot_extra_width = card.custom_minimum_size.x + float(row.get_theme_constant("separation"))


## Shows the gift slot card only while the experiment is on and the active
## slot has a gift waiting; widens the HELD/NEXT panel to make room.
func _refresh_gift_slot() -> void:
	if _gift_slot_column == null:
		return
	var head_id: StringName = &""
	var count: int = 0
	if match_provider != null and _active_slot >= 0 and match_provider.has_method(&"gift_slot_head"):
		head_id = match_provider.gift_slot_head(_active_slot)
		count = int(match_provider.gift_slot_count(_active_slot))
	var show_card: bool = head_id != &""
	if _gift_slot_column.visible != show_card:
		_gift_slot_column.visible = show_card
		_held_next_panel.offset_right = _gift_slot_panel_base_right + (_gift_slot_extra_width if show_card else 0.0)
	if show_card:
		_gift_slot_label.text = "GIFT: %s" % _special_display_name(head_id)
		if count > 1:
			_gift_slot_label.text += " x%d" % count
		_refresh_gift_slot_glyph()
	if head_id != _gift_slot_id:
		_gift_slot_id = head_id
		_gift_slot_preview.queue_redraw()


## Bontago-1pi.18.7: the use_gift_slot binding for the player's current device
## family, drawn by the shared InputGlyph (keycap/pad art, or its fallback). Rebuilt
## only when the device or the bound events changed, so a rebind in the pause
## menu shows up on the card without any signal of its own.
func _refresh_gift_slot_glyph(force: bool = false) -> void:
	if _gift_slot_glyph_row == null:
		return
	var event: InputEvent = gift_slot_binding()
	var signature: String = "%s|%s" % [Settings.active_input_device(), event.as_text() if event != null else ""]
	if signature == _gift_slot_glyph_signature and not force:
		return
	_gift_slot_glyph_signature = signature
	if _gift_slot_glyph != null:
		_gift_slot_glyph_row.remove_child(_gift_slot_glyph)
		_gift_slot_glyph.queue_free()
		_gift_slot_glyph = null
	if event == null:
		return
	_gift_slot_glyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
	_gift_slot_glyph_row.add_child(_gift_slot_glyph)
	_gift_slot_glyph.set_event(event)


## The first InputMap event of GIFT_SLOT_ACTION that belongs to the active input
## device family (gamepad vs keyboard/mouse, the same split the Controls page
## uses), or null when that family has none.
func gift_slot_binding() -> InputEvent:
	if not InputMap.has_action(GIFT_SLOT_ACTION):
		return null
	var want_gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	for event: InputEvent in InputMap.action_get_events(GIFT_SLOT_ACTION):
		var is_gamepad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_gamepad == want_gamepad:
			return event
	return null


func _on_input_device_changed(_device: StringName) -> void:
	if _gift_slot_column != null and _gift_slot_column.visible:
		_refresh_gift_slot_glyph()


func _on_gift_slot_preview_draw() -> void:
	if _gift_slot_id == &"":
		return
	var texture: Texture2D = SpecialDef.preview_icon_for(_gift_slot_id)
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	var fit: float = minf(_gift_slot_preview.size.x / texture_size.x, _gift_slot_preview.size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * fit
	_gift_slot_preview.draw_texture_rect(texture, Rect2((_gift_slot_preview.size - draw_size) * 0.5, draw_size), false, _active_color)


func _draw_static_shape(control: Control, shape: BlockShape, color: Color) -> void:
	var gift_id: StringName = _held_gift_id if control == _shape_preview else _next_gift_id
	var texture: Texture2D = SpecialDef.preview_icon_for(gift_id) if gift_id != &"" else _preview_texture(shape)
	if texture == null:
		return
	if _glue_active:
		_draw_glue_overlay(control)
	var texture_size: Vector2 = texture.get_size()
	var scale: float = minf(control.size.x / texture_size.x, control.size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * scale
	control.draw_texture_rect(texture, Rect2((control.size - draw_size) * 0.5, draw_size), false, color)




func _on_capture_ring_draw() -> void:
	var size: Vector2 = _capture_ring.size
	var radius: float = minf(size.x, size.y) * 0.5 - RING_LINE_WIDTH
	var center: Vector2 = size * 0.5
	_capture_ring.draw_arc(center, radius, 0.0, TAU, 48, RING_BACKGROUND_COLOR, RING_LINE_WIDTH)
	if _capture_progress > 0.0:
		_capture_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _capture_progress, 48, _capture_color, RING_LINE_WIDTH
		)
