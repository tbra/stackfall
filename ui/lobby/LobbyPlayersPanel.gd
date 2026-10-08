class_name LobbyPlayersPanel
extends VBoxContainer
## The lobby's right-hand roster (Bontago-1pi.53, packages E1 + PL1a, docs/
## LOBBY_REWORK_PLAN.md "Right panel"): the "Players" title row with its
## "N players · M bots · K/S seats" header, and one LobbySeatRow per seat (the humans
## from the roster in slot order, then one row per bot). Extracted 1:1 from ui/Lobby.gd
## in E1 so the seat-row package could grow it without touching the Lobby again.
##
## **PL1a: the seat table.** The panel owns the lobby's seat table (core/rules/
## LobbySeats: colour, team pick, bot difficulty per seat). It reconciles the table
## with the live roster and config on every apply / roster change / host publish,
## draws every row from it, and applies the HOST's edits (colour click, team click,
## bot difficulty, remove bot) through LobbySeats, then redraws and emits
## [signal seats_changed] (or [signal remove_bot_requested]).
##
## **PL1b: header controls, self-edit, Start.** The header carries the host's "Teams"
## toggle and "+ Add bot" button ([signal teams_toggled], [signal add_bot_requested];
## a client sees the toggle read-only and no Add button). A CLIENT edits only its OWN
## row's colour and team: the click is sent as
## `net_provider.request_seat_pref(colour, team)` and the row follows the next lobby-data
## echo (no optimistic update). The HOST applies a client's request from
## Events.net_seat_pref_requested through LobbySeats.apply_human_pref (exact team cap,
## colour swap) and republishes -- only while the lobby is still open (a host, no Start
## committed, no match in progress; Net refuses mid-match requests too). Start:
## [method finalize_start_config] reconciles the table with Net's CURRENT slot map
## (slots move when a player leaves or is kicked, so no slot is ever cached) and
## flattens it LAST into the start config; [method start_blocker] says why Start must
## wait (teams on and everyone explicitly on one team, a seat clash) and the same text
## is shown under the rows.
##
## **What stays in the Lobby.** The hidden spins (%PlayerCountSpin, %AiCountSpin),
## %TeamModeOption and every publish/clamp rule: the panel never writes a control
## and talks to Net only through [member net_provider] (the same `Variant` test seam
## the Lobby uses): read-only queries, plus a client's own-seat request. It reports
## what the player asked for through signals; the Lobby turns that into a config
## edit and republishes.
##
## **The hook contract (Lobby <-> panel; PL1 must not need to edit the Lobby):**
## - [method apply]`(config, roster, seats)` -- once per lobby-data apply. `roster` is
##   the dict's `"roster"` value or null when the dict carried none (rows stay),
##   `seats` is its `"seats"` table or `{}`.
## - [method on_roster_changed]`(roster)` -- a live Events.net_roster_changed payload;
##   re-renders against the last applied config.
## - [method build_roster]`(config)` -- the outbound `"roster"` of a host publish.
## - [method seats_data] -- the `"seats"` table merged into a host publish; `{}` means
##   "write no key" (no table yet). [method build_roster] reconciles the table with the
##   publish's own config and the live peers FIRST, so the table that follows it in
##   `_publish_lobby_data` is already current.
## - [method finalize_start_config]`(config) -> String` -- Start: called AFTER the Lobby
##   clamped [method MatchConfig.clamp_to_connected_peers] (P1 review F1: sanitize drops
##   team arrays whose length differs from player_count, so flattening must see the
##   clamped count); resolves teams freshly each Start. Returns "" or the reason Start
##   must not go ahead (the config is then untouched).
## - [method start_blocker] -- non-empty reason disables Start and is shown as the
##   Start button's tooltip and under the rows (F4).
## - [method set_editable] -- host/client gate, pushed by the Lobby every frame (rows
##   are only redrawn when it changes).
## - [method focus_entries] + [signal focus_entries_changed] -- controls the Lobby
##   adds to its focus loop; the signal is emitted whenever rows are redrawn. The host's
##   Teams toggle and Add bot button, then the colour box, team button, difficulty
##   dropdown and remove button of every row; a client's own colour box and team button.
## - Signals [signal seats_changed], [signal teams_toggled], [signal add_bot_requested],
##   [signal remove_bot_requested]: the panel updates its own seat table FIRST and
##   emits second; the Lobby republishes (host only), so [method seats_data] already
##   carries the change.

