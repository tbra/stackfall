extends GutTest
## F1 performance overlay and its demand-driven PerfSampler, through what a caller sees: the Labels the overlay
## shows for a canned metrics snapshot, the F1 key and pad chord, and the sampler's `sampled` signal.
## Never a child index, alignment or tint. The frame warn flag is read from the public PerfOverlay.rows builder.

const WINDOW_S: float = 0.1
const STEP_WAIT_S: float = 0.5

var _config: DebugConfig = null
var _probe_before: bool = false


func before_each() -> void:
	_probe_before = PerfProbe.enabled
	PerfProbe.enabled = false
	_config = DebugConfig.new()
	_config.stats_window_s = WINDOW_S
	DebugMode.set_override_for_test(false)


func after_each() -> void:
	DebugMode.clear_override_for_test()
	PerfProbe.enabled = _probe_before
	Input.action_release(&"camera_snap_home")


func _canned(extra: Dictionary = {}) -> Dictionary:
	var m: Dictionary = {
		"window_s": 1.0, "fps": 137.0, "frame_ms": 61.0, "frame_ms_max": 83.0,
		"physics_ms": 2.5, "physics_ms_max": 4.5,
		"steps_current": 3737, "steps_peak": 4848, "steps_multi_pct": 12.0, "steps_max_setting": 8,
		"effects_current": 5151, "effects_peak": 6262,
		"blocks_total": 1234, "blocks_awake": 987, "blocks_sleeping": 247,
		"territory_ms": 1.0, "territory_peak_ms": 2.0, "territory_load_pct": 3.0,
		"weather_ms": 1.0, "weather_peak_ms": 2.0, "weather_load_pct": 3.0,
		"gifts_ms": 1.0, "gifts_peak_ms": 2.0, "gifts_load_pct": 3.0,
		"registry_ms": 1.0, "registry_peak_ms": 2.0, "registry_load_pct": 3.0,
		"block_effects_ms": 1.0, "block_effects_peak_ms": 2.0, "block_effects_load_pct": 3.0,
		"snapshot_ms": 1.0, "snapshot_peak_ms": 2.0, "snapshot_load_pct": 3.0,
		"draw_calls": 4321, "objects_in_frame": 8765, "primitives": 2468013,
		"vram_mb": 3333.0, "static_mem_mb": 2222.0,
		"node_count": 9876, "object_count": 13579, "orphan_nodes": 31,
		"match_state": "ZZSTATE", "players": 6, "weather_id": "zzfog", "weather_intensity": 0.5,
		"net_mode": 0, "net_peers": 5, "net_ping_ms": 4242.0, "net_snapshot_bps": 777777.0,
	}
	m.merge(extra, true)
	return m


func _make_sampler(demand_driven: bool = false) -> PerfSampler:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	sampler.demand_driven = demand_driven
	add_child_autofree(sampler)
	return sampler


func _make_overlay(sampler: PerfSampler) -> PerfOverlay:
	var overlay: PerfOverlay = PerfOverlay.new()
	overlay.config = _config
	overlay.sampler = sampler
	add_child_autofree(overlay)
	return overlay


func _key_f1() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_F1
	event.pressed = true
	return event


func _pad_r3() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_RIGHT_STICK
	event.pressed = true
	return event


## Lower-cased visible Label text with spaces and underscores removed, so "block_effects" matches "Block effects".
func _shown(overlay: PerfOverlay) -> String:
	var out: PackedStringArray = PackedStringArray()
	if not overlay.visible:
		return ""
	for node: Node in overlay.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree() and label.text != "":
			out.append(label.text)
	return " ".join(out).to_lower().replace(" ", "").replace("_", "")


## Shows `metrics` through the overlay's sampler signal, the way a real window closes.
func _feed(sampler: PerfSampler, metrics: Dictionary) -> void:
	sampler.latest = metrics
	sampler.sampled.emit(metrics)


func _cycle_to(overlay: PerfOverlay, presses: int) -> void:
	for i: int in presses:
		overlay._unhandled_input(_key_f1())


func _has(overlay: PerfOverlay, needle: String) -> bool:
	return _shown(overlay).contains(needle.to_lower().replace(" ", "").replace("_", ""))


# --- rows ---------------------------------------------------------------------

func test_basic_shows_frame_physics_steps_effects_and_blocks_only() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	for kept: String in ["137", "61", "83", "3737", "4848", "5151", "6262", "1234", "987", "247"]:
		assert_true(_has(overlay, kept), "BASIC shows %s" % kept)
	for detailed_only: String in ["4321", "8765", "2468013", "3333", "2222", "9876", "13579", "zzfog", "zzstate"]:
		assert_false(_has(overlay, detailed_only), "BASIC leaves out %s" % detailed_only)


