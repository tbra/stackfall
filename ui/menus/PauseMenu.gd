class_name PauseMenu
extends CanvasLayer
## In-game pause overlay: abandon a game and go back to the main menu (or lobby).
## Instantiated once by game/main/Main.gd and kept alive for the whole session (unlike
## ui/menus/OptionsMenu.gd, which is built and freed on demand), so it is always listening for the
## pause_menu action. Self-contained: it only emits signals or reads Events, and never reaches into
## game/main/Main.gd's node tree.
##
## Physics/simulation is never paused (host authority: only the host runs physics, and every
## other player keeps playing in an online match). Opening this overlay only suppresses the *local*
## player's own input (Events.pause_menu_opened/closed; game/player/PlayerController.gd listens)
## and releases the mouse so the overlay's own buttons are reachable.
##
## DECISION: restyled to the shared cream-card/pastel-pill look of MainMenu and Lobby (stackfall_theme.tres, MenuStyleFactory, MenuVisualTuning), which this file only consumes. There is no Quit game entry: one ConfirmationDialog serves the two destructive entries, Leave match and Return to lobby (host only, between Options and Leave); `_pending_action` says which one a confirm answers.
##
## Which entries a session gets is decided by game/main/Main.gd through `context_provider`, so this
## menu never names Net or Match.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/ui/options_visual_tuning.tres")

## Every pastel pill/well/card color this menu's restyle draws from, so none of the styling in
## _apply_visual_style() is a magic number. Read only, like MainMenu and Lobby.
@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")

## game/main/Main.gd sets this true for the duration of ui/menus/Tutorial.gd's scene. DECISION
## (minor ambiguity): Tutorial has its own ui_cancel -> _end_tutorial() handler, and the two are
## unrelated siblings under Main whose _unhandled_input order is not relied on, so this menu never
## opens while Tutorial owns the scene instead of risking a double-toggle on the shared Escape/Start
## key. (Options nested inside this menu is different: Godot's deepest-node-first delivery is
## documented.)
var suppressed: bool = false

## The menu is a CanvasLayer, so it and the Options menu it hosts draw above ui/hud/HUD.gd
## (CanvasLayer 1) and swallow mouse clicks that would fall through to HUD controls.
## DECISION: 100 leaves room for debug overlays below and stays a script
## export rather than a tuning resource (a draw-order constant, not a tunable).
const OVERLAY_LAYER: int = 100

## Emitted once Leave match is confirmed. game/main/Main.gd is the one listener: online, it calls
## Net.leave() (which tears the match world down and returns to the main menu); offline
## (sandbox/hot-seat), it aborts the match and shows the main menu directly. PauseMenu itself
## never touches Net/Match.
signal leave_match_requested

## Emitted once Return to lobby is confirmed (or at once when no match is in progress, so nothing
## is lost). game/main/Main.gd is the one listener; it re-checks that this peer is the host before
## ending the match for everyone.
signal return_to_lobby_requested

## What the Return to lobby entry shows, decided by whoever owns the session (game/main/Main.gd),
## never by this menu: HIDDEN where no lobby exists to return to (offline sandbox/hot-seat; Leave
## match already goes to the main menu there), ENABLED for the host (a hosted session always has a
## lobby, local vs-bots included), DISABLED for a client.
enum ReturnEntry { HIDDEN, ENABLED, DISABLED }

## Which destructive action the shared confirmation dialog is currently asking
## about; NONE while it is closed.
enum PendingAction { NONE, LEAVE, RETURN_TO_LOBBY }