# DECISION (ui/lobby/LobbyPlayersPanel.gd, E1): these signals are the contract the
# seat-row packages (PL1a/PL1b) emit from this class; E1 installed them and the
# Lobby's connections.
## The seat table changed (colour, team pick or bot difficulty): republish.
signal seats_changed
## The host flipped the Teams toggle (PL1b). The panel has already re-seeded its team
## picks (1, 2, 1, 2, ... when switched on); the Lobby writes team_mode and republishes.
signal teams_toggled(enabled: bool)
## The host pressed "+ Add bot" (PL1b); the Lobby grows ai_count by one and republishes.
signal add_bot_requested
## The host removed the bot at [param ordinal] (0 = the first bot row). The panel has
## already dropped it from its own table.
signal remove_bot_requested(ordinal: int)
## [method focus_entries] may have changed: the Lobby rewires its loop.
signal focus_entries_changed
## Rows were rebuilt: [param ready_count] of [param row_count] seats are ready. The
## Lobby's bottom-left "Waiting for players" pill reads it.
signal roster_rendered(ready_count: int, row_count: int)

## Difficulty labels for the synthetic bot roster entries [method bot_roster_entries]
## builds, in MatchConfig.AiDifficulty enum order (EASY, NORMAL, HARD) -- the same order
## the Lobby fills %AiDifficultyOption with (P4, Bontago-d5c.5).
const _AI_DIFFICULTY_LABELS: Array[String] = LobbySeatRow.DIFFICULTY_LABELS

## The same layered-pastel tunables the Lobby draws from; the Lobby overwrites this
## with its own export in _ready() so a swapped resource reaches the rows too.
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")
## Sizes and spacings of the rows (colour box, separation, name size, seat controls).
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/lobby_layout_tuning.tres")

## DECISION (ui/lobby/LobbyPlayersPanel.gd): same `Variant` test seam as
## ui/Lobby.gd's net_provider, which forwards its own value here.
var net_provider: Variant = null
## The colour palette (the Lobby's default_config.player_colors, the same eight colours
## as MatchConfig.default_player_colors()); a seat's colour INDEX picks from it and an
## index past its end reads gray.
var palette: PackedColorArray = PackedColorArray()

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _player_count_label: Label = %PlayerCountLabel
@onready var _teams_toggle: CheckButton = %TeamsToggle
@onready var _add_bot_button: Button = %AddBotButton
@onready var _start_blocker_label: Label = %StartBlockerLabel

var _config: MatchConfig = null
## The seat table: the dict's table until a roster has been seen, afterwards always
## reconciled with the live humans and config (LobbySeats.reconcile).
var _seats: Dictionary = {}
var _is_editable: bool = false
## Built by _render(): LobbySeatRows, seated humans (slot order), then seat-less humans
## (spectators), then bots by ordinal.
var _player_rows: Array[Node] = []
## The last human roster entries (peer_id != -1) and whether any roster was seen yet;
## a redraw without a new roster (seat edit, editable flip) reuses them.
var _humans: Array[Dictionary] = []
var _roster_seen: bool = false
## config.ai_difficulty of the last applied/published config: a change is the old
## %AiDifficultyOption talking ("every bot is now Hard"), see _sync_seats().
var _default_difficulty: int = LobbySeats.UNSET
## Start went through finalize_start_config(): the lobby is closed for seat edits (a
## client's late request must not touch a table the match was just built from). Reset
## when the panel is shown again.
var _start_committed: bool = false
## start_blocker() is asked every frame: the answer is recomputed only when its inputs
## (live slot map, seat table, team cap, bot count/difficulty) change.
var _blocker_inputs: int = 0
var _blocker_text: String = ""
var _blocker_known: bool = false
## Which header controls were focus stops at the last _refresh_header() (-1 = never): a change
## tells the Lobby to rewire its loop even when no row was redrawn.
var _header_focus_state: int = -1


func _ready() -> void:
	var art: UiArtTable = UiArtTable.shared()
	art.apply_button_icon(_teams_toggle, art.lobby_icon(UiArtTable.KEY_TEAMS))
	art.apply_button_icon(_add_bot_button, art.lobby_icon(UiArtTable.KEY_BOT_ADD))
	_teams_toggle.toggled.connect(_on_teams_toggle_toggled)
	_add_bot_button.pressed.connect(_on_add_bot_pressed)
	visibility_changed.connect(_on_visibility_changed)
	Events.net_seat_pref_requested.connect(_on_seat_pref_requested)
	_refresh_header()


# --- Hooks the Lobby calls -----------------------------------------------------

