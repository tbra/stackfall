class_name HUD
extends CanvasLayer
## Spec 2.10's HUD, scoped to what M2/Bontago-mv0.9 need: a timer ring around
## the held-block preview, a separate next-block preview, max height,
## per-player territory share, capture ring, a LOCKED indicator, and a
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
## per-player cluster and the bottom-right minimap) and fixes the iso
## preview renderer to center on each shape's own projected bounding box
## instead of its cell centroid (see _draw_iso_shape()'s own DECISION).
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


## Bontago-mp0.3.3 (owner review 2026-09-26: "bar ~22-25% of screen width"):
## 300px is 23.4% of the 1280px reference width tools/capture_mockup08.tscn
## and every other fixed HUD offset in this file already assume.
const SHARE_BAR_MAX_WIDTH: float = 300.0
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
## the timer ring's disc and the next-shape card's iso cubes.
const DROP_SHADOW_OFFSET: Vector2 = Vector2(2.0, 3.0)
const DROP_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.35)
## Bontago-mp0.3.3 (owner review 2026-09-26, next-shape card; owner review
## 2026-09-27 extended to the held-shape card too): isometric cube projection
## constants for _draw_iso_shape() below -- a 2:1 axonometric tile (top
## diamond width : height) is the standard "iso block" look the mockup's blue
## L-piece uses. These are the *unit* sizes _draw_iso_shape() measures a
## shape's own bounding box against before rescaling to ISO_FIT_FRACTION of
## whichever card is drawing -- see that function's own doc.
const ISO_TILE_WIDTH: float = 14.0
const ISO_TILE_HEIGHT: float = 7.0
const ISO_CUBE_HEIGHT: float = 11.0
## Bontago-mp0.3.3 (owner review 2026-09-27: "scale the iso drawing so the
## shape fills ~65-75% of the card regardless of shape size"); 0.7 sits in
## the middle of that range.
const ISO_FIT_FRACTION: float = 0.7
const ELIMINATED_COLOR: Color = Color(0.4, 0.4, 0.4, 0.5)
## Bontago-mv0.9: a distinct grey from ELIMINATED_COLOR (same idea, different
## meaning) for the release-locked ring/label, so a locked-but-not-eliminated
## slot never reads as "this player is out".
const LOCKED_COLOR: Color = Color(0.75, 0.75, 0.75, 0.9)

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

	# Bontago-mp0.3.3 (mockup 08 restyle): no boxy panel behind the top-left
	# readouts (feedback/graphics_feedback.md, Bontago-mp0.2) -- every label
	# there gets a soft outline instead, so it stays legible directly over a
	# bright sky. The next-shape and held-shape cards are the readouts that
	# do keep a backing panel (see _style_panel()'s own doc).
	_style_panel(_held_next_panel)
	_style_panel(_next_shape_card)
	_style_panel(_held_shape_card)
	for label: Label in [
		_turn_label, _height_label, _locked_label, _special_indicator,
		_gift_toast_label, _reject_label,
	]:
		label.add_theme_color_override("font_color", hud_visual_tuning.panel_text_color)
		_apply_text_outline(label)
	# Bontago-mp0.3.3 (owner review 2026-09-26: "row gap ~12 px"). The status
	# labels above sit in %StatusPill, a VBoxContainer nested right under
	# %SharesBox inside their shared %TopLeftCluster (ui/HUD.tscn) -- both
	# stack directly under however many player rows currently exist, so
	# nothing here floats independent of row count (the earlier "orphaned
	# mid-left text" bug).
	_shares_box.add_theme_constant_override("separation", 12)

	Events.turn_changed.connect(_on_turn_changed)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.placement_relocated.connect(_on_placement_relocated)
	Events.territory_share_changed.connect(_on_territory_share_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.match_won.connect(_on_match_won)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_claimed.connect(_on_gift_claimed)


func _process(_delta: float) -> void:
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
	if match_provider == null or _active_slot < 0:
		return
	set_feed_progress(match_provider.feed_progress(_active_slot))
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
	_pull_current_shapes(slot_id)
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
	_pull_current_shapes(slot_id)
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


## Bontago-mp0.3.3: seconds left on the block timer, shown as the bold
## numeral inside the timer ring (mockup 08's "6"). A negative value (the
## -1.0 default, or a caller's own choice) draws no numeral at all.
func set_feed_seconds(seconds: float) -> void:
	_feed_seconds_left = seconds
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
	_winner_label.text = "Team %d wins!" % (team_id + 1)
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
##
## Bontago-keo.17 (owner decision "b"): Events.gift_claimed's second argument
## is the RESOLVED RECIPIENT slot -- the one teammate nearest the crate, not
## every teammate. This HUD toast is still a team-wide notification (a
## teammate should see "your team claimed a special" even on the frame they
## don't hold it), so both sides of the comparison go through
## _team_of_slot(): the active slot's own team against the recipient's team.
func _on_gift_claimed(_gift_id: int, slot_id: int, special_id: StringName) -> void:
	if _team_of_slot(_active_slot) != _team_of_slot(slot_id):
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
	_minimap.set_match_state(raster, running_config.player_colors, homes)


## M7 P5 / Bontago-mp0.3.3: the one StyleBoxFlat a reskinned HUD panel uses,
## built from hud_visual_tuning so ui/HUD.tscn itself holds no colour
## literals (mirrors ui/Minimap.gd's own panel styling for the minimap's
## frame/backdrop). Only the next-shape and held-shape cards use this now --
## mockup 08's top-left readouts are plain outlined text
## (_apply_text_outline() below), not a panel.
func _style_panel(panel: Panel) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = hud_visual_tuning.panel_background_color
	style.border_color = hud_visual_tuning.panel_border_color
	style.set_border_width_all(int(hud_visual_tuning.panel_border_width_px))
	style.set_corner_radius_all(int(hud_visual_tuning.panel_corner_radius_px))
	panel.add_theme_stylebox_override("panel", style)


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


## Bontago-mp0.3.3 (mockup 08): one row per player, a small team-colored
## diamond glyph (_on_row_glyph_draw() below) beside a slim rounded
## territory-share bar -- a dark translucent track (bar_track's StyleBoxFlat)
## under a saturated team-colored fill (bar_fill, still a plain ColorRect so
## tests/unit/test_hud.gd's existing `ColorRect` assertions on _share_bars
## keep compiling unchanged) and a subtle highlight sheen on top. Replaces
## the old boxy SharesPanel background entirely (Bontago-mp0.2).
func _ensure_share_row_count(count: int) -> void:
	while _share_rows.size() < count:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var glyph: Control = Control.new()
		glyph.custom_minimum_size = Vector2(
			hud_visual_tuning.hud_row_glyph_size_px, hud_visual_tuning.hud_row_glyph_size_px
		)
		glyph.set_meta(&"glyph_color", Color.WHITE)
		glyph.draw.connect(_on_row_glyph_draw.bind(glyph))

		var bar_track: Panel = Panel.new()
		bar_track.custom_minimum_size = Vector2(SHARE_BAR_MAX_WIDTH, SHARE_BAR_HEIGHT)
		var track_style: StyleBoxFlat = StyleBoxFlat.new()
		track_style.bg_color = hud_visual_tuning.hud_share_bar_track_color
		track_style.set_corner_radius_all(int(SHARE_BAR_HEIGHT * 0.5))
		# Bontago-mp0.3.3 (owner review 2026-09-26: "thin light inner border").
		track_style.border_color = hud_visual_tuning.hud_share_bar_border_color
		track_style.set_border_width_all(1)
		bar_track.add_theme_stylebox_override("panel", track_style)

		var bar_fill: ColorRect = ColorRect.new()
		bar_fill.custom_minimum_size = Vector2(0.0, SHARE_BAR_HEIGHT)
		bar_fill.size = Vector2(0.0, SHARE_BAR_HEIGHT)
		bar_track.add_child(bar_fill)

		var highlight: ColorRect = ColorRect.new()
		highlight.color = hud_visual_tuning.hud_share_bar_highlight_color
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.size = Vector2(SHARE_BAR_MAX_WIDTH, SHARE_BAR_HEIGHT * 0.35)
		highlight.position = Vector2(0.0, 1.0)
		bar_track.add_child(highlight)

		var label: Label = Label.new()
		# Bontago-mp0.3.3 (owner review 2026-09-26: "percent label optional/
		# small ... with a text shadow").
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", hud_visual_tuning.panel_text_color)
		_apply_text_outline(label)

		row.add_child(glyph)
		row.add_child(bar_track)
		row.add_child(label)
		_shares_box.add_child(row)
		_share_rows.append(row)
		_share_bars.append(bar_fill)
		_share_labels.append(label)
		_share_glyphs.append(glyph)
	while _share_rows.size() > count:
		var last: int = _share_rows.size() - 1
		(_share_rows[last] as Node).queue_free()
		_share_rows.remove_at(last)
		_share_bars.remove_at(last)
		_share_labels.remove_at(last)
		_share_glyphs.remove_at(last)


func _update_share_row(i: int, share: float) -> void:
	var eliminated: bool = _is_slot_eliminated(i)
	var color: Color = ELIMINATED_COLOR if eliminated else _color_for_slot(i)
	var bar: ColorRect = _share_bars[i]
	bar.color = color
	var width: float = SHARE_BAR_MAX_WIDTH * clampf(share, 0.0, 1.0)
	bar.custom_minimum_size = Vector2(width, SHARE_BAR_HEIGHT)
	bar.size = Vector2(width, SHARE_BAR_HEIGHT)
	var label: Label = _share_labels[i]
	label.text = "P%d: %.0f%%%s" % [i + 1, share * 100.0, "  (out)" if eliminated else ""]
	var glyph: Control = _share_glyphs[i]
	glyph.set_meta(&"glyph_color", color)
	glyph.queue_redraw()


## Small faceted diamond beside each share bar (mockup 08), tinted the same
## color _update_share_row() just gave that row's bar. Bontago-mp0.3.3 (owner
## review 2026-09-26: "faceted (two-tone, lit/shade halves)") -- split down
## the vertical diagonal into a lightened left half (facing the mockup's
## implied upper-left light) and a darkened right half, instead of one flat
## fill, so the glyph itself reads as a small faceted gem/block like the
## mockup's.
func _on_row_glyph_draw(glyph: Control) -> void:
	var color: Color = glyph.get_meta(&"glyph_color", Color.WHITE)
	var half: float = hud_visual_tuning.hud_row_glyph_size_px * 0.5
	var center: Vector2 = glyph.size * 0.5
	var top: Vector2 = center + Vector2(0.0, -half)
	var right: Vector2 = center + Vector2(half, 0.0)
	var bottom: Vector2 = center + Vector2(0.0, half)
	var left: Vector2 = center + Vector2(-half, 0.0)
	glyph.draw_colored_polygon(
		PackedVector2Array([top, left, bottom]), color.lightened(0.25)
	)
	glyph.draw_colored_polygon(
		PackedVector2Array([top, right, bottom]), color.darkened(0.25)
	)
	var outline: PackedVector2Array = PackedVector2Array([top, right, bottom, left, top])
	glyph.draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.55), 1.5, true)


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
		var ring_color: Color = LOCKED_COLOR if _locked else _active_color
		_timer_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _feed_progress, 48, ring_color, RING_LINE_WIDTH
		)
	if _feed_seconds_left >= 0.0:
		_draw_timer_numeral(center)


