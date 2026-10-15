class_name GoalFlag
extends HomeFlag
## A goal flag (spec 2.2, 2.3): one in the center by default, 1-5 in setup,
## extras placed symmetrically at 0.4 * field_radius.
##
## Extends HomeFlag because a goal flag is the same beacon (socket, ring and
## crystal, M7 P8) at a larger scale in a neutral color; what it adds is spec
## 2.3's capture display, "a radial progress ring appears on each goal flag
## while someone is capturing it". That capture ring is a second, separate
## flat annulus arc lying on the disk (distinct from the beacon's own always-
## on Ring mesh above it), rebuilt only when the progress it shows actually
## moves.
##
## Bontago-470.7: the beacon also shows who has *claimed* the goal
## (set_control(), fed by Field from GoalControl.owners()): the ring and
## crystal take the controller's colour with boosted emission, a tall banded
## light beam rises from it, a flash and spark burst play when the claim
## changes, and a contested goal flickers between the contesting colours with
## a striped beam. The shared-hold capture ring below is unchanged and reads
## on top of this.
##
## Bontago-1pi.18.6 / mp0.152: set_claim_ring() draws one flat translucent cel-shaded zone
## (shaders/territory/goal_claim_zone.gdshader: stepped fill, inward rings, dashed rim) on the ground.
## Field always passes Match.goal_zone_visual_radius(): the claim radius while the bigger-claim-radius
## experiment is on, else the goal no-build zone radius, so players always see the claimed area.
## The node is only absent for a radius <= 0 (null match context).
##
## Visual only: who is capturing and how far along they are is WinChecker's
## answer, arriving through Events.goal_capture_progress and
## Field.set_capture_progress().

## Smallest change in progress that is worth rebuilding the arc mesh for. One
## ring segment is 1 / capture_ring_segments of a turn, so anything finer than
## that cannot change a single triangle.
const PROGRESS_EPSILON: float = 0.001

const BEAM_SHADER: Shader = preload("res://shaders/territory/goal_beam.gdshader")
const CLAIM_ZONE_SHADER: Shader = preload("res://shaders/territory/goal_claim_zone.gdshader")
const BEAM_SEGMENTS: int = 16
## Bungee, the Stackfall Arcade numeral face (docs/ui_reskin), for the timer text.
const TIMER_FONT: Font = preload("res://assets/ui/fonts/Bungee-Regular.ttf")
## Neutral / contested sentinels, the same values GoalControl returns.
const NEUTRAL: int = GoalControl.NEUTRAL
const CONTESTED: int = GoalControl.CONTESTED

var _ring: MeshInstance3D = null
var _ring_material: StandardMaterial3D = null
var _capture_team: int = -1
var _capture_progress: float = 0.0
var _drawn_progress: float = -1.0

var _control: int = NEUTRAL
var _control_color: Color = Color.WHITE
var _contest_colors: PackedColorArray = PackedColorArray()
var _flash: float = 0.0
var _clock_s: float = 0.0
var _beam: MeshInstance3D = null
var _beam_material: ShaderMaterial = null
var _burst: CPUParticles3D = null

## Bontago-1pi.188/189: camera-facing timer above the crystal, plus the CTF "xN" chip.
var _timer_label: Label3D = null
var _multiplier_label: Label3D = null
## True in Capture the Flag (count-up hold clock), false in Classic (capture countdown).
var _timer_counts_up: bool = false
## CTF: seconds the current holder has held this beacon (reset when the holder changes).
var _held_s: float = 0.0
## Classic: the shared capture's time left as of the last progress update, ticked down locally.
var _countdown_left_s: float = -1.0
## Classic: the claimant team's colour for the running countdown (set_countdown()).
var _countdown_color: Color = Color.WHITE
var _multiplier: int = 0

var _claim_ring: MeshInstance3D = null
var _claim_ring_radius: float = 0.0
var _claim_zone_material: ShaderMaterial = null


func _ready() -> void:
	# DECISION (game/flags/GoalFlag.gd, Bontago-xtq.33): the goal beacon's neutral
	# color and scale now come from BeaconVisualTuning (neutral_color,
	# goal_scale_factor) instead of TerritoryVisuals (goal_flag_color,
	# goal_flag_scale), which this file was the only reader of for those two
	# purposes -- TerritoryVisuals.goal_flag_color keeps its own, unrelated
	# fallback uses in Field.gd/TerritoryOverlay.gd untouched.
	_color = beacon_visuals.neutral_color
	super()
	_build_ring()
	_build_beam()
	_build_burst()
	_build_timer_labels()
	_refresh_control_visuals()