## Styling that used to live in the Lobby's _apply_visual_style().
func apply_visual_style() -> void:
	_player_count_label.add_theme_color_override("font_color", tuning.ink_color)
	# PL1b: the header controls are the same chip / pill family as the rest of the screen
	# (cream off, mint on; powder blue like the team numbers); no new colours.
	MenuStyleFactory.apply_toggle_chip(
		_teams_toggle, tuning.pill_cream_color, tuning.pill_cream_hover_color,
		tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
	)
	MenuStyleFactory.apply_pill(
		_add_bot_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning
	)
	_start_blocker_label.add_theme_color_override("font_color", tuning.ink_color)


## One lobby-data apply (Lobby._apply_data(), after the controls were written).
## [param roster] null = the dict carried no roster, so the humans stay as they were;
## [param seats] is the dict's table ({} = none: the panel keeps its own).
func apply(config: MatchConfig, roster: Variant, seats: Dictionary) -> void:
	_config = config
	_default_difficulty = config.ai_difficulty
	if not seats.is_empty():
		# Off the wire: a well-formed table before any accessor touches it.
		_seats = LobbySeats.normalize(seats)
	if roster != null:
		_humans = _human_entries(roster)
		_roster_seen = true
	if _roster_seen:
		_reconcile_current()
		_render()
	else:
		_refresh_header()


## DECISION (ui/Lobby.gd, Bontago-mv0.6): Events.net_roster_changed's payload is the
## roster Net just built, so it goes straight to the rows rather than being re-derived
## from net_provider.peer_ids()/peer_info() the way [method build_roster] does for a
## host's own outbound publish.
func on_roster_changed(roster: Array) -> void:
	_humans = _human_entries(roster)
	_roster_seen = true
	_reconcile_current()
	_render()


## The host's outbound `"roster"`: every connected peer, then the bot seats. Also
## brings the seat table in line with this publish's config and the live peers, so the
## [method seats_data] call that follows carries a current table (a new human has a
## colour and team, a leaver's colour is free, the bot list is `config.ai_count` long).
func build_roster(config: MatchConfig) -> Array[Dictionary]:
	var roster: Array[Dictionary] = []
	if net_provider == null:
		return roster
	for peer_id: int in net_provider.peer_ids():
		var info: Dictionary = net_provider.peer_info(peer_id)
		roster.append({
			LobbySeats.FIELD_PEER_ID: peer_id,
			LobbySeats.FIELD_SLOT_ID: int(info.get(LobbySeats.FIELD_SLOT_ID, -1)),
			LobbySeats.FIELD_NAME: str(info.get(LobbySeats.FIELD_NAME, "")),
			LobbySeats.FIELD_READY: bool(info.get(LobbySeats.FIELD_READY, false)),
		})
	_sync_seats(config, _human_entries(roster))
	roster.append_array(bot_roster_entries(config))
	return roster


## M5 P4 (docs/archive/M5_PLAN.md): one synthetic row per bot seat, slot_id running
## from player_count - ai_count to player_count - 1 -- the same formula
## autoload/match/MatchLifecycle.gd's _build_slots() uses for
## PlayerSlot.is_bot, so the lobby preview and the real match slots never
## disagree about which ids are bots. A bot has no connected peer behind it
## to ready up, so ready is always true; Net.all_peers_ready() only ever
## iterates real peers (its own header), so this can never let an unready
## human's Start gate open.
##
## Split out of the roster build (Bontago-1pi.9b) so a render can re-derive "how
## many bots exist right now" from the config alone, instead of trusting an
## incoming roster's own bot rows -- a live Events.net_roster_changed payload
## (autoload/Net.gd's _broadcast_roster()) never includes them, only a host's own
## outbound publish does.
## PL1a: each bot's difficulty is its own seat's (the table, else config.ai_difficulty).
func bot_roster_entries(config: MatchConfig) -> Array[Dictionary]:
	var bots: Array[Dictionary] = []
	var bot_start: int = config.player_count - config.ai_count
	for ordinal: int in range(config.ai_count):
		var seat_difficulty: int = LobbySeats.difficulty_of(_seats, LobbySeats.bot_key(ordinal))
		if seat_difficulty == LobbySeats.UNSET:
			seat_difficulty = config.ai_difficulty
		var label: String = _AI_DIFFICULTY_LABELS[clampi(seat_difficulty, 0, _AI_DIFFICULTY_LABELS.size() - 1)]
		bots.append({
			LobbySeats.FIELD_PEER_ID: -1,
			LobbySeats.FIELD_SLOT_ID: bot_start + ordinal,
			LobbySeats.FIELD_NAME: "%s (%s)" % [_bot_name(config, ordinal), label],
			LobbySeats.FIELD_READY: true,
		})
	return bots


