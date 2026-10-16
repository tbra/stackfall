extends GutTest
## Weather replication: the host records what it would rpc; a client is fed that payload
## (or a hostile one) through the same net_weather_state() entry.

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


# --- Presentation -----------------------------------------------------------------------

# --- Lobby ---------------------------------------------------------------------------------