## Bontago-1pi.203: also rebuilds the claim beam and burst, which bake
## BeaconVisualTuning at construction like the base beacon does.
func rebuild_beacon() -> void:
	super()
	for node: Node in [_beam, _burst]:
		if node != null:
			remove_child(node)
			node.queue_free()
	_build_beam()
	_build_burst()
	_refresh_control_visuals()


func banner_scale() -> float:
	return beacon_visuals.goal_scale_factor


func _process(delta: float) -> void:
	_clock_s += delta
	_tick_timer(delta)
	_flash = maxf(_flash - delta / maxf(beacon_visuals.claim_flash_duration_s, 0.001), 0.0)
	if _control == CONTESTED:
		_color = _flicker_color()
		_apply_color()
		_apply_claim_zone_color()
	super(delta)
	if _beam_material != null and _beam.visible:
		_beam_material.set_shader_parameter(
			&"scroll", _clock_s * beacon_visuals.claim_beam_scroll_speed
		)
		if _control == CONTESTED:
			_apply_beam_colors()


func _emission_boost() -> float:
	var boost: float = 1.0
	if _control >= 0:
		boost = beacon_visuals.claimed_emission_boost
	elif _control == CONTESTED:
		boost = beacon_visuals.contested_emission_boost
	return boost + _flash * beacon_visuals.claim_flash_boost


func _extra_ring_scale() -> float:
	return _flash * beacon_visuals.claim_flash_ring_scale


## Who controls this goal: a team id (>= 0) with its colour, NEUTRAL, or
## CONTESTED with the colours of the teams contesting it (the flicker/stripe
## colours; contested_color fills in when fewer than two are given). A change
## of claimed team triggers the flash and burst; the very first call never does.
func set_control(control: int, owner_color: Color, contest_colors: PackedColorArray) -> void:
	var was: int = _control
	if control != was:
		_held_s = 0.0
	var claim_changed: bool = control >= 0 and (control != was or owner_color != _control_color)
	_control = control
	_control_color = owner_color
	_contest_colors = contest_colors
	if claim_changed:
		_flash = 1.0
		if _burst != null and beacon_visuals.claim_burst_count > 0:
			_burst.color = owner_color
			_burst.restart()
			_burst.emitting = true
	_refresh_control_visuals()
	_refresh_timer_text()


func control() -> int:
	return _control


func beam_visible() -> bool:
	return _beam != null and _beam.visible


## Colour the crystal/ring currently wear.
func shown_color() -> Color:
	return _color


func _flicker_color() -> Color:
	var hz: float = maxf(beacon_visuals.contested_flicker_hz, 0.001)
	var first: bool = fposmod(_clock_s * hz, 1.0) < 0.5
	return _contest_pair()[0 if first else 1]


func _contest_pair() -> PackedColorArray:
	var first: Color = _contest_colors[0] if _contest_colors.size() > 0 else beacon_visuals.neutral_color
	var second: Color = _contest_colors[1] if _contest_colors.size() > 1 else beacon_visuals.contested_color
	return PackedColorArray([first, second])


func _refresh_control_visuals() -> void:
	if _beam == null:
		return
	if _control >= 0:
		_color = _control_color
	elif _control == CONTESTED:
		_color = _flicker_color()
	else:
		_color = beacon_visuals.neutral_color
	_apply_color()
	_apply_claim_zone_color()
	_beam.visible = _control != NEUTRAL
	_apply_beam_colors()


func _apply_beam_colors() -> void:
	if _beam_material == null:
		return
	if _control == CONTESTED:
		var pair: PackedColorArray = _contest_pair()
		_beam_material.set_shader_parameter(&"color_a", pair[0])
		_beam_material.set_shader_parameter(&"color_b", pair[1])
		_beam_material.set_shader_parameter(&"striped", 1.0)
	else:
		_beam_material.set_shader_parameter(&"color_a", _control_color)
		_beam_material.set_shader_parameter(&"color_b", _control_color)
		_beam_material.set_shader_parameter(&"striped", 0.0)


