class_name PauseMenu
extends CanvasLayer
## Bontago-xtq.42 (M7 P42, owner playtest: "there's no pause menu, I can't
## abandon a game and go back to the main menu or quit the game").
## Instantiated once by game/Main.gd (kept alive for the whole session, unlike
## ui/OptionsMenu.gd which MainMenu/this menu build and free on demand) so it
## is always listening for the pause_menu action, whatever screen is up.
## Self-contained the same way ui/OptionsMenu.gd's own header documents: only
## ever emits signals or reads Events -- never reaches into game/Main.gd's
## node tree.
##
## Physics/simulation is never paused (CLAUDE.md's host-authority model: only
## the host runs physics, and every other player keeps playing in an online
## match) -- opening this overlay only suppresses the *local* player's own
## input (Events.pause_menu_opened/closed; game/PlayerController.gd is the
## one listener today, the same "gate input, don't touch the scene tree"
## contract ui/TuningPanel.gd's own F4 toggle already established) and
## releases the mouse so the overlay's own buttons are reachable.
##
## DECISION (ui/PauseMenu.gd, Bontago-1pi.7, owner: "In-game pause menu
## doesn't match the rest of the menu graphically, also remove quit game as
## an option"): restyled to the same cream-card/pastel-pill/airy-spacing look
## ui/MainMenu.gd and ui/Lobby.gd already use (ui/theme/stackfall_theme.tres,
## ui/theme/MenuStyleFactory.gd, config/MenuVisualTuning) -- this file only
## consumes those, it owns none of them (they belong to other packages). The
## Quit game button, its confirmation path and the quit_callable test seam
## are gone outright: with Quit removed, the shared "which destructive action
## is pending" selector this class used to need (one ConfirmationDialog fed
## by a Leave-or-Quit choice) collapses to a single path, so the dialog now
## exists solely to confirm Leave match.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")

## M7 P7 look (Bontago-1pi.7): every pastel pill/well/card color this menu's
## restyle draws from, so none of the styling in _apply_visual_style() below
## is a magic number (CLAUDE.md "No magic numbers"). Owned by another
## package (config/MenuVisualTuning.gd) -- this file only reads it, the same
## way ui/MainMenu.gd and ui/Lobby.gd already do.
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## game/Main.gd sets this true for the duration of ui/Tutorial.gd's own scene
## (start_tutorial_from_menu()/_on_tutorial_finished()). DECISION (ui/
## PauseMenu.gd, minor ambiguity): Tutorial already has its own ui_cancel ->
## _end_tutorial() handler (ui/Tutorial.gd's own doc comment), and this menu
## and Tutorial are unrelated siblings under Main -- their _unhandled_input
## dispatch order relative to each other is not documented or relied on
## anywhere else in this codebase (unlike Options nested inside this menu,
## where Godot's deepest-node-first delivery is an established, documented
## guarantee -- see ui/OptionsMenu.gd's own _unhandled_input() doc comment).
## Rather than risk a double-toggle race on the shared Escape/Start key, this
## menu simply never opens while Tutorial owns the scene; Tutorial's own
## Escape-to-quit keeps working unmodified.
var suppressed: bool = false

## Bontago-59o.3: the menu is a CanvasLayer (was a plain Control at layer 0),
## so it and the Options menu it hosts draw above ui/HUD.gd (CanvasLayer 1)
## and swallow mouse clicks that used to fall through to HUD controls.
## DECISION: 100 leaves room for debug overlays below and stays a script
## export rather than a tuning resource (a draw-order constant, not a tunable).
const OVERLAY_LAYER: int = 100

## Emitted once Leave match is confirmed. game/Main.gd is the one listener:
## online, it calls Net.leave() (which already tears the match world down and
## returns to the main menu via its own _on_net_mode_changed()); offline
## (sandbox/hot-seat), it aborts the match and shows the main menu directly.
## PauseMenu itself never touches Net/Match -- see game/Main.gd's own
## _on_pause_leave_requested() DECISION comment for why that split lives
## there, not here.
signal leave_match_requested

var _options_menu: OptionsMenu = null

@onready var _root: Control = %Root
@onready var _center: CenterContainer = %Center
@onready var _panel: PanelContainer = %Panel
@onready var _title_label: Label = %Title
@onready var _resume_button: Button = %ResumeButton
@onready var _options_button: Button = %OptionsButton
@onready var _leave_button: Button = %LeaveButton
@onready var _confirm_dialog: ConfirmationDialog = %ConfirmDialog