## Bontago-1pi.62: the host-assigned name of bot `ordinal` (MatchConfig.bot_names), or
## "Bot n" before any was assigned (an older host).
func _bot_name(config: MatchConfig, ordinal: int) -> String:
	if config != null and ordinal < config.bot_names.size() and config.bot_names[ordinal] != "":
		return config.bot_names[ordinal]
	return PlayerNames.bot_fallback(ordinal + 1)


## The `"seats"` table a host publish merges in (empty = no key yet). Until a roster has
## been seen it is the table last applied, so a republish never drops a table another
## build wrote.
func seats_data() -> Dictionary:
	return _seats.duplicate(true)


## Start hook, see the header. Called by Lobby._on_start_pressed() with the config about
## to start, AFTER MatchConfig.clamp_to_connected_peers(): reconciles the seat table with
## the live seated peers and Net's CURRENT slot map (never a remembered one: a lobby
## leave or kick renumbers the slots), then LobbySeats.flatten_to_config() writes the
## seats' colours, bot difficulties and (teams on) resolved teams into `config_to_start`,
## LAST, so nothing after it can change player_count and drop the per-slot arrays.
## Returns "" on success; otherwise the reason (the config is untouched and the Lobby
## does not start). Random picks resolve afresh on every call.
## DECISION (ui/lobby/LobbyPlayersPanel.gd, PL1b): the team shuffle's base seed is the
## match seed when the lobby has one, else a host randi() (LobbySeats.resolve_seed; the
## result rides in slot_team_ids / team_numbers, so no peer ever re-resolves it).
func finalize_start_config(config_to_start: MatchConfig) -> String:
	if net_provider == null:
		return ""
	var slot_map: Dictionary = _live_slot_map()
	var table: Dictionary = _live_table(config_to_start, slot_map)
	var reason: String = LobbySeats.flatten_to_config(
		table, slot_map, config_to_start, LobbySeats.resolve_seed(config_to_start, randi())
	)
	if not reason.is_empty():
		return reason
	_start_committed = true
	_refresh_header()
	return ""


## Start gate hook, see the header: "" when Start may go ahead (also for a client, which
## has no Start). Cached against its inputs, since the Lobby asks every frame.
func start_blocker() -> String:
	if not _is_editable or _config == null or net_provider == null:
		return ""
	var slot_map: Dictionary = _live_slot_map()
	var cap: int = _team_cap()
	var inputs: int = hash([slot_map, _seats, cap, _config.ai_count, _config.ai_difficulty])
	if not _blocker_known or inputs != _blocker_inputs:
		_blocker_inputs = inputs
		_blocker_known = true
		_blocker_text = LobbySeats.start_blocker(_live_table(_config, slot_map), slot_map, cap)
		_show_blocker()
	return _blocker_text


## Host/client gate, pushed by the Lobby every frame: rows are drawn live for the host
## (and a client's own row for it) and read-only for everyone else, and only a CHANGE
## redraws them.
func set_editable(is_host: bool) -> void:
	if is_host == _is_editable:
		return
	_is_editable = is_host
	if _roster_seen:
		_render()
	else:
		_refresh_header()
	_show_blocker()


## What the Lobby last pushed through [method set_editable].
func is_editable() -> bool:
	return _is_editable


## Controls the Lobby adds to its focus loop, in visual order: the host's Teams toggle
## and Add bot button, then per row the colour box, the team button, a bot's difficulty
## dropdown and its remove button -- every row for the host, only its own row's colour
## box and team button for a client. A disabled header control is no focus stop.
func focus_entries() -> Array[Control]:
	var entries: Array[Control] = []
	for header_control: Control in [_teams_toggle, _add_bot_button]:
		if header_control.visible and header_control.focus_mode != Control.FOCUS_NONE:
			entries.append(header_control)
	for row_node: Node in _player_rows:
		var row: LobbySeatRow = row_node as LobbySeatRow
		entries.append_array(row.focusable_controls())
	return entries


# --- Seat table ------------------------------------------------------------------

## The human entries of a roster payload (bot rows inside it, if any, are dropped and
## rebuilt from the seat table): seated humans in slot order first, seat-less ones
## (spectators, slot < 0) after them.
func _human_entries(roster_data: Variant) -> Array[Dictionary]:
	var seated: Array[Dictionary] = []
	var spectators: Array[Dictionary] = []
	if roster_data is Array:
		for entry_variant: Variant in roster_data as Array:
			if not entry_variant is Dictionary:
				continue
			var entry: Dictionary = entry_variant as Dictionary
			if int(entry.get(LobbySeats.FIELD_PEER_ID, -1)) == -1:
				continue
			if int(entry.get(LobbySeats.FIELD_SLOT_ID, -1)) >= 0:
				seated.append(entry)
			else:
				spectators.append(entry)
	seated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get(LobbySeats.FIELD_SLOT_ID, -1)) < int(b.get(LobbySeats.FIELD_SLOT_ID, -1))
	)
	seated.append_array(spectators)
	return seated


