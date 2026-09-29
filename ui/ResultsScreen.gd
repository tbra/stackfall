class_name ResultsScreen
extends Control
## Bontago-1pi.6 (owner playtest: "the win screen always says 'Team x wins!'
## even when not playing in teams, let's add a proper win screen with stats
## and options to replay, go back to lobby and change some settings").
##
## Shown once per match end, driven entirely by Events.match_results_ready
## (autoload/match/MatchStats.gd's own header documents the payload shape:
## winner_kind/winner_id/winner_name/match_duration/rows). Self-contained the
## same way ui/PauseMenu.gd/ui/OptionsMenu.gd are: it never reaches into
## game/Main.gd's node tree, only Events and the two `Variant` provider seams
## below (ui/HUD.gd's own match_provider/ui/Lobby.gd's own net_provider
## precedent) -- so game/Main.gd's own edit is a one-line instantiate/hide,
## exactly the brief's "no other Main.gd changes".
##
## **The reported bug** was ui/HUD.gd's %WinnerLabel always printing
## "Team %d wins!" (HUD.show_winner()), even in free-for-all where every slot
## is its own team. That label is already forced invisible on `main`
## (game/Main.gd's HUD wiring); this screen reads `winner_name` from the
## payload instead of formatting its own -- MatchStats._winner_name() already
## picks a player's own display_name in FFA and "Team %d" in team mode, so the
## fix lives in reading the payload's own field rather than in a second
## ad hoc format string.
##
## **Host-only actions.** Replay/Back to lobby call net/MatchNet.gd's
## request_replay()/request_return_to_lobby() directly (both already handle
## the local-host-vs-remote-RPC split themselves, spec 3.4 "the host checks
## every intent"); on a client both buttons -- and the Settings button, since
## a client's own edits could never reach the host's copy of the config
## request_replay() restarts with -- are disabled with a "waiting for host"
## hint instead.
##
## **Quick settings.** DECISION (ui/ResultsScreen.gd, Bontago-1pi.6, minor
## ambiguity -- CLAUDE.md "pick the simplest reasonable option"): a compact
## panel editing the host's own `Match.config` in place (block timer, gravity,
## special frequency, gifts, bot count/difficulty -- MatchConfig fields
## sanitize() already clamps), applied only on its own Apply button. This is
## safe to mutate directly: net/MatchNet.gd's _replay_current_match() reads
## `_authority().config` -- the same running match's own duplicate this panel
## edits -- fresh at the moment Replay is pressed, never a cached copy, so an
## Applied change here is exactly what the next Replay starts with. Only ever
## opened when this screen's own host gate already passed (_update_host_gate()
## disables %SettingsButton on a client, the same as the other two buttons),
## so nothing here needs its own separate host check.

## Test seams (Variant, not a static type): ui/HUD.gd's own match_provider and
## ui/Lobby.gd's own net_provider precedent -- defaulted to the real
## autoloads in _ready(), replaceable with a fake object in a GUT test so no
## test needs a real Match/Net/MatchNet session running.
var match_provider: Variant = null
var net_provider: Variant = null
var match_net_provider: Variant = null

const _AI_DIFFICULTY_LABELS: Array[String] = ["Easy", "Normal", "Hard"]

## Column header labels, in the same order _build_row_cells() below emits
## per-row text -- kept next to each other so a column can never drift out of
## sync between the header and the data rows.
const _COLUMN_HEADERS: Array[String] = [
	"Player", "Team", "Placed", "Lost", "Gifts", "Specials", "Territory", "Status",
]
## _make_cell()'s size_flags_stretch_ratio per column, matching _COLUMN_HEADERS
## index for index so header and data cells line up.
const _COLUMN_RATIOS: Array[float] = [3.0, 1.4, 1.0, 1.0, 1.0, 1.0, 1.2, 1.6]

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## The last results payload shown, kept for _apply_visual_style()-independent
## re-reads (none today, but mirrors ui/Lobby.gd's own "keep the last applied
## data" habit) and so a test can inspect exactly what was rendered.
var last_results: Dictionary = {}

@onready var _headline: Label = %Headline
@onready var _rows_list: VBoxContainer = %RowsList
@onready var _waiting_hint: Label = %WaitingHint
@onready var _replay_button: Button = %ReplayButton
@onready var _lobby_button: Button = %LobbyButton
@onready var _settings_button: Button = %SettingsButton

