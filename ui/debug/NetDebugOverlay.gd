class_name NetDebugOverlay
extends CanvasLayer
## F3 network panel, available in every build: link, snapshot and intent figures from a NetStatsSource plus
## controls for the lag/loss simulator (core/net/NetSim.gd, applied through the source).
##
## It polls the source only while visible, at NetConfig.stats_hz, and reads and never writes game state:
## the only thing it writes is the simulator, through NetStatsSource.set_simulation().

const NO_VALUE: String = "-"
const ROLE_NAMES: PackedStringArray = ["Offline", "Host", "Client"]
const PERCENT_PER_FRACTION: float = 100.0
# DECISION: slider steps are named constants here, not NetConfig fields: they only shape this panel's controls.
const LAG_STEP_MS: float = 5.0
const LOSS_STEP: float = 0.01

## Where the numbers come from. Transitional default: the live autoloads, until the round panels hand one in.
var source: NetStatsSource = NetStatsLive.new()
@export var net_config: NetConfig = preload("res://config/net/net_config.tres")
## Layout tunables (the gaps); the parent may hand one in before add_child, else the debug-mode one.
var config: DebugConfig = null

var _panel: UiDebugPanel = null
var _lag_slider: HSlider = null
var _lag_value_label: UiText = null
var _loss_slider: HSlider = null
var _loss_value_label: UiText = null
var _poll_left_s: float = 0.0


func _ready() -> void:
	if config == null:
		config = DebugMode.config()
	visible = false
	_panel = UiDebugPanel.new()
	_panel.heading = "NETWORK"
	_panel.toggle_action = &"net_debug_toggle"
	_panel.modifier_action = &"camera_snap_home"
	# Created empty and in display order; _show fills them.
	var no_rows: Array[DebugRow] = []
	_panel.set_note(&"offline", "")
	_panel.set_section(&"link", "Link", no_rows)
	_panel.set_section(&"snapshots", "Snapshots", no_rows)
	_panel.set_table(&"peers", "Peers", PackedStringArray(), no_rows)
	_panel.set_table(&"intents", "Intents", PackedStringArray(), no_rows)
	_build_simulator(_panel.content())
	_panel.visible = false
	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"net_debug_toggle"):
		# The pad half of this action is Y alone, so a pad press only counts with Back held (the Back + Y chord).
		if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
			return
		visible = not visible
		_panel.visible = visible
		if visible:
			_poll(true)
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventJoypadButton and event.is_action_pressed(&"ui_accept") \
			and Input.is_action_pressed(&"camera_snap_home"):
		_apply_preset()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.NET, 0.0)


## Bottom-right stack, right above F2's panel (ui/debug/DebugOverlayLayout.gd); follows the HUD scale.
func _process(delta: float) -> void:
	if not visible:
		DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.NET, 0.0)
		return
	_poll_left_s -= delta
	if _poll_left_s <= 0.0:
		_poll(false)
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.NET, _panel.size.y)
	DebugOverlayLayout.place_stack(_panel, DebugOverlayLayout.Stack.NET, config)


# --- Stats display ------------------------------------------------------------

## One reading. `opening` also points the simulator sliders at the live simulation; while open they are the user's.
func _poll(opening: bool) -> void:
	_poll_left_s = 1.0 / maxf(net_config.stats_hz, 0.01)
	var stats: NetStats = source.read()
	if opening:
		_set_sliders(stats.sim_lag_ms, stats.sim_loss)
	var role: String = ROLE_NAMES[clampi(int(stats.role), 0, ROLE_NAMES.size() - 1)]
	var is_host: bool = stats.role == NetStats.Role.HOST
	var online: bool = stats.role != NetStats.Role.OFFLINE
	_panel.set_note(&"offline", "" if online else "Offline: no network session.")
	var link: Array[DebugRow] = [DebugRow.pair("role", role)]
	var snapshots: Array[DebugRow] = []
	if online:
		link.append(DebugRow.pair("slot", str(stats.local_slot)))
		if not is_host:
			link.append(DebugRow.pair("rtt", "%.0f ms" % stats.local_rtt_ms))
			link.append(DebugRow.pair("interp delay", "%.0f ms" % stats.interp_delay_ms))
			link.append(DebugRow.pair("arrival jitter", "%.0f ms" % stats.arrival_jitter_ms))
			link.append(DebugRow.pair("loss", "%.1f%%" % (stats.loss_fraction * PERCENT_PER_FRACTION)))
			link.append(DebugRow.pair("dropped unknown", str(stats.dropped_unknown)))
		snapshots.append(DebugRow.pair("per second", "%.0f" % stats.snapshots_per_s))
		snapshots.append(DebugRow.pair("bytes per second", "%.0f B/s" % stats.snapshot_bytes_per_s))
		snapshots.append(DebugRow.pair("last bytes", str(stats.last_snapshot_bytes) if is_host else NO_VALUE))
		snapshots.append(DebugRow.pair("last bodies", str(stats.last_snapshot_bodies) if is_host else NO_VALUE))
		snapshots.append(DebugRow.pair("last fragments", str(stats.last_snapshot_fragments) if is_host else NO_VALUE))
	_panel.set_section(&"link", "Link", link)
	_panel.set_section(&"snapshots", "Snapshots", snapshots)
	_panel.set_table(&"peers", "Peers", PackedStringArray(["player", "rtt ms", "jitter ms"]), _peer_rows(stats))
	_panel.set_table(&"intents", "Intents", PackedStringArray(["player", "sent", "ok", "no", "cursors no"]), _intent_rows(stats))


