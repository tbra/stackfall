extends GutTest
## Weather replication and lobby (Bontago-22y.10). There is no second peer in
## a unit test (the Net autoload owns the tree's MultiplayerAPI), so the wire
## is exercised at its two ends: the host WeatherNet records exactly what it
## would rpc, and a client WeatherNet is handed that payload (or a hostile one)
## through the same net_weather_state() entry the RPC calls. Real two-process
## ENet delivery is the manual/harness check listed in the Bead comment.

const DELTA: float = 0.25

## Stands in for the Match autoload: WeatherNet needs weather() and state().
class StubMatch:
	extends RefCounted
	var weather_ref: MatchWeather
	var match_state: int = MatchAutoload.State.PLAYING

	func weather() -> MatchWeather:
		return weather_ref

	func state() -> int:
		return match_state

var _stubs: Array[StubMatch] = []
var _nodes: Array[WeatherNet] = []
var _events: Array = []


func before_each() -> void:
	_events.clear()
	Events.weather_started.connect(_on_started)
	Events.weather_stopped.connect(_on_stopped)


func after_each() -> void:
	Events.weather_started.disconnect(_on_started)
	Events.weather_stopped.disconnect(_on_stopped)
	for node: WeatherNet in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


func _on_started(weather_id: StringName) -> void:
	_events.append(["start", weather_id])


func _on_stopped(weather_id: StringName) -> void:
	_events.append(["stop", weather_id])


func _def(id: StringName) -> WeatherTuning:
	var def: WeatherTuning = WeatherTuning.new()
	def.id = id
	def.ramp_in_s = 2.0
	def.ramp_out_s = 2.0
	def.hold_min_s = 10.0
	def.hold_max_s = 10.0
	return def


func _weather(host: bool) -> MatchWeather:
	var w: MatchWeather = MatchWeather.new()
	w.set_defs([_def(&"storm"), _def(&"rain"), _def(&"snow")])
	var s: WeatherScheduleTuning = WeatherScheduleTuning.new()
	s.first_delay_s = 1.0
	s.gap_min_s = 5.0
	s.gap_max_s = 5.0
	w.set_schedule_tuning(s)
	w.set_host_override(host)
	return w


func _net_for(weather: MatchWeather, host: bool, match_state: int = MatchAutoload.State.PLAYING) -> WeatherNet:
	var fake: FakeNet = FakeNet.host({1: 0}, [0]) if host else FakeNet.client(0)
	var stub: StubMatch = StubMatch.new()
	stub.weather_ref = weather
	stub.match_state = match_state
	_stubs.append(stub)
	var node: WeatherNet = WeatherNet.new()
	add_child(node)
	node.set_providers(fake, stub)
	_nodes.append(node)
	return node


func _config(mode: int) -> MatchConfig:
	var c: MatchConfig = MatchConfig.new()
	c.weather_mode = mode as MatchConfig.WeatherMode
	c.rng_seed = 5
	return c


func _run(w: MatchWeather, seconds: float) -> void:
	for _i: int in range(int(round(seconds / DELTA))):
		w.tick(DELTA)


## Host in a live event; returns the wire payload it last sent, then frees the
## host WeatherNet so the client below (same global Events bus) cannot echo
## back into it.
func _host_payload(seconds: float) -> Dictionary:
	var host_weather: MatchWeather = _weather(true)
	var host_net: WeatherNet = _net_for(host_weather, true)
	host_weather.begin_match(_config(MatchConfig.WeatherMode.CHANGING))
	_run(host_weather, seconds)
	var payload: Dictionary = host_net.last_sent_state.duplicate(true)
	assert_gt(host_net.states_sent, 0, "host announced its state")
	host_net.free()
	host_weather.reset()
	_events.clear()
	return payload


# --- Host sends -------------------------------------------------------------------

