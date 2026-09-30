extends GutTest
## Bontago-sen.6: ghost rim glow and the pre-drop warning pulse (presentation
## only; GhostPreview never reads or changes the real block timer here).

var _ghost: GhostPreview
var _tuning: GhostTuning


func before_each() -> void:
	_ghost = GhostPreview.new()
	add_child_autofree(_ghost)
	_tuning = _ghost.ghost_tuning


func _strength() -> float:
	return float(_ghost._material.get_shader_parameter(&"glow_strength"))


func test_glow_uniforms_set_on_ready() -> void:
	assert_almost_eq(_strength(), _tuning.glow_strength, 0.0001)
	assert_almost_eq(
		float(_ghost._material.get_shader_parameter(&"glow_rim_power")), _tuning.glow_rim_power, 0.0001
	)


func test_pulse_inactive_above_lead_time() -> void:
	_ghost.set_drop_time_left(_tuning.glow_warning_lead_seconds + 0.5)
	_ghost.advance_glow(0.1)
	assert_false(_ghost.is_pulse_active())
	assert_almost_eq(_strength(), _tuning.glow_strength, 0.0001)


func test_pulse_inactive_without_timer() -> void:
	_ghost.set_drop_time_left(-1.0)
	assert_false(_ghost.is_pulse_active())
	assert_eq(_ghost.pulse_frequency_hz(), 0.0)


func test_pulse_active_and_frequency_increases_within_lead() -> void:
	var lead: float = _tuning.glow_warning_lead_seconds
	_ghost.set_drop_time_left(lead * 0.99)
	assert_true(_ghost.is_pulse_active())
	var early: float = _ghost.pulse_frequency_hz()
	_ghost.set_drop_time_left(lead * 0.5)
	var mid: float = _ghost.pulse_frequency_hz()
	_ghost.set_drop_time_left(0.0)
	var late: float = _ghost.pulse_frequency_hz()
	assert_gt(mid, early)
	assert_gt(late, mid)
	assert_almost_eq(late, _tuning.glow_pulse_end_hz, 0.0001)


func test_pulse_modulates_glow_above_steady_level() -> void:
	_ghost.set_drop_time_left(_tuning.glow_warning_lead_seconds * 0.5)
	var peak: float = 0.0
	for i: int in range(60):
		_ghost.advance_glow(1.0 / 60.0)
		peak = maxf(peak, _strength())
	assert_gt(peak, _tuning.glow_strength * 1.5)


func test_pulse_resets_after_drop() -> void:
	_ghost.set_drop_time_left(0.2)
	_ghost.advance_glow(0.05)
	assert_true(_ghost.is_pulse_active())
	# New block: the timer refills to full.
	_ghost.set_drop_time_left(6.0)
	_ghost.advance_glow(0.016)
	assert_false(_ghost.is_pulse_active())
	assert_almost_eq(_strength(), _tuning.glow_strength, 0.0001)


func test_glow_follows_tint_colour_in_shader_albedo() -> void:
	_ghost.set_player_color(Color(0.2, 0.4, 0.9, 1.0))
	var tint: Color = _ghost.current_tint_color()
	assert_almost_eq(tint.b, 0.9, 0.001, "shader derives the rim colour from albedo_color")


func test_gift_glow_overlay_follows_tint_and_level() -> void:
	var shape: BlockShape = load("res://config/blocks/L3.tres") as BlockShape
	if shape == null:
		pending("no block shape")
		return
	_ghost.set_shape(shape)
	_ghost.set_held_gift(&"freeze")
	_ghost.set_drop_time_left(0.0)
	_ghost.advance_glow(0.01)
	var glow: ShaderMaterial = _ghost._gift_glow_material
	assert_not_null(glow)
	assert_almost_eq(float(glow.get_shader_parameter(&"glow_strength")), _ghost.glow_level(), 0.0001)


## Bontago-sen.12: a locked (greyed, interval-locked) piece is never force
## dropped, so it must not pulse even when the timer is inside the lead.
func test_locked_piece_never_pulses_inside_lead_time() -> void:
	_ghost.set_drop_time_left(0.5)
	assert_true(_ghost.is_pulse_active(), "control: unlocked piece pulses")
	_ghost.set_locked(true)
	assert_false(_ghost.is_pulse_active())
	assert_eq(_ghost.pulse_frequency_hz(), 0.0)
	_ghost.advance_glow(0.1)
	assert_almost_eq(_strength(), _tuning.glow_strength, 0.0001)
	_ghost.set_locked(false)
	assert_true(_ghost.is_pulse_active())
