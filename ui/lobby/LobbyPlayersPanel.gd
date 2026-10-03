class_name LobbyPlayersPanel
extends VBoxContainer
## The lobby's right-hand roster (Bontago-1pi.53, package E1, docs/
## LOBBY_REWORK_PLAN.md "Right panel"): the "Players" title row with its
## "N players · M bots · K/S seats" header, and one pill row per seat (a human
## from the roster, then one synthetic row per bot). Extracted 1:1 from ui/Lobby.gd
## so the seat-row package (PL1) can grow it without touching the Lobby again.
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
##   "write no key". E1 only echoes the table last applied.
## - [method finalize_start_config]`(config)` -- Start: called AFTER the Lobby clamped
##   [method MatchConfig.clamp_to_connected_peers] (P1 review F1: sanitize drops team
##   arrays whose length differs from player_count, so flattening must see the
##   clamped count); must resolve teams freshly each Start. E1: no-op.
## - [method start_blocker] -- non-empty reason disables Start and is shown as the
##   Start button's tooltip (F4). E1: always "".
## - [method set_editable] -- host/client gate, pushed by the Lobby every frame.
## - [method focus_entries] + [signal focus_entries_changed] -- controls the Lobby
##   adds to its focus loop; emit the signal whenever the set changes. E1: none
##   (rows carry no focusable control).
## - Signals [signal seats_changed], [signal teams_toggled], [signal add_bot_requested],
##   [signal remove_bot_requested]: the panel updates its own seat table FIRST and
##   emits second; the Lobby republishes (host only), so [method seats_data] already
##   carries the change.

# DECISION (ui/lobby/LobbyPlayersPanel.gd, E1): these five signals are the contract
# the seat-row package (PL1) emits from this class; E1 only installs them and the
# Lobby's connections, so the unused-signal warning is silenced on each.
## The seat table changed (colour, team pick or bot difficulty): republish.
@warning_ignore("unused_signal")
signal seats_changed
## The host flipped the Teams toggle.
@warning_ignore("unused_signal")
signal teams_toggled(enabled: bool)
## The host pressed "+ Add bot".
@warning_ignore("unused_signal")
signal add_bot_requested
## The host removed the bot at [param ordinal] (0 = the first bot row).
@warning_ignore("unused_signal")
signal remove_bot_requested(ordinal: int)
## [method focus_entries] gained or lost a control: the Lobby rewires its loop.
@warning_ignore("unused_signal")
signal focus_entries_changed
## Rows were rebuilt: [param ready_count] of [param row_count] seats are ready. The
## Lobby's bottom-left "Waiting for players" pill reads it.
signal roster_rendered(ready_count: int, row_count: int)

## Difficulty labels for the synthetic bot rows [method bot_roster_entries] builds,
## in MatchConfig.AiDifficulty enum order (EASY, NORMAL, HARD) -- the same order the
## Lobby fills %AiDifficultyOption with (P4, Bontago-d5c.5).
const _AI_DIFFICULTY_LABELS: Array[String] = ["Easy", "Normal", "Hard"]

## The same layered-pastel tunables the Lobby draws from; the Lobby overwrites this
## with its own export in _ready() so a swapped resource reaches the rows too.
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")
## Sizes and spacings of the rows (colour box, separation, name size).
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/lobby_layout_tuning.tres")

## DECISION (ui/lobby/LobbyPlayersPanel.gd): same `Variant` test seam as
## ui/Lobby.gd's net_provider, which forwards its own value here.
var net_provider: Variant = null
## Per-slot colours (the Lobby's default_config.player_colors); a slot past its end
## reads gray.
var palette: PackedColorArray = PackedColorArray()

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _player_count_label: Label = %PlayerCountLabel

var _config: MatchConfig = null
var _seats: Dictionary = {}
var _is_editable: bool = false
## Built by _render(), in roster order -- the same index pairs a row with its entry.
var _player_rows: Array[Node] = []


# --- Hooks the Lobby calls -----------------------------------------------------

## Styling that used to live in the Lobby's _apply_visual_style().
func apply_visual_style() -> void:
	_player_count_label.add_theme_color_override("font_color", tuning.ink_color)


## One lobby-data apply (Lobby._apply_data(), after the controls were written).
## [param roster] null = the dict carried no roster, so the rows stay as they are.
func apply(config: MatchConfig, roster: Variant, seats: Dictionary) -> void:
	_config = config
	_seats = seats
	if roster != null:
		_render(roster)


