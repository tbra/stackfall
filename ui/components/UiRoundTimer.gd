class_name UiRoundTimer
extends PanelContainer
## The design system's RoundTimer (owner 2026-10-12, "Need a round timer component"): the match
## clock on a hud-plate in Bungee numerals as m:ss. It counts the time left down in a limited match
## and, in a mode with no limit, the time played up. The last HUDVisualTuning.round_timer_hurry_seconds
## turn the plate edge and numerals rim gold; sudden death (overtime) swaps the clock for its flare
## label. Display only: the host's clock is fed in by the HUD, so a client shows the host's time.
## Sizes and colours come from HUDVisualTuning and ArcadeVisualTuning.

enum Phase { HIDDEN, RUNNING, HURRY, OVERTIME }

const TUNING_PATH: String = "res://config/ui/hud_visual_tuning.tres"
const THEME_PATH: String = "res://ui/theme/stackfall_theme.tres"
const SECONDS_PER_MINUTE: int = 60
## The widest clock the plate reserves room for (overtime text may still grow it).
const WIDEST_CLOCK: String = "88:88"

## The phase currently shown.
var phase: Phase = Phase.HIDDEN
## The label holding the clock text.
var label: Label = null
## Seconds left at or under which the clock is in the hurry phase (HUDVisualTuning default).
var hurry_seconds: float = 0.0:
	set(value):
		hurry_seconds = value
		_refresh()

var _seconds: float = 0.0
var _counting_up: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	hurry_seconds = tuning().round_timer_hurry_seconds
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", (load(THEME_PATH) as Theme).get_font(&"font", &"DisplayLabel"))
	add_child(label)
	_refresh()


static func tuning() -> HUDVisualTuning:
	return load(TUNING_PATH) as HUDVisualTuning


## "m:ss" for a whole number of seconds (minutes are not capped: 100 minutes reads "100:00"). Pure.
static func format_clock(total_seconds: int) -> String:
	var whole: int = maxi(total_seconds, 0)
	return "%d:%02d" % [whole / SECONDS_PER_MINUTE, whole % SECONDS_PER_MINUTE]


## The phase a countdown of [param seconds_left] is in: hurry once it is at or under
## [param hurry_threshold] (rounded up like the clock text, so "0:30" is already hurry). Pure.
static func phase_for_remaining(seconds_left: float, hurry_threshold: float) -> Phase:
	if ceil(seconds_left) <= hurry_threshold:
		return Phase.HURRY
	return Phase.RUNNING


## Shows the time left in a limited match, rounded up so the clock never reads 0:00 before the end.
func show_remaining(seconds_left: float) -> void:
	_seconds = maxf(seconds_left, 0.0)
	_counting_up = false
	phase = phase_for_remaining(_seconds, hurry_seconds)
	_refresh()


## Shows the time played in a match with no limit (counts up, never hurry).
func show_elapsed(seconds_played: float) -> void:
	_seconds = maxf(seconds_played, 0.0)
	_counting_up = true
	phase = Phase.RUNNING
	_refresh()


## Shows the sudden-death (overtime) label in place of the clock.
func show_overtime() -> void:
	phase = Phase.OVERTIME
	_refresh()


## One call for the HUD: sudden death shows the overtime label; a limited match
## ([param limit_minutes] > 0) counts [param seconds_left] down; an unlimited one counts
## [param seconds_played] up.
func show_match(limit_minutes: int, seconds_left: float, sudden_death: bool, seconds_played: float) -> void:
	if sudden_death:
		show_overtime()
	elif limit_minutes > 0:
		show_remaining(seconds_left)
	else:
		show_elapsed(seconds_played)


## The match clock length in minutes for [param config] (0 = no limit): classic keeps its match
## timer, every timed mode its round timer. Pure.
static func limit_minutes_for(config: MatchConfig) -> int:
	if config == null:
		return 0
	if MatchConfig.timer_is_match_timer(config.game_mode):
		return config.match_timer_minutes
	return config.round_timer_minutes


## Hides the plate (no clock to show: pre-match, or a spectator-less tool view).
func clear() -> void:
	phase = Phase.HIDDEN
	_refresh()


## The text the plate shows right now.
func clock_text() -> String:
	if phase == Phase.OVERTIME:
		return tuning().round_timer_overtime_text
	return format_clock(int(floor(_seconds)) if _counting_up else int(ceil(_seconds)))


## The accent of [param phase_value]: the numeral colour and the plate edge.
static func accent_for(phase_value: Phase, arcade: ArcadeVisualTuning = null) -> Color:
	var a: ArcadeVisualTuning = arcade if arcade != null else MenuStyleFactory.arcade_tuning()
	match phase_value:
		Phase.HURRY:
			return a.rim_color
		Phase.OVERTIME:
			return a.flare_color
	return a.cream_color


func _refresh() -> void:
	if label == null:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var hud: HUDVisualTuning = tuning()
	visible = phase != Phase.HIDDEN
	var accent: Color = accent_for(phase, arcade)
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = hud.surface_color
	box.border_color = accent if phase != Phase.RUNNING else hud.surface_border_color
	box.set_border_width_all(int(hud.panel_border_width_px))
	box.set_corner_radius_all(arcade.radius_block_px)
	box.content_margin_left = float(arcade.space_3_px)
	box.content_margin_right = float(arcade.space_3_px)
	box.content_margin_top = float(arcade.space_1_px)
	box.content_margin_bottom = float(arcade.space_1_px)
	add_theme_stylebox_override("panel", box)
	label.text = clock_text()
	label.add_theme_font_size_override("font_size", hud.round_timer_font_px)
	label.add_theme_color_override("font_color", accent)
	# Bungee numerals are proportional: reserve the widest clock so the plate does not jitter.
	var font: Font = label.get_theme_font("font")
	label.custom_minimum_size.x = font.get_string_size(
		WIDEST_CLOCK, HORIZONTAL_ALIGNMENT_LEFT, -1, hud.round_timer_font_px).x