## Bontago-mp0.3.3: the bold numeral inside the timer ring (mockup 08's "6"),
## ceil()'d the same way a countdown reads to a player (still shows "1" for
## the last fraction of a second, not "0").
func _draw_timer_numeral(center: Vector2) -> void:
	var text: String = str(int(ceil(_feed_seconds_left)))
	var font: Font = _timer_ring.get_theme_default_font()
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TIMER_NUMERAL_FONT_SIZE).x
	var baseline: Vector2 = center + Vector2(-text_width * 0.5, TIMER_NUMERAL_FONT_SIZE * 0.35)
	_timer_ring.draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TIMER_NUMERAL_FONT_SIZE, 3, Color.BLACK
	)
	_timer_ring.draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, TIMER_NUMERAL_FONT_SIZE, Color.WHITE
	)


## Bontago-mp0.3.3 (owner review 2026-09-27: the old flat front-elevation
## held-shape icon read as "a stray flat glyph of two small red squares"
## next to the timer ring, unlabeled and easy to mistake for a leftover --
## restyled into its own %HeldShapeCard (ui/HUD.tscn, styled alongside
## %NextShapeCard in _ready(), with a static "HELD" label above it) and now
## drawn with the same iso-cube renderer as the next-shape card, so "what am
## I holding" and "what's coming next" read as one consistent visual language
## instead of two different icon styles.
func _on_shape_preview_draw() -> void:
	_draw_iso_shape(_shape_preview, _held_shape, _active_color)