func _build_beam() -> void:
	var height: float = beacon_visuals.claim_beam_height
	var radius: float = beacon_visuals.claim_beam_radius * banner_scale()
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = BEAM_SEGMENTS
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.name = &"ClaimBeam"
	_beam.mesh = mesh
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEAM_SHADER
	_beam_material.set_shader_parameter(&"intensity", beacon_visuals.claim_beam_alpha)
	_beam_material.set_shader_parameter(&"energy_scale", beacon_visuals.emission_scale)
	_beam_material.set_shader_parameter(&"band_count", beacon_visuals.claim_beam_band_count)
	_beam_material.set_shader_parameter(&"band_floor", beacon_visuals.claim_beam_band_floor)
	_beam.material_override = _beam_material
	_beam.position = Vector3(0.0, beacon_visuals.socket_height + height * 0.5, 0.0)
	_beam.visible = false
	add_child(_beam)


func _build_burst() -> void:
	_burst = CPUParticles3D.new()
	_burst.name = &"ClaimBurst"
	_burst.one_shot = true
	_burst.emitting = false
	_burst.amount = maxi(beacon_visuals.claim_burst_count, 1)
	_burst.lifetime = maxf(beacon_visuals.claim_flash_duration_s, 0.1)
	_burst.explosiveness = 1.0
	_burst.direction = Vector3.UP
	_burst.spread = 180.0
	_burst.initial_velocity_min = beacon_visuals.claim_burst_speed * 0.5
	_burst.initial_velocity_max = beacon_visuals.claim_burst_speed
	_burst.gravity = Vector3(0.0, -beacon_visuals.claim_burst_speed, 0.0)
	_burst.scale_amount_min = 1.0
	_burst.scale_amount_max = 1.0
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE * beacon_visuals.claim_burst_size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(2.0, 2.0, 2.0)
	quad.material = material
	_burst.mesh = quad
	_burst.position = Vector3(
		0.0, beacon_visuals.socket_height + beacon_visuals.crystal_height * banner_scale() * 0.5, 0.0
	)
	add_child(_burst)


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = &"CaptureRing"
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_material.emission_enabled = true
	_ring.material_override = _ring_material
	_ring.position = Vector3(0.0, visuals.capture_ring_lift, 0.0)
	_ring.visible = false
	add_child(_ring)


## Spec 2.3's capture display. `progress` runs 0..1 over
## TerritoryTuning.capture_hold; team_id -1 or progress 0 hides the ring.
func set_capture(team_id: int, progress: float, color: Color) -> void:
	_capture_team = team_id
	_capture_progress = clampf(progress, 0.0, 1.0)
	if _claim_zone_material != null:
		_claim_zone_material.set_shader_parameter(
			&"capture", _capture_progress if _capture_team >= 0 else 0.0
		)
	if _ring == null:
		return
	if _capture_team < 0 or _capture_progress <= 0.0:
		_ring.visible = false
		_drawn_progress = 0.0
		return
	_ring_material.albedo_color = color
	_ring_material.emission = color
	_ring_material.emission_energy_multiplier = visuals.capture_ring_emission
	_ring.visible = true
	if absf(_capture_progress - _drawn_progress) >= PROGRESS_EPSILON:
		_ring.mesh = _build_arc(_capture_progress)
		_drawn_progress = _capture_progress


func capture_team() -> int:
	return _capture_team


func capture_progress() -> float:
	return _capture_progress


func ring_visible() -> bool:
	return _ring != null and _ring.visible


## An annulus arc covering `progress` of a full turn, starting at +z and
## running clockwise seen from above, so it fills the way a clock hand does.
func _build_arc(progress: float) -> ArrayMesh:
	var segments: int = maxi(visuals.capture_ring_segments, 3)
	var used: int = maxi(int(ceil(progress * float(segments))), 1)
	var outer: float = visuals.capture_ring_radius
	var inner: float = maxf(outer - visuals.capture_ring_thickness, 0.001)
	var sweep: float = TAU * progress

	return build_annulus_mesh(outer, inner, sweep, used)


