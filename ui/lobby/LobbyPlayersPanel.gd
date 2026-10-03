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
## [signal seats_changed] (or [signal remove_bot_requested]). A client's rows are
## read-only here (PL1b adds the client's own-seat requests).
##
## **What stays in the Lobby.** The hidden spins (%PlayerCountSpin, %AiCountSpin),
## %TeamModeOption and every publish/clamp rule: the panel never writes a control
## and never talks to Net itself except for read-only queries through
## [member net_provider] (the same `Variant` test seam the Lobby uses). It reports
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
## - [method finalize_start_config]`(config)` -- Start: called AFTER the Lobby clamped
##   [method MatchConfig.clamp_to_connected_peers] (P1 review F1: sanitize drops team
##   arrays whose length differs from player_count, so flattening must see the
##   clamped count); must resolve teams freshly each Start. PL1a: no-op (PL1b).
## - [method start_blocker] -- non-empty reason disables Start and is shown as the
##   Start button's tooltip (F4). PL1a: always "" (PL1b).
## - [method set_editable] -- host/client gate, pushed by the Lobby every frame (rows
##   are only redrawn when it changes).
## - [method focus_entries] + [signal focus_entries_changed] -- controls the Lobby
##   adds to its focus loop; the signal is emitted whenever rows are redrawn. PL1a: the
##   host's colour box, team button, difficulty dropdown and remove button of every row
##   (none for a client).
## - Signals [signal seats_changed], [signal teams_toggled], [signal add_bot_requested],
##   [signal remove_bot_requested]: the panel updates its own seat table FIRST and
##   emits second; the Lobby republishes (host only), so [method seats_data] already
##   carries the change.

# DECISION (ui/lobby/LobbyPlayersPanel.gd, E1): these signals are the contract the
# seat-row packages (PL1a/PL1b) emit from this class; E1 installed them and the
# Lobby's connections. teams_toggled and add_bot_requested are PL1b's (the header
# controls), so the unused-signal warning stays silenced on those two.
## The seat table changed (colour, team pick or bot difficulty): republish.
signal seats_changed
## The host flipped the Teams toggle (PL1b).
@warning_ignore("unused_signal")
signal teams_toggled(enabled: bool)
## The host pressed "+ Add bot" (PL1b).
@warning_ignore("unused_signal")
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


# --- Hooks the Lobby calls -----------------------------------------------------

## Styling that used to live in the Lobby's _apply_visual_style().
func apply_visual_style() -> void:
	_player_count_label.add_theme_color_override("font_color", tuning.ink_color)


## One lobby-data apply (Lobby._apply_data(), after the controls were written).
## [param roster] null = the dict carried no roster, so the humans stay as they were;
## [param seats] is the dict's table ({} = none: the panel keeps its own).
func apply(config: MatchConfig, roster: Variant, seats: Dictionary) -> void:
	_config = config
	_default_difficulty = config.ai_difficulty
	if not seats.is_empty():
		_seats = seats.duplicate(true)
	if roster != null:
		_humans = _human_entries(roster)
		_roster_seen = true
	if _roster_seen:
		_reconcile_current()
		_render()


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
			"peer_id": peer_id,
			"slot_id": int(info.get("slot_id", -1)),
			"name": str(info.get("name", "")),
			"ready": bool(info.get("ready", false)),
		})
	_sync_seats(config, _human_entries(roster))
	roster.append_array(bot_roster_entries(config))
	return roster


## M5 P4 (docs/M5_PLAN.md): one synthetic row per bot seat, slot_id running
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
			"peer_id": -1,
			"slot_id": bot_start + ordinal,
			"name": "Bot %d (%s)" % [ordinal + 1, label],
			"ready": true,
		})
	return bots


## The `"seats"` table a host publish merges in (empty = no key yet). Until a roster has
## been seen it is the table last applied, so a republish never drops a table another
## build wrote.
func seats_data() -> Dictionary:
	return _seats.duplicate(true)


## Start hook, see the header. DECISION (PL1a): the flatten into the start config and
## the teams start blocker are PL1b's (they need the Start path's slot map and the
## Teams toggle); until then Start is the legacy one.
func finalize_start_config(_config_to_start: MatchConfig) -> void:
	pass


## Start gate hook, see the header. PL1a: nothing blocks Start.
func start_blocker() -> String:
	return ""


## Host/client gate, pushed by the Lobby every frame: rows are drawn live for the host
## and read-only for everyone else, and only a CHANGE redraws them.
func set_editable(is_host: bool) -> void:
	if is_host == _is_editable:
		return
	_is_editable = is_host
	if _roster_seen:
		_render()


## What the Lobby last pushed through [method set_editable].
func is_editable() -> bool:
	return _is_editable


## Controls the Lobby adds to its focus loop, in visual order: per row the colour box,
## the team button, a bot's difficulty dropdown and its remove button -- host only.
func focus_entries() -> Array[Control]:
	var entries: Array[Control] = []
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
			if int(entry.get("peer_id", -1)) == -1:
				continue
			if int(entry.get("slot_id", -1)) >= 0:
				seated.append(entry)
			else:
				spectators.append(entry)
	seated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot_id", -1)) < int(b.get("slot_id", -1))
	)
	seated.append_array(spectators)
	return seated


## Peer ids of the entries that hold a seat (slot >= 0), in the entries' order.
func _seated_peer_ids(entries: Array[Dictionary]) -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for entry: Dictionary in entries:
		if int(entry.get("slot_id", -1)) >= 0:
			ids.append(int(entry.get("peer_id", -1)))
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


func _on_color_cycle_requested(key: int, backwards: bool) -> void:
	if _is_editable and LobbySeats.cycle_color(_seats, key, backwards):
		_seats_edited()


func _on_team_cycle_requested(key: int, backwards: bool) -> void:
	if _is_editable and LobbySeats.cycle_team(_seats, key, _team_cap(), backwards):
		_seats_edited()


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
	var seat_count: int = _config.player_count if _config != null else _humans.size()
	_player_count_label.text = format_roster_header(_humans.size(), bot_total, seat_count)

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
	var peer_id: int = int(entry.get("peer_id", -1))
	var key: int = LobbySeats.KEY_NONE
	if int(entry.get("slot_id", -1)) >= 0 and LobbySeats.has_seat(_seats, LobbySeats.human_key(peer_id)):
		key = LobbySeats.human_key(peer_id)
	var row: LobbySeatRow = _new_row(key)
	row.display_name = str(entry.get("name", "?"))
	row.subtitle = _human_subtitle(entry, peer_id)
	row.is_ready = bool(entry.get("ready", false))
	row.build(tuning, layout_tuning)
	return row


## A bot seat: "Bot n" with an "AI" subtitle (the difficulty is the dropdown beside it),
## always ready.
func _build_bot_row(ordinal: int) -> LobbySeatRow:
	var key: int = LobbySeats.bot_key(ordinal)
	var row: LobbySeatRow = _new_row(key)
	row.display_name = "Bot %d" % (ordinal + 1)
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
	row.editable = _is_editable and key != LobbySeats.KEY_NONE
	row.show_team = _team_cap() > 0
	row.team_pick = maxi(LobbySeats.team_of(_seats, key), MatchConfig.TEAM_PICK_RANDOM)
	return row


## The seat's colour from the palette; gray for a seat-less row or an index the
## palette does not have.
func _seat_color(key: int) -> Color:
	var index: int = LobbySeats.color_of(_seats, key)
	if index >= 0 and index < palette.size():
		return palette[index]
	return Color.GRAY


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
	return "%s · %d ms" % [transport, int(entry.get("ping_ms", 0.0))]


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
