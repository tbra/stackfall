class_name HUD
extends CanvasLayer
## Spec 1.10's HUD: a timer ring numeral, held-block and next-block previews, max height,
## per-player territory share rows (diamond + bar, top-left), a capture ring, a greyed
## locked ring, a pending-special queue indicator and the
## live minimap (ui/hud/Minimap.gd, a 2D draw off the live TerritoryRaster; see its
## class doc). The held and next cards sit in one grouped %HeldNextPanel in the
## bottom-left corner, and the previews are pre-rendered mesh thumbnails.
##
## There is no "turn" -- every slot plays at once (spec 1.4) -- so this HUD shows
## **the local player's own status**. `_active_slot` is whichever slot this HUD's
## widgets currently read: the local slot, set by set_local_slot() off
## Events.turn_changed (net/MatchNet.gd substitutes the local slot into that signal)
## and called directly by game/sandbox/Sandbox.gd when its debug hotkey cycles slots.
##
## "Connects to Events only — no node paths out of ui/": it
## wires itself to the Events bus in _ready() and never walks the scene tree
## looking for collaborators. It reads the Match autoload for display data a
## signal payload doesn't carry (a slot's colour, name, or a shape id's
## BlockShape, whether a slot is eliminated, whether its release is locked)
## but never decides anything — spawning a Block, validity, and the raster
## all stay Match's job.
##
## DECISION (ui/hud/HUD.gd): every *gameplay-feel* number (durations, colors,
## hatch scale) already lives in GhostTuning (which parks the HUD
## tunables there too). Pure screen-space drawing geometry for this
## placeholder layout — ring line width, background alpha, the preview's
## cell size in pixels — stays inline: CLAUDE.md's "no magic numbers" is about
## tunables that affect gameplay feel, not every pixel constant behind a debug HUD.


const SHARE_BAR_MAX_WIDTH: float = 200.0
const SHARE_BAR_HEIGHT: float = 14.0
const SKY_NET_CONFIG: NetConfig = preload("res://config/net/net_config.tres")
const RING_LINE_WIDTH: float = 8.0
## Subtle drop shadow shared by the timer ring's disc.
const DROP_SHADOW_OFFSET: Vector2 = Vector2(2.0, 3.0)
const DROP_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.35)
const ELIMINATED_COLOR: Color = Color(0.4, 0.4, 0.4, 0.5)
@export var ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
## durations for the "Special queued: <name>" claim toast below
## (see config/gifts/GiftConfig.gd's own "-- Claim feedback --" section for why
## these live there rather than in ghost_tuning above).
@export var gift_config: GiftConfig = preload("res://config/gifts/gift_config.tres")
## The action whose bound glyph the gift slot card shows (PlayerController spends the slot on it).
const GIFT_SLOT_ACTION: StringName = &"use_gift_slot"
## Gap between the gift card's border and its icon/glyph (screen-space geometry, see the DECISION above).
const GIFT_CARD_INSET_PX: float = 6.0
const GIFT_CARD_ICON_GLYPH_GAP_PX: float = 2.0
## Fallback player colours for a slot Match cannot name — before a match
## starts, or in a HUD-only test with no Match behind it. An @export var
## rather than a const: a const's value has to resolve while the script is
## still being parsed, and the editor parses HUD.gd (through Main -> LocalPlayer)
## before it can load a .tres whose script is MatchConfig, which made the
## constant null and the parse fail.
@export var default_palette: MatchConfig = preload("res://config/match/match_defaults.tres")
## The minimap's camera framing and the panels' colours; see config/ui/HUDVisualTuning.gd's
## class doc. Pure screen-space geometry stays inline (DECISION above).
@export var hud_visual_tuning: HUDVisualTuning = preload("res://config/ui/hud_visual_tuning.tres")
## DECISION (ui/hud/HUD.gd): a Variant test seam for the same reason
## PlayerController has one: GUT can't double a plain autoload. Defaults to the real
## autoload; tests overwrite it with a fake after add_child().
var match_provider: Variant = null
## where a human seat's replicated name comes from, anything
## answering name_for_slot(slot_id) -> String. Null means the real Net autoload.
var name_provider: Variant = null

@onready var _turn_label: Label = %TurnLabel
@onready var _timer_ring: Control = %TimerRing
## The match clock in the top-right corner (UiRoundTimer).
var _round_timer: UiRoundTimer = null
## Seconds the current unlimited match has been live (the round clock counts up from it).
var _round_played_s: float = 0.0
@onready var _shape_preview: Control = %ShapePreview
@onready var _next_shape_preview: Control = %NextShapePreview
@onready var _next_label: Label = $HeldNextPanel/HeldNextRow/NextColumn/NextLabel
@onready var _held_label: Label = $HeldNextPanel/HeldNextRow/HeldColumn/HeldLabel
@onready var _special_indicator: Label = %SpecialIndicator
@onready var _height_label: Label = %HeightLabel
@onready var _shares_box: VBoxContainer = %SharesBox
@onready var _status_pill: VBoxContainer = %StatusPill
@onready var _capture_ring: Control = %CaptureRing
@onready var _toasts: ToastStack = %ToastStack
## feedback pictograms (config/ui/hud_feedback_icon_table.tres)
## beside held height, the capture ring and the reject/relocated message.
@onready var _capture_icon: TextureRect = %CaptureIcon
@onready var _reject_icon: TextureRect = %RejectIcon
@export var feedback_icons: HudFeedbackIconTable = preload("res://config/ui/hud_feedback_icon_table.tres")
## Refusal reason id -> the sentence show_reject() displays.
@export var reject_messages: RejectMessageTable = preload("res://config/ui/reject_message_table.tres")
@onready var _winner_label: Label = %WinnerLabel
## The next-shape card's own backing panel. The top-left readouts have no boxy
## backing panel of their own: just outlined text and slim bars, on one arcade plate.
@onready var _next_shape_card: Panel = %NextShapeCard
## The held-shape icon's own labeled card, styled the same as _next_shape_card.
@onready var _held_shape_card: Panel = %HeldShapeCard
## The outer frame around both
## %HeldShapeCard and %NextShapeCard (ui/hud/HUD.tscn's HeldNextRow), styled the
## same as those two inner cards so the group reads as one panel rather than
## two loose cards -- DECISION: keeps the inner cards' own borders too
## (nested, not replaced) rather than stripping their styling now that
## they're grouped, since a Panel with no stylebox override at all would fall
## back to the engine's default gray theme box, which reads worse than a
## slightly nested double border in the same palette.
@onready var _held_next_panel: Panel = %HeldNextPanel
@onready var _minimap: Minimap = %Minimap
## parent of every HUD control (see _build_scale_root()).
var _scale_root: Control = null
@onready var _top_left_backplate: Panel = %TopLeftBackplate
@onready var _top_left_cluster: VBoxContainer = $TopLeftCluster
var _top_left_cluster_base_right: float = 0.0

var _shapes_by_id: Dictionary = {}
## Placeholder id for a queued gift whose def id is unknown (icon falls back).
const GENERIC_GIFT_ID: StringName = &"gift"
var _preview_textures: Dictionary[StringName, Texture2D] = {}
## Whichever slot this HUD's widgets currently read: the local player's slot.
var _active_slot: int = -1
var _active_color: Color = Color.WHITE
## Stackfall Arcade: the shared design tokens, the stackfall theme (fonts for the
## code-built labels) and its display (Bungee) font for numerals, percentages and the countdown.
var _arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
var _ui_theme: Theme = preload("res://ui/theme/stackfall_theme.tres")
var _display_font: Font = null
## The two label columns whose cards fade to locked_card_alpha while the release lock holds.
var _lock_fade_nodes: Array[Control] = []
## Timer numeral shown while a QoL experiment has the block timer paused.
const QOL_PAUSED_TEXT: String = "||"
var _feed_progress: float = 1.0
## QoL experiments: queued-block count and "timer paused"
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
## Client-only smoothing between sparse goal_capture_progress updates.
var _capture_ext: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()