## DECISION: a client sees the entry disabled rather than a
## "leave to the host's lobby" variant (keep it simple; a client's own way out
## stays Leave match). The inline hint under the entry explains why (no tooltips).
const RETURN_CLIENT_HINT: String = "Only the host can return everyone to the lobby"
const RETURN_CONFIRM_TEXT: String = "End this match for everyone and return to the lobby?"
const RETURN_CONFIRM_OK_TEXT: String = "End match"
const RETURN_CONFIRM_TITLE: String = "Return to lobby?"
const LEAVE_CONFIRM_TITLE: String = "Leave match?"
const CONFIRM_ACTION_ID: StringName = &"confirm"
const LEAVE_CONFIRM_TEXT: String = "Leave this match and return to the main menu?"
const LEAVE_CONFIRM_OK_TEXT: String = "Leave match"

## () -> Dictionary, read each time the menu opens (and by the confirm step).
## {"return_entry": ReturnEntry, "match_in_progress": bool}. game/main/Main.gd assigns it; with
## none set the entry stays hidden and a press never asks for confirmation. A seam rather than
## reading Net/Match here, so this menu stays decoupled from both.
var context_provider: Callable = Callable()

var _froze_tree: bool = false
var _options_menu: OptionsMenu = null
## the built-once Options window, hidden between opens (see OptionsMenu.present()).
var _options_cache: OptionsMenu = null
var _pending_action: PendingAction = PendingAction.NONE
var _confirm_origin: UiBlockButton = null
## Restores the focus modes UiFocusTrap.suspend_outside() cleared while Options is open.
var _restore_focus: Callable = Callable()

@onready var _root: Control = %Root
@onready var _center: CenterContainer = %Center
@onready var _panel: UiPanel = %Panel
@onready var _title_label: UiText = %Title
@onready var _resume_button: UiBlockButton = %ResumeButton
@onready var _options_button: UiBlockButton = %OptionsButton
@onready var _return_button: UiBlockButton = %ReturnLobbyButton
@onready var _leave_button: UiBlockButton = %LeaveButton
@onready var _confirm_dialog: UiDialog = %ConfirmDialog
## Inline reason shown under the Return to lobby entry while a client sees it disabled (hidden otherwise).
var return_hint: UiText = null