## Bontago-1pi.18.6: shows (radius > 0) or removes (radius <= 0 or non-finite) the
## ground ring marking the goal claim area. Field passes Match.goal_zone_visual_radius()
## (the capture radius with the experiment on, else goal_zone_radius) once when the flags are placed. Builds one
## MeshInstance3D + one mesh + one material on first use, rebuilds the mesh only if
## the radius changes, and does nothing at all for a radius <= 0.
##
## DECISION: the band is centred on the claim radius (a cell votes when its centre is
## within that radius) rather than hanging outside it, so the drawn line is the rule's
## edge. It is shown for any radius > 0, including a multiplier of exactly 1.0 where it
## simply coincides with the (separately drawn) no-build circle.
func set_claim_ring(radius: float) -> void:
	var wanted: float = radius if is_finite(radius) and radius > 0.0 else 0.0
	if wanted <= 0.0:
		if _claim_ring != null:
			remove_child(_claim_ring)
			_claim_ring.queue_free()
			_claim_ring = null
		_claim_zone_material = null
		_claim_ring_radius = 0.0
		return
	if _claim_ring == null:
		_claim_ring = _build_claim_ring_node()
		add_child(_claim_ring)
	elif is_equal_approx(wanted, _claim_ring_radius):
		return
	_claim_ring_radius = wanted
	_claim_ring.mesh = _build_claim_ring_mesh(wanted)


func claim_ring_visible() -> bool:
	return _claim_ring != null and _claim_ring.visible


## The radius the ring currently marks (0.0 when none is drawn).
func claim_ring_radius() -> float:
	return _claim_ring_radius


func claim_ring_node() -> MeshInstance3D:
	return _claim_ring


func _build_claim_ring_node() -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = &"ClaimRadiusRing"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_claim_zone_material = ShaderMaterial.new()
	_claim_zone_material.shader = CLAIM_ZONE_SHADER
	var tuning: BeaconVisualTuning = beacon_visuals
	_claim_zone_material.set_shader_parameter(&"rim_width", tuning.claim_ring_width)
	_claim_zone_material.set_shader_parameter(&"rim_alpha", clampf(tuning.claim_ring_alpha, 0.0, 1.0))
	_claim_zone_material.set_shader_parameter(&"fill_alpha", tuning.claim_zone_fill_alpha)
	_claim_zone_material.set_shader_parameter(&"cel_steps", tuning.claim_zone_cel_steps)
	_claim_zone_material.set_shader_parameter(&"ring_count", tuning.claim_zone_ring_count)
	_claim_zone_material.set_shader_parameter(&"ring_speed", tuning.claim_zone_ring_speed)
	_claim_zone_material.set_shader_parameter(&"ring_width", tuning.claim_zone_ring_width)
	_claim_zone_material.set_shader_parameter(&"dash_count", tuning.claim_zone_dash_count)
	_claim_zone_material.set_shader_parameter(&"capture_boost", tuning.claim_zone_capture_boost)
	_claim_zone_material.set_shader_parameter(&"rim_edge_lighten", tuning.claim_zone_rim_lighten)
	_claim_zone_material.set_shader_parameter(&"capture", _capture_progress if _capture_team >= 0 else 0.0)
	node.material_override = _claim_zone_material
	node.position = Vector3(0.0, tuning.claim_ring_lift, 0.0)
	_apply_claim_zone_color()
	return node


## DECISION (Bontago-mp0.147): the zone is one filled disc mesh (the fan is an annulus
## with inner radius 0) out to the rim's outer edge; the shader draws the stepped fill,
## drifting rings and rim from the vertex's local XZ distance, so the mesh stays static
## and the one transparent draw carries every cue. No new gameplay state: colour follows
## set_control() (neutral tint, owner colour, or the contested flicker) and the fill
## brightens with the capture progress set_capture() already receives.
func _build_claim_ring_mesh(radius: float) -> ArrayMesh:
	var segments: int = maxi(beacon_visuals.claim_ring_segments, 3)
	var half: float = maxf(beacon_visuals.claim_ring_width, 0.001) * 0.5
	if _claim_zone_material != null:
		_claim_zone_material.set_shader_parameter(&"zone_radius", radius)
	return build_annulus_mesh(radius + half, 0.0, TAU, segments)


func _claim_zone_color() -> Color:
	if _control >= 0:
		return _control_color
	if _control == CONTESTED:
		return _color
	return beacon_visuals.claim_ring_color


func _apply_claim_zone_color() -> void:
	if _claim_zone_material != null:
		_claim_zone_material.set_shader_parameter(&"zone_color", _claim_zone_color())


# --- Timer label (Bontago-1pi.188 / 1pi.189) ---------------------------------