## Peer ids of the entries that hold a seat (slot >= 0), in the entries' order.
func _seated_peer_ids(entries: Array[Dictionary]) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for entry: Dictionary in entries:
		if int(entry.get(LobbySeats.FIELD_SLOT_ID, -1)) >= 0:
			ids.append(int(entry.get(LobbySeats.FIELD_PEER_ID, -1)))
	return ids


func _team_cap() -> int:
	return _config.team_pick_cap() if _config != null else 0


## Reconciles the table with the last roster and applied config.
func _reconcile_current() -> void:
	if _config == null:
		return
	_seats = LobbySeats.reconcile(
		_seats, _seated_peer_ids(_humans), _config.ai_count, _config.ai_difficulty, _config.team_pick_cap()
	)


## The host-publish counterpart of _reconcile_current(): `config` is the one about to
## be published (the panel's own `_config` is the previous one).
## DECISION (ui/lobby/LobbyPlayersPanel.gd, PL1a): while the old %AiDifficultyOption is
## still in the Lobby, a CHANGE of config.ai_difficulty sets every bot to it (the
## dropdown's pre-rework meaning); each bot's own dropdown then refines one bot.
## Without a change the bots keep their own, and the value is only the default of new
## bots.
func _sync_seats(config: MatchConfig, human_entries: Array[Dictionary]) -> void:
	_seats = LobbySeats.reconcile(
		_seats, _seated_peer_ids(human_entries), config.ai_count, config.ai_difficulty, config.team_pick_cap()
	)
	if _default_difficulty != LobbySeats.UNSET and config.ai_difficulty != _default_difficulty:
		for ordinal: int in range(LobbySeats.bot_count(_seats)):
			LobbySeats.set_difficulty(_seats, LobbySeats.bot_key(ordinal), config.ai_difficulty)
	_default_difficulty = config.ai_difficulty


## An edit the panel already applied to its table: redraw, then tell the Lobby (which
## republishes the table).
func _seats_edited() -> void:
	_render()
	seats_changed.emit()


## Host: edits the table. Client (own row only): asks the host for the next colour; the
## row changes when the host's lobby data comes back.
func _on_color_cycle_requested(key: int, backwards: bool) -> void:
	if _is_editable:
		if LobbySeats.cycle_color(_seats, key, backwards):
			Events.lobby_ui_cue.emit(&"colour_change")
			_seats_edited()
	elif _is_own_seat(key):
		var current: int = LobbySeats.color_of(_seats, key)
		if current != LobbySeats.UNSET:
			Events.lobby_ui_cue.emit(&"colour_change")
			net_provider.request_seat_pref(posmod(current + (-1 if backwards else 1), LobbySeats.palette_size()), LobbySeats.UNCHANGED)


## Same split for the team pick: the host edits, a client asks for its own.
func _on_team_cycle_requested(key: int, backwards: bool) -> void:
	if _is_editable:
		if LobbySeats.cycle_team(_seats, key, _team_cap(), backwards):
			Events.lobby_ui_cue.emit(&"team_change")
			_seats_edited()
	elif _is_own_seat(key) and _team_cap() > 0:
		var current: int = LobbySeats.team_of(_seats, key)
		if current != LobbySeats.UNSET:
			Events.lobby_ui_cue.emit(&"team_change")
			net_provider.request_seat_pref(LobbySeats.UNCHANGED, TeamAssigner.next_pick(current, _team_cap(), backwards))


func _on_difficulty_chosen(key: int, difficulty: int) -> void:
	if _is_editable and LobbySeats.set_difficulty(_seats, key, difficulty):
		_seats_edited()


## The table loses the bot first (later bots move down an ordinal with their picks and
## the colour is free again), then the Lobby is asked to drop `ai_count` by one.
func _on_remove_requested(key: int) -> void:
	if not _is_editable or not LobbySeats.remove_bot(_seats, key):
		return
	_render()
	remove_bot_requested.emit(LobbySeats.bot_ordinal(key))


# --- Header controls, client self-edit, Start (PL1b) ----------------------------------

