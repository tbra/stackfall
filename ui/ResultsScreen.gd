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
## every intent"); on a client both buttons are disabled with a "waiting for
## host" hint instead.
##
## Bontago-1pi.72.1: the quick Settings panel (owner: "get rid of the quick
## settings option") is gone; Play again / Back to lobby are the only actions.

## Test seams (Variant, not a static type): ui/HUD.gd's own match_provider and
## ui/Lobby.gd's own net_provider precedent -- defaulted to the real
## autoloads in _ready(), replaceable with a fake object in a GUT test so no
## test needs a real Match/Net/MatchNet session running.
var match_provider: Variant = null
var net_provider: Variant = null
var match_net_provider: Variant = null

@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## The last results payload shown, kept for _apply_visual_style()-independent
## re-reads (none today, but mirrors ui/Lobby.gd's own "keep the last applied
## data" habit) and so a test can inspect exactly what was rendered.
var last_results: Dictionary = {}

@onready var _headline: Label = %Headline
## Bontago-1pi.23: mode scores sit in their own small label; they used to be
## appended to the 28pt headline and spilled over the table header.
@onready var _mode_outcome: Label = %ModeOutcome
@onready var _rows_list: VBoxContainer = %RowsList
@onready var _waiting_hint: Label = %WaitingHint
@onready var _replay_button: Button = %ReplayButton
@onready var _lobby_button: Button = %LobbyButton

## DECISION (Bontago-mp0.11): keep the stats table scrollable within the
## viewport so eight player rows remain reachable.
func _refresh_layout() -> void:
	var available: Vector2 = get_viewport_rect().size - Vector2.ONE * tuning.menu_edge_margin_px * 2.0
	$Center/Card.custom_minimum_size.x = minf(available.x, tuning.menu_max_width_px)
	$Center/Card/Layout/TableScroll.custom_minimum_size.y = maxf(0.0, available.y * 0.4)


func _ready() -> void:
	add_to_group(SunFlare.FULLSCREEN_UI_GROUP)
	visible = false
	_refresh_layout()
	get_viewport().size_changed.connect(_refresh_layout)
	if match_provider == null:
		match_provider = Match
	if net_provider == null:
		net_provider = Net
	if match_net_provider == null:
		match_net_provider = MatchNet

	Events.match_results_ready.connect(_on_match_results_ready)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.match_scope_reset.connect(clear_results)
	Events.pause_menu_closed.connect(_on_pause_menu_closed)

	_replay_button.pressed.connect(_on_replay_pressed)
	_lobby_button.pressed.connect(_on_lobby_pressed)
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


## Bontago-1pi.46 (G9; Events.match_scope_reset runs this). ROOT CAUSE: the screen is a
## persistent Main child that only ever replaced its stats rows when the NEXT results
## arrived, so after Replay / Back to lobby / Leave the previous match's table (header
## row, one row per player) stayed in the hidden tree and `last_results` kept its
## payload -- a new match did not look like a fresh launch. Drops the rows and the
## payload; the overlay itself is hidden by _on_match_state_changed() already.
func clear_results() -> void:
	last_results = {}
	for child: Node in _rows_list.get_children():
		_rows_list.remove_child(child)
		child.queue_free()


## Bontago-1pi.72.1 (owner playtest: pause menu open when the round ended, then
## the results could not be used after unpausing). ROOT CAUSE: PlayerController
## re-captures the mouse on Events.pause_menu_closed, and the focused Resume
## button vanished with the menu, so nothing on this screen had focus or a
## usable cursor. DECISION: PauseMenu now closes itself when results arrive, and
## this screen re-asserts cursor + focus whenever a pause menu closes while it is
## up. Deferred so it runs after every other pause_menu_closed listener
## (PlayerController's capture) whatever their connection order.
func _on_pause_menu_closed() -> void:
	if visible:
		_claim_input.call_deferred()


func _claim_input() -> void:
	if not visible:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not _replay_button.disabled:
		_replay_button.grab_focus()
	elif not _lobby_button.disabled:
		_lobby_button.grab_focus()


## Public entry point (also the one GUT tests drive directly, the same
## "call the handler, don't fake the signal" style tests/unit/test_pause_menu.gd
## uses for _unhandled_input()) -- populates the headline and stats table,
## applies the host/client button gate, shows the screen and releases the
## mouse.
func show_results(results: Dictionary) -> void:
	last_results = results
	_headline.text = _headline_text(results)
	var outcome: String = mode_outcome_text(results, _resolved_team_numbers()).strip_edges()
	_mode_outcome.text = outcome
	_mode_outcome.visible = not outcome.is_empty()
	_populate_rows(results)
	_update_host_gate()
	visible = true
	move_to_front()
	_claim_input()


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
	var headline: String = "It's a draw!" if winner_id < 0 or winner_name.is_empty() else "%s wins!" % winner_name
	var shared: String = shared_winners_text(results, _resolved_team_numbers())
	if not shared.is_empty():
		headline = shared
	return headline