@onready var _settings_panel: Control = %SettingsPanel
@onready var _block_timer_spin: SpinBox = %BlockTimerSpin
@onready var _gravity_spin: SpinBox = %GravitySpin
@onready var _special_freq_spin: SpinBox = %SpecialFreqSpin
@onready var _gifts_check: CheckBox = %GiftsCheck
@onready var _ai_count_spin: SpinBox = %AiCountSpin
@onready var _ai_difficulty_option: OptionButton = %AiDifficultyOption
@onready var _settings_apply_button: Button = %SettingsApplyButton
@onready var _settings_close_button: Button = %SettingsCloseButton


func _ready() -> void:
	visible = false
	if match_provider == null:
		match_provider = Match
	if net_provider == null:
		net_provider = Net
	if match_net_provider == null:
		match_net_provider = MatchNet

	if _ai_difficulty_option.item_count == 0:
		for label: String in _AI_DIFFICULTY_LABELS:
			_ai_difficulty_option.add_item(label)

	Events.match_results_ready.connect(_on_match_results_ready)
	Events.match_state_changed.connect(_on_match_state_changed)

	_replay_button.pressed.connect(_on_replay_pressed)
	_lobby_button.pressed.connect(_on_lobby_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_settings_apply_button.pressed.connect(_on_settings_apply_pressed)
	_settings_close_button.pressed.connect(_on_settings_close_pressed)

	_settings_panel.visible = false
	_apply_visual_style()
	_wire_focus_chain()


func _on_match_results_ready(results: Dictionary) -> void:
	show_results(results)


## A new match state (a Replay restart or a Back-to-lobby, on host or on a
## mirroring client) must always take this overlay down -- it only belongs
## on top of State.END. Idempotent: hiding an already-hidden Control is a
## no-op.
func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if to_state != Match.State.END:
		hide()
		_settings_panel.visible = false


## Bontago-1pi.15.1: ui_cancel closes the quick-settings sub-panel the same
## way ui/OptionsMenu.gd/ui/Lobby.gd close their own popups with B -- this
## screen itself has no "back" (Replay/Back to lobby are the only two ways
## off a results screen, both explicit host actions), so ui_cancel only ever
## does something while %SettingsPanel is open.
func _unhandled_input(event: InputEvent) -> void:
	if _settings_panel.visible and event.is_action_pressed(&"ui_cancel"):
		_on_settings_close_pressed()
		get_viewport().set_input_as_handled()


## Public entry point (also the one GUT tests drive directly, the same
## "call the handler, don't fake the signal" style tests/unit/test_pause_menu.gd
## uses for _unhandled_input()) -- populates the headline and stats table,
## applies the host/client button gate, shows the screen and releases the
## mouse.
func show_results(results: Dictionary) -> void:
	last_results = results
	_headline.text = _headline_text(results)
	_populate_rows(results)
	_update_host_gate()
	visible = true
	move_to_front()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# On a client every button is disabled (see _update_host_gate() above) --
	# grabbing focus on a disabled Button is harmless but pointless, so only
	# the host's own screen actually lands keyboard/gamepad focus anywhere.
	if not _replay_button.disabled:
		_replay_button.grab_focus()


## The reported defect's fix: read the payload's own winner_name (a player's
## display_name in FFA, "Team %d" in team mode -- MatchStats._winner_name())
## rather than formatting a second "Team %d wins!" string here that would
## repeat HUD.gd's bug. winner_id < 0 or an empty winner_name (never produced
## by the engine today, but the payload is untrusted input on a client -- see
## MatchStats.validate_results_payload()) reads as a draw instead of crashing
## on a blank headline.
func _headline_text(results: Dictionary) -> String:
	var winner_id: int = int(results.get("winner_id", -1))
	var winner_name: String = String(results.get("winner_name", ""))
	if winner_id < 0 or winner_name.is_empty():
		return "It's a draw!"
	return "%s wins!" % winner_name


# --- Stats table -------------------------------------------------------------

## Pure and static so a test can assert placement order without touching the
## scene tree. DECISION (ui/ResultsScreen.gd, minor ambiguity): the payload
## carries no explicit "placement" field, so this derives one -- the winning
## team's row(s) first, then surviving slots ranked by their team's own
## territory_share (higher first), then eliminated slots ranked by how long
## they survived (a later eliminated_at outranks an earlier one). Reasonable
## and stable, not spec-mandated.
static func sorted_rows(results: Dictionary) -> Array[Dictionary]:
	var winner_kind: String = String(results.get("winner_kind", MatchStats.WINNER_KIND_SLOT))
	var winner_id: int = int(results.get("winner_id", -1))
	var raw_rows: Array = results.get("rows", [])
	var rows: Array[Dictionary] = []
	for raw_row: Variant in raw_rows:
		var row: Dictionary = (raw_row as Dictionary).duplicate()
		var is_winner: bool = winner_id >= 0 and (
			(winner_kind == MatchStats.WINNER_KIND_TEAM and int(row.get("team_id", -1)) == winner_id)
			or (winner_kind == MatchStats.WINNER_KIND_SLOT and int(row.get("slot_id", -1)) == winner_id)
		)
		row["is_winner"] = is_winner
		rows.append(row)
	rows.sort_custom(_row_less_than)
	return rows


static func _row_less_than(a: Dictionary, b: Dictionary) -> bool:
	var a_winner: bool = bool(a.get("is_winner", false))
	var b_winner: bool = bool(b.get("is_winner", false))
	if a_winner != b_winner:
		return a_winner
	var a_alive: bool = float(a.get("eliminated_at", MatchStats.NOT_ELIMINATED)) < 0.0
	var b_alive: bool = float(b.get("eliminated_at", MatchStats.NOT_ELIMINATED)) < 0.0
	if a_alive != b_alive:
		return a_alive
	if a_alive:
		return float(a.get("territory_share", 0.0)) > float(b.get("territory_share", 0.0))
	return float(a.get("eliminated_at", 0.0)) > float(b.get("eliminated_at", 0.0))


func _populate_rows(results: Dictionary) -> void:
	for child: Node in _rows_list.get_children():
		_rows_list.remove_child(child)
		child.queue_free()

	var winner_kind: String = String(results.get("winner_kind", MatchStats.WINNER_KIND_SLOT))
	_rows_list.add_child(_build_header_row())
	for row: Dictionary in sorted_rows(results):
		_rows_list.add_child(_build_data_row(row, winner_kind))


func _build_header_row() -> HBoxContainer:
	var header: HBoxContainer = HBoxContainer.new()
	header.name = "HeaderRow"
	for i: int in range(_COLUMN_HEADERS.size()):
		var cell: Label = _make_cell(_COLUMN_HEADERS[i], _COLUMN_RATIOS[i])
		cell.add_theme_color_override("font_color", tuning.label_muted_color)
		header.add_child(cell)
	return header


func _build_data_row(row: Dictionary, winner_kind: String) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var is_winner: bool = bool(row.get("is_winner", false))
	var is_bot: bool = bool(row.get("is_bot", false))
	panel.set_meta(&"slot_id", int(row.get("slot_id", -1)))
	panel.set_meta(&"is_winner", is_winner)
	panel.add_theme_stylebox_override(
		"panel",
		MenuStyleFactory.make_badge(tuning.pill_mint_color if is_winner else tuning.pill_cream_color, tuning)
	)

	var box: HBoxContainer = HBoxContainer.new()
	panel.add_child(box)

	var name_text: String = String(row.get("name", ""))
	if is_bot:
		name_text += " (Bot)"
	var team_text: String = "-" if winner_kind == MatchStats.WINNER_KIND_SLOT else "Team %d" % (int(row.get("team_id", 0)) + 1)
	var eliminated_at: float = float(row.get("eliminated_at", MatchStats.NOT_ELIMINATED))
	var status_text: String = "Survived" if eliminated_at < 0.0 else "Out @ %ds" % int(round(eliminated_at))
	var territory_text: String = "%d%%" % int(round(float(row.get("territory_share", 0.0)) * 100.0))

	var cell_texts: Array[String] = [
		name_text, team_text,
		str(int(row.get("blocks_placed", 0))),
		str(int(row.get("blocks_lost", 0))),
		str(int(row.get("gifts_claimed", 0))),
		str(int(row.get("specials_used", 0))),
		territory_text, status_text,
	]
	for i: int in range(cell_texts.size()):
		var cell: Label = _make_cell(cell_texts[i], _COLUMN_RATIOS[i])
		cell.add_theme_color_override("font_color", tuning.ink_color)
		box.add_child(cell)
	return panel


func _make_cell(text: String, ratio: float) -> Label:
	var cell: Label = Label.new()
	cell.text = text
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.size_flags_stretch_ratio = ratio
	cell.clip_text = true
	return cell


# --- Host/client gate ---------------------------------------------------------

func _update_host_gate() -> void:
	var is_host: bool = net_provider != null and bool(net_provider.is_host())
	_replay_button.disabled = not is_host
	_lobby_button.disabled = not is_host
	_settings_button.disabled = not is_host
	_waiting_hint.visible = not is_host


func _on_replay_pressed() -> void:
	if match_net_provider != null:
		match_net_provider.request_replay()


func _on_lobby_pressed() -> void:
	if match_net_provider != null:
		match_net_provider.request_return_to_lobby()


# --- Quick settings panel ------------------------------------------------------

func _current_config() -> MatchConfig:
	if match_provider == null:
		return null
	return match_provider.config as MatchConfig


func _on_settings_pressed() -> void:
	var config: MatchConfig = _current_config()
	if config == null:
		return
	_block_timer_spin.value = config.block_timer
	_gravity_spin.value = config.gravity_multiplier
	_special_freq_spin.value = config.special_frequency
	_gifts_check.button_pressed = config.gifts_enabled
	_ai_count_spin.value = config.ai_count
	_ai_difficulty_option.selected = config.ai_difficulty
	_settings_panel.visible = true
	_settings_apply_button.grab_focus()


func _on_settings_close_pressed() -> void:
	_settings_panel.visible = false
	_settings_button.grab_focus()


## Applies the panel's edited fields onto the host's own running config in
## place (see this file's own header DECISION for why that's the correct
## target) and re-clamps with MatchConfig.sanitize() -- the same call every
## other wire/lobby entry point makes before trusting a config's fields.
func _on_settings_apply_pressed() -> void:
	var config: MatchConfig = _current_config()
	if config != null:
		config.block_timer = float(_block_timer_spin.value)
		config.gravity_multiplier = float(_gravity_spin.value)
		config.special_frequency = int(_special_freq_spin.value)
		config.gifts_enabled = _gifts_check.button_pressed
		config.ai_count = int(_ai_count_spin.value)
		config.ai_difficulty = _ai_difficulty_option.selected
		config.sanitize()
		# The Lobby is recreated after Back to lobby and reads Net's cached
		# lobby data. Publish the edited config now, preserving its roster until
		# the new Lobby refreshes that roster on entry.
		if net_provider != null and bool(net_provider.is_host()):
			var data: Dictionary = config.to_dict()
			var previous: Dictionary = net_provider.lobby_data()
			if previous.has("roster"):
				data["roster"] = previous["roster"]
			net_provider.set_lobby_data(data)
	_settings_panel.visible = false
	_settings_button.grab_focus()


# --- Visual style + focus chain -------------------------------------------------

## Same StyleBoxFlat-from-MenuVisualTuning technique ui/Lobby.gd's own
## _apply_visual_style() doc comment describes: no image assets, everything
## drawn from ui/theme/MenuStyleFactory.gd on top of the shared
## ui/theme/stackfall_theme.tres Theme this scene's root sets.
func _apply_visual_style() -> void:
	var card: PanelContainer = %Card
	card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	var settings_card: PanelContainer = %SettingsCard
	settings_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))

	MenuStyleFactory.apply_pill(
		_replay_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_lobby_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_settings_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_settings_apply_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_settings_close_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning
	)
	_waiting_hint.add_theme_color_override("font_color", tuning.label_muted_color)

	var well_box: StyleBoxFlat = MenuStyleFactory.make_well(tuning)
	MenuStyleFactory.hide_spinbox_arrows(_block_timer_spin)
	MenuStyleFactory.hide_spinbox_arrows(_gravity_spin)
	MenuStyleFactory.hide_spinbox_arrows(_special_freq_spin)
	MenuStyleFactory.hide_spinbox_arrows(_ai_count_spin)
	for spin: SpinBox in [_block_timer_spin, _gravity_spin, _special_freq_spin, _ai_count_spin]:
		var line_edit: LineEdit = spin.get_line_edit()
		if line_edit != null:
			line_edit.add_theme_stylebox_override("normal", well_box)


## Gamepad/keyboard navigability -- same runtime get_path_to() chaining
## ui/PauseMenu.gd's own _wire_focus_chain() doc comment explains.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [_replay_button, _lobby_button, _settings_button]
	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL

	var settings_chain: Array[Control] = [
		_block_timer_spin, _gravity_spin, _special_freq_spin, _gifts_check,
		_ai_count_spin, _ai_difficulty_option, _settings_apply_button, _settings_close_button,
	]
	for i: int in range(settings_chain.size()):
		var current: Control = settings_chain[i]
		var prev: Control = settings_chain[(i - 1 + settings_chain.size()) % settings_chain.size()]
		var next: Control = settings_chain[(i + 1) % settings_chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