func test_detailed_adds_probes_draw_memory_nodes_and_state() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 2)
	_feed(sampler, _canned())
	for kept: String in ["137", "1234", "4321", "8765", "2468013", "3333", "2222", "9876", "13579", "zzfog", "zzstate"]:
		assert_true(_has(overlay, kept), "DETAILED shows %s" % kept)
	for probe: String in ["territory", "weather", "gifts", "registry", "block_effects", "snapshot"]:
		assert_true(_has(overlay, probe), "DETAILED names probe %s" % probe)


func test_no_net_numbers_even_when_online() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 2)
	_feed(sampler, _canned({"net_mode": 1}))
	assert_false(_has(overlay, "4242"), "ping belongs to F3")
	assert_false(_has(overlay, "777777"), "snapshot bytes belong to F3")


func test_role_tag_follows_net_mode() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 2)
	var seen: Dictionary = {}
	for mode: int in [0, 1, 2]:
		_feed(sampler, _canned({"net_mode": mode}))
		seen[mode] = _shown(overlay)
	assert_ne(seen[0], seen[1], "host reads differently from offline")
	assert_ne(seen[1], seen[2], "client reads differently from host")
	assert_ne(seen[0], seen[2], "client reads differently from offline")


func test_new_reading_replaces_the_old_one() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	_feed(sampler, _canned({"fps": 59.0}))
	assert_true(_has(overlay, "59"))
	assert_false(_has(overlay, "137"), "old fps gone")


# --- mode cycle and toggle ----------------------------------------------------

func test_mode_cycle_hidden_basic_detailed_hidden() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_feed(sampler, _canned())
	assert_eq(_shown(overlay), "", "starts hidden")
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	assert_true(_has(overlay, "137"), "BASIC")
	assert_false(_has(overlay, "4321"), "BASIC has no draw calls")
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	assert_true(_has(overlay, "4321"), "DETAILED")
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	assert_eq(_shown(overlay), "", "back to hidden")


func test_f1_toggles_with_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	assert_true(_has(overlay, "137"), "F1 opens the overlay in a player build")


func test_f1_toggles_with_debug_on() -> void:
	DebugMode.set_override_for_test(true)
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	_cycle_to(overlay, 1)
	_feed(sampler, _canned())
	assert_true(_has(overlay, "137"))


func test_pad_stick_click_needs_back_chord_with_debug_off() -> void:
	var sampler: PerfSampler = _make_sampler()
	var overlay: PerfOverlay = _make_overlay(sampler)
	overlay._unhandled_input(_pad_r3())
	_feed(sampler, _canned())
	assert_eq(_shown(overlay), "", "stick click alone does nothing")
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(_pad_r3())
	_feed(sampler, _canned())
	assert_true(_has(overlay, "137"), "Back + R3 opens it")


# --- hidden costs nothing -----------------------------------------------------

func test_hidden_overlay_leaves_a_demand_driven_sampler_idle() -> void:
	var sampler: PerfSampler = _make_sampler(true)
	var overlay: PerfOverlay = _make_overlay(sampler)
	watch_signals(sampler)
	await wait_seconds(STEP_WAIT_S)
	assert_signal_not_emitted(sampler, "sampled", "hidden: no window closes")
	assert_eq(PerfProbe.start(), 0, "hidden: probes stay off")
	_cycle_to(overlay, 1)
	await wait_seconds(STEP_WAIT_S)
	assert_signal_emitted(sampler, "sampled", "BASIC wants samples")
	assert_ne(PerfProbe.start(), 0, "shown: probes on")
	_cycle_to(overlay, 2)
	await wait_process_frames(2)
	var count: int = get_signal_emit_count(sampler, "sampled")
	await wait_seconds(STEP_WAIT_S)
	assert_eq(get_signal_emit_count(sampler, "sampled"), count, "hidden again: sampling stops")
	assert_eq(PerfProbe.start(), 0, "hidden again: probes off")


# --- sampler: demand-driven ---------------------------------------------------

func test_demand_driven_sampler_is_idle_until_wanted() -> void:
	var sampler: PerfSampler = _make_sampler(true)
	watch_signals(sampler)
	await wait_seconds(STEP_WAIT_S)
	assert_signal_not_emitted(sampler, "sampled")