## Every winning id: mode.winners when a mode payload lists it (a CTF tie is a
## shared win), else just winner_id. Empty when nobody won. Bontago-1pi.25.1:
## a Domination match that ended early (home elimination) has an empty
## winners list, so it falls back to the finish winner_id the same way.
static func winner_ids(results: Dictionary) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var mode: Variant = results.get("mode")
	if mode is Dictionary:
		for id_text: String in String((mode as Dictionary).get("winners", "")).split(",", false):
			out.append(int(id_text))
	if out.is_empty() and int(results.get("winner_id", -1)) >= 0:
		out.append(int(results.get("winner_id", -1)))
	return out


## Bontago-22y.7: a tied timed mode lists every top team in mode.winners
## ("0,2"); returns "Teams 1 & 3 share the win!" for two or more, else "".
static func shared_winners_text(results: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var mode: Variant = results.get("mode")
	if not (mode is Dictionary):
		return ""
	var ids: PackedStringArray = String((mode as Dictionary).get("winners", "")).split(",", false)
	if ids.size() < 2:
		return ""
	var ffa: bool = String(results.get("winner_kind", MatchStats.WINNER_KIND_SLOT)) == MatchStats.WINNER_KIND_SLOT
	var names: PackedStringArray = PackedStringArray()
	for id_text: String in ids:
		names.append(player_label(results, int(id_text)) if ffa else str(team_number_in(team_numbers, int(id_text))))
	return "%s %s share the win!" % ["Players" if ffa else "Teams", " & ".join(names)]


## Bontago-22y.11: a non-classic results payload carries a "mode" block (mode
## id + per-team scores); this renders it as extra headline lines. Classic has
## no block, so this returns "" and its headline is unchanged.
## DECISION: the outcome shares the headline Label (no new scene node) so the
## classic layout cannot move.
static func mode_outcome_text(results: Dictionary, team_numbers: PackedInt32Array = PackedInt32Array()) -> String:
	var mode: Variant = results.get("mode")
	if not (mode is Dictionary):
		return ""
	var block: Dictionary = mode
	var mode_id: int = int(block.get("mode_id", MatchConfig.GameMode.CLASSIC))
	if mode_id < 0 or mode_id >= MatchConfig.GAME_MODE_LABELS.size():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	var scores: Array = block.get("scores", []) as Array
	var ffa: bool = String(results.get("winner_kind", MatchStats.WINNER_KIND_SLOT)) == MatchStats.WINNER_KIND_SLOT
	var unit: String = " m" if mode_id == MatchConfig.GameMode.REACH_THE_SKY else ""
	var elimination: bool = mode_id == MatchConfig.GameMode.ELIMINATION
	# Domination scores are territory shares (0..1), shown as percentages.
	var domination: bool = mode_id == MatchConfig.GameMode.DOMINATION
	for team: int in range(scores.size()):
		var value_text: String = "%s%s" % [String.num(float(scores[team]), 1), unit]
		if elimination:
			value_text = survivor_text(int(scores[team]))
		elif domination:
			value_text = "%d%%" % int(round(float(scores[team]) * 100.0))
		parts.append("%s: %s" % [player_label(results, team) if ffa else "Team %d" % team_number_in(team_numbers, team), value_text])
	var text: String = "
%s" % MatchConfig.GAME_MODE_LABELS[mode_id]
	if not parts.is_empty():
		text += " - " + ", ".join(parts)
	if elimination:
		var order: PackedStringArray = String(block.get("order", "")).split(",", false)
		if not order.is_empty():
			var names: PackedStringArray = PackedStringArray()
			for slot_text: String in order:
				names.append(player_label(results, int(slot_text)))
			text += "
Out, first to last: " + ", ".join(names)
	return text


## Bontago-1pi.72.1: a slot's name exactly as its table row shows it (display name,
## " (Bot)" suffix), so the subtitle and the table agree. Falls back to
## "Player N" for a slot with no row (an old/short payload).
static func player_label(results: Dictionary, slot_id: int) -> String:
	for raw_row: Variant in results.get("rows", []) as Array:
		var row: Dictionary = raw_row as Dictionary
		if int(row.get("slot_id", -1)) == slot_id:
			return row_name_text(row)
	return "Player %d" % (slot_id + 1)


static func row_name_text(row: Dictionary) -> String:
	var name_text: String = String(row.get("name", ""))
	if bool(row.get("is_bot", false)):
		name_text += " (Bot)"
	return name_text


## Lobby rework (Bontago-1pi.53): the label number of dense team `team_id` --
## `team_numbers` (MatchConfig.team_numbers of a host-resolved lobby) maps it to
## the number the team had in the lobby; empty or short (legacy configs, FFA, an
## unresolved TEAMS_N) falls back to team id + 1, the old numbering.
static func team_number_in(team_numbers: PackedInt32Array, team_id: int) -> int:
	if team_id >= 0 and team_id < team_numbers.size():
		return team_numbers[team_id]
	return team_id + 1


## MatchConfig.team_numbers of the running match when its lobby teams are
## host-resolved, else empty. On a client Match.config is the replicated config,
## so host and clients label the same teams the same way.
func _resolved_team_numbers() -> PackedInt32Array:
	var config: MatchConfig = _current_config()
	if config == null or not config.teams_resolved():
		return PackedInt32Array()
	return config.team_numbers


## Elimination: a team's living players as HUD/Results text.
static func survivor_text(alive: int) -> String:
	if alive <= 0:
		return "out"
	return "alive" if alive == 1 else "%d alive" % alive


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
	var winners: PackedInt32Array = winner_ids(results)
	var raw_rows: Array = results.get("rows", [])
	var rows: Array[Dictionary] = []
	for raw_row: Variant in raw_rows:
		var row: Dictionary = (raw_row as Dictionary).duplicate()
		var is_winner: bool = (
			(winner_kind == MatchStats.WINNER_KIND_TEAM and winners.has(int(row.get("team_id", -1))))
			or (winner_kind == MatchStats.WINNER_KIND_SLOT and winners.has(int(row.get("slot_id", -1))))
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
	ScoreTable.populate(_rows_list, results, tuning, _resolved_team_numbers())


## Bontago-1pi.72.2: the one mode column. # DECISION: Capture the Flag shows the
## team's beacon points (mode.scores), Reach the Sky the team's record in metres
## (mode.scores; Height is the player's own best), every other mode (Classic,
## Elimination, Domination) the team's peak territory share during the round.
static func mode_stat_header(results: Dictionary) -> String:
	match _results_mode_id(results):
		MatchConfig.GameMode.CAPTURE_THE_FLAG:
			return "Points"
		MatchConfig.GameMode.REACH_THE_SKY:
			return "Team best"
	return "Peak %"


static func mode_stat_text(results: Dictionary, row: Dictionary) -> String:
	var team_id: int = int(row.get("team_id", 0))
	var mode_id: int = _results_mode_id(results)
	if mode_id == MatchConfig.GameMode.CAPTURE_THE_FLAG or mode_id == MatchConfig.GameMode.REACH_THE_SKY:
		var scores: Array = (results.get("mode", {}) as Dictionary).get("scores", []) as Array
		var value: float = float(scores[team_id]) if team_id >= 0 and team_id < scores.size() else 0.0
		return "%s m" % String.num(value, 1) if mode_id == MatchConfig.GameMode.REACH_THE_SKY else str(int(round(value)))
	return "%d%%" % int(round(float(row.get("peak_territory", 0.0)) * 100.0))


static func _results_mode_id(results: Dictionary) -> int:
	var mode: Variant = results.get("mode")
	if mode is Dictionary:
		return int((mode as Dictionary).get("mode_id", MatchConfig.GameMode.CLASSIC))
	return MatchConfig.GameMode.CLASSIC


# --- Host/client gate ---------------------------------------------------------

func _update_host_gate() -> void:
	var is_host: bool = net_provider != null and bool(net_provider.is_host())
	_replay_button.disabled = not is_host
	_lobby_button.disabled = not is_host
	_waiting_hint.visible = not is_host


func _on_replay_pressed() -> void:
	if match_net_provider != null:
		match_net_provider.request_replay()


func _on_lobby_pressed() -> void:
	if match_net_provider != null:
		match_net_provider.request_return_to_lobby()


func _current_config() -> MatchConfig:
	if match_provider == null:
		return null
	return match_provider.config as MatchConfig


# --- Visual style + focus chain -------------------------------------------------

## Same StyleBoxFlat-from-MenuVisualTuning technique ui/Lobby.gd's own
## _apply_visual_style() doc comment describes: no image assets, everything
## drawn from ui/theme/MenuStyleFactory.gd on top of the shared
## ui/theme/stackfall_theme.tres Theme this scene's root sets.
func _apply_visual_style() -> void:
	var card: PanelContainer = %Card
	card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))

	MenuStyleFactory.apply_pill(
		_replay_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_lobby_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning
	)
	_waiting_hint.add_theme_color_override("font_color", tuning.label_muted_color)


## Gamepad/keyboard navigability -- same runtime get_path_to() chaining
## ui/PauseMenu.gd's own _wire_focus_chain() doc comment explains.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [_replay_button, _lobby_button]
	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