func test_host_sends_state_on_every_phase_change() -> void:
	var w: MatchWeather = _weather(true)
	var net: WeatherNet = _net_for(w, true)
	w.begin_match(_config(MatchConfig.WeatherMode.CHANGING))
	assert_eq(net.states_sent, 1, "calm announced at match start")
	assert_eq(int(net.last_sent_state["sched"]), MatchWeather.Sched.CALM)
	assert_almost_eq(float(net.last_sent_state["left"]), 1.0, 0.001, "calm carries remaining time for the cue")
	_run(w, 2.0)
	assert_eq(int(net.last_sent_state["sched"]), MatchWeather.Sched.EVENT)
	assert_ne(String(net.last_sent_state["id"]), "")
	var sent_at_event: int = net.states_sent
	_run(w, 4.0)
	assert_gt(net.states_sent, sent_at_event, "ramp-in to hold announced")
	assert_eq(int(net.last_sent_state["phase"]), WeatherTuning.Phase.HOLD)


func test_a_joining_peer_is_handed_the_current_state() -> void:
	var w: MatchWeather = _weather(true)
	var net: WeatherNet = _net_for(w, true)
	w.begin_match(_config(MatchConfig.WeatherMode.CHANGING))
	_run(w, 6.0)
	var before: int = net.states_sent
	Events.net_peer_joined.emit(2, 1, "late")
	assert_eq(net.states_sent, before + 1)
	assert_eq(net.last_sent_state, w.state_dict())
	assert_eq(int(net.last_sent_state["sched"]), MatchWeather.Sched.EVENT)


func test_a_joining_peer_gets_nothing_when_no_weather_is_running() -> void:
	var w: MatchWeather = _weather(true)
	var net: WeatherNet = _net_for(w, true)
	Events.net_peer_joined.emit(2, 1, "late")
	assert_eq(net.states_sent, 0)


func test_a_client_does_not_send_state() -> void:
	var w: MatchWeather = _weather(false)
	var net: WeatherNet = _net_for(w, false)
	Events.weather_state_changed.emit(w.state_dict())
	assert_eq(net.states_sent, 0)


# --- Client applies -----------------------------------------------------------------

func test_client_reproduces_the_hosts_event_from_the_payload() -> void:
	var payload: Dictionary = _host_payload(6.0)
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	client_net.net_weather_state(payload)
	assert_eq(client_net.states_applied, 1)
	assert_eq(String(client_weather.active_id()), String(payload["id"]))
	assert_eq(_events.size(), 1)
	assert_eq(_events[0][0], "start")
	# The client never simulates weather: ticking presents intensity only.
	client_weather.tick(1.0)
	assert_gte(client_weather.active_intensity(), 0.0)
	assert_eq(client_weather.mode(), MatchConfig.WeatherMode.CHANGING)


func test_a_late_joiner_lands_in_the_middle_of_a_hold_at_full_intensity() -> void:
	var host_weather: MatchWeather = _weather(true)
	var host_net: WeatherNet = _net_for(host_weather, true)
	host_weather.begin_match(_config(MatchConfig.WeatherMode.CHANGING))
	_run(host_weather, 8.0)
	assert_eq(host_weather.event_phase(), WeatherTuning.Phase.HOLD)
	Events.net_peer_joined.emit(3, 2, "late")
	var payload: Dictionary = host_net.last_sent_state.duplicate(true)
	host_net.free()
	host_weather.reset()
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	client_net.net_weather_state(payload)
	assert_eq(client_weather.event_phase(), WeatherTuning.Phase.HOLD)
	assert_almost_eq(client_weather.active_intensity(), 1.0, 0.001)


func test_client_ends_the_event_when_the_host_reports_calm() -> void:
	var payload: Dictionary = _host_payload(6.0)
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	client_net.net_weather_state(payload)
	var calm: Dictionary = payload.duplicate()
	calm["sched"] = MatchWeather.Sched.CALM
	calm["id"] = ""
	calm["left"] = 30.0
	client_net.net_weather_state(calm)
	assert_eq(client_weather.active_id(), &"")
	assert_eq(_events.back(), ["stop", StringName(payload["id"])])
	assert_almost_eq(client_weather.next_event_in(), 30.0, 0.001)


