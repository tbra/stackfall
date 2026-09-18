class_name NetDebugOverlay
extends CanvasLayer
## Spec Part 4 M3's debug overlay: ping, snapshot size, interpolation delay
## and packet loss, plus controls for core/net/NetSim.gd's simulated
## lag/loss (docs/M3a_PLAN.md P4).
##
## "The overlay reads and never writes game state" (docs/M3a_PLAN.md "Must
## NOT"): every label comes straight from Net.stats(), refreshed on
## Events.net_stats_updated; the only things this script writes are the
## simulator's own tunables, through Net.set_simulation(), which is the seam
## P1 built for exactly this.

## DECISION (ui/NetDebugOverlay.gd): same `Variant` test seam as
## ui/MainMenu.gd, ui/Lobby.gd and ui/HUD.gd's match_provider.
var net_provider: Variant = null

@export var net_config: NetConfig = preload("res://config/net_config.tres")

@onready var _mode_label: Label = %ModeLabel
@onready var _ping_label: Label = %PingLabel
@onready var _snapshot_label: Label = %SnapshotLabel
@onready var _interp_label: Label = %InterpLabel
@onready var _loss_label: Label = %LossLabel
@onready var _lag_slider: HSlider = %LagSlider
@onready var _lag_value_label: Label = %LagValueLabel
@onready var _loss_slider: HSlider = %LossSlider
@onready var _loss_value_label: Label = %LossValueLabel
@onready var _preset_button: Button = %PresetButton
@onready var _off_button: Button = %OffButton

## Guards _on_slider_changed while a preset/off button is writing both
## sliders, so it doesn't call Net.set_simulation() twice with a half-applied
## pair of values.
var _applying_preset: bool = false


func _ready() -> void:
	net_provider = Net
	visible = false
	_lag_slider.max_value = net_config.max_interp_delay_ms
	_loss_slider.min_value = 0.0
	_loss_slider.max_value = 1.0
	_lag_slider.value_changed.connect(_on_lag_changed)
	_loss_slider.value_changed.connect(_on_loss_changed)
	_preset_button.pressed.connect(_on_preset_pressed)
	_off_button.pressed.connect(_on_off_pressed)
	Events.net_stats_updated.connect(_on_stats_updated)
	_refresh_labels(net_provider.stats() if net_provider != null else {})


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"net_debug_toggle"):
		return
	# See tools/bootstrap_project.gd's DECISION: the gamepad half of this
	# action is bound to Y alone (every button is already spoken for), so a
	# joypad press only counts as the toggle while camera_snap_home (Back) is
	# also held — the two-action chord that stands in for "Back+Y". A
	# keyboard press (F3) needs no modifier.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
		return
	visible = not visible
	get_viewport().set_input_as_handled()


# --- Stats display ------------------------------------------------------------

func _on_stats_updated(stats: Dictionary) -> void:
	_refresh_labels(stats)


func _refresh_labels(stats: Dictionary) -> void:
	var mode_names: PackedStringArray = ["Offline", "Host", "Client"]
	var mode: int = int(stats.get("mode", 0))
	_mode_label.text = "Mode: %s (%d peers)" % [
		mode_names[clampi(mode, 0, mode_names.size() - 1)], int(stats.get("peers", 0))
	]
	_ping_label.text = "Ping: %.0f ms" % float(stats.get("ping_ms", 0.0))
	_snapshot_label.text = "Snapshot: %.0f B/s (last %d B)" % [
		float(stats.get("snapshot_bps", 0.0)), int(stats.get("snapshot_last_bytes", 0))
	]
	_interp_label.text = "Interp delay: %.0f ms" % float(stats.get("interp_delay_ms", 0.0))
	_loss_label.text = "Loss: %.1f%%" % (float(stats.get("loss_pct", 0.0)) * 100.0)


# --- Simulated lag/loss controls ---------------------------------------------

func _on_lag_changed(value: float) -> void:
	_lag_value_label.text = "%.0f ms" % value
	if not _applying_preset:
		_push_simulation()


func _on_loss_changed(value: float) -> void:
	_loss_value_label.text = "%.1f%%" % (value * 100.0)
	if not _applying_preset:
		_push_simulation()


func _push_simulation() -> void:
	if net_provider != null:
		net_provider.set_simulation(_lag_slider.value, 0.0, _loss_slider.value)


## Spec Part 4 M3's one-key acceptance condition: "a client with 100 ms of
## simulated lag and 2% packet loss". net_config.sim_preset_lag_ms /
## sim_preset_loss are the tunables (CLAUDE.md: no magic numbers here).
func _on_preset_pressed() -> void:
	_applying_preset = true
	_lag_slider.value = net_config.sim_preset_lag_ms
	_loss_slider.value = net_config.sim_preset_loss
	_applying_preset = false
	_push_simulation()


func _on_off_pressed() -> void:
	_applying_preset = true
	_lag_slider.value = 0.0
	_loss_slider.value = 0.0
	_applying_preset = false
	_push_simulation()