## Bontago-mp0.3.3 (owner review 2026-09-26: "Draw the BlockShape cells as
## small iso cubes ... 3 face shades (top light, left mid, right dark), like
## the mockup's blue L piece"); owner review 2026-09-27 extended this to the
## held-shape card too (_on_shape_preview_draw() above) once it got its own
## labeled card.
func _on_next_shape_preview_draw() -> void:
	_draw_iso_shape(_next_shape_preview, _next_shape, _active_color)


## Isometric (2:1 axonometric) render of `shape`'s cells, each a small cube
## with three shaded faces (top lightened, left mid, right darkened -- a
## fixed upper-left light, matching the row glyphs' own two-tone DECISION
## above). All the fit/centering geometry lives in the pure _iso_fit() helper
## below (headlessly testable, see tests/unit/test_hud.gd
## test_iso_fit_centers_and_frames_every_block_shape) -- this function is
## just "sort back-to-front, then draw one cube per fitted top".
func _draw_iso_shape(control: Control, shape: BlockShape, color: Color) -> void:
	if shape == null:
		return
	var cells: Array[Vector3i] = shape.cells.duplicate()
	# Depth key: further back (smaller x+z, taller/lower y) draws first, so a
	# cube nearer the viewer (or stacked above another) paints over it. This
	# key is invariant to any constant shift of the cell coordinates, so it
	# does not depend on _iso_fit()'s own centering.
	cells.sort_custom(
		func(a: Vector3i, b: Vector3i) -> bool:
			return (a.x + a.z - a.y * 2) < (b.x + b.z - b.y * 2)
	)
	var fit: Dictionary = _iso_fit(cells, control.size)
	var tops: Array[Vector2] = fit["tops"]
	var tile_w: float = fit["tile_w"]
	var tile_h: float = fit["tile_h"]
	var cube_h: float = fit["cube_h"]
	for i: int in range(cells.size()):
		_draw_iso_cube(control, tops[i], color, tile_w, tile_h, cube_h)