var _share_rows: Array = []
var _share_bars: Array = []
var _share_labels: Array = []
## the ellipsized player-name label of each row, parallel to _share_labels
## (which holds only the mode-specific value text).
var _share_name_labels: Array = []
## Last values fed to the rows, so a mode-state or roster change can repaint them.
var _last_shares: PackedFloat32Array = PackedFloat32Array()
var _mode_state: Dictionary = {}
## the small team-colored diamond glyph drawn beside each
## player's share bar (mockup 08), parallel to _share_rows/_share_bars/
## _share_labels above.
var _share_glyphs: Array = []
## Stackfall Arcade: the "· YOU" marker label of each row, shown on the local player's row only.
var _share_you_labels: Array = []
## per-row CTF "xN" chip (rim gold), visible while a team holds several beacons.
var _share_mult_labels: Array = []
## Seconds left on the active slot's block timer, drawn as the bold numeral
## inside the timer ring (mockup 08's "6"). -1 until the first _process()
## poll (or a test's direct set_feed_seconds() call) has a real value, so a
## bare HUD-only instance draws no numeral at all.
var _feed_seconds_left: float = -1.0
## Last MapDef pushed to the minimap, so repeated territory_share_changed
## ticks (every placement) don't re-frame its camera when the map hasn't
## actually changed.
var _last_map_def: MapDef = null
## change-gates for the per-frame _process() polls.
var _last_gift_states: Array[Dictionary] = []
var _last_height_text: String = ""
var _last_special_signature: Array = []
## live per-team score line for timed modes (Capture the Flag),
## built in code under the status pill so HUD.tscn and classic stay unchanged.
var _mode_score_label: Label = null
## big centred 3-2-1 label, built in code (no scene edit).
## Driven by the host's replicated countdown (Match.countdown_remaining()),
## never by a local timer, so clients stay in step with the host.
var _reject_icon_tween: Tween
var _countdown_label: Label = null
## red "Eliminated by <name>" banner for the local player.
var _eliminated_label: Label = null
var _countdown_was_active: bool = false
var _go_left_s: float = 0.0

## QoL gift slot: a third card beside HELD/NEXT, built in
## code and shown only while the experiment has a gift waiting. Styled with the
## same helpers as the HELD/NEXT cards.
var _gift_slot_column: VBoxContainer = null
var _gift_slot_label: Label = null
var _gift_slot_preview: Control = null
var _gift_slot_id: StringName = &""
var _gift_slot_panel_base_right: float = 0.0
## Space the extra column adds to the HELD/NEXT panel (card width plus row separation).
var _gift_slot_extra_width: float = 0.0
## the use_gift_slot binding drawn along the card's bottom edge
## (one InputGlyph for the active device family) and what it was built from.
var _gift_slot_glyph_row: HBoxContainer = null
var _gift_slot_glyph: InputGlyph = null
var _gift_slot_glyph_signature: String = ""
## F8 / PADDLE4 (hud_toggle) hides every HUD control at once.
## DECISION: the HUD owns this state (every in-match HUD element hangs off its
## HudScaleRoot; the pause menu, results, loading and F1-F4 overlays are other
## layers, so they are untouched). It toggles the scale root, not HUD.visible,
## which the results screen already uses. Not gated by DebugMode, and the state
## resets on Events.match_scope_reset so each new match starts with the HUD shown.
var _hud_hidden: bool = false
## A PADDLE4 press waits for its release before toggling, so PADDLE4+PADDLE1
## (the sandbox slow-motion chord) can cancel it instead of also hiding the HUD.
var _hud_pad_pending: bool = false



func _ready() -> void:
	_build_scale_root()
	match_provider = Match
	_shapes_by_id = _load_shapes_by_id()
	_timer_ring.draw.connect(_on_timer_ring_draw)
	_build_round_timer()
	_shape_preview.draw.connect(_on_shape_preview_draw)
	_next_shape_preview.draw.connect(_on_next_shape_preview_draw)
	_capture_ring.draw.connect(_on_capture_ring_draw)
	_setup_feedback_icons()
	_winner_label.visible = false
	_capture_ring.visible = false
	_special_indicator.visible = false

	# Stackfall Arcade: every HUD group sits on a disc-900 plate (hud-plate opacity)
	# so the same HUD reads over the day, night, storm and snow skies; cards inside a plate are
	# disc-700 blocks. The CanvasLayer is not a Control, so each root group gets the stackfall theme
	# explicitly (Rubik text, cream ink); numerals use Bungee through _display_font.
	_display_font = _ui_theme.get_font(&"font", &"DisplayLabel")
	for themed: Control in [
		_top_left_cluster, _status_pill, _held_next_panel, _special_indicator, _toasts,
	]:
		themed.theme = _ui_theme
	_style_panel(_top_left_backplate)
	_style_panel(_held_next_panel)
	_style_panel(_next_shape_card, true)
	_style_panel(_held_shape_card, true)
	_lock_fade_nodes = [_held_shape_card, _next_shape_card]
	_build_gift_slot_column()
	# The status pill keeps only the locked/special/toast rows.
	_turn_label.visible = false
	_height_label.visible = false
	for label: Label in [
		_turn_label, _height_label, _special_indicator,
	]:
		label.add_theme_color_override("font_color", hud_visual_tuning.ink_color)
	_height_label.add_theme_color_override("font_color", hud_visual_tuning.muted_ink_color)
	for caption: Label in [_held_label, _next_label]:
		_style_card_caption(caption)
	for plated: Label in [_turn_label, _height_label]:
		_style_status_plate(plated, hud_visual_tuning.ink_color)
	# DECISION: the queued-special chip is a small plate under the scoreboard with its
	# label in rim gold (components.md TipBanner "Special queued"); the claim toast is the rim Callout.
	_style_status_plate(_special_indicator, _arcade.rim_color)
	_setup_toast_stack()
	_reject_icon.visible = false
	# Row gap of the scoreboard (rows are tight, the plate carries the grouping).
	_shares_box.add_theme_constant_override("separation", int(hud_visual_tuning.hud_row_gap_px))
	_top_left_cluster_base_right = _top_left_cluster.offset_right
	get_viewport().size_changed.connect(_apply_hud_layout)
	Settings.hud_scale_changed.connect(_on_hud_scale_changed)
	Settings.ui_scale_changed.connect(_on_hud_scale_changed)
	Settings.minimap_size_changed.connect(_on_minimap_size_changed)
	_minimap.set_size_px(UiScaleTuning.shared().minimap_size_px_for(UiScaleTuning.runtime_minimap_preset()))
	_apply_hud_layout()
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
	Events.match_scope_reset.connect(_capture_ext.clear)
	Events.match_scope_reset.connect(_show_hud)
	Events.match_state_changed.connect(_on_match_state_changed_glue)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.gift_flight_spawned.connect(_on_gift_state_changed)
	Events.gift_landed.connect(_on_gift_state_changed)
	Events.gift_expired.connect(_on_gift_state_changed)
	Events.input_device_changed.connect(_on_input_device_changed)
	# the world build awaits frames, so the HUD can be created after
	# the LOADING/COUNTDOWN state emits it would otherwise prime on. Catch up now.
	if Match.is_in_progress(Match.state()):
		prime_pregame_widgets()


func _build_countdown_label() -> void:
	# Bungee 128 px in cream on a disc-950 drop (design "countdown" style); GO switches to rim gold.
	_countdown_label = _make_countdown_style_label(
		"CountdownLabel", hud_visual_tuning.countdown_font_size, _arcade.cream_color
	)
	# the "Eliminated by <name>" banner is the same style in alert red.
	_eliminated_label = _make_countdown_style_label(
		"EliminatedLabel", hud_visual_tuning.eliminated_font_size, _arcade.alert_color
	)
	_eliminated_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The big centred countdown look (Bungee, drop shadow), shared by the 3-2-1 and