func _ready() -> void:
	layer = OVERLAY_LAYER
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_confirm_dialog.confirmed.connect(_on_confirm_dialog_confirmed)
	_apply_visual_style()
	_wire_focus_chain()


## Paints this menu with the same cream-card/pastel-pill language
## ui/MainMenu.gd's own _apply_visual_style() and ui/Lobby.gd's own
## _apply_visual_style() already established -- a single flat cream card (no
## offset shadow-card stack; this overlay is a small, transient popup, not
## one of those two screens' own front-and-center layout) plus pastel pills:
## Resume in coral (the primary action, matching Host/Start's own coral),
## Options in cream (secondary, matching every other Options button in this
## project), Leave match in dark slate (the one remaining destructive
## action, so it reads with more weight than the two non-destructive
## buttons above it -- the same color Direct Join uses to stand out on
## ui/MainMenu.gd).
func _apply_visual_style() -> void:
	_panel.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	_title_label.add_theme_color_override("font_color", tuning.ink_color)
	MenuStyleFactory.apply_pill(_resume_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_options_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_leave_button, tuning.pill_dark_slate_color, tuning.pill_dark_slate_hover_color, tuning.label_ink_light_color, tuning)
	# DECISION: the cream Options pill uses dark ink for both its text and glyph.
	_options_button.add_theme_color_override("icon_normal_color", tuning.ink_color)
	_options_button.add_theme_color_override("icon_hover_color", tuning.ink_color)


## pause_menu (Esc/gamepad Start, tools/bootstrap_project.gd) toggles this
## overlay open/closed; ui_cancel closes it while open, matching every other
## menu's back gesture (ui/OptionsMenu.gd/ui/Tutorial.gd's own doc comments).
## Suppressed entirely while Tutorial owns the scene (see `suppressed` above)
## or while Options is open as a child (Options's own _unhandled_input already
## consumes ui_cancel first via Godot's deepest-node-first delivery -- this
## guard only matters for a *second* pause_menu press, e.g. gamepad Start
## again, while Options is up; simplest reasonable behavior is "do nothing,
## use Options's own Back button/ui_cancel to get back here first").
func _unhandled_input(event: InputEvent) -> void:
	if suppressed or _options_menu != null:
		return
	if event.is_action_pressed(&"pause_menu"):
		_toggle_menu()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func _toggle_menu() -> void:
	if visible:
		_close()
	else:
		_open()


func _open() -> void:
	visible = true
	Events.pause_menu_opened.emit()
	_resume_button.grab_focus()


func _close() -> void:
	visible = false
	Events.pause_menu_closed.emit()


## Bontago-xtq.42 fix round 2 (orchestrator review finding 3): game/Main.gd's
## own suppress-on-menu/lobby hooks (see `suppressed`'s own doc above) call
## this, unconditionally, every time they make this menu inert -- a match can
## end some way other than this menu's own Leave button (the host
## disconnecting, Net dropping to OFFLINE outright) while this overlay happens
## to be open, and Events.pause_menu_closed must still reach
## game/PlayerController.gd so its input re-enables (harmless there too: no
## PlayerController instance exists once the match world is gone). Idempotent
## -- a no-op when already closed -- so callers never need to check `visible`
## themselves first.
func force_close() -> void:
	if visible:
		_close()


func _on_resume_pressed() -> void:
	_close()


## Same overlay-over-background technique ui/MainMenu.gd's own
## _on_options_pressed()/_on_options_closed() already use: hide this menu's
## own %Center rather than this whole Control, so Options's semi-transparent
## background still shows the pause overlay's own Background behind it.
func _on_options_pressed() -> void:
	if _options_menu != null:
		return
	_options_menu = OPTIONS_MENU_SCENE.instantiate() as OptionsMenu
	_center.visible = false
	_root.add_child(_options_menu)
	_options_menu.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	if _options_menu != null:
		_options_menu.queue_free()
		_options_menu = null
	_center.visible = true
	_options_button.grab_focus()


func _on_leave_pressed() -> void:
	_confirm_dialog.dialog_text = "Leave this match and return to the main menu?"
	_confirm_dialog.popup_centered()


func _on_confirm_dialog_confirmed() -> void:
	_close()
	leave_match_requested.emit()


## Gamepad/keyboard navigability, the same runtime get_path_to() chaining
## ui/OptionsMenu.gd's own _wire_focus_chain() doc comment explains (there,
## because rebind rows are built dynamically; here, simply to keep one single
## computation style for "chain every focusable control top to bottom, wrap
## around" rather than authoring focus_neighbor_* by hand in the .tscn).
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [_resume_button, _options_button, _leave_button]
	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