## DECISION (ui/Lobby.gd, Bontago-mv0.6): Events.net_roster_changed's payload is the
## roster Net just built, so it goes straight to the rows rather than being re-derived
## from net_provider.peer_ids()/peer_info() the way [method build_roster] does for a
## host's own outbound publish.
func on_roster_changed(roster: Array) -> void:
	_render(roster)


## The host's outbound `"roster"`: every connected peer, then the bot seats.
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
func bot_roster_entries(config: MatchConfig) -> Array[Dictionary]:
	var bots: Array[Dictionary] = []
	var difficulty: String = _AI_DIFFICULTY_LABELS[
		clampi(config.ai_difficulty, 0, _AI_DIFFICULTY_LABELS.size() - 1)
	]
	var bot_start: int = config.player_count - config.ai_count
	for slot_id: int in range(bot_start, config.player_count):
		var bot_index: int = slot_id - bot_start + 1
		bots.append({
			"peer_id": -1,
			"slot_id": slot_id,
			"name": "Bot %d (%s)" % [bot_index, difficulty],
			"ready": true,
		})
	return bots


## The `"seats"` table a host publish merges in (empty = no key). E1 keeps no table of
## its own: it hands back the one last applied, so a republish never drops a table that
## another build wrote.
func seats_data() -> Dictionary:
	return _seats.duplicate(true)


## Start hook, see the header. E1: nothing to resolve yet.
func finalize_start_config(_config_to_start: MatchConfig) -> void:
	pass


## Start gate hook, see the header. E1: nothing blocks Start.
func start_blocker() -> String:
	return ""


## Host/client gate; E1 rows have no control to gate, PL1 reads it.
func set_editable(is_host: bool) -> void:
	_is_editable = is_host


## What the Lobby last pushed through [method set_editable].
func is_editable() -> bool:
	return _is_editable


## Controls the Lobby adds to its focus loop, in visual order (E1: none).
func focus_entries() -> Array[Control]:
	return []


# --- Rendering -------------------------------------------------------------------

## DECISION (ui/Lobby.gd, Bontago-1pi.9b): owner playtest -- "the right panel
## lists 'players+bots'/'players', I can add bots up to the player limit" --
## traced to two different roster payload shapes landing here: Net's own
## live roster events (autoload/Net.gd's _broadcast_roster(), reached via
## on_roster_changed()) never include bot rows (Net has no concept of
## ai_count), while a full lobby-data apply's own roster does. Whichever
## happened to run last decided whether the header (and the row list) showed
## bots at all, even though ai_count itself hadn't changed -- read by the owner as
## an inconsistent, confusing count. [param roster_data] now only ever supplies the
## human rows (bot rows inside it, if any, are dropped and rebuilt);
## bot_roster_entries(_config) is the single source of truth for the bot rows
## actually drawn, on every call path alike.
func _render(roster_data: Variant) -> void:
	var humans: Array[Dictionary] = []
	if roster_data is Array:
		for entry_variant: Variant in roster_data as Array:
			var entry: Dictionary = entry_variant as Dictionary
			if int(entry.get("peer_id", -1)) != -1:
				humans.append(entry)
	var bots: Array[Dictionary] = bot_roster_entries(_config) if _config != null else []
	var display_roster: Array[Dictionary] = humans.duplicate()
	display_roster.append_array(bots)

	# "3 players * 2 bots * 5/8 seats" (or, with no bots, "3 players * 3/8
	# seats") -- unambiguous about how many of each are seated, unlike the
	# old bare "roster.size() / seats" this replaces.
	# DECISION (ui/lobby/LobbyPlayersPanel.gd, E1): the seat count is the applied
	# config's player_count; the Lobby used to read its %PlayerCountSpin, which
	# _apply_data() writes from that same sanitized value (and every host edit
	# republishes), so the two agree whenever the Lobby is shown.
	var seat_count: int = _config.player_count if _config != null else humans.size()
	_player_count_label.text = format_roster_header(humans.size(), bots.size(), seat_count)

	for row: Node in _player_rows:
		row.queue_free()
	_player_rows.clear()
	var ready_count: int = 0
	for entry: Dictionary in display_roster:
		var ready: bool = bool(entry.get("ready", false))
		if ready:
			ready_count += 1
		var row: PanelContainer = _build_player_row(entry, ready)
		_player_list.add_child(row)
		_player_rows.append(row)
	roster_rendered.emit(ready_count, display_roster.size())


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