func test_client_state_counts_down_the_calm_cue_locally() -> void:
	var payload: Dictionary = _host_payload(0.5)
	assert_eq(int(payload["sched"]), MatchWeather.Sched.CALM)
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	client_net.net_weather_state(payload)
	var start: float = client_weather.next_event_in()
	client_weather.tick(0.25)
	assert_almost_eq(client_weather.next_event_in(), start - 0.25, 0.001)


# --- Rejection -----------------------------------------------------------------------

func _hostile_cases(valid: Dictionary) -> Dictionary:
	var cases: Dictionary = {}
	var missing: Dictionary = valid.duplicate()
	missing.erase("phase")
	cases["missing key"] = missing
	var extra: Dictionary = valid.duplicate()
	extra["surprise"] = 1
	cases["extra key"] = extra
	var bad_id: Dictionary = valid.duplicate()
	bad_id["id"] = "meteor_storm"
	cases["unknown id"] = bad_id
	var typed_wrong: Dictionary = valid.duplicate()
	typed_wrong["mode"] = "wind"
	cases["string mode"] = typed_wrong
	var bad_enum: Dictionary = valid.duplicate()
	bad_enum["phase"] = 9
	cases["phase out of range"] = bad_enum
	var bad_sched: Dictionary = valid.duplicate()
	bad_sched["sched"] = -1
	cases["sched out of range"] = bad_sched
	var bad_mode: Dictionary = valid.duplicate()
	bad_mode["mode"] = 42
	cases["mode out of range"] = bad_mode
	var nan_t: Dictionary = valid.duplicate()
	nan_t["t"] = NAN
	cases["nan time"] = nan_t
	var inf_left: Dictionary = valid.duplicate()
	inf_left["left"] = INF
	cases["inf left"] = inf_left
	var negative: Dictionary = valid.duplicate()
	negative["t"] = -1.0
	cases["negative time"] = negative
	var huge: Dictionary = valid.duplicate()
	huge["left"] = 1.0e9
	cases["absurd time"] = huge
	var version: Dictionary = valid.duplicate()
	version["v"] = 99
	cases["wrong version"] = version
	var calm_with_id: Dictionary = valid.duplicate()
	calm_with_id["sched"] = MatchWeather.Sched.CALM
	cases["calm claiming an id"] = calm_with_id
	var off_running: Dictionary = valid.duplicate()
	off_running["mode"] = MatchConfig.WeatherMode.OFF
	cases["off mode running"] = off_running
	var neg_epoch: Dictionary = valid.duplicate()
	neg_epoch["epoch"] = -3
	cases["negative epoch"] = neg_epoch
	return cases


func test_malformed_state_is_rejected_and_changes_nothing() -> void:
	var valid: Dictionary = _host_payload(6.0)
	assert_eq(int(valid["sched"]), MatchWeather.Sched.EVENT, "fixture reaches an event")
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	var cases: Dictionary = _hostile_cases(valid)
	for label: String in cases.keys():
		client_net.net_weather_state(cases[label] as Dictionary)
		assert_eq(client_net.states_applied, 0, label)
		assert_eq(client_weather.active_id(), &"", label)
		assert_false(client_weather.is_running(), label)
	assert_eq(client_net.states_refused, cases.size())
	assert_eq(_events.size(), 0, "no presentation signal from garbage")
	client_net.net_weather_state(valid)
	assert_eq(client_net.states_applied, 1, "the untouched payload is still accepted")


func test_a_type_confused_payload_is_rejected_not_crashed_on() -> void:
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	client_net.net_weather_state({})
	client_net.net_weather_state({"v": 1})
	assert_eq(client_net.states_applied, 0)
	assert_eq(client_net.states_refused, 2)
	assert_eq(client_weather.sanitize_wire_state("not a dictionary"), {})
	assert_eq(client_weather.sanitize_wire_state(null), {})
	assert_eq(client_weather.sanitize_wire_state([1, 2, 3]), {})