## the elimination banner. Added hidden to the HUD.
func _make_countdown_style_label(label_name: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.name = label_name
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _display_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", _arcade.disc_950_color)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", _arcade.countdown_drop_px)
	label.visible = false
	_scale_root.add_child(label)
	return label


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
		_countdown_label.add_theme_color_override("font_color", _arcade.cream_color)
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
		_countdown_label.add_theme_color_override("font_color", _arcade.rim_color)
		_countdown_label.visible = true
		return
	if _go_left_s > 0.0:
		_go_left_s -= delta
	if _go_left_s <= 0.0:
		_countdown_label.visible = false


func _process(delta: float) -> void:
	_update_countdown_label(delta)
	if Net.is_client() and Match.is_live(Match.state()):
		extrapolate_capture(delta, Match._territory_tuning.capture_hold)
	# DECISION (ui/hud/HUD.gd): the minimap rotates with the camera yaw, read from Viewport.get_camera_3d() rather
	# than a node path into the camera rig or a new Events signal: a generic engine query
	# does not reintroduce the deep-node-path pattern the class doc warns against. Runs
	# unconditionally (before the active-slot gate) so the minimap keeps tracking the
	# camera between active-slot changes; a null camera (tests, no 3D scene) leaves
	# Minimap's basis at whatever it last was (its own no-op guard).
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var basis: Basis = camera.global_transform.basis
		var forward: Vector3 = -basis.z
		var right: Vector3 = basis.x
		_minimap.set_camera_basis(Vector2(right.x, right.z), Vector2(forward.x, forward.z))
	_update_gift_markers()
	_update_round_timer(delta)
	if match_provider == null or _active_slot < 0:
		return
	set_feed_progress(match_provider.feed_progress(_active_slot))
	if match_provider.has_method(&"qol_backlog_count"):
		var paused_now: bool = bool(match_provider.qol_timer_paused(_active_slot))
		if paused_now != _qol_paused:
			_qol_paused = paused_now
			_timer_ring.queue_redraw()
		_qol_backlog = int(match_provider.qol_backlog_count(_active_slot))
	# The timer ring's numeral. Guarded by has_method() like _update_minimap()'s raster()
	# read: Variant doubles (FakeMatch) have no feed_time_left(), and a bare HUD-only
	# instance should draw no numeral rather than error.
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


## The match clock on a hud-plate, in the top-right corner: its top aligned with the
## player-stats backplate and its right edge with the minimap (read from those nodes).
func _build_round_timer() -> void:
	var slot: Control = Control.new()
	slot.name = "RoundTimerSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.anchor_left = 1.0
	slot.anchor_right = 1.0
	slot.offset_left = _minimap.offset_right
	slot.offset_right = slot.offset_left
	slot.offset_top = _top_left_backplate.offset_top
	slot.offset_bottom = slot.offset_top
	slot.theme = _ui_theme
	_scale_root.add_child(slot)
	_round_timer = UiRoundTimer.new()
	_round_timer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE)
	_round_timer.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_round_timer.grow_vertical = Control.GROW_DIRECTION_END
	_round_timer.clear()
	slot.add_child(_round_timer)


## Feeds the round clock from the Match autoload (the host's clock on a client too). Hidden outside
## live play and in the sandbox.
func _update_round_timer(delta: float) -> void:
	if _round_timer == null:
		return
	var live: bool = match_provider != null and match_provider.has_method(&"match_timer_left") 		and Match.is_live(Match.state())
	# get() so a provider without a config (e.g. a countdown-only test double) reads as null.
	var running_config: Variant = match_provider.get(&"config") if match_provider != null else null
	if not live or running_config == null or bool(running_config.sandbox):
		_round_played_s = 0.0
		_round_timer.clear()
		return
	_round_played_s += delta
	_round_timer.show_match(
		UiRoundTimer.limit_minutes_for(running_config as MatchConfig),
		float(match_provider.match_timer_left()), bool(match_provider.sudden_death_active()), _round_played_s)


## Bottom edge of the timer ring in HUD pixels: the Tutorial's tip banner sits just under it.
func timer_ring_bottom_px() -> float:
	return _timer_ring.offset_bottom * _scale_root.scale.y


# --- Public API ------------------------------------------------------------------

## Points every per-slot widget (timer ring, held/next previews, locked state) at
## `slot_id`. Called from Events.turn_changed (net/MatchNet.gd already substitutes
## the local slot into that signal) and from game/sandbox/Sandbox.gd whenever
## its debug hotkey cycles which slot it is driving.
func set_local_slot(slot_id: int) -> void:
	_active_slot = slot_id
	_active_color = _color_for_slot(slot_id)
	_minimap.set_local_slot(slot_id)
	_refresh_you_markers()
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


## Pulls whatever `match_provider` holds for `slot_id` right now. Events.feed_block_issued
## fires once, when Match first feeds a slot, usually before set_local_slot
## runs (the sandbox and MatchNet wire the local slot in after
## Match.start_match()), so the held/next previews would otherwise stay null for the
## whole match. Later feed_block_issued ticks keep it current.
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


## Spec 1.4's release-locked state (Match.is_release_locked): the held
## piece may be aimed but not released again until the interval boundary.
## Greys the ring out (no LOCKED text); a no-op call when nothing changed,
## matching set_capture's shape.
func set_locked(locked: bool) -> void:
	if _locked == locked:
		return
	_locked = locked
	for card: Control in _lock_fade_nodes:
		card.modulate.a = hud_visual_tuning.locked_card_alpha if locked else 1.0
	_timer_ring.queue_redraw()


## fraction runs 1 -> 0 as the slot's block timer counts down; drives the
## timer ring's radial fill.
func set_feed_progress(fraction: float) -> void:
	var clamped: float = clampf(fraction, 0.0, 1.0)
	if is_equal_approx(clamped, _feed_progress):
		return
	_feed_progress = clamped
	_timer_ring.queue_redraw()


## Seconds left on the block timer, shown as the bold numeral inside the timer ring.
## A negative value (the -1.0 default, or a caller's own choice) draws no numeral.
func set_feed_seconds(seconds: float) -> void:
	if is_equal_approx(seconds, _feed_seconds_left):
		return
	_feed_seconds_left = seconds
	_timer_ring.queue_redraw()


## sizes the three pictograms from the table. The held-height
## icon only shows while a block is held (set_tower_and_block_height); the reject
## icon sits centred above the message and is hidden until a message plays.
func _setup_feedback_icons() -> void:
	var px: float = float(feedback_icons.icon_px)
	# DECISION: the held-height icon is gone from the HUD; with the
	# height text hidden it was a label-less icon that carried no information.
	_capture_icon.texture = feedback_icons.icon_for(HudFeedbackIconTable.Feedback.CAPTURE)
	_capture_icon.offset_left = -px * 0.5
	_capture_icon.offset_right = px * 0.5
	_capture_icon.offset_top = -px * 0.5
	_capture_icon.offset_bottom = px * 0.5
	_reject_icon.offset_left = -px * 0.5
	_reject_icon.offset_right = px * 0.5
	_reject_icon.offset_bottom = _toasts.offset_top
	_reject_icon.offset_top = _toasts.offset_top - px
	_reject_icon.modulate.a = 0.0


## Shows `feedback`'s pictogram with the message and fades it with the label.
func _play_reject_icon(feedback: HudFeedbackIconTable.Feedback, fade_s: float) -> void:
	_reject_icon.texture = feedback_icons.icon_for(feedback)
	_reject_icon.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if _reject_icon_tween != null and _reject_icon_tween.is_valid():
		_reject_icon_tween.kill()
	_reject_icon_tween = create_tween()
	_reject_icon_tween.tween_property(_reject_icon, ^"modulate:a", 0.0, fade_s)


