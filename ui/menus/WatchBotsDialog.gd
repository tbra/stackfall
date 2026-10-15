class_name WatchBotsDialog
extends UiDialog
## Bontago-1pi.212: the debug-only "Watch bots" picker (main menu, Debug page). Mode, number of bots,
## difficulty (all one level or mixed), gifts and weather; Start emits `confirmed` with the choices as a
## WatchBotsOptions (game/main/WatchBotsOptions.gd, which also builds the MatchConfig and remembers the last
## values). Built from ui/components only; the match itself is started by game/main/Main.gd.

## Start was pressed; the options are already saved as the next defaults.
signal confirmed(options: WatchBotsOptions)

const DIALOG_TITLE: String = "Watch bots"
const DIALOG_TEXT: String = "Every seat is a bot. You only watch."
const START_ID: StringName = &"start"
const START_TEXT: String = "Start"
const ROW_MODE: String = "Mode"
const ROW_BOTS: String = "Bots"
const ROW_DIFFICULTY: String = "Difficulty"
const ROW_GIFTS: String = "Gifts"
const ROW_WEATHER: String = "Weather"
const ON_TEXT: String = "On"
const OFF_TEXT: String = "Off"

var mode_cycler: UiCycler = null
var bots_stepper: UiStepper = null
var difficulty_cycler: UiCycler = null
var gifts_toggle: UiChipToggle = null
var weather_toggle: UiChipToggle = null

var _mode_ids: Array[int] = []


func _init() -> void:
	super()
	title = DIALOG_TITLE
	dialog_text = DIALOG_TEXT
	var limits: WatchBotsTuning = WatchBotsOptions.tuning()

	mode_cycler = UiCycler.new()
	for mode_id: int in MatchConfig.SELECTABLE_GAME_MODES:
		_mode_ids.append(mode_id)
		mode_cycler.add_item(MatchConfig.GAME_MODE_LABELS[mode_id])
	_add_row(ROW_MODE, mode_cycler)

	bots_stepper = UiStepper.new()
	bots_stepper.min_value = limits.min_bots
	bots_stepper.max_value = limits.max_bots
	_add_row(ROW_BOTS, bots_stepper)

	difficulty_cycler = UiCycler.new()
	for label: String in WatchBotsOptions.DIFFICULTY_LABELS:
		difficulty_cycler.add_item(label)
	_add_row(ROW_DIFFICULTY, difficulty_cycler)

	gifts_toggle = _make_toggle()
	_add_row(ROW_GIFTS, gifts_toggle)
	weather_toggle = _make_toggle()
	_add_row(ROW_WEATHER, weather_toggle)

	add_action(START_ID, START_TEXT, UiBlockButton.Look.PRIMARY)
	action_chosen.connect(_on_action_chosen)


## Loads the last used values into the controls and opens the dialog.
func present(saved: WatchBotsOptions = null) -> void:
	apply_options(saved if saved != null else WatchBotsOptions.load_saved())
	open()


func apply_options(options: WatchBotsOptions) -> void:
	mode_cycler.select(maxi(_mode_ids.find(options.mode), 0))
	bots_stepper.value = options.bots
	difficulty_cycler.select(int(options.difficulty))
	_set_toggle(gifts_toggle, options.gifts)
	_set_toggle(weather_toggle, options.weather)


## The choices as shown right now.
func current_options() -> WatchBotsOptions:
	var options: WatchBotsOptions = WatchBotsOptions.new()
	options.mode = _mode_ids[clampi(mode_cycler.selected(), 0, _mode_ids.size() - 1)]
	options.bots = bots_stepper.value
	options.difficulty = clampi(difficulty_cycler.selected(), 0, WatchBotsOptions.DIFFICULTY_LABELS.size() - 1) as WatchBotsOptions.Difficulty
	options.gifts = gifts_toggle.is_on()
	options.weather = weather_toggle.is_on()
	return options


func _on_action_chosen(id: StringName) -> void:
	if id != START_ID:
		return
	var options: WatchBotsOptions = current_options()
	options.save()
	confirmed.emit(options)


func _make_toggle() -> UiChipToggle:
	var toggle: UiChipToggle = UiChipToggle.new()
	toggle.label = ON_TEXT
	toggle.toggled.connect(_on_toggle_changed.bind(toggle))
	return toggle


func _set_toggle(toggle: UiChipToggle, on: bool) -> void:
	toggle.set_on_silent(on)
	toggle.label = ON_TEXT if on else OFF_TEXT


func _on_toggle_changed(on: bool, toggle: UiChipToggle) -> void:
	toggle.label = ON_TEXT if on else OFF_TEXT


## Adds a settings row above the action blocks (the base dialog appends Cancel first).
func _add_row(label_text: String, control: Control) -> void:
	var row: UiRow = UiRow.new().setup(label_text, control)
	panel.content.add_child(row)
	panel.content.move_child(row, cancel_button().get_index())
