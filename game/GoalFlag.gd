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
## Bontago-1pi.18.6 (QoL experiment 4): while the bigger-claim-radius toggle is on,
## set_claim_ring() draws one flat translucent ring on the ground at the radius the
## host uses for capture, so players can see where claiming counts. With the
## toggle off the ring node is never created.
##
## Visual only: who is capturing and how far along they are is WinChecker's
## answer, arriving through Events.goal_capture_progress and
## Field.set_capture_progress().

## Smallest change in progress that is worth rebuilding the arc mesh for. One
## ring segment is 1 / capture_ring_segments of a turn, so anything finer than
## that cannot change a single triangle.
const PROGRESS_EPSILON: float = 0.001

const BEAM_SHADER: Shader = preload("res://shaders/goal_beam.gdshader")
const BEAM_SEGMENTS: int = 16
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

var _claim_ring: MeshInstance3D = null
var _claim_ring_radius: float = 0.0


func _ready() -> void:
	# DECISION (game/GoalFlag.gd, Bontago-xtq.33): the goal beacon's neutral
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
	_refresh_control_visuals()


func banner_scale() -> float:
	return beacon_visuals.goal_scale_factor


func _process(delta: float) -> void:
	_clock_s += delta
	_flash = maxf(_flash - delta / maxf(beacon_visuals.claim_flash_duration_s, 0.001), 0.0)
	if _control == CONTESTED:
		_color = _flicker_color()
		_apply_color()
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


func control() -> int:
	return _control


func beam_visible() -> bool:
	return _beam != null and _beam.visible


## Colour the crystal/ring currently wear.
func shown_color() -> Color:
	return _color


func flash_amount() -> float:
	return _flash


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


## The arc currently drawn, or null before the first capture.
func ring_mesh() -> Mesh:
	return _ring.mesh if _ring != null else null


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
## ground ring marking the goal claim radius. Field passes Match.qol_claim_radius(),
## the exact value capture uses, once when the flags are placed. Builds one
## MeshInstance3D + one mesh + one material on first use, rebuilds the mesh only if
## the radius changes, and does nothing at all while the toggle is off.
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
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(
		beacon_visuals.claim_ring_color.r, beacon_visuals.claim_ring_color.g,
		beacon_visuals.claim_ring_color.b, clampf(beacon_visuals.claim_ring_alpha, 0.0, 1.0)
	)
	node.material_override = material
	node.position = Vector3(0.0, beacon_visuals.claim_ring_lift, 0.0)
	return node


## A flat full-circle annulus in the XZ plane: a band claim_ring_width wide centred on
## `radius`, built once (not per frame).
func _build_claim_ring_mesh(radius: float) -> ArrayMesh:
	var segments: int = maxi(beacon_visuals.claim_ring_segments, 3)
	var half: float = maxf(beacon_visuals.claim_ring_width, 0.001) * 0.5
	var outer: float = radius + half
	var inner: float = maxf(radius - half, 0.0)
	return build_annulus_mesh(outer, inner, TAU, segments)