func set_height(meters: float) -> void:
	_set_height_text("Height: %.2f m%s" % [meters, sky_target_suffix(_mode_state)])


## " / 100 m" on the height line in Reach the Sky (the race
## target, NetConfig.build_height_target_m, the same value the host wins on), else "".
static func sky_target_suffix(state: Dictionary) -> String:
	if int(state.get("mode_id", -1)) != MatchConfig.GameMode.REACH_THE_SKY:
		return ""
	return " / %.0f m" % SKY_NET_CONFIG.build_height_target_m


## The held-height readout names both numbers while a local block is held: the slot's
## tallest *placed* structure (Match.max_height_for_slot()) does not move while the held
## block is wheeled up, and the follow camera keeps the ghost fixed at screen centre,
## so raising would otherwise look capped.
func set_tower_and_block_height(tower_meters: float, block_meters: float) -> void:
	_set_height_text("Tower: %.2f m%s   Block: %.1f m" % [tower_meters, sky_target_suffix(_mode_state), block_meters])


## only touches the Label (which re-lays out text) on change.
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
	_toasts.push(
		# DECISION: sentence case, not the old uppercase, so a full sentence stays readable.
		reject_messages.message_for(reason),
		_arcade.alert_color, HudCallout.Glyph.CROSS,
		ghost_tuning.hud_reject_message_duration, ghost_tuning.hud_reject_fade_duration
	)
	_play_reject_icon(HudFeedbackIconTable.Feedback.REJECTED, ghost_tuning.hud_reject_fade_duration)


## A manual click over enemy territory is refused (show_reject(), nothing spawns), but
## the interval boundary still auto-drops the held piece and
## PlacementRules.closest_valid_point() relocates it into the player's own territory,
## often only metres from the refused spot; without a message that read as "the
## rejected placement still happened". Reuses show_reject()'s label/tween shape (hold,
## then fade) with its own wording, colour (the bluish-white of
## GhostTuning.auto_drop_flash_color, tying it to the auto-drop flash) and durations
## (hud_relocated_message_duration/hud_relocated_fade_duration), so tuning the reject
## message never detunes this one.
func show_relocated() -> void:
	# DECISION: the forced auto-drop is a neutral correction, not a refusal, so it
	# takes the mint Callout face with a check; a refusal stays alert + cross.
	_toasts.push(
		"RELOCATED INTO YOUR TERRITORY", _arcade.mint_color, HudCallout.Glyph.CHECK,
		ghost_tuning.hud_relocated_message_duration, ghost_tuning.hud_relocated_fade_duration
	)
	_play_reject_icon(HudFeedbackIconTable.Feedback.RELOCATED, ghost_tuning.hud_relocated_fade_duration)


## DECISION (ui/hud/HUD.gd): a separate results screen owns the "who won"
## announcement, so this in-HUD banner never appears. Keeps computing/storing the text
## and tint (a cheap seam for a results-screen consumer) but never flips `visible`:
## Events.match_won -> _on_match_won() -> show_winner() still fires with no on-screen
## effect. %WinnerLabel stays in ui/hud/HUD.tscn so reviving the banner needs no new node.
func show_winner(team_id: int, color: Color) -> void:
	_winner_label.text = PlayerNames.winner_text(ResultsScreen.team_number_in(_resolved_team_numbers(), team_id))
	_winner_label.modulate = color
	_winner_label.visible = false


## The local player's own claim feedback beside the pending-special indicator
## (_refresh_special_indicator() above): same fade shape as show_reject() but its own
## durations (GiftConfig.claim_toast_visible_duration_s/claim_toast_fade_duration_s),
## since a claim toast and a rejection read differently and shouldn't share one timing.
func show_gift_toast(special_id: StringName) -> void:
	_toasts.push(
		("Special queued: %s" % _special_display_name(special_id)).to_upper(),
		_arcade.rim_color, HudCallout.Glyph.STAR,
		gift_config.claim_toast_visible_duration_s, gift_config.claim_toast_fade_duration_s
	)


# --- Events reactions --------------------------------------------------------

## net/MatchNet.gd's EVENT_TURN_CHANGED handler substitutes this instance's local slot
## before re-emitting, so `slot_id` is the slot this HUD should read.
func _on_turn_changed(slot_id: int) -> void:
	set_local_slot(slot_id)


func _on_feed_block_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName) -> void:
	if slot_id != _active_slot:
		return
	set_held_shape(_shapes_by_id.get(shape_id) as BlockShape)
	set_next_shape(_shapes_by_id.get(next_shape_id) as BlockShape)
	_refresh_special_indicator()


func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	# DECISION (ui/hud/HUD.gd): one HUD instance shows exactly one slot's status
	# — the local slot (see
	# the class doc comment) — so every rejection for any other slot is
	# silently ignored here. A per-viewer HUD for simultaneous multiplayer is
	# already what _active_slot picks out; nothing else changes.
	if slot_id != _active_slot:
		return
	show_reject(reason)


