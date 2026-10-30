extends GutTest
## Contract of TuningSkyTab, the F4 Sky tab model: which resources it owns, the time-of-day
## choice and its live lock on every cycle Skybox, live apply of a sky edit and reset to the shipped
## values.

const CYCLE_PATH: String = "res://config/sky/sky_cycle.tres"
const OVERLAY_PATH: String = "res://config/sky/storm_overlay.tres"
const CONFIG_PATH: String = "res://config/sky/skybox_config.tres"
const SUNSET: String = "sunset"
const DAWN: String = "dawn"
const NIGHT: String = "night"
const EDIT_STEP: float = 0.25
const PHASE_TOLERANCE: float = 0.0001
const SLIDER_PHASE: float = 0.6
const EDITED_SUNSET_PHASE: float = 0.55


## Records every Skybox API call the tab makes, without the real Skybox scene build (its _ready()
## only joins the tuning group).
class SpySkybox extends Skybox:
	var cycle_active: bool = false
	var locked: float = -1.0
	var phase_now: float = 0.4
	var lock_calls: Array[float] = []
	var refresh_calls: int = 0

	func _ready() -> void:
		add_to_group(Skybox.TUNING_GROUP)

	func set_locked_phase(phase: float) -> void:
		lock_calls.append(phase)
		locked = phase

	func locked_phase() -> float:
		return locked

	func is_cycle_active() -> bool:
		return cycle_active

	func current_cycle_phase() -> float:
		return phase_now if cycle_active else -1.0

	func refresh_sky_def() -> void:
		refresh_calls += 1


var _cycle: SkyCycleDef
var _overlay: SkyOverlayDef
var _config: SkyboxConfig
var _tab: TuningSkyTab