## True while seat edits are welcome: this is the host's lobby, Start has not gone
## through, and no match is running. Net refuses mid-match requests itself; the lobby
## re-checks because the stretch between Start's flatten and Net's match flag (the
## loading overlay's pre-start frames) belongs to this screen, not to Net.
## DECISION (ui/lobby/LobbyPlayersPanel.gd, PL1b): `match_in_progress` is asked only when
## the provider has it (the real Net does; the FakeNet test double does not).
func _lobby_open() -> bool:
	if not _is_editable or _start_committed or net_provider == null:
		return false
	return not (net_provider.has_method(&"match_in_progress") and bool(net_provider.match_in_progress()))


## `key` is the local player's own human seat (the one a client may edit).
func _is_own_seat(key: int) -> bool:
	return net_provider != null and key > LobbySeats.KEY_NONE and key == int(net_provider.local_peer_id())


## The Teams toggle. Switching ON re-seeds every pick (1, 2, 1, 2, ... in seat order,
## plan section 2); OFF keeps the picks hidden. The table changes first, then the Lobby
## is asked to write team_mode (OFF or TEAMS_4: "on, up to 4 teams") and republish.
func _on_teams_toggle_toggled(pressed: bool) -> void:
	if not _lobby_open():
		_refresh_header()
		return
	if pressed:
		LobbySeats.seed_team_picks(_seats)
	teams_toggled.emit(pressed)
	_refresh_header()


## "+ Add bot". DECISION (ui/lobby/LobbyPlayersPanel.gd, PL1b): the table is NOT edited
## here -- the Lobby grows ai_count and its publish reconciles the table, which appends
## the new bot exactly as LobbySeats.add_bot would (lowest free colour, the smaller of
## teams 1/2, the lobby's default difficulty). The cap is 8 seats (humans + bots).
func _on_add_bot_pressed() -> void:
	if not _lobby_open() or LobbySeats.seat_count(_seats) >= MatchConfig.PLAYER_COUNT_MAX:
		return
	add_bot_requested.emit()


## A client's own-seat request (Net.request_seat_pref -> Events.net_seat_pref_requested;
## Net already vetoed an unknown / spectator sender and out-of-range values). Applied
## only while the lobby is open, through the exact team cap and the colour swap rule; a
## refused or no-op request changes and publishes nothing.
func _on_seat_pref_requested(peer_id: int, color_index: int, team_pick: int) -> void:
	if not _lobby_open():
		return
	_reconcile_current()
	if LobbySeats.apply_human_pref(_seats, peer_id, color_index, team_pick, _team_cap()):
		_seats_edited()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_start_committed = false
		_refresh_header()


## The header controls' state from the applied config and the panel's role: the Teams
## toggle shows whether teams are on (live for the host, read-only for a client), "+ Add
## bot" exists for the host and is disabled when all 8 seats are taken. A control that
## cannot be used is no focus stop; focus that sat on one that just went away moves to
## the Teams toggle.
func _refresh_header() -> void:
	var open: bool = _lobby_open()
	_teams_toggle.set_pressed_no_signal(_team_cap() > 0)
	_teams_toggle.disabled = not open
	_teams_toggle.focus_mode = Control.FOCUS_ALL if open else Control.FOCUS_NONE
	_add_bot_button.visible = _is_editable
	var add_enabled: bool = open and LobbySeats.seat_count(_seats) < MatchConfig.PLAYER_COUNT_MAX
	var add_had_focus: bool = _add_bot_button.has_focus()
	_add_bot_button.disabled = not add_enabled
	_add_bot_button.focus_mode = Control.FOCUS_ALL if add_enabled else Control.FOCUS_NONE
	if add_had_focus and not add_enabled:
		_add_bot_button.release_focus()
		_grab(_teams_toggle)
	_show_blocker()
	var focus_state: int = int(open) + 2 * int(add_enabled)
	if focus_state != _header_focus_state:
		_header_focus_state = focus_state
		focus_entries_changed.emit()


## The start blocker's text under the rows (host only, empty = hidden).
func _show_blocker() -> void:
	var text: String = _blocker_text if _is_editable else ""
	_start_blocker_label.text = text
	_start_blocker_label.visible = not text.is_empty()


## {peer_id: slot_id} of every peer Net lists RIGHT NOW. Never cached: the host's slots
## move when a player leaves or is kicked and when the lobby is re-entered.
func _live_slot_map() -> Dictionary:
	var slot_map: Dictionary = {}
	if net_provider == null:
		return slot_map
	for peer_id: int in net_provider.peer_ids():
		slot_map[peer_id] = int(net_provider.slot_of_peer(peer_id))
	return slot_map