func _peer_rows(stats: NetStats) -> Array[DebugRow]:
	var rows: Array[DebugRow] = []
	for peer: NetStats.PeerRow in stats.peers:
		var row: DebugRow = DebugRow.new()
		row.cells = PackedStringArray([peer.name, "%.0f" % peer.rtt_ms, "%.0f" % peer.rtt_jitter_ms])
		rows.append(row)
	return rows


## A host row has all four counters; a client only knows its own `sent`, so the rest read "-".
func _intent_rows(stats: NetStats) -> Array[DebugRow]:
	var rows: Array[DebugRow] = []
	var is_host: bool = stats.role == NetStats.Role.HOST
	for intent: NetStats.IntentRow in stats.intents:
		var row: DebugRow = DebugRow.new()
		row.cells = PackedStringArray([_player_name(stats, intent.slot_id), str(intent.sent)])
		for count: int in [intent.accepted, intent.refused, intent.cursors_refused]:
			row.cells.append(str(count) if is_host else NO_VALUE)
		rows.append(row)
	return rows


func _player_name(stats: NetStats, slot_id: int) -> String:
	for peer: NetStats.PeerRow in stats.peers:
		if peer.slot_id == slot_id:
			return peer.name
	return "slot %d" % slot_id


# --- Simulated lag/loss controls ---------------------------------------------

func _build_simulator(box: VBoxContainer) -> void:
	box.add_child(UiText.make(UiText.Role.CAPTION, "Simulator"))
	_lag_slider = _slider_row(box, "lag", net_config.max_interp_delay_ms, LAG_STEP_MS)
	_loss_slider = _slider_row(box, "loss", 1.0, LOSS_STEP)
	_lag_value_label = _value_label(_lag_slider)
	_loss_value_label = _value_label(_loss_slider)
	_lag_slider.value_changed.connect(_on_slider_changed)
	_loss_slider.value_changed.connect(_on_slider_changed)
	var buttons: HBoxContainer = HBoxContainer.new()
	var preset: UiBlockButton = UiBlockButton.new()
	preset.name = &"PresetButton"
	preset.text = "Preset %.0f ms / %.0f%%" % [net_config.sim_preset_lag_ms, net_config.sim_preset_loss * PERCENT_PER_FRACTION]
	preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset.pressed.connect(_apply_preset)
	buttons.add_child(preset)
	var off: UiBlockButton = UiBlockButton.new()
	off.name = &"OffButton"
	off.text = "Off"
	off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off.pressed.connect(_apply_off)
	buttons.add_child(off)
	box.add_child(buttons)


## A name, a slider and a value label in one row; the value label is the row's last child.
func _slider_row(box: VBoxContainer, title: String, high: float, step: float) -> HSlider:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(UiText.make(UiText.Role.CAPTION, title))
	var slider: HSlider = HSlider.new()
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	row.add_child(UiText.make(UiText.Role.CAPTION))
	box.add_child(row)
	return slider


func _value_label(slider: HSlider) -> UiText:
	var row: Node = slider.get_parent()
	return row.get_child(row.get_child_count() - 1) as UiText


func _set_sliders(lag_ms: float, loss: float) -> void:
	_lag_slider.set_value_no_signal(lag_ms)
	_loss_slider.set_value_no_signal(loss)
	_lag_value_label.text = "%.0f ms" % _lag_slider.value
	_loss_value_label.text = "%.0f%%" % (_loss_slider.value * PERCENT_PER_FRACTION)


func _on_slider_changed(_value: float) -> void:
	_push_simulation()


func _push_simulation() -> void:
	_set_sliders(_lag_slider.value, _loss_slider.value)
	source.set_simulation(_lag_slider.value, _loss_slider.value)


## The one-key acceptance condition ("a client with 100 ms of simulated lag and 2% packet loss"):
## net_config.sim_preset_lag_ms / sim_preset_loss. On a pad: Back + A while the panel is open.
func _apply_preset() -> void:
	_set_sliders(net_config.sim_preset_lag_ms, net_config.sim_preset_loss)
	_push_simulation()


func _apply_off() -> void:
	_set_sliders(0.0, 0.0)
	_push_simulation()