func test_a_state_outside_a_live_match_is_ignored() -> void:
	var valid: Dictionary = _host_payload(6.0)
	for state: int in [MatchAutoload.State.LOBBY, MatchAutoload.State.LOADING, MatchAutoload.State.END]:
		var client_weather: MatchWeather = _weather(false)
		var client_net: WeatherNet = _net_for(client_weather, false, state)
		client_net.net_weather_state(valid)
		assert_eq(client_net.states_applied, 0, "state %d" % state)
		assert_eq(client_weather.active_id(), &"")
	var countdown_weather: MatchWeather = _weather(false)
	var countdown_net: WeatherNet = _net_for(countdown_weather, false, MatchAutoload.State.COUNTDOWN)
	countdown_net.net_weather_state(valid)
	assert_eq(countdown_net.states_applied, 1, "countdown accepts: the host's PLAYING event may arrive first")


func test_a_stale_epoch_is_ignored() -> void:
	var valid: Dictionary = _host_payload(6.0)
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	var newer: Dictionary = valid.duplicate()
	newer["epoch"] = int(valid["epoch"]) + 1
	client_net.net_weather_state(newer)
	assert_eq(client_net.states_applied, 1)
	client_net.net_weather_state(valid)
	assert_eq(client_net.states_applied, 1, "an older match's late packet is dropped")
	assert_eq(client_net.states_refused, 1)


func test_the_host_ignores_a_weather_message_sent_to_it() -> void:
	var host_weather: MatchWeather = _weather(true)
	var host_net: WeatherNet = _net_for(host_weather, true)
	host_weather.begin_match(_config(MatchConfig.WeatherMode.RAIN))
	var forged: Dictionary = host_weather.state_dict()
	forged["sched"] = MatchWeather.Sched.EVENT
	forged["id"] = "snow"
	host_net.net_weather_state(forged)
	assert_eq(host_net.states_refused, 1)
	assert_eq(host_weather.active_id(), &"")
	assert_false(host_weather.apply_replicated_state(forged, true), "the model itself refuses on the host")


func test_match_reset_clears_a_client_so_a_new_match_starts_clean() -> void:
	var valid: Dictionary = _host_payload(6.0)
	var client_weather: MatchWeather = _weather(false)
	var client_net: WeatherNet = _net_for(client_weather, false)
	client_net.net_weather_state(valid)
	assert_eq(client_weather.active_id(), StringName(valid["id"]))
	client_weather.reset()
	assert_eq(client_weather.active_id(), &"")
	assert_eq(_events.back()[0], "stop")
	var older: Dictionary = valid.duplicate()
	older["epoch"] = 0
	client_net.net_weather_state(older)
	assert_eq(client_net.states_applied, 2, "epochs restart per match on the client")


# --- Presentation -----------------------------------------------------------------------

func test_presenter_instances_the_active_scene_and_frees_it_on_stop() -> void:
	var presenter: WeatherPresenter = WeatherPresenter.new()
	add_child_autofree(presenter)
	var wind: WeatherTuning = _def(&"storm")
	wind.presentation_scene = "res://vfx/weather/storm_presentation.tscn"
	presenter.set_defs([wind])
	Events.weather_started.emit(&"storm")
	assert_eq(presenter.active_count(), 1)
	Events.weather_intensity_changed.emit(&"storm", 0.6)
	assert_almost_eq(presenter.presentation_for(&"storm").intensity, 0.6, 0.0001)
	Events.weather_started.emit(&"storm")
	assert_eq(presenter.active_count(), 1, "a repeated start does not double-instance")
	Events.weather_stopped.emit(&"storm")
	assert_eq(presenter.active_count(), 0)
	Events.weather_started.emit(&"unknown")
	assert_eq(presenter.active_count(), 0, "unknown ids present nothing")