## The seat table brought in line with `slot_map` and `config` just before it is judged or
## flattened: seated peers only (a spectator holds no seat), in slot order; a peer that
## joined since the last publish gets its defaults, one that left drops out, and the bot
## list follows config.ai_count. A fresh table: the panel's own is not touched.
func _live_table(config: MatchConfig, slot_map: Dictionary) -> Dictionary:
	var seated: Array[int] = []
	for peer_id: int in slot_map.keys():
		if int(slot_map[peer_id]) >= 0:
			seated.append(peer_id)
	seated.sort_custom(func(a: int, b: int) -> bool:
		return int(slot_map[a]) < int(slot_map[b])
	)
	var peer_ids: PackedInt32Array = PackedInt32Array(seated)
	return LobbySeats.reconcile(_seats, peer_ids, config.ai_count, config.ai_difficulty, config.team_pick_cap())


# --- Rendering -------------------------------------------------------------------

## DECISION (ui/Lobby.gd, Bontago-1pi.9b): owner playtest -- "the right panel
## lists 'players+bots'/'players', I can add bots up to the player limit" --
## traced to two different roster payload shapes landing here: Net's own
## live roster events (autoload/Net.gd's _broadcast_roster(), reached via
## on_roster_changed()) never include bot rows (Net has no concept of
## ai_count), while a full lobby-data apply's own roster does. Whichever
## happened to run last decided whether the header (and the row list) showed
## bots at all, even though ai_count itself hadn't changed -- read by the owner as
## an inconsistent, confusing count. The stored human entries now only ever supply
## the human rows (bot rows inside a roster are dropped); the seat table is the single
## source of truth for the bot rows actually drawn, on every call path alike.
func _render() -> void:
	var bot_total: int = LobbySeats.bot_count(_seats)

	# "3 players * 2 bots * 5/8 seats" (or, with no bots, "3 players * 3/8
	# seats") -- unambiguous about how many of each are seated, unlike the
	# old bare "roster.size() / seats" this replaces.
	# DECISION (ui/lobby/LobbyPlayersPanel.gd, E1): the seat count is the applied
	# config's player_count; the Lobby used to read its %PlayerCountSpin, which
	# _apply_data() writes from that same sanitized value (and every host edit
	# republishes), so the two agree whenever the Lobby is shown.
	# Bontago-1pi.106: the player/bot count controls are gone, so the denominator is always the maximum.
	var seat_count: int = MatchConfig.PLAYER_COUNT_MAX
	# Bontago-1pi.95: the label clips (never widens the card); the tooltip carries the full text.
	_player_count_label.text = format_roster_header(_humans.size(), bot_total, seat_count)
	_player_count_label.tooltip_text = _player_count_label.text

	var focus_memory: Dictionary = _remember_focus()
	for row: Node in _player_rows:
		# Out of the tree at once (not only queued): the redraw can run inside a
		# button's own `pressed` signal, and the new rows must be the only ones.
		_player_list.remove_child(row)
		row.queue_free()
	_player_rows.clear()

	var ready_count: int = 0
	for entry: Dictionary in _humans:
		var human_row: LobbySeatRow = _build_human_row(entry)
		if human_row.is_ready:
			ready_count += 1
		_add_row(human_row)
	for ordinal: int in range(bot_total):
		ready_count += 1
		_add_row(_build_bot_row(ordinal))
	_refresh_header()
	_restore_focus(focus_memory)
	roster_rendered.emit(ready_count, _player_rows.size())
	focus_entries_changed.emit()


func _add_row(row: LobbySeatRow) -> void:
	row.color_cycle_requested.connect(_on_color_cycle_requested)
	row.team_cycle_requested.connect(_on_team_cycle_requested)
	row.difficulty_chosen.connect(_on_difficulty_chosen)
	row.remove_requested.connect(_on_remove_requested)
	_player_list.add_child(row)
	_player_rows.append(row)


## DECISION (ui/Lobby.gd, Bontago-1pi.9b): "3 players" (plural handled),
## "2 bots" only appended when there are any (a 0-bot lobby doesn't need to
## announce that), then the seat fraction against [param seats] -- how many seats
## this lobby is configured for, not a hardcoded MatchConfig.PLAYER_COUNT_MAX.
static func format_roster_header(humans: int, bots: int, seats: int) -> String:
	var human_word: String = "player" if humans == 1 else "players"
	if bots <= 0:
		return "%d %s · %d/%d seats" % [humans, human_word, humans, seats]
	var bot_word: String = "bot" if bots == 1 else "bots"
	return "%d %s · %d %s · %d/%d seats" % [humans, human_word, bots, bot_word, humans + bots, seats]