func _build_timer_labels() -> void:
	var tuning: BeaconVisualTuning = beacon_visuals
	var base_y: float = tuning.beacon_top_height(banner_scale()) + tuning.timer_height
	_timer_label = _make_timer_label(tuning, tuning.timer_text_color, 1.0)
	_timer_label.name = &"TimerLabel"
	_timer_label.position = Vector3(0.0, base_y, 0.0)
	add_child(_timer_label)
	_multiplier_label = _make_timer_label(tuning, tuning.timer_multiplier_color, tuning.timer_multiplier_scale)
	_multiplier_label.name = &"MultiplierLabel"
	_multiplier_label.position = Vector3(0.0, base_y + tuning.timer_multiplier_gap, 0.0)
	add_child(_multiplier_label)
	_refresh_timer_text()


func _make_timer_label(tuning: BeaconVisualTuning, color: Color, size_scale: float) -> Label3D:
	var label: Label3D = Label3D.new()
	label.font = TIMER_FONT
	label.font_size = roundi(float(tuning.timer_font_size) * size_scale)
	label.outline_size = roundi(float(tuning.timer_outline_size) * size_scale)
	label.pixel_size = tuning.timer_pixel_size
	label.modulate = color
	label.outline_modulate = tuning.timer_outline_color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = tuning.timer_no_depth_test
	label.shaded = false
	label.double_sided = true
	label.visible = false
	return label


## Switches between the Classic countdown (false) and the CTF count-up (true).
func set_timer_counts_up(counts_up: bool) -> void:
	_timer_counts_up = counts_up
	_held_s = 0.0
	_refresh_timer_text()


## Classic: the shared capture's team and 0..1 progress with the full hold time;
## the label counts down from what is left and is re-synced on every update.
## claim_color is the claimant team's colour (Field passes its slot colour); it tints
## the timer text while the countdown runs and nobody controls the beacon yet.
func set_countdown(team_id: int, progress: float, hold_seconds: float, claim_color: Color) -> void:
	_countdown_color = claim_color
	if team_id < 0 or progress <= 0.0:
		_countdown_left_s = -1.0
	else:
		_countdown_left_s = BeaconTimerText.remaining_seconds(progress, hold_seconds)
	_refresh_timer_text()


## CTF: how many beacons this beacon's holder controls (0/1 = no chip).
func set_multiplier(held_count: int) -> void:
	_multiplier = held_count
	_refresh_timer_text()


func timer_text() -> String:
	if _timer_label == null:
		return ""
	return _timer_label.text if _timer_label.visible else ""


func multiplier_chip_text() -> String:
	if _multiplier_label == null:
		return ""
	return _multiplier_label.text if _multiplier_label.visible else ""


func _tick_timer(delta: float) -> void:
	if _timer_counts_up:
		if _control >= 0:
			_held_s += delta
	elif _countdown_left_s > 0.0:
		_countdown_left_s = maxf(_countdown_left_s - delta, 0.0)
	else:
		return
	_refresh_timer_text()


## Bontago-1pi.197: the timer text wears the controlling player's colour while a
## team holds the beacon (_control_color, which clients also receive through
## set_control()); with nobody in control it falls back to timer_text_color.
## Classic capture-in-progress (no controller yet) uses the claimant's colour from
## set_countdown(); with no claimant it falls back to timer_text_color.
func _timer_text_color() -> Color:
	if _control >= 0:
		return _control_color
	if _countdown_left_s >= 0.0:
		return _countdown_color
	return beacon_visuals.timer_text_color


func _refresh_timer_text() -> void:
	if _timer_label == null:
		return
	var text: String = ""
	var chip: String = ""
	if beacon_visuals.timer_enabled:
		if _timer_counts_up:
			text = BeaconTimerText.ctf_text(_control, _held_s)
			if not text.is_empty():
				chip = BeaconTimerText.multiplier_text(_multiplier)
		elif _countdown_left_s >= 0.0:
			text = BeaconTimerText.clock(int(ceil(_countdown_left_s)))
	if _timer_label.text != text:
		_timer_label.text = text
	_timer_label.modulate = _timer_text_color()
	_timer_label.visible = not text.is_empty()
	if _multiplier_label.text != chip:
		_multiplier_label.text = chip
	_multiplier_label.visible = not chip.is_empty()