func test_match_net_builds_the_weather_child_and_forwards_providers() -> void:
	var net: Node = load("res://net/MatchNet.gd").new()
	net.set_process(false)
	add_child_autofree(net)
	var child: Node = net.get_node_or_null("WeatherNet")
	assert_not_null(child)
	assert_true(child is WeatherNet)
	assert_not_null(child.get_node_or_null("WeatherPresenter"))


# --- Lobby ---------------------------------------------------------------------------------

func _make_lobby(is_host: bool) -> Lobby:
	var scene: PackedScene = load("res://ui/Lobby.tscn")
	var lobby: Lobby = autofree(scene.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func test_lobby_weather_row_has_every_mode_in_enum_order_and_defaults_changing() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%WeatherOption")
	assert_eq(option.item_count, MatchConfig.WeatherMode.size())
	assert_eq(option.get_item_text(MatchConfig.WeatherMode.RANDOM), "Random")
	assert_eq(option.get_item_text(MatchConfig.WeatherMode.CHANGING), "Changing")
	assert_eq(option.get_item_text(MatchConfig.WeatherMode.STORM), "Storm")
	assert_eq(option.selected, MatchConfig.WeatherMode.CHANGING, "Changing is the default")


func test_host_choosing_weather_publishes_it() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%WeatherOption")
	option.select(MatchConfig.WeatherMode.SNOW)
	option.item_selected.emit(MatchConfig.WeatherMode.SNOW)
	var calls: Array[Dictionary] = (lobby.net_provider as FakeNet).set_lobby_data_calls
	assert_eq(calls.size(), 1)
	assert_eq(int(calls[0].get("weather_mode")), MatchConfig.WeatherMode.SNOW)


func test_client_row_is_disabled_and_mirrors_the_hosts_choice() -> void:
	var lobby: Lobby = _make_lobby(false)
	var option: UiDropdown = lobby.get_node("%WeatherOption")
	assert_true(option.disabled, "clients cannot edit match settings")
	var config: MatchConfig = MatchConfig.new()
	config.weather_mode = MatchConfig.WeatherMode.CHANGING
	lobby._apply_data(config.to_dict())
	assert_eq(option.selected, MatchConfig.WeatherMode.CHANGING)
	var calls: Array[Dictionary] = (lobby.net_provider as FakeNet).set_lobby_data_calls
	assert_eq(calls.size(), 0, "applying remote data must not echo")


func test_host_row_is_enabled_and_reachable_from_the_popup_focus_chain() -> void:
	var lobby: Lobby = _make_lobby(true)
	var option: UiDropdown = lobby.get_node("%WeatherOption")
	assert_false(option.disabled)
	assert_eq(option.focus_mode, Control.FOCUS_ALL)
	assert_false(option.focus_neighbor_top.is_empty(), "gamepad d-pad can reach it")
	assert_false(option.focus_neighbor_bottom.is_empty())


func test_a_hostile_weather_mode_over_the_wire_is_clamped() -> void:
	var lobby: Lobby = _make_lobby(false)
	lobby._apply_data({"weather_mode": 250})
	var option: UiDropdown = lobby.get_node("%WeatherOption")
	assert_eq(option.selected, MatchConfig.WeatherMode.CHANGING)


func test_a_constant_type_replicates_as_a_held_event_and_a_client_stays_at_full_intensity() -> void:
	var host_weather: MatchWeather = _weather(true)
	host_weather.begin_match(_config(MatchConfig.WeatherMode.RAIN))
	for _i: int in range(80):
		host_weather.tick(0.25)
	assert_eq(host_weather.active_id(), &"rain")
	var client_weather: MatchWeather = _weather(false)
	assert_true(client_weather.apply_replicated_state(host_weather.state_dict(), true))
	for _i: int in range(400):
		client_weather.tick(0.25)
	assert_eq(client_weather.active_id(), &"rain")
	assert_eq(client_weather.event_phase(), WeatherTuning.Phase.HOLD)
	assert_almost_eq(client_weather.active_intensity(), 1.0, 0.001)