## Same per-viewer-HUD filter as _on_placement_rejected() above. `point` (the
## disk-local landing spot) is not shown; the message text alone says what this HUD needs.
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
## `team_numbers` is MatchConfig.team_numbers of a match whose lobby teams were
## host-resolved (dense team id -> the number the team had in the lobby); empty = the
## "team id + 1" label.
static func mode_score_text(state: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var scores: Array = state.get("scores", []) as Array
	if scores.is_empty():
		return ""
	if int(state.get("mode_id", -1)) == MatchConfig.GameMode.DOMINATION:
		return domination_text(state, team_numbers)
	var parts: PackedStringArray = PackedStringArray()
	# Reach the Sky scores are record heights in meters.
	var unit: String = " m" if int(state.get("mode_id", -1)) == MatchConfig.GameMode.REACH_THE_SKY else ""
	var elimination: bool = int(state.get("mode_id", -1)) == MatchConfig.GameMode.ELIMINATION
	for team: int in range(scores.size()):
		if elimination:
			parts.append("%d: %s" % [ResultsScreen.team_number_in(team_numbers, team), ResultsScreen.survivor_text(int(scores[team]))])
		else:
			parts.append("%d: %s%s" % [ResultsScreen.team_number_in(team_numbers, team), String.num(float(scores[team]), 1), unit])
	return "  ".join(parts)


## Domination territory race, "Leading: 2 (41%)" (ties list every leader). The
## per-team bars above already show each share, so this only adds the leader; the time left is the
## UiRoundTimer's. Pure.
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
	return text


## what the row value shows for `team` in this mode state: Capture
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


## the line under the rows. CTF and Reach the Sky put their score in the rows, so
## nothing is left for them; Domination and Elimination keep their summary line. The
## round clock is UiRoundTimer's, not part of it. Pure.
static func mode_status_text(state: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var mode_id: int = int(state.get("mode_id", -1))
	if mode_id != MatchConfig.GameMode.CAPTURE_THE_FLAG and mode_id != MatchConfig.GameMode.REACH_THE_SKY:
		return mode_score_text(state, team_numbers)
	return ""


func _on_mode_state_changed(state: Dictionary) -> void:
	_mode_state = state
	set_territory_shares(_last_shares)
	var text: String = mode_status_text(state, _resolved_team_numbers())
	if _mode_score_label == null:
		if text.is_empty():
			return
		_mode_score_label = Label.new()
		_style_status_plate(_mode_score_label, hud_visual_tuning.ink_color)
		_height_label.get_parent().add_child(_mode_score_label)
	_mode_score_label.text = text
	_mode_score_label.visible = not text.is_empty()


func _on_goal_capture_progress(team_id: int, progress: float) -> void:
	_capture_ext.snap(team_id, progress)
	_minimap.set_capture(team_id, progress)
	set_capture(team_id, progress, _color_for_team(team_id) if team_id >= 0 else Color.WHITE)


## A client gets capture progress only when the territory raster changes, so on
## a static board the ring froze. Advance it at the hold rate
## between updates, the same ClaimProgressExtrapolator Sfx uses; callers gate
## this to live client matches. Each real update snaps it back.
func extrapolate_capture(delta: float, hold_seconds: float) -> void:
	if not _capture_ext.advance(delta, hold_seconds):
		return
	var team_id: int = _capture_ext.team()
	_minimap.set_capture(team_id, _capture_ext.progress())
	set_capture(team_id, _capture_ext.progress(), _color_for_team(team_id))


## A shared win (CTF tie) replaces the sole-winner text, from the payload's
## winners list. Single-winner payloads leave show_winner()'s text untouched.
func _on_match_results_ready(results: Dictionary) -> void:
	# The results screen owns the end of a match; the whole HUD (previews, stats, timer
	# ring, countdown, minimap) steps aside so nothing draws over its card.
	visible = false
	var shared: String = ResultsScreen.shared_winners_text(results, _resolved_team_numbers())
	if not shared.is_empty():
		_winner_label.text = shared


func _on_match_won(team_id: int) -> void:
	_capture_ext.clear()
	show_winner(team_id, _color_for_team(team_id))


## The status label already reads home_flag_alive, but it is only rebuilt on
## turn_changed/set_local_slot, so an elimination that lands in between would
## sit invisible until the next one. Repainting it here is the whole
## reaction.
func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	if slot_id != _active_slot:
		return
	set_held_shape(null)
	set_next_shape(null)
	show_eliminated_banner(slot_id)
	set_local_slot(_active_slot)


## the large red "Eliminated by <name>" text for `slot_id`'s own
## screen; "Eliminated" alone when the eliminator is unknown (a disconnect, a
## knockout with no single attacker). Stays up until the match leaves play.
func show_eliminated_banner(slot_id: int) -> void:
	if _eliminated_label == null:
		return
	var by_slot: int = -1
	if match_provider != null and match_provider.has_method(&"eliminated_by"):
		by_slot = int(match_provider.eliminated_by(slot_id))
	if by_slot >= 0:
		_eliminated_label.text = hud_visual_tuning.eliminated_by_text % _name_for_slot(by_slot)
	else:
		_eliminated_label.text = hud_visual_tuning.eliminated_text
	_eliminated_label.visible = true


## An instant refresh for the local slot the moment it claims a crate, rather than
## waiting up to one frame for _process()'s poll below.
## _refresh_special_indicator() re-reads Match itself (not the signal's special_id) so
## this handler and the per-frame poll can never disagree about the queue.
##
## Events.gift_claimed's second argument is the RESOLVED RECIPIENT slot -- the one
## teammate nearest the crate, not every teammate. This toast is still a team-wide
## notification (a teammate should see "your team claimed a special" even on the frame
## they don't hold it), so both sides of the comparison go through _team_of_slot().
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
		# _process() polls this every frame; skip the
		# minimap's duplicate + redraw unless a crate actually changed.
		var states: Array[Dictionary] = match_provider.gift_states()
		if states == _last_gift_states:
			return
		_last_gift_states = states.duplicate(true)
		_minimap.set_gift_states(states)


# --- Helpers -----------------------------------------------------------------

## Forwards the running match's MapDef to the minimap. Null-safe like
## _team_of_slot(): match_provider == null or no config yet
## (pre-match, or a bare HUD-only test) leaves the minimap in its initial
## hidden/disabled state. Only pushes set_map_def() when the map actually changed, so
## a placement's territory-share tick doesn't re-frame the minimap.
##
## Also forwards the live TerritoryRaster/player colors/home positions every tick
## (Minimap.set_match_state(), cheap reference stores), guarded by has_method(&"raster")
## like set_feed_seconds()'s feed_time_left() read: the real Match autoload has
## raster(), tests/support/FakeMatch.gd does not, and a bare HUD-only instance should
## leave the minimap as it was rather than error.
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
	# Lobby rework: territory and goal colours are per TEAM
	# (territory_colors()); the home beacons stay per SLOT (player_colors).
	_minimap.set_match_state(raster, running_config.territory_colors(), homes, running_config.player_colors)
	_update_gift_markers()


## Stackfall Arcade: the plate every HUD group sits on (disc-900 at hud-plate opacity,
## radius-panel, a solid disc-950 drop under it), or with `inner` a disc-700 card with a compact lip
## (radius-block). Colours and radii come from hud_visual_tuning / ArcadeVisualTuning so the HUD
## scene holds no literals.
func _style_panel(panel: Panel, inner: bool = false) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	if inner:
		style.bg_color = _arcade.disc_700_color
		style.border_color = MenuStyleFactory.lip_for(_arcade.disc_700_color)
		style.border_width_bottom = _arcade.lip_sm_px
		style.set_corner_radius_all(_arcade.radius_block_px)
	else:
		style.bg_color = hud_visual_tuning.surface_color
		style.border_color = hud_visual_tuning.surface_border_color
		style.set_border_width_all(int(hud_visual_tuning.panel_border_width_px))
		style.set_corner_radius_all(int(hud_visual_tuning.panel_corner_radius_px))
		style.shadow_color = _arcade.disc_950_color
		style.shadow_size = 1
		style.shadow_offset = Vector2(0.0, float(_arcade.drop_sm_px))
	panel.add_theme_stylebox_override("panel", style)


## HELD / NEXT card captions: the design's `label` text style (Rubik 800, 13 px, dust).
func _style_card_caption(caption: Label) -> void:
	caption.theme_type_variation = &"FieldLabel"
	caption.add_theme_color_override("font_color", _arcade.dust_color)


## A small status plate under the scoreboard (queued special, round clock): the
## label on a hud-plate with `ink` text.
func _style_status_plate(label: Label, ink: Color) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = hud_visual_tuning.surface_color
	style.border_color = hud_visual_tuning.surface_border_color
	style.set_border_width_all(int(hud_visual_tuning.panel_border_width_px))
	style.set_corner_radius_all(_arcade.radius_block_px)
	style.content_margin_left = float(_arcade.space_3_px)
	style.content_margin_right = float(_arcade.space_3_px)
	style.content_margin_top = float(_arcade.space_1_px)
	style.content_margin_bottom = float(_arcade.space_1_px)
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_font_size_override("font_size", _arcade.font_size_label_px)
	label.theme_type_variation = &"FieldLabel"
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## every HUD control lives under this root. The window's UI scale (content scale
## factor) scales the whole canvas, so the root is scaled by HUD scale / UI scale and sized to the logical
## canvas divided by that factor: the HUD's on-screen size follows the HUD scale alone, and every HUD
## anchor (corners, timer, toasts, held/next) still resolves against the visible canvas.
## DECISION: a HUD-only root Control rather than a CanvasLayer transform, because a CanvasLayer's scale
## does not rescale the anchors' parent rect and would push right/bottom anchored panels off screen.
func _build_scale_root() -> void:
	_scale_root = Control.new()
	_scale_root.name = "HudScaleRoot"
	_scale_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scale_root)
	for child: Node in get_children():
		if child != _scale_root and child is Control:
			child.reparent(_scale_root, false)


func _show_hud() -> void:
	_hud_hidden = false
	_hud_pad_pending = false
	if _scale_root != null:
		_scale_root.visible = true


func _toggle_hud() -> void:
	_hud_hidden = not _hud_hidden
	if _scale_root != null:
		_scale_root.visible = not _hud_hidden


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var pad: InputEventJoypadButton = event as InputEventJoypadButton
		if event.is_action(&"hud_toggle"):
			if pad.pressed:
				_hud_pad_pending = true
			elif _hud_pad_pending:
				_hud_pad_pending = false
				_toggle_hud()
			return
		if pad.pressed:
			_hud_pad_pending = false
		return
	if event.is_action_pressed(&"hud_toggle"):
		_toggle_hud()


## Sizes and scales the scale root for the current viewport and scale settings.
func _apply_hud_layout() -> void:
	if _scale_root == null:
		return
	var factor: float = maxf(UiScaleTuning.hud_relative_factor(), 0.01)
	_scale_root.scale = Vector2(factor, factor)
	_scale_root.position = Vector2.ZERO
	_scale_root.size = get_viewport().get_visible_rect().size / factor
	_fit_top_left_cluster()


func _on_hud_scale_changed(_value: float) -> void:
	_apply_hud_layout()


func _on_minimap_size_changed(preset: int) -> void:
	_minimap.set_size_px(UiScaleTuning.shared().minimap_size_px_for(preset))


## on a narrow (UI-scaled) canvas the scoreboard would run under the centred timer
## ring; its right edge is clamped to keep UiScaleTuning.hud_timer_clearance_px clear of it.
func _fit_top_left_cluster() -> void:
	var canvas_w: float = _scale_root.size.x
	var ring_left: float = canvas_w * _timer_ring.anchor_left + _timer_ring.offset_left
	var limit: float = ring_left - float(UiScaleTuning.shared().hud_timer_clearance_px) - hud_visual_tuning.card_padding_px
	_top_left_cluster.offset_right = minf(_top_left_cluster_base_right, maxf(limit, _top_left_cluster.offset_left))
	_resize_top_left_backplate()


func _resize_top_left_backplate() -> void:
	var padding: float = hud_visual_tuning.card_padding_px
	_top_left_backplate.size = Vector2(
		maxf(_top_left_cluster.size.x, _top_left_cluster.get_combined_minimum_size().x) + padding * 2.0,
		_top_left_cluster.get_combined_minimum_size().y + padding * 2.0
	)
	# the status rows (locked/special/toast/mode score) live
	# outside the stats box, stacked just below it.
	_status_pill.position = Vector2(
		_top_left_backplate.position.x, _top_left_backplate.position.y + _top_left_backplate.size.y + padding
	)


## Every transient HUD message (reject, relocated, gift claimed) goes through
## the one bottom-centre ToastStack, which sits above the HELD/NEXT card row so it never covers the
## cards, the gift card's key prompt or the minimap. Audit: the 3-2-1/GO numeral is a persistent
## state display (stays centred); the winner banner is hidden (the results screen owns it); the
## special-queued chip and pending-gift line are status rows (stay in the status pill), not toasts.
func _setup_toast_stack() -> void:
	_toasts.styler = _style_toast
	_toasts.max_visible = hud_visual_tuning.toast_max_visible
	_toasts.gap_px = int(hud_visual_tuning.toast_row_gap_px)
	var half: float = hud_visual_tuning.toast_max_width_px * 0.5
	_toasts.offset_left = -half
	_toasts.offset_right = half
	_toasts.offset_bottom = _held_next_panel.offset_top - hud_visual_tuning.toast_gap_above_cards_px
	_toasts.offset_top = _toasts.offset_bottom


func _style_toast(label: Label, face: Color, glyph: HudCallout.Glyph) -> void:
	if label.get_node_or_null("CalloutIcon") == null:
		_style_callout(label, glyph)
	_set_callout(label, face, glyph)


## The one Callout look every transient HUD
## message shares (claim toast, refusal, relocation): a block face (alert / mint / rim) with a
## dark lip, an ink icon tile on its left (HudCallout) and uppercase ink text. The face is the
## label's own "normal" stylebox, so a single modulate fade fades face, tile and text together.
func _style_callout(label: Label, glyph: HudCallout.Glyph) -> void:
	var tuning: HUDVisualTuning = hud_visual_tuning
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.set_corner_radius_all(int(tuning.toast_corner_radius_px))
	style.border_width_bottom = int(tuning.toast_border_width_px)
	style.shadow_color = _arcade.disc_950_color
	style.shadow_size = 1
	style.shadow_offset = Vector2(0.0, float(_arcade.drop_sm_px))
	style.content_margin_left = tuning.toast_padding_x_px * 2.0 + tuning.callout_icon_px
	style.content_margin_right = tuning.toast_padding_x_px
	style.content_margin_top = tuning.toast_padding_y_px
	style.content_margin_bottom = tuning.toast_padding_y_px
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_font_override("font", _ui_theme.get_font(&"font", &"FieldLabel"))
	label.add_theme_font_size_override("font_size", tuning.toast_font_size)
	label.add_theme_color_override("font_color", _arcade.ink_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tile: HudCallout = HudCallout.new()
	tile.name = "CalloutIcon"
	tile.configure(tuning, _arcade)
	tile.glyph = glyph
	tile.anchor_top = 0.5
	tile.anchor_bottom = 0.5
	tile.offset_left = tuning.toast_padding_x_px
	tile.offset_right = tuning.toast_padding_x_px + tuning.callout_icon_px
	tile.offset_top = -tuning.callout_icon_px * 0.5
	tile.offset_bottom = tuning.callout_icon_px * 0.5
	label.add_child(tile)
	_set_callout(label, _arcade.rim_color, glyph)


## Paints `label`'s Callout with `face` (its lip is the face's design lip) and `glyph`.
func _set_callout(label: Label, face: Color, glyph: HudCallout.Glyph) -> void:
	var style: StyleBoxFlat = label.get_theme_stylebox("normal") as StyleBoxFlat
	if style != null:
		style.bg_color = face
		style.border_color = MenuStyleFactory.lip_for(face)
	var tile: HudCallout = label.get_node_or_null("CalloutIcon") as HudCallout
	if tile != null:
		tile.glyph = glyph


## No dedicated Events signal exists for "home flag lost", so, like PlayerController,
## the HUD reads the already-documented PlayerSlot.home_flag_alive straight off
## Match.slot().
func _is_slot_eliminated(slot_id: int) -> bool:
	if match_provider == null:
		return false
	var slot: PlayerSlot = match_provider.slot(slot_id)
	return slot != null and not slot.home_flag_alive


## null-safe mirror of config/match/MatchConfig.gd's team_of_slot()
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
## slot's colour); otherwise team id t is slot t, so _color_for_slot(team_id).
func _color_for_team(team_id: int) -> Color:
	if match_provider != null:
		var running_config: Variant = match_provider.config
		if running_config != null and bool(running_config.teams_resolved()):
			var colors: PackedColorArray = running_config.territory_colors()
			if team_id >= 0 and team_id < colors.size():
				return colors[team_id]
	return _color_for_slot(team_id)


## Whether team `team_id` is out. Resolved lobby teams: every slot of the team has
## lost its home flag (team ids no longer equal slot ids); otherwise "slot t is team t".
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
	var live_color: Variant = null
	if match_provider != null:
		var slot: PlayerSlot = match_provider.slot(slot_id)
		if slot != null:
			live_color = slot.color
	return SlotColors.resolve(slot_id, live_color, default_palette.player_colors)


## PlayerSlot.display_name when Match has built one, otherwise the "Player N" fallback
## (pre-match, and in a bare HUD-only test with no FakeMatch.slots_by_id entry).
##
## A human seat's replicated roster name wins over the slot's own label (the host never
## copies roster names onto its PlayerSlots, so its slots still read "Player N"); bots
## keep their slot label.
func _name_for_slot(slot_id: int) -> String:
	var peer_name: String = String(_names().name_for_slot(slot_id))
	if match_provider != null:
		var slot: PlayerSlot = match_provider.slot(slot_id)
		if slot != null:
			return PlayerNames.label_for_slot(slot_id, slot.display_name, slot.is_bot, peer_name)
	return PlayerNames.label_for_slot(slot_id, "", false, peer_name)


## the display name of the row for team `team_id`: the roster name of
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


## The pending-special queue indicator, next to the next-shape preview. Reads
## `_active_slot` the same way the previews do (the local
## slot) rather than tracking a slot of its own. No dedicated "a
## special was consumed at spawn" signal exists, so, like set_feed_progress/set_height/
## set_locked above, _process() polls it every frame; _on_gift_claimed() above only
## shortcuts the wait for the specific claim case.
func _refresh_special_indicator() -> void:
	_refresh_gift_slot()
	if match_provider == null or _active_slot < 0:
		_last_special_signature = []
		_set_glue_active(false)
		_special_indicator.visible = false
		_set_gift_icons(&"", &"")
		_held_label.text = "HELD"
		_next_label.text = "NEXT"
		_next_label.add_theme_color_override("font_color", _arcade.dust_color)
		return
	var count: int = int(match_provider.pending_special_count(_active_slot))
	var head_id: StringName = match_provider.held_special(_active_slot)
	var glue_charges: int = 0
	if match_provider.has_method(&"glue_drops_left"):
		glue_charges = int(match_provider.glue_drops_left(_active_slot))
	# nothing below depends on anything but these inputs.
	# a claimed gift staged as the block AFTER next is not the next piece;
	# the NEXT preview keeps the ordinary block and the label marks the queued gift.
	var staged_id: StringName = StringName(match_provider.after_next_special(_active_slot)) if match_provider.has_method(&"after_next_special") else &""
	var staged_count: int = 1 if staged_id != &"" else 0
	var next_id: StringName = _next_gift_id_for(count - staged_count, head_id)
	var signature: Array = [_active_slot, _active_color, count, head_id, next_id, glue_charges, _qol_backlog, staged_id]
	if signature == _last_special_signature:
		return
	_last_special_signature = signature
	_set_gift_icons(head_id, next_id)
	_set_glue_active(glue_charges > 0)
	_held_label.text = "HELD: %s" % _special_display_name(head_id) if head_id != &"" else "HELD"
	var next_is_gift: bool = count - staged_count > (1 if head_id != &"" else 0)
	_next_label.text = "NEXT · GIFT" if next_is_gift else "NEXT"
	if staged_count > 0:
		_next_label.text += " +1" if next_is_gift else " · +1 GIFT"
	_next_label.add_theme_color_override("font_color", _arcade.rim_color if (next_is_gift or staged_count > 0) else _arcade.dust_color)
	if _qol_backlog > 0:
		_next_label.text += " +%d" % _qol_backlog
	if count <= 0 and glue_charges <= 0:
		_special_indicator.visible = false
		return
	var pending_text: String = _special_display_text(head_id, count) if count > 0 else ""
	var glue_text: String = "Glue ×%d" % glue_charges if glue_charges > 0 else ""
	_special_indicator.text = "%s · %s" % [pending_text, glue_text] if count > 0 and glue_charges > 0 else pending_text + glue_text
	_special_indicator.visible = true


## "Special ×N" once a second one is queued (N > 1); just the head id's
## display name otherwise (decision: matches the next-shape preview, which
## also never shows a bare count for a single item).
func _special_display_text(head_id: StringName, count: int) -> String:
	var display_name: String = _special_display_name(head_id)
	if count > 1:
		return "%s ×%d" % [display_name, count]
	return display_name


## MatchGifts.PENDING_SPECIAL_ID is the placeholder every claim draws until the real
## weighted SpecialDef pick is installed (autoload/match/MatchGifts.gd's own DECISION);
## shown as the generic "Special" rather than its literal id ("special_pending"
## .capitalize() would misleadingly read "Special Pending"). A real special's id is
## shown as its own String.capitalize() (snake_case -> Title Case), e.g. "jumping_bean"
## -> "Jumping Bean".
func _special_display_name(head_id: StringName) -> String:
	return DisplayNames.special(head_id)


## One row per player: a small team-colored diamond glyph (the shared SlotDiamond)
## beside a slim rounded territory-share bar. Each bar is ONE ui/menus/ShareBar.gd
## control drawing its track, the team-colored fill inside it and a sheen.
func _ensure_share_row_count(count: int) -> void:
	while _share_rows.size() < count:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", _arcade.space_2_px)

		var glyph: SlotDiamond = SlotDiamond.create(Color.WHITE)

		# Name column: the player's name (ellipsized) and, on the local row only, "· YOU" in rim gold.
		var name_box: HBoxContainer = HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 0)
		name_box.custom_minimum_size = Vector2(hud_visual_tuning.hud_row_name_width_px, 0.0)
		name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label: Label = Label.new()
		name_label.theme_type_variation = &"FieldLabel"
		name_label.add_theme_font_size_override("font_size", _arcade.font_size_button_sm_px)
		name_label.add_theme_color_override("font_color", hud_visual_tuning.ink_color)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var you_label: Label = Label.new()
		you_label.theme_type_variation = &"FieldLabel"
		you_label.add_theme_font_size_override("font_size", _arcade.font_size_label_px)
		you_label.add_theme_color_override("font_color", _arcade.rim_color)
		you_label.text = hud_visual_tuning.hud_you_text
		you_label.visible = false
		you_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		you_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_box.add_child(name_label)
		name_box.add_child(you_label)

		var bar: ShareBar = ShareBar.new()
		bar.configure(hud_visual_tuning)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var label: Label = Label.new()
		# The score/percentage in Bungee, right-aligned in a fixed column.
		label.add_theme_font_override("font", _display_font)
		label.add_theme_font_size_override("font_size", _arcade.font_size_button_sm_px)
		label.add_theme_color_override("font_color", _arcade.cream_color)
		label.custom_minimum_size = Vector2(hud_visual_tuning.hud_row_value_width_px, 0.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		row.add_child(glyph)
		row.add_child(name_box)
		var mult_label: UiText = UiText.make(UiText.Role.VALUE, "", _arcade.rim_color)
		mult_label.visible = false
		row.add_child(mult_label)
		row.add_child(bar)
		row.add_child(label)
		_shares_box.add_child(row)
		_share_rows.append(row)
		_share_bars.append(bar)
		_share_labels.append(label)
		_share_name_labels.append(name_label)
		_share_glyphs.append(glyph)
		_share_you_labels.append(you_label)
		_share_mult_labels.append(mult_label)
	while _share_rows.size() > count:
		var last: int = _share_rows.size() - 1
		(_share_rows[last] as Node).queue_free()
		_share_rows.remove_at(last)
		_share_bars.remove_at(last)
		_share_labels.remove_at(last)
		_share_name_labels.remove_at(last)
		_share_glyphs.remove_at(last)
		_share_you_labels.remove_at(last)
		_share_mult_labels.remove_at(last)


## Shows the "· YOU" marker on the row of the active slot's team only.
func _refresh_you_markers() -> void:
	for i: int in range(_share_you_labels.size()):
		(_share_you_labels[i] as Label).visible = _active_slot >= 0 and _team_of_slot(_active_slot) == i


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
	var glyph: SlotDiamond = _share_glyphs[i]
	glyph.set_color(color)
	(_share_you_labels[i] as Label).visible = _active_slot >= 0 and _team_of_slot(_active_slot) == i
	var chip: String = BeaconTimerText.multiplier_text_in_state(_mode_state, i)
	var mult_label: Label = _share_mult_labels[i]
	mult_label.text = chip
	mult_label.visible = not chip.is_empty()


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
	# A soft offset dark disc behind everything else, then the round hud-plate itself
	# so the numeral always has contrast against a bright sky.
	_timer_ring.draw_circle(center + DROP_SHADOW_OFFSET, radius - RING_LINE_WIDTH * 0.5, DROP_SHADOW_COLOR)
	_timer_ring.draw_circle(center, radius - RING_LINE_WIDTH * 0.5, hud_visual_tuning.panel_background_color)
	var locked: bool = _locked or _qol_paused
	# FeedTimer: the active player's colour counts down around a
	# disc-500 track; the last `timer_hurry_seconds` turn ring and number rim gold; a release lock
	# draws one full `locked` circle (disc-500), with no text.
	var hurry: bool = _feed_seconds_left >= 0.0 and _feed_seconds_left <= hud_visual_tuning.timer_hurry_seconds
	if locked:
		_timer_ring.draw_arc(center, radius, 0.0, TAU, 48, _arcade.locked_color, RING_LINE_WIDTH)
	else:
		_timer_ring.draw_arc(center, radius, 0.0, TAU, 48, _arcade.disc_500_color, RING_LINE_WIDTH)
		if _feed_progress > 0.0:
			# DECISION (ui/hud/HUD.gd): this HUD is per-viewer, so there is only
			# ever one player's colour to draw here.
			var ring_color: Color = _arcade.rim_color if hurry else _active_color
			_timer_ring.draw_arc(
				center, radius, -PI * 0.5, -PI * 0.5 + TAU * _feed_progress, 48, ring_color, RING_LINE_WIDTH
			)
	if _feed_seconds_left >= 0.0:
		_draw_timer_numeral(center, hurry and not locked)


## the bold numeral inside the timer ring, ceil()'d the same way a countdown
## reads to a player (still shows "1" for the last fraction of a second, not "0"). Stackfall
## Arcade: Bungee in cream (rim in the hurry window). The lock shows only as the full `locked`
## ring, never as text.
func _draw_timer_numeral(center: Vector2, hurry: bool) -> void:
	var font: Font = _display_font if _display_font != null else _timer_ring.get_theme_default_font()
	var font_size: int = _arcade.font_size_timer_px
	var color: Color = _arcade.rim_color if hurry else _arcade.cream_color
	var text: String = QOL_PAUSED_TEXT if _qol_paused else str(int(ceil(maxf(_feed_seconds_left, 0.0))))
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline: Vector2 = center + Vector2(-text_width * 0.5, font_size * 0.35)
	_timer_ring.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


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


## gift ids currently shown by the held/next previews
## (&"" = ordinary block). A gift draws SpecialDef.preview_icon_for() (the
## generic gift icon when the def has none) instead of the shape image.
var _held_gift_id: StringName = &""
var _next_gift_id: StringName = &""


## The next piece is a gift iff more is queued than the held piece accounts
## for; the id is the queue head (falls back to a generic placeholder id).
func _next_gift_id_for(count: int, head_id: StringName) -> StringName:
	if count <= (1 if head_id != &"" else 0):
		return &""
	var next_id: StringName = &""
	if match_provider.has_method(&"next_special"):
		next_id = match_provider.next_special(_active_slot)
	return next_id if next_id != &"" else GENERIC_GIFT_ID


## while Glue charges remain, the held/next previews wear a
## jelly tint (HoneyCoatTuning.hud_jelly_tint) drawn over the block silhouette.
const HONEY_TUNING_PATH: String = "res://config/gifts/honey_coat_tuning.tres"
static var _honey_tuning: HoneyCoatTuning = null
var _glue_active: bool = false


## leaving a match (lobby/end) drops the overlay at once and
## forces the next refresh to re-read the charges.
func _on_match_state_changed_glue(_from_state: int, to_state: int) -> void:
	if _eliminated_label != null and (Match.is_lobby_or_end(to_state) or Match.is_pregame(to_state)):
		_eliminated_label.visible = false
	if to_state != Match.State.END:
		visible = true
	if Match.is_pregame(to_state):
		prime_pregame_widgets()
	if Match.is_lobby_or_end(to_state):
		_last_special_signature = []
		_set_glue_active(false)


## The player-stat rows and minimap otherwise fill in only on the first
## territory_share_changed, which the solver emits once play begins, so the countdown
## would show an empty stats panel and no minimap. Called on LOADING/COUNTDOWN (the
## HUD is loaded behind the Ready screen): builds one zero-share row per team and
## pushes the map/raster/homes to the minimap.
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


func _set_glue_active(active: bool) -> void:
	if active == _glue_active:
		return
	_glue_active = active
	_shape_preview.queue_redraw()
	_next_shape_preview.queue_redraw()


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
	_style_card_caption(_gift_slot_label)
	var card: Panel = Panel.new()
	card.custom_minimum_size = _held_shape_card.custom_minimum_size
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_panel(card, true)
	# the icon sits above a strip reserved for the bound-key glyph, so
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


## the use_gift_slot binding for the player's current device
## family, drawn by the shared InputGlyph (keycap/pad art, or its fallback). Rebuilt
## only when the device or the bound events changed, so a rebind in the pause
## menu shows up on the card without any signal of its own.
func _refresh_gift_slot_glyph(force: bool = false) -> void:
	if _gift_slot_glyph_row == null:
		return
	var signature: String = InputGlyph.signature_for_action(GIFT_SLOT_ACTION)
	if signature == _gift_slot_glyph_signature and not force:
		return
	_gift_slot_glyph_signature = signature
	if _gift_slot_glyph != null:
		_gift_slot_glyph_row.remove_child(_gift_slot_glyph)
		_gift_slot_glyph.queue_free()
		_gift_slot_glyph = null
	var built: Array[InputGlyph] = InputGlyph.build_for_action(_gift_slot_glyph_row, GIFT_SLOT_ACTION, 1)
	if not built.is_empty():
		_gift_slot_glyph = built[0]


func _on_input_device_changed(_device: StringName) -> void:
	if _gift_slot_column != null and _gift_slot_column.visible:
		_refresh_gift_slot_glyph()


## the gift icon is never tinted with the player colour.
func _on_gift_slot_preview_draw() -> void:
	if _gift_slot_id == &"":
		return
	var texture: Texture2D = SpecialDef.preview_icon_for(_gift_slot_id)
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	var fit: float = minf(_gift_slot_preview.size.x / texture_size.x, _gift_slot_preview.size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * fit
	_gift_slot_preview.draw_texture_rect(texture, Rect2((_gift_slot_preview.size - draw_size) * 0.5, draw_size), false, Color.WHITE)


func _draw_static_shape(control: Control, shape: BlockShape, color: Color) -> void:
	var gift_id: StringName = _held_gift_id if control == _shape_preview else _next_gift_id
	var texture: Texture2D = SpecialDef.preview_icon_for(gift_id) if gift_id != &"" else _preview_texture(shape)
	if texture == null:
		return
	var texture_size: Vector2 = texture.get_size()
	var scale: float = minf(control.size.x / texture_size.x, control.size.y / texture_size.y)
	var draw_size: Vector2 = texture_size * scale
	var image_rect: Rect2 = Rect2((control.size - draw_size) * 0.5, draw_size)
	control.draw_texture_rect(texture, image_rect, false, color)
	if _glue_active and gift_id == &"":
		if _honey_tuning == null:
			_honey_tuning = load(HONEY_TUNING_PATH) as HoneyCoatTuning
		# Jelly tint follows the silhouette exactly (same texture, amber modulate).
		control.draw_texture_rect(texture, image_rect, false, _honey_tuning.hud_jelly_tint)


func _on_capture_ring_draw() -> void:
	var size: Vector2 = _capture_ring.size
	var radius: float = minf(size.x, size.y) * 0.5 - RING_LINE_WIDTH
	var center: Vector2 = size * 0.5
	_capture_ring.draw_arc(center, radius, 0.0, TAU, 48, _arcade.disc_500_color, RING_LINE_WIDTH)
	if _capture_progress > 0.0:
		_capture_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _capture_progress, 48, _capture_color, RING_LINE_WIDTH
		)