## Bontago-mp0.3.5 (review r2, item 4): one white pill row per roster entry -- a
## colour box in the seat's colour, bold name, a small muted subtitle ("Host · you" /
## "LAN · <ping> ms"), and a Ready (mint)/Not ready (peach) badge on the right.
## PL1a adds the per-seat controls (see LobbySeatRow).
func _build_human_row(entry: Dictionary) -> LobbySeatRow:
	var peer_id: int = int(entry.get(LobbySeats.FIELD_PEER_ID, -1))
	var key: int = LobbySeats.KEY_NONE
	if int(entry.get(LobbySeats.FIELD_SLOT_ID, -1)) >= 0 and LobbySeats.has_seat(_seats, LobbySeats.human_key(peer_id)):
		key = LobbySeats.human_key(peer_id)
	var row: LobbySeatRow = _new_row(key)
	row.display_name = str(entry.get(LobbySeats.FIELD_NAME, "?"))
	row.subtitle = _human_subtitle(entry, peer_id)
	row.is_ready = bool(entry.get(LobbySeats.FIELD_READY, false))
	row.is_host = peer_id == Net.HOST_PEER_ID
	row.build(tuning, layout_tuning)
	return row


## A bot seat: "Bot n" with an "AI" subtitle (the difficulty is the dropdown beside it),
## always ready.
func _build_bot_row(ordinal: int) -> LobbySeatRow:
	var key: int = LobbySeats.bot_key(ordinal)
	var row: LobbySeatRow = _new_row(key)
	row.display_name = _bot_name(_config, ordinal)
	row.subtitle = "AI"
	row.is_bot = true
	row.is_ready = true
	row.difficulty = LobbySeats.difficulty_of(_seats, key)
	row.build(tuning, layout_tuning)
	return row


## A row with the seat-derived fields every kind of row shares.
func _new_row(key: int) -> LobbySeatRow:
	var row: LobbySeatRow = LobbySeatRow.new()
	row.seat_key = key
	row.seat_color = _seat_color(key)
	# The host works every seat; a client only its own (colour and team).
	row.editable = key != LobbySeats.KEY_NONE and (_is_editable or _is_own_seat(key))
	row.show_team = _team_cap() > 0
	row.team_pick = maxi(LobbySeats.team_of(_seats, key), MatchConfig.TEAM_PICK_RANDOM)
	return row


## The seat's colour from the palette; gray for a seat-less row or an index the
## palette does not have.
func _seat_color(key: int) -> Color:
	var index: int = LobbySeats.color_of(_seats, key)
	return SlotColors.palette_color(index, palette, Color.GRAY)


func _human_subtitle(entry: Dictionary, peer_id: int) -> String:
	var is_local: bool = net_provider != null and peer_id == int(net_provider.local_peer_id())
	# Net.HOST_PEER_ID's own value (ENet convention: the host is always peer id 1) --
	# autoload/Net.gd's own const, read directly off the real autoload class since
	# net_provider is a Variant test seam here.
	if peer_id == Net.HOST_PEER_ID:
		return "Host · you" if is_local else "Host"
	if is_local:
		return "you"
	var transport: String = "Steam" if (net_provider != null and bool(net_provider.is_steam_session())) else "LAN"
	return "%s · %d ms" % [transport, int(entry.get(LobbySeats.FIELD_PING_MS, 0.0))]


# --- Focus across a redraw -------------------------------------------------------

## Which control of which row holds focus (a pad user who cycled a colour must still be
## on that colour box after the rows are redrawn).
func _remember_focus() -> Dictionary:
	if not is_inside_tree():
		return {}
	var holder: Control = get_viewport().gui_get_focus_owner()
	if holder == null:
		return {}
	for index: int in range(_player_rows.size()):
		var row: LobbySeatRow = _player_rows[index] as LobbySeatRow
		if row.is_ancestor_of(holder):
			return {"key": row.seat_key, "kind": row.kind_of(holder), "index": index}
	return {}


## Focus goes to the same control of the same seat; when that seat or control is gone
## (a removed bot) to the row now at its position, preferring the same kind.
func _restore_focus(memory: Dictionary) -> void:
	if memory.is_empty() or _player_rows.is_empty():
		return
	var kind: StringName = memory["kind"]
	for row_node: Node in _player_rows:
		var row: LobbySeatRow = row_node as LobbySeatRow
		if row.seat_key == int(memory["key"]) and _grab(row.control_of(kind)):
			return
	var fallback: LobbySeatRow = _player_rows[mini(int(memory["index"]), _player_rows.size() - 1)] as LobbySeatRow
	for candidate: Control in [fallback.control_of(kind), fallback.color_button]:
		if _grab(candidate):
			return


func _grab(control: Control) -> bool:
	if control == null or control.focus_mode == Control.FOCUS_NONE:
		return false
	control.grab_focus()
	return true