## Pure geometry half of the iso preview: projects each of `cells` (in the
## given order -- painter-sort order for a real draw, but the fit itself is
## order-independent) into unscaled axonometric space, then scales and
## centers the whole set so it fits inside `control_size`. Returns
## {"tops": Array[Vector2], "tile_w": float, "tile_h": float, "cube_h":
## float} -- exactly what _draw_iso_cube() needs per cell, already scaled
## and positioned; `tops[i]` corresponds to `cells[i]`.
##
## DECISION (ui/HUD.gd, owner playtest 2026-09-27: "some of the blocks are
## rendered oddly in the previews"). ROOT CAUSE: the previous version
## centered cells on the shape's own centroid (the mean of its cell indices)
## and anchored that centroid at the card's center -- but the centroid of a
## shape's cell indices does not generally project to the center of the
## shape's own iso-projected bounding box (e.g. L3's cells (0,0,0)/(1,0,0)/
## (0,1,0) project to a box whose true center sits ~3.5/5.25 unit-px away
## from the centroid-anchored origin), so asymmetric shapes drew off-center
## inside their card, occasionally scaled/positioned close enough to an edge
## to look clipped or lopsided. FIX: measure every cell's unscaled projected
## position first, take the actual min/max bounding box of that projection,
## and anchor the *box's own center* (`raw_center` below) at the card's
## center instead of the centroid's projection -- this is the "auto-fit
## camera to the shape's AABB" the assignment asks for: every BlockShape
## (config/blocks/*.tres) now ends up centered and fully in frame regardless
## of how lopsided its cell layout is, with the same consistent axonometric
## orientation and per-face shading as before.
func _iso_fit(cells: Array[Vector3i], control_size: Vector2) -> Dictionary:
	var half_w: float = ISO_TILE_WIDTH * 0.5
	var unit_tops: Array[Vector2] = []
	var min_pt: Vector2 = Vector2.INF
	var max_pt: Vector2 = -Vector2.INF
	for cell: Vector3i in cells:
		var top: Vector2 = Vector2(
			(cell.x - cell.z) * ISO_TILE_WIDTH * 0.5, (cell.x + cell.z) * ISO_TILE_HEIGHT * 0.5 - cell.y * ISO_CUBE_HEIGHT
		)
		unit_tops.append(top)
		min_pt = min_pt.min(top + Vector2(-half_w, 0.0))
		max_pt = max_pt.max(top + Vector2(half_w, ISO_TILE_HEIGHT + ISO_CUBE_HEIGHT))
	var raw_size: Vector2 = max_pt - min_pt
	# The projected AABB's own center, in the same unscaled units as
	# `unit_tops` -- this, not the cell centroid, is what belongs at the
	# card's center for the shape to read as centered.
	var raw_center: Vector2 = (min_pt + max_pt) * 0.5

	var scale: float = 1.0
	if raw_size.x > 0.0 and raw_size.y > 0.0:
		var target: Vector2 = control_size * ISO_FIT_FRACTION
		scale = minf(target.x / raw_size.x, target.y / raw_size.y)

	var center: Vector2 = control_size * 0.5
	var tops: Array[Vector2] = []
	for unit_top: Vector2 in unit_tops:
		tops.append(center + (unit_top - raw_center) * scale)
	return {
		"tops": tops,
		"tile_w": ISO_TILE_WIDTH * scale,
		"tile_h": ISO_TILE_HEIGHT * scale,
		"cube_h": ISO_CUBE_HEIGHT * scale,
	}