func test_set_wanted_true_samples_and_false_stops() -> void:
	var sampler: PerfSampler = _make_sampler(true)
	watch_signals(sampler)
	sampler.set_wanted(true)
	await wait_seconds(STEP_WAIT_S)
	assert_signal_emitted(sampler, "sampled")
	sampler.set_wanted(false)
	await wait_process_frames(2)
	var count: int = get_signal_emit_count(sampler, "sampled")
	await wait_seconds(STEP_WAIT_S)
	assert_eq(get_signal_emit_count(sampler, "sampled"), count, "no window closes after set_wanted(false)")


func test_continuous_sampler_ignores_set_wanted_false() -> void:
	var sampler: PerfSampler = _make_sampler(false)
	watch_signals(sampler)
	sampler.set_wanted(false)
	await wait_seconds(STEP_WAIT_S)
	assert_signal_emitted(sampler, "sampled", "logger and soak need continuous samples")


func test_probe_follows_wanted_for_a_demand_driven_sampler() -> void:
	var sampler: PerfSampler = _make_sampler(true)
	assert_eq(PerfProbe.start(), 0, "not wanted")
	sampler.set_wanted(true)
	assert_ne(PerfProbe.start(), 0, "wanted")
	sampler.set_wanted(false)
	assert_eq(PerfProbe.start(), 0, "not wanted again")


func test_rising_edge_starts_a_fresh_window() -> void:
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = _config
	sampler.demand_driven = true
	autofree(sampler)
	sampler.record_frame(0.4)
	sampler.set_wanted(true)
	sampler.record_frame(0.25)
	var m: Dictionary = sampler.sample_now()
	assert_almost_eq(float(m["window_s"]), 0.25, 0.001, "time before the rising edge is not counted")


# --- sampler and logger columns -----------------------------------------------

func test_collect_has_no_net_keys_but_keeps_net_mode() -> void:
	var sampler: PerfSampler = _make_sampler()
	var m: Dictionary = sampler.collect({}, 1.0)
	for dropped: String in ["net_peers", "net_ping_ms", "net_snapshot_bps"]:
		assert_false(m.has(dropped), "%s moved to F3" % dropped)
	assert_true(m.has("net_mode"), "role tag still needs net_mode")


func test_logger_columns_drop_the_net_keys() -> void:
	for dropped: String in ["net_peers", "net_ping_ms", "net_snapshot_bps"]:
		assert_false(PerfLogger.COLUMNS.has(dropped), "%s column" % dropped)
	assert_true(PerfLogger.COLUMNS.has("fps"))


# --- rows builder: frame warn rule ----------------------------------------------

const WARN_MS: float = 40.0


func _any_warn(rows: Array[DebugRow]) -> bool:
	for row: DebugRow in rows:
		if row.warn:
			return true
	return false


func test_rows_hidden_is_empty() -> void:
	assert_eq(PerfOverlay.rows(_canned(), PerfOverlay.Mode.HIDDEN, WARN_MS).size(), 0)


func test_rows_empty_metrics_read_dash_and_do_not_warn() -> void:
	for mode: PerfOverlay.Mode in [PerfOverlay.Mode.BASIC, PerfOverlay.Mode.DETAILED]:
		var rows: Array[DebugRow] = PerfOverlay.rows({}, mode, WARN_MS)
		assert_gt(rows.size(), 0)
		for row: DebugRow in rows:
			assert_true(row.cells[1].contains("-"), "%s reads -" % row.cells[0])
		assert_false(_any_warn(rows), "no reading, no warning")


func test_rows_below_threshold_has_no_warn_row() -> void:
	var rows: Array[DebugRow] = PerfOverlay.rows(_canned({"frame_ms_max": WARN_MS - 0.5}), PerfOverlay.Mode.BASIC, WARN_MS)
	assert_false(_any_warn(rows))


func test_rows_exactly_at_threshold_warns() -> void:
	var rows: Array[DebugRow] = PerfOverlay.rows(_canned({"frame_ms_max": WARN_MS}), PerfOverlay.Mode.BASIC, WARN_MS)
	assert_true(_any_warn(rows))


func test_rows_above_threshold_warns_in_both_modes() -> void:
	for mode: PerfOverlay.Mode in [PerfOverlay.Mode.BASIC, PerfOverlay.Mode.DETAILED]:
		var rows: Array[DebugRow] = PerfOverlay.rows(_canned({"frame_ms_max": WARN_MS + 10.0}), mode, WARN_MS)
		assert_true(_any_warn(rows))


func test_rows_warn_follows_the_threshold_argument() -> void:
	var m: Dictionary = _canned({"frame_ms_max": 30.0})
	assert_false(_any_warn(PerfOverlay.rows(m, PerfOverlay.Mode.BASIC, 31.0)))
	assert_true(_any_warn(PerfOverlay.rows(m, PerfOverlay.Mode.BASIC, 29.0)))