func _load_fresh(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func before_each() -> void:
	_cycle = _load_fresh(CYCLE_PATH) as SkyCycleDef
	_overlay = _load_fresh(OVERLAY_PATH) as SkyOverlayDef
	_config = _load_fresh(CONFIG_PATH) as SkyboxConfig
	_tab = TuningSkyTab.new(_cycle, _overlay, _config, get_tree())


func _spy(cycle_active: bool) -> SpySkybox:
	var spy: SpySkybox = SpySkybox.new()
	spy.cycle_active = cycle_active
	spy.sky_def = _cycle.duplicate() as SkyCycleDef
	add_child_autofree(spy)
	return spy


func _count_in(list: Array[Resource], resource: Resource) -> int:
	var count: int = 0
	for entry: Resource in list:
		if entry == resource:
			count += 1
	return count


# --- Ownership --------------------------------------------------------------------

func test_resources_hold_the_cycle_every_day_key_night_and_overlay_once() -> void:
	var found: Array[Resource] = _tab.resources()
	assert_eq(_count_in(found, _cycle), 1, "the cycle")
	for key: SkyKeyframe in _cycle.day_keyframes:
		assert_eq(_count_in(found, key), 1, "each day keyframe")
	assert_eq(_count_in(found, _cycle.night), 1, "the night keyframe")
	assert_eq(_count_in(found, _overlay), 1, "the overlay")
	assert_eq(found.size(), _cycle.day_keyframes.size() + 3, "nothing else")


func test_owns_exactly_the_sky_resources() -> void:
	assert_gt(_tab.resources().size(), 0, "fixture: the tab has resources")
	for resource: Resource in _tab.resources():
		assert_true(_tab.owns(resource))
	assert_false(_tab.owns(_config), "the skybox config is not a Sky tab row source")
	assert_false(_tab.owns(PhysicsTuning.new()))
	assert_false(_tab.owns(null))


func test_section_tags_tell_the_resources_apart() -> void:
	assert_eq(_tab.section_tag(_cycle), "", "the cycle has no prefix")
	assert_eq(_tab.section_tag(null), "")
	assert_eq(_tab.section_tag(PhysicsTuning.new()), "", "a foreign resource has no tag")
	var tags: Array[String] = []
	for key: SkyKeyframe in _cycle.day_keyframes:
		tags.append(_tab.section_tag(key))
	tags.append(_tab.section_tag(_cycle.night))
	tags.append(_tab.section_tag(_overlay))
	for tag: String in tags:
		assert_ne(tag, "", "keyframes, night and overlay each carry a tag")
		assert_eq(tags.count(tag), 1, "tag %s is unique" % tag)


func test_shipped_counterpart_is_a_separate_copy_of_the_shipped_values() -> void:
	var shipped_cycle: SkyCycleDef = _tab.shipped_counterpart(_cycle) as SkyCycleDef
	assert_not_null(shipped_cycle)
	assert_ne(shipped_cycle, _cycle, "a separate instance")
	assert_almost_eq(shipped_cycle.haze_strength, _cycle.haze_strength, 0.00001)
	_cycle.haze_strength += EDIT_STEP
	assert_ne(shipped_cycle.haze_strength, _cycle.haze_strength, "a live edit does not touch the counterpart")
	for index: int in range(_cycle.day_keyframes.size()):
		var counterpart: SkyKeyframe = _tab.shipped_counterpart(_cycle.day_keyframes[index]) as SkyKeyframe
		assert_not_null(counterpart, "day key %d" % index)
		assert_ne(counterpart, _cycle.day_keyframes[index])
		assert_almost_eq(counterpart.fog_density, _cycle.day_keyframes[index].fog_density, 0.00001)
	assert_not_null(_tab.shipped_counterpart(_cycle.night), "night")


func test_shipped_counterpart_is_null_for_resources_with_their_own_file_and_strangers() -> void:
	assert_null(_tab.shipped_counterpart(_overlay), "the overlay has its own .tres")
	assert_null(_tab.shipped_counterpart(PhysicsTuning.new()))
	assert_null(_tab.shipped_counterpart(null))


# --- Time of day ------------------------------------------------------------------

func test_a_preset_choice_locks_every_running_cycle_at_its_phase() -> void:
	var spy: SpySkybox = _spy(true)
	var other: SpySkybox = _spy(true)
	for choice: String in [SUNSET, DAWN, NIGHT]:
		var expected: float = _cycle.locked_phase_for(choice)
		assert_gt(expected, -0.5, "fixture: the cycle locks a phase for %s" % choice)
		assert_true(_tab.apply_time_of_day(choice))
		assert_almost_eq(spy.lock_calls[-1], expected, PHASE_TOLERANCE, "%s locks the cycle" % choice)
		assert_almost_eq(other.lock_calls[-1], expected, PHASE_TOLERANCE, "%s locks the second sky too" % choice)
		assert_eq(_tab.time_choice, choice)
		assert_almost_eq(_tab.displayed_phase(), expected, PHASE_TOLERANCE)


func test_running_unlocks_the_cycle() -> void:
	var spy: SpySkybox = _spy(true)
	_tab.apply_time_of_day(SUNSET)
	assert_true(_tab.apply_time_of_day(TuningSkyTab.TIME_RUNNING))
	assert_almost_eq(spy.lock_calls[-1], -1.0, PHASE_TOLERANCE)
	assert_eq(_tab.time_choice, TuningSkyTab.TIME_RUNNING)


func test_custom_locks_where_the_cycle_is_now() -> void:
	var spy: SpySkybox = _spy(true)
	assert_true(_tab.apply_time_of_day(TuningSkyTab.TIME_CUSTOM))
	assert_almost_eq(spy.lock_calls[-1], spy.phase_now, PHASE_TOLERANCE, "no jump")
	assert_almost_eq(_tab.displayed_phase(), spy.phase_now, PHASE_TOLERANCE)
	assert_eq(_tab.time_choice, TuningSkyTab.TIME_CUSTOM)


func test_custom_phase_moves_the_lock_and_clamps_to_zero_one() -> void:
	var spy: SpySkybox = _spy(true)
	_tab.apply_custom_time_of_day(SLIDER_PHASE)
	assert_almost_eq(spy.lock_calls[-1], SLIDER_PHASE, PHASE_TOLERANCE)
	assert_eq(_tab.time_choice, TuningSkyTab.TIME_CUSTOM, "moving the slider selects Custom")
	assert_almost_eq(_tab.displayed_phase(), SLIDER_PHASE, PHASE_TOLERANCE)
	_tab.apply_custom_time_of_day(1.5)
	assert_almost_eq(spy.lock_calls[-1], 1.0, PHASE_TOLERANCE)
	_tab.apply_custom_time_of_day(-0.5)
	assert_almost_eq(spy.lock_calls[-1], 0.0, PHASE_TOLERANCE)


func test_an_unknown_choice_is_rejected_and_changes_nothing() -> void:
	var spy: SpySkybox = _spy(true)
	_tab.apply_time_of_day(SUNSET)
	var calls: int = spy.lock_calls.size()
	assert_false(_tab.apply_time_of_day("midnight"))
	assert_eq(_tab.time_choice, SUNSET)
	assert_eq(spy.lock_calls.size(), calls, "no lock was pushed")


func test_a_static_sky_is_never_locked() -> void:
	var spy: SpySkybox = _spy(false)
	assert_true(_tab.apply_time_of_day(SUNSET))
	_tab.apply_custom_time_of_day(SLIDER_PHASE)
	assert_eq(spy.lock_calls.size(), 0, "a sky with no running cycle has nothing to lock")


func test_has_running_cycle_follows_the_live_skyboxes() -> void:
	assert_false(_tab.has_running_cycle(), "no Skybox")
	var spy: SpySkybox = _spy(false)
	assert_false(_tab.has_running_cycle(), "a static sky")
	spy.cycle_active = true
	assert_true(_tab.has_running_cycle())


func test_displayed_phase_without_a_live_sky_is_a_valid_phase_for_running() -> void:
	var phase: float = _tab.displayed_phase()
	assert_true(phase >= 0.0 and phase <= 1.0, "the slider can show it")


# --- Live apply -------------------------------------------------------------------

func test_cycle_field_edit_copies_onto_each_live_skybox_and_refreshes_it() -> void:
	var spy: SpySkybox = _spy(true)
	var edited: float = _cycle.haze_strength + EDIT_STEP
	_cycle.haze_strength = edited
	assert_true(_tab.on_field_changed(_cycle, "haze_strength"), "the tab's own edit")
	assert_eq(spy.refresh_calls, 1)
	assert_almost_eq(spy.sky_def.haze_strength, edited, 0.00001, "the Skybox's own copy carries the edit")


func test_keyframe_night_and_overlay_edits_refresh_too() -> void:
	var spy: SpySkybox = _spy(true)
	var key: SkyKeyframe = _cycle.day_keyframes[0]
	var fog_before: float = key.fog_density
	assert_true(_tab.on_field_changed(key, "fog_density"))
	assert_true(_tab.on_field_changed(_cycle.night, "fog_density"))
	assert_true(_tab.on_field_changed(_overlay, "fog_density"))
	assert_eq(spy.refresh_calls, 3)
	assert_eq(key.fog_density, fog_before, "the edit hook does not change the value itself")


func test_cycle_length_edit_goes_through_its_own_seam() -> void:
	var spy: SpySkybox = _spy(true)
	assert_true(_tab.on_field_changed(_cycle, "cycle_length_seconds"))
	assert_eq(spy.refresh_calls, 0, "the length is a rate, not a definition refresh")


func test_a_non_sky_resource_is_not_the_tabs_edit() -> void:
	var spy: SpySkybox = _spy(true)
	assert_false(_tab.on_field_changed(_config, "theme_name"))
	assert_false(_tab.on_field_changed(PhysicsTuning.new(), "gravity_multiplier"))
	assert_eq(spy.refresh_calls, 0)


func test_editing_the_selected_presets_phase_moves_the_sky() -> void:
	var spy: SpySkybox = _spy(true)
	_tab.apply_time_of_day(SUNSET)
	_cycle.cycle_locked_phase_sunset = EDITED_SUNSET_PHASE
	_tab.on_field_changed(_cycle, "cycle_locked_phase_sunset")
	assert_almost_eq(spy.lock_calls[-1], EDITED_SUNSET_PHASE, PHASE_TOLERANCE)


func test_editing_a_preset_phase_leaves_a_custom_lock_alone() -> void:
	var spy: SpySkybox = _spy(true)
	_tab.apply_custom_time_of_day(SLIDER_PHASE)
	_cycle.cycle_locked_phase_sunset = EDITED_SUNSET_PHASE
	_tab.on_field_changed(_cycle, "cycle_locked_phase_sunset")
	assert_almost_eq(spy.lock_calls[-1], SLIDER_PHASE, PHASE_TOLERANCE)


# --- Reset ------------------------------------------------------------------------

func test_reset_restores_shipped_values_and_keeps_the_live_keyframe_objects() -> void:
	var shipped: SkyCycleDef = _load_fresh(CYCLE_PATH) as SkyCycleDef
	var shipped_overlay: SkyOverlayDef = _load_fresh(OVERLAY_PATH) as SkyOverlayDef
	var key: SkyKeyframe = _cycle.day_keyframes[1]
	var night: SkyNightKeyframe = _cycle.night
	_cycle.haze_strength += EDIT_STEP
	key.fog_density += EDIT_STEP
	night.fog_density += EDIT_STEP
	_overlay.fog_density += EDIT_STEP
	_tab.reset()
	assert_eq(_cycle.day_keyframes[1], key, "reset keeps the live keyframe objects")
	assert_eq(_cycle.night, night)
	assert_almost_eq(_cycle.haze_strength, shipped.haze_strength, 0.00001)
	assert_almost_eq(key.fog_density, shipped.day_keyframes[1].fog_density, 0.00001)
	assert_almost_eq(night.fog_density, shipped.night.fog_density, 0.00001)
	assert_almost_eq(_overlay.fog_density, shipped_overlay.fog_density, 0.00001)