## Bontago-mp0.3.5 (review r2, item 4): one white pill row per roster entry --
## a clay-cube icon in the slot's colour (a flat rounded square standing in
## for mockup 11's iso cube glyph, given the time budget), bold name, a small
## muted subtitle ("Host · you" / "LAN · <ping> ms" / "AI · <difficulty>"),
## and a Ready (mint)/Not ready (peach) badge on the right, replacing the
## previous plain "Mira  (ready)" Label row.
func _build_player_row(entry: Dictionary, ready: bool) -> PanelContainer:
	var slot_id: int = int(entry.get("slot_id", -1))
	var peer_id: int = int(entry.get("peer_id", -1))
	var raw_name: String = str(entry.get("name", "?"))
	var display_name: String = raw_name
	var subtitle: String = ""
	if peer_id == -1:
		# Bot rows: bot_roster_entries() packs the difficulty into the name as
		# "Bot 1 (Normal)" -- split it back into a name + subtitle pair.
		var open_paren: int = raw_name.find("(")
		if open_paren != -1:
			display_name = raw_name.substr(0, open_paren).strip_edges()
			subtitle = "AI · %s" % raw_name.substr(open_paren + 1, raw_name.length() - open_paren - 2)
		else:
			subtitle = "AI"
	else:
		var is_local: bool = net_provider != null and peer_id == int(net_provider.local_peer_id())
		# Net.HOST_PEER_ID's own value (ENet convention: the host is always
		# peer id 1) -- autoload/Net.gd's own const, read directly off the
		# real autoload class since net_provider is a Variant test seam here.
		if peer_id == Net.HOST_PEER_ID:
			subtitle = "Host · you" if is_local else "Host"
		elif is_local:
			subtitle = "you"
		else:
			var transport: String = "Steam" if (net_provider != null and bool(net_provider.is_steam_session())) else "LAN"
			subtitle = "%s · %d ms" % [transport, int(entry.get("ping_ms", 0.0))]

	var slot_color: Color = palette[slot_id] if slot_id >= 0 and slot_id < palette.size() else Color.GRAY

	var row: PanelContainer = PanelContainer.new()
	# Bontago-mp0.3.5 (review r3, problem 5): make_flat_list() draws
	# pill_cream_hover_color, which is the *exact same* Color as
	# card_cream_color (config/MenuVisualTuning.gd) -- the row was blending
	# invisibly into %PlayersCard's own background instead of reading as a
	# raised white pill (mockup 11). tuning.pill_white_color is a real near-
	# white the card can never match.
	row.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_white_color, tuning))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if layout_tuning.seat_row_min_height_px > 0:
		row.custom_minimum_size = Vector2(0.0, float(layout_tuning.seat_row_min_height_px))
	var layout: HBoxContainer = HBoxContainer.new()
	layout.add_theme_constant_override("separation", layout_tuning.seat_row_separation_px)
	row.add_child(layout)

	var icon: PanelContainer = PanelContainer.new()
	icon.custom_minimum_size = layout_tuning.color_box_size_px
	var icon_box: StyleBoxFlat = StyleBoxFlat.new()
	icon_box.bg_color = slot_color
	icon_box.set_corner_radius_all(layout_tuning.color_box_corner_radius_px)
	icon.add_theme_stylebox_override("panel", icon_box)
	layout.add_child(icon)

	var text_column: VBoxContainer = VBoxContainer.new()
	text_column.add_theme_constant_override("separation", layout_tuning.seat_text_separation_px)
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = Label.new()
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", layout_tuning.seat_name_font_size)
	name_label.text = display_name
	var subtitle_label: Label = Label.new()
	subtitle_label.theme_type_variation = &"CaptionLabel"
	subtitle_label.text = subtitle
	text_column.add_child(name_label)
	text_column.add_child(subtitle_label)
	layout.add_child(text_column)

	var badge: PanelContainer = PanelContainer.new()
	var badge_color: Color = tuning.pill_mint_color if ready else tuning.ground_band_apricot_color
	badge.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(badge_color, tuning))
	var badge_label: Label = Label.new()
	badge_label.text = ("%s Ready" % char(0x2713)) if ready else ("%s Not ready" % char(0x231A))
	badge_label.add_theme_color_override("font_color", tuning.ink_color)
	badge.add_child(badge_label)
	layout.add_child(badge)
	return row