## One iso cube, `top` being the top-most vertex of its top diamond face, at
## the given (already shape-fit) tile/cube-height dimensions.
func _draw_iso_cube(
	control: Control, top: Vector2, color: Color, tile_w: float, tile_h: float, cube_h: float
) -> void:
	var right: Vector2 = top + Vector2(tile_w * 0.5, tile_h * 0.5)
	var bottom: Vector2 = top + Vector2(0.0, tile_h)
	var left: Vector2 = top + Vector2(-tile_w * 0.5, tile_h * 0.5)
	var down: Vector2 = Vector2(0.0, cube_h)

	var top_face: PackedVector2Array = PackedVector2Array([top, right, bottom, left])
	var left_face: PackedVector2Array = PackedVector2Array([left, bottom, bottom + down, left + down])
	var right_face: PackedVector2Array = PackedVector2Array([right, bottom, bottom + down, right + down])

	control.draw_colored_polygon(left_face, color.darkened(0.1))
	control.draw_colored_polygon(right_face, color.darkened(0.35))
	control.draw_colored_polygon(top_face, color.lightened(0.3))

	var outline: Color = Color(0.0, 0.0, 0.0, 0.45)
	control.draw_polyline(PackedVector2Array([top, right, bottom, left, top]), outline, 1.0, true)
	control.draw_polyline(PackedVector2Array([bottom, bottom + down]), outline, 1.0, true)
	control.draw_polyline(PackedVector2Array([left, left + down]), outline, 1.0, true)
	control.draw_polyline(PackedVector2Array([right, right + down]), outline, 1.0, true)


func _on_capture_ring_draw() -> void:
	var size: Vector2 = _capture_ring.size
	var radius: float = minf(size.x, size.y) * 0.5 - RING_LINE_WIDTH
	var center: Vector2 = size * 0.5
	_capture_ring.draw_arc(center, radius, 0.0, TAU, 48, RING_BACKGROUND_COLOR, RING_LINE_WIDTH)
	if _capture_progress > 0.0:
		_capture_ring.draw_arc(
			center, radius, -PI * 0.5, -PI * 0.5 + TAU * _capture_progress, 48, _capture_color, RING_LINE_WIDTH
		)