func _ready() -> void:
	# this menu (and Options/confirm dialog beneath it) must keep running while
	# it has paused the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.net_peer_joined.connect(_on_peer_joined_while_open)
	# The scene authors the dialog column under the UiPanel; its own content column is where it lives.
	var column: Node = %Layout
	column.reparent(_panel.content, false)
	add_to_group(SunFlare.FULLSCREEN_UI_GROUP)
	layer = OVERLAY_LAYER
	visible = false
	_resume_button.pressed.connect(_on_resume_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_return_button.pressed.connect(_on_return_lobby_pressed)
	_leave_button.pressed.connect(_on_leave_pressed)
	_build_return_hint()
	_confirm_dialog.action_chosen.connect(_on_confirm_action_chosen)
	_confirm_dialog.canceled.connect(_on_confirm_dialog_canceled)
	Events.match_results_ready.connect(_on_match_results_ready)
	_apply_visual_style()
	_wire_focus_chain()


## The Stackfall Arcade Dialog: a centred 340 px disc-800 plate on a
## disc-900 scrim, a centred uppercase heading, stacked full-width blocks. Resume is the one primary
## (flare face, ink label); Options and Return to lobby are secondary disc-600 blocks; Leave match is
## a secondary block with a flare label (destructive, always followed by a confirm). Look only.
func _apply_visual_style() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var scrim: Color = arcade.disc_900_color
	scrim.a = arcade.scrim_alpha
	($Root/Background as ColorRect).color = scrim
	_panel.custom_minimum_size.x = float(OPTIONS_TUNING.dialog_width_px)
	# the plate is a UiPanel (no heading, the centred UiText title is the heading), the blocks
	# are UiBlockButtons (Resume primary, the rest secondary). Leave match is the DANGER look
	# (a secondary block with an alert label).
	_leave_button.variant = UiBlockButton.Look.DANGER
	# DECISION: every block's icon follows its label ink in all draw states
	# (apply_ink covers both), so no per-node icon overrides here.


## pause_menu (Esc/gamepad Start, tools/bootstrap_project.gd) toggles this overlay open/closed;
## ui_cancel closes it while open, matching every other menu's back gesture. Suppressed entirely
## while Tutorial owns the scene (see `suppressed`) or while Options is open as a child: Options's
## own _unhandled_input already consumes ui_cancel first (deepest-node-first delivery), so this
## guard only matters for a second pause_menu press, which does nothing.
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
	refresh_return_entry()
	_apply_freeze()
	Events.pause_menu_opened.emit()
	_resume_button.grab_focus()


func _exit_tree() -> void:
	_release_freeze()


## freezes the whole tree while open iff the session context says no remote
## human is connected (context key "freeze_tree"; absent = never, so a bare menu is inert).
func _apply_freeze() -> void:
	# Only claim a freeze nobody else holds (Sandbox F11 may already have paused the tree), so
	# closing never releases somebody else's pause.
	if bool(_context().get("freeze_tree", false)) and not get_tree().paused:
		get_tree().paused = true
		_froze_tree = true


func _release_freeze() -> void:
	if _froze_tree:
		_froze_tree = false
		get_tree().paused = false


## DECISION: a human joining while the menu is open unfreezes the world at once
## (the menu stays open, input still gated); the simplest safe rule, no join blocking needed.
func _on_peer_joined_while_open(_peer_id: int, _slot_id: int, _player_name: String) -> void:
	if _froze_tree and not bool(_context().get("freeze_tree", false)):
		_release_freeze()


func _close() -> void:
	# a confirmation left up behind a closed menu (the match ended
	# some other way while it was asked) must not outlive it.
	_pending_action = PendingAction.NONE
	_confirm_dialog.hide()
	_center.visible = true
	visible = false
	_release_freeze()
	Events.pause_menu_closed.emit()


## game/main/Main.gd's suppress-on-menu/lobby hooks (see `suppressed`) call this, unconditionally,
## every time they make this menu inert: a match can end some way other than this menu's own Leave
## button (the host disconnecting, Net dropping to OFFLINE) while this overlay is open, and
## Events.pause_menu_closed must still reach game/player/PlayerController.gd so its input
## re-enables. Idempotent: a no-op when already closed, so callers never check `visible` first.
func force_close() -> void:
	if visible:
		_close()


## A pause menu left open when the round ends would leave the
## results unusable. DECISION: the menu closes itself when results arrive, so it
## never covers the results screen and Events.pause_menu_closed fires once;
## ui/menus/ResultsScreen.gd then claims cursor and focus.
func _on_match_results_ready(_results: Dictionary) -> void:
	force_close()


func _on_resume_pressed() -> void:
	_close()


## Same overlay-over-background technique as MainMenu's _on_options_pressed()/_on_options_closed():
## hide this menu's own %Center rather than this whole Control, so Options's semi-transparent
## background still shows the pause overlay's own Background behind it.
func _on_options_pressed() -> void:
	if _options_menu != null:
		return
	var first_open: bool = _options_cache == null
	if first_open:
		_options_cache = OPTIONS_MENU_SCENE.instantiate() as OptionsMenu
	_options_menu = _options_cache
	_center.visible = false
	if first_open:
		_root.add_child(_options_menu)
	else:
		_options_menu.present()
	_restore_focus = UiFocusTrap.suspend_outside(_options_menu, get_tree().root)
	if not _options_menu.closed.is_connected(_on_options_closed):
		_options_menu.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	if _options_menu != null:
		_options_menu.dismiss()
		_options_menu = null
	if _restore_focus.is_valid():
		_restore_focus.call()
		_restore_focus = Callable()
	_center.visible = true
	_options_button.grab_focus()


func _on_leave_pressed() -> void:
	_ask_confirmation(PendingAction.LEAVE, LEAVE_CONFIRM_TITLE, LEAVE_CONFIRM_TEXT, LEAVE_CONFIRM_OK_TEXT, _leave_button)


## A match in progress asks first (it ends for everyone); with
## none running (the results screen is up) there is nothing to lose, so it goes
## straight through. A disabled entry (client) is inert even if something calls
## this directly.
func _on_return_lobby_pressed() -> void:
	if _return_button.disabled or not _return_button.visible:
		return
	if bool(_context().get("match_in_progress", false)):
		_ask_confirmation(PendingAction.RETURN_TO_LOBBY, RETURN_CONFIRM_TITLE, RETURN_CONFIRM_TEXT, RETURN_CONFIRM_OK_TEXT, _return_button)
		return
	_close()
	return_to_lobby_requested.emit()


func _ask_confirmation(action: PendingAction, title: String, text: String, ok_text: String, origin: UiBlockButton) -> void:
	if _confirm_dialog.visible:
		return
	_pending_action = action
	_confirm_origin = origin
	_confirm_dialog.title = title
	_confirm_dialog.dialog_text = text
	_confirm_dialog.clear_actions()
	_confirm_dialog.add_action(CONFIRM_ACTION_ID, ok_text, UiBlockButton.Look.DANGER)
	_center.visible = false  # the plate behind a modal would ghost through the scrim
	_confirm_dialog.open()


func _on_confirm_action_chosen(_id: StringName) -> void:
	_on_confirm_dialog_confirmed()


func _on_confirm_dialog_confirmed() -> void:
	var action: PendingAction = _pending_action
	_close()
	match action:
		PendingAction.LEAVE:
			leave_match_requested.emit()
		PendingAction.RETURN_TO_LOBBY:
			return_to_lobby_requested.emit()


## Cancel/close of the dialog: focus goes back to the button that asked, so a
## gamepad or keyboard player is not left with nothing focused.
func _on_confirm_dialog_canceled() -> void:
	_pending_action = PendingAction.NONE
	_confirm_dialog.hide()
	_center.visible = true
	if _confirm_origin != null and is_instance_valid(_confirm_origin) and visible:
		_confirm_origin.grab_focus()


func _context() -> Dictionary:
	if context_provider.is_valid():
		return context_provider.call() as Dictionary
	return {}


## The inline reason under the Return to lobby entry (a body-text label; no tooltip).
func _build_return_hint() -> void:
	return_hint = UiText.make(UiText.Role.BODY)
	return_hint.name = "ReturnHint"
	return_hint.visible = false
	var column: Node = _return_button.get_parent()
	column.add_child(return_hint)
	column.move_child(return_hint, _return_button.get_index() + 1)


## applies the session context to the Return to lobby entry and
## rebuilds the focus ring around the entries a player can actually reach (a
## hidden or disabled entry is skipped, so neither stick nor Tab lands on it).
## Called on every open, so the entry always reflects the session as it is now.
func refresh_return_entry() -> void:
	var entry: int = int(_context().get("return_entry", ReturnEntry.HIDDEN))
	_return_button.visible = entry != ReturnEntry.HIDDEN
	_return_button.disabled = entry != ReturnEntry.ENABLED
	return_hint.visible = entry == ReturnEntry.DISABLED
	return_hint.text = RETURN_CLIENT_HINT if entry == ReturnEntry.DISABLED else ""
	_wire_focus_chain()


## Gamepad/keyboard navigability: the same runtime get_path_to() chaining as
## ui/menus/OptionsMenu.gd's _wire_focus_chain(), kept as one computation style rather than
## authoring focus_neighbor_* by hand in the .tscn.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [_resume_button, _options_button]
	if _return_button.visible and not _return_button.disabled:
		chain.append(_return_button)
	chain.append(_leave_button)
	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
	if not chain.has(_return_button):
		_return_button.focus_mode = Control.FOCUS_NONE
	# left / right (no neighbour set) must not leave the pause panel.
	UiFocusTrap.trap(_resume_button.get_parent() as Control)
