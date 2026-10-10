class_name LobbySection
extends UiSection
## One block of the lobby's settings column (Bontago-1pi.53, package S1a,
## docs/LOBBY_REWORK_PLAN.md section 2). Bontago-1pi.159.7: now a thin compatibility layer over
## [UiSection] (ui/components/UiSection.gd), which owns the header, summary, icon, Advanced
## disclosure, focus hand-over and signals. What stays here is the Lobby-facing surface the screens
## and tests still call: the `layout_tuning` export + [method apply_style], `summary()`, the
## panel-heading and ON/OFF state-word statics. Deleted by the Lobby / Options migrations
## (1pi.159.2 / 1pi.159.3), which use UiSection, UiPanel and UiToggle directly.

## Sizes and spacings; the Lobby overwrites it with its own export before styling.
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/lobby_layout_tuning.tres")


## Takes the Lobby's own layout resource (the Lobby calls this from _apply_visual_style(); no new
## colours are introduced) and restyles the header and the bar.
func apply_style(tuning: MenuVisualTuning, layout: LobbyLayoutTuning) -> void:
	layout_tuning = layout
	_apply_layout()
	for label: Label in [_title_label, _summary_label]:
		label.add_theme_color_override("font_color", tuning.label_muted_color)
	_icon_rect.modulate = tuning.label_muted_color
	_style_disclosure()


func _apply_layout() -> void:
	advanced_indent_px = layout_tuning.advanced_indent_px
	bar_padding_px = layout_tuning.advanced_toggle_padding_px
	super._apply_layout()


func summary() -> String:
	return get_summary()


## Panel heading (Bontago-hfa.5): the label's text in capitals with the flare notch on its left,
## shared by the lobby's two panels ("MATCH SETTINGS", "PLAYERS").
static func style_heading(label: Label) -> void:
	UiTitleRow.style_heading_label(label)


## Bontago-1pi.149 (components.md "Toggle": the ON/OFF word is required): a toggle chip gets a
## word beside it, mint ON / dust OFF, in the same row (a sibling after the chip, so the chip
## keeps its text, focus, signals and tests). The word follows `toggled`, the chip's
## visibility, and [method refresh_state_word] for a programmatic set_pressed_no_signal().
const STATE_WORD_META: StringName = &"state_word"
const STATE_WORD_NAME: String = "StateWord"
const STATE_WORD_ON: String = "ON"
const STATE_WORD_OFF: String = "OFF"
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/options_visual_tuning.tres")


## [param value_column_width_px] > 0: the word is at least that wide (a settings row's value
## column; the Lobby also puts it in its value-cell group), so the chip keeps the row's shared
## control right edge.
static func attach_state_word(check: BaseButton, value_column_width_px: int = 0) -> Label:
	if check.has_meta(STATE_WORD_META):
		return check.get_meta(STATE_WORD_META) as Label
	var word: Label = Label.new()
	word.name = "%s%s" % [check.name, STATE_WORD_NAME]
	word.theme_type_variation = &"DisplayLabel"
	word.add_theme_font_size_override("font_size", OPTIONS_TUNING.value_font_size_px)
	word.custom_minimum_size.x = float(maxi(OPTIONS_TUNING.state_word_min_width_px, value_column_width_px))
	word.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent: Node = check.get_parent()
	parent.add_child(word)
	parent.move_child(word, check.get_index() + 1)
	check.set_meta(STATE_WORD_META, word)
	check.toggled.connect(func(_pressed: bool) -> void: refresh_state_word(check))
	check.visibility_changed.connect(func() -> void: refresh_state_word(check))
	refresh_state_word(check)
	return word


## Redraws the word beside `check` (no-op when none was attached).
static func refresh_state_word(check: BaseButton) -> void:
	if not check.has_meta(STATE_WORD_META):
		return
	var word: Label = check.get_meta(STATE_WORD_META) as Label
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	word.text = STATE_WORD_ON if check.button_pressed else STATE_WORD_OFF
	word.add_theme_color_override("font_color", arcade.mint_color if check.button_pressed else arcade.dust_color)
	word.visible = check.visible
