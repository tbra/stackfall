class_name Lobby
extends Control
## Every spec 1.9 match setting as a control, synced as lobby data so every
## client sees the host's settings (spec 2.6 "Steam lobbies store match
## settings as lobby data").
##
## **The round trip.** The host builds a MatchConfig from its controls,
## serializes it with to_dict(), merges in the roster, and calls
## Net.set_lobby_data(). Every instance — including the host itself, so its
## own UI never waits on an echo that may not arrive over a stub or a lossy
## transport — applies the same Dictionary through _apply_data(): from_dict(),
## then sanitize() so a value that arrived out of its spec 1.9 range is
## clamped rather than trusted. A flag stops that inbound apply from re-triggering
## another outbound publish.
##
## **Host-only editing.** Net.is_host() is true on the host and offline
## (autoload/Net.gd's docstring), so gating on it alone is the "offline still works"
## rule this project uses everywhere else. A client's
## controls are disabled; only its own Ready checkbox stays live.
##
## Connects to Events and Net only — no node paths into game/main/Main.gd. Start
## is a signal for whoever owns scene-building (Main) to react to; this script never
## calls Match.start_match() itself, on the host or on a client.

## Emitted when the host presses Start with every peer ready. `config` is the
## sanitized MatchConfig the lobby is currently showing.
signal start_requested(config: MatchConfig)

## Emitted when the player presses the header's Back pill. Whoever owns scene
## transitions (game/main/Main.gd) is the only listener; a signal keeps the "no node
## paths into game/main/Main.gd" boundary intact instead of calling a scene-tree path.
signal back_requested

@export var default_config: MatchConfig = preload("res://config/match/match_defaults.tres")

## The layered-pastel tunable set ui/menus/MainMenu.gd draws its visual style from
## (config/ui/MenuVisualTuning.gd), so the Lobby matches the Main Menu's look with zero
## magic numbers here (CLAUDE.md "No magic numbers").
@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")

## The two columns of the lobby; the settings form itself is the LobbySettingsCard.
const CARD_SETTINGS: String = "SettingsCard"
const CARD_PLAYERS: String = "PlayersCard"

## Sizes and spacings new to the lobby (section spacing, seat colour box, row height,
## advanced indent); also handed to the players panel. Never touches the
## MenuVisualTuning look above.
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/ui/lobby_layout_tuning.tres")

## The lobby-data key of the seat table (LobbySeats: humans + bots
## with colour / team / difficulty), next to "roster". Published by _publish_lobby_data,
## read by _apply_data, and carried across the results screen's republish
## (ResultsScreen.LOBBY_SEATS_KEY points here).
const SEATS_KEY: String = "seats"
## Height counts this many times the sideways distance when a hop picks the stop across panels.
const SPATIAL_HEIGHT_WEIGHT: float = 4.0

## DECISION (ui/lobby/Lobby.gd): same `Variant` test seam as ui/menus/MainMenu.gd and
## ui/hud/HUD.gd's match_provider. The players panel reads the
## same seam (peer ids/info for the roster, local peer id for the "you" subtitle),
## so a swap here is forwarded to it -- tests assign this after _ready().
var net_provider: Variant = null:
	set(value):
		net_provider = value
		if _players_panel != null:
			_players_panel.net_provider = value

## %MapThumbnail is the (hidden) pictogram of the one map; it lives under %HiddenSources.
## The settings form (every other setting control) is the LobbySettingsCard.
@onready var _card: LobbySettingsCard = %LobbySettingsCard
@onready var _map_thumbnail: PanelContainer = %MapThumbnail
var _map_thumbnail_icon: TextureRect = null
## The Players/AI steppers, the default-difficulty dropdown and the
## segmented Teams control left the settings card (seats, bots and teams are
## managed in the players panel). They live on as hidden
## sources of truth under %HiddenSources (the pattern the map combo already uses): every
## read and write of `.value` / `.selected`, the host-only gating, the bot clamp and
## the round trip are unchanged, and the panel drives them (_on_teams_toggled,
## _set_bot_count). They are never focus stops.
## DECISION (ui/lobby/Lobby.gd): with the panel's Teams toggle and "+ Add bot" button now
## the only way to change them, they are no longer a temporary fallback but the
## state holders chosen for the lobby:
## _apply_data() / _clamp_ai_count_to_seats() and every existing lobby test read and
## write them, so removing them would rewrite the whole config round trip (and
## tests/unit/ui/test_lobby.gd's 31 references) for no player-visible change.
@onready var _player_count_spin: SpinBox = %PlayerCountSpin
@onready var _ai_count_spin: SpinBox = %AiCountSpin
@onready var _ai_difficulty_option: UiCycler = %AiDifficultyOption
@onready var _team_mode_option: OptionButton = %TeamModeOption
## The right-hand roster (title row, header text, seat rows) lives in
## ui/lobby/LobbyPlayersPanel.gd; this script keeps only the hooks
## (_publish_lobby_data/_apply_data/_on_roster_changed/_on_start_pressed/
## _update_host_only_state) that feed it. %PlayerList and %PlayerCountLabel are
## the panel's own unique names, so they resolve through %PlayersPanel.
@onready var _players_panel: LobbyPlayersPanel = %PlayersPanel
@onready var _ready_check: CheckButton = %ReadyCheck
@onready var _start_button: Button = %StartButton
@onready var _invite_friends_button: Button = %InviteFriendsButton

@onready var _settings_card: UiPanel = %SettingsCard
@onready var _players_card: UiPanel = %PlayersCard
## the title row is a UiTitleRow (eyebrow, LOBBY, status badge left; Back right,
## all centred on one line, left edge on the card padding); the badge is a UiStatusBadge.
@onready var _header_row: UiTitleRow = %Header
@onready var _status_badge: UiStatusBadge = %StatusBadge
@onready var _header_eyebrow: Label = %Eyebrow
@onready var _back_button: UiBlockButton = %BackButton
## opens the Options overlay. DECISION: it sits in the header beside Back, outside the
## vertical focus loop (like Back)
## (left from Start/Ready, then left again) or the lobby_options shortcut (O / pad Select).
@onready var _options_button: UiBlockButton = %OptionsButton
## components.md footer chip: an uppercase label chip, "3 OF 4 READY".
const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const ALL_READY_TEXT: String = "ALL READY"
const READY_COUNT_FORMAT: String = "%d OF %d READY"
## The bottom-left "Waiting for players * X of Y ready" pill, updated every time the
## players panel rebuilds its rows (_on_roster_rendered()).
@onready var _waiting_status_pill: UiStatusBadge = %WaitingStatusPill

## The hidden seat sources of truth, gated to the host (the settings card gates its own controls).
var _settings_controls: Array[Control] = []

## True while _apply_data() is writing sanitized values back into the
## controls, so the value-changed signals that causes fire without
## re-publishing what was just received (an infinite echo).
var _applying_remote_data: bool = false
var _last_config: MatchConfig = null
## The live OptionsMenu overlay while open, else null; and the callable that
## restores the focus modes UiFocusTrap cleared for it.
var _options_menu: OptionsMenu = null
## the built-once Options window, hidden between opens (see OptionsMenu.present()).
var _options_cache: OptionsMenu = null
var _restore_focus: Callable = Callable()
## Footer buttons' visibility the focus loop was last wired for (_update_host_only_state()).
var _start_was_shown: bool = false
var _ready_was_shown: bool = true
var _invite_was_shown: bool = false
## how many lobby-data applies ran, so a publish can tell its own signal echo.
var _apply_count: int = 0
## the non-Steam internet join-code row (isolated in ui/menus/JoinCodeRow.gd).
var _join_code_row: JoinCodeRow = null


## the two cards are design-system [UiPanel]s (plate, lip, padding; no clip, so the
## ledge shows like the Options window). The scene authors each card's rows as direct children; they
## move into the panel's content column before any @onready lookup runs.
func _enter_tree() -> void:
	for card_name: String in [CARD_SETTINGS, CARD_PLAYERS]:
		var card: UiPanel = find_child(card_name, true, false) as UiPanel
		if card == null:
			continue
		for child: Node in card.get_children():
			if child == card.content.get_parent():
				continue
			child.owner = null
			child.reparent(card.content, false)
			child.owner = self
			(child as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.content.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	# DECISION: a provider assigned before the node enters the tree is kept,
	# so a test can seat a Lobby on a second real Net instance and drive the real entry path.
	if net_provider == null:
		net_provider = Net
	_configure_players_panel()
	_arrange_header()
	_populate_options()
	_settings_controls = [_player_count_spin, _ai_count_spin, _ai_difficulty_option, _team_mode_option]
	_connect_control_signals()
	_start_button.pressed.connect(_on_start_pressed)
	_ready_check.toggled.connect(_on_ready_toggled)
	_invite_friends_button.pressed.connect(_on_invite_friends_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_options_button.pressed.connect(open_options)
	_build_join_code_row()
	_connect_click_and_hover_sounds()
	Events.net_lobby_data_changed.connect(_on_lobby_data_changed)
	Events.net_peer_joined.connect(_on_peer_joined)
	Events.net_peer_left.connect(_on_peer_left)
	Events.net_roster_changed.connect(_on_roster_changed)

	# Returning from results creates a fresh Lobby while Net keeps its hosted
	# session. Read the last published settings so quick edits made there are
	# reflected by the controls and the next Start action.
	var initial_data: Dictionary = net_provider.lobby_data()
	_apply_data(initial_data if not initial_data.is_empty() else default_config.to_dict())
	# the roster and the Ready toggle are views of Net's live state, drawn
	# before anything else can look at them (a cached lobby snapshot is from before the match).
	_show_live_roster()
	_sync_ready_toggle_from_net()
	# Net.host_game() populates its own HOST_PEER_ID roster entry directly and only emits
	# net_mode_changed, not net_roster_changed / a lobby-data publish, so a Lobby scene
	# opened straight after hosting would not see the host's own row until a second peer
	# joined and triggered _on_peer_joined()'s republish. This host-only kick (a no-op for
	# a client, whose _republish_roster_if_host() guard is already false) draws the host's
	# own row on the very first frame.
	_republish_roster_if_host()
	_apply_visual_style()
	_update_host_only_state()
	(_start_button as UiBlockButton).hint_action = &"lobby_confirm"
	_players_panel.add_bot_button().hint_action = &"lobby_add_bot"
	_options_button.hint_action = &"lobby_options"
	_back_button.hint_action = &"ui_cancel"
	_wire_focus_chain()
	_card.focus_entry()
	# the first focus above may have scrolled the column; open at the top.
	_card.scroll_to_top()
	visibility_changed.connect(_on_lobby_visibility_changed)


func _on_lobby_visibility_changed() -> void:
	if is_visible_in_tree():
		_card.scroll_to_top()


func _process(_delta: float) -> void:
	# DECISION (ui/lobby/Lobby.gd): Events.net_roster_changed (added
	# below) tells this screen a peer's ready flag flipped, but Net's
	# aggregate all_peers_ready() is still just a plain method, and deriving
	# the same bool from the roster payload here would duplicate Net's own
	# rule. Refreshing the Start button's gate every frame stays simpler than
	# inventing a second cross-package signal just for that one aggregate.
	# Cheap: two method calls and a bool compare on a screen with a handful
	# of controls.
	_update_host_only_state()


## Hands the players panel everything it renders from (the Lobby's own tunables, the
## per-slot palette, the net seam) and connects its signals -- the narrow Lobby <->
## panel contract documented in ui/lobby/LobbyPlayersPanel.gd. Runs before the first
## _apply_data() so even the first rows are built from the Lobby's own resources.
func _configure_players_panel() -> void:
	_players_card.custom_minimum_size.x = float(layout_tuning.players_card_min_width_px)
	_players_panel.net_provider = net_provider
	_players_panel.tuning = tuning
	_players_panel.layout_tuning = layout_tuning
	_players_panel.palette = default_config.player_colors
	_players_panel.seats_changed.connect(_on_seats_changed)
	_players_panel.teams_toggled.connect(_on_teams_toggled)
	_players_panel.add_bot_requested.connect(_on_add_bot_requested)
	_players_panel.remove_bot_requested.connect(_on_remove_bot_requested)
	_players_panel.roster_rendered.connect(_on_roster_rendered)
	_players_panel.focus_entries_changed.connect(_on_players_focus_entries_changed)


# --- Building settings controls ----------------------------------------------


## The title row: STACKFALL eyebrow, LOBBY and the status badge on the left, Back on the right, all
## centred on one line (UiTitleRow.add_trailing's rule), so the wordmark sits on the card's left edge
## and no item floats above or below the others.
func _arrange_header() -> void:
	_header_row.move_child(_header_eyebrow, 0)
	_header_row.move_child(_status_badge, _header_row.label.get_index() + 1)
	_header_row.move_child(_options_button, -1)
	_header_row.move_child(_back_button, -1)
	for item: Control in [_header_eyebrow, _status_badge, _options_button, _back_button]:
		item.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_eyebrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_expose(_header_row.label, "HeaderTitle")
	_expose(_status_badge.label, "StatusBadgeLabel")
	_expose(_waiting_status_pill.label, "WaitingStatusLabel")
	_status_badge.live = true


## Makes a runtime-built [param node] reachable as `%unique_name` from this screen (what the scene
## would have done had the component been authored with its children).
func _expose(node: Node, unique_name: String) -> void:
	node.name = unique_name
	node.owner = self
	node.unique_name_in_owner = true


## The hidden sources of truth are plain OptionButtons nobody clicks; %AiDifficultyOption (default
## difficulty) is a UiCycler. The visible option rows live in the settings card.
func _populate_options() -> void:
	_decorate_map_picker()
	_fill_cycle(_ai_difficulty_option, ["Easy", "Normal", "Hard"])
	_fill_option(_team_mode_option, ["Off", "2 teams", "3 teams", "4 teams"])


## every map combo row shows its variant's pictogram (UiArtTable) and
## the thumbnail beside the picker shows the selected one. Reads only the selected
## index, so host and client (replicated config) agree.
func _decorate_map_picker() -> void:
	var art: UiArtTable = UiArtTable.shared()
	if _map_thumbnail_icon == null:
		_map_thumbnail_icon = TextureRect.new()
		_map_thumbnail_icon.name = "MapThumbnailIcon"
		_map_thumbnail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map_thumbnail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_map_thumbnail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_map_thumbnail_icon.custom_minimum_size = Vector2.ONE * float(art.map_icon_px)
		_map_thumbnail.add_child(_map_thumbnail_icon)
	_refresh_map_thumbnail()


func _refresh_map_thumbnail() -> void:
	if _map_thumbnail_icon != null:
		_map_thumbnail_icon.texture = UiArtTable.shared().map_pictogram()


func _fill_option(option: OptionButton, labels: Array) -> void:
	option.clear()
	for label: String in labels:
		option.add_item(label)


## The UiCycler twin of _fill_option(): same index order, same stored ints.
func _fill_cycle(selector: UiCycler, labels: Array) -> void:
	selector.clear()
	for label: String in labels:
		selector.add_item(label)


## DECISION: ui/lobby/Lobby.tscn carries zero static focus_neighbor_* NodePaths -- the specials
## checklist is built dynamically and doesn't exist yet when the scene file is authored, so any chain
## covering it has to be computed at runtime. Mirrors ui/menus/OptionsMenu.gd's own
## _wire_focus_chain() (get_path_to()-based circular top/bottom wiring). Player rows (rebuilt by the
## players panel on every roster change) enter the chain through the panel's focus_entries().
##
## ONE closed loop in visual order: the settings card's stops (its sections, Advanced chips and open
## Advanced controls), then the players panel's entries and the footer. The card drops whatever a
## collapsed block, a mode or a master switch hides, and asks for a rebuild on every change
## (layout_changed), so there is never an invisible focus stop.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = _card.focus_stops()
	# The players panel's own focusable controls sit between the settings and the footer, in visual
	# order; the panel asks for a rewire through focus_entries_changed.
	_settings_stops = chain.duplicate()
	chain.append_array(_players_panel.focus_entries())
	chain.append(_invite_friends_button)
	if _join_code_row != null:
		chain.append(_join_code_row.copy_button())
	chain.append_array([_ready_check, _start_button])
	_main_chain = chain
	_rewire_focus()


## The settings card showed or hid a row, section or Advanced block: its stops changed.
func _on_card_layout_changed() -> void:
	if not _main_chain.is_empty():
		_wire_focus_chain()


## Rewires the main loop from the chain built by _wire_focus_chain(): called on every
## state change that can hide or show a stop (a section or Advanced toggle, a game
## mode change, the panel's entries) -- never per frame (_process only gates
## editability). A no-op until the first build.
func _rewire_focus() -> void:
	if _main_chain.is_empty():
		return
	_wire_loop(_visible_chain(_main_chain))
	_wire_back_button(_visible_chain(_main_chain))
	# The spatial pass needs settled rects: it runs one frame later, never in this call.
	_schedule_spatial_rewire()


## The loop above is vertical list order; this pass overrides the neighbours
## that must follow the DRAWN layout, from the real global rects: the gift / experiment chip grids
## move in 2D, the players panel's rows move by column (down from a colour diamond = the diamond
## below, the last row = Add bot, up reverses) and the settings column <-> players panel hops are
## symmetric (the nearest stop by height). Layout-dependent, so it also runs one frame after every
## rewire (_schedule_spatial_rewire) and when the settings column scrolls.
func _wire_spatial() -> void:
	if _main_chain.is_empty() or size.x <= 0.0 or _players_panel.size.x <= 0.0:
		return  # not laid out yet: the deferred pass runs once the rects exist
	var settings: Array[Control] = _visible_chain(_settings_stops)
	var panel: Array[Control] = _visible_chain(_players_panel.focus_entries())
	var panel_left_edge: Array[Control] = []
	if not panel.is_empty() and _all_laid_out(panel):
		panel_left_edge = _wire_panel_spatial(panel, settings)
	# The gift / experiment chips form grids (one per parent container) that move in 2D.
	var grids: Dictionary[Node, Array] = {}
	for control: Control in settings:
		var chip: UiChipToggle = control as UiChipToggle
		if chip != null:
			grids.get_or_add(chip.get_parent(), [] as Array).append(chip)
	for grid: Array in grids.values():
		var chips: Array[Control] = []
		chips.assign(grid)
		if _all_laid_out(chips):
			_wire_chip_grid(chips, panel_left_edge)
	# Every other settings stop hops right into the panel (the chips handled theirs above).
	for control: Control in settings:
		if control is UiChipToggle:
			continue
		var target: Control = _nearest_by_height(control, panel_left_edge)
		if target != null and control.size.y > 0.0:
			control.focus_neighbor_right = control.get_path_to(target)


## Chips of one grid: up / down / left / right by position. A side with no chip keeps the list loop
## (up from the top row = the Advanced chip, down from the bottom row = what follows the list), and
## the right edge hops into the players panel.
func _wire_chip_grid(chips: Array[Control], panel_edge: Array[Control]) -> void:
	if chips.is_empty():
		return
	var up_exit: Control = chips[0].get_node_or_null(chips[0].focus_neighbor_top) as Control
	var down_exit: Control = chips[chips.size() - 1].get_node_or_null(chips[chips.size() - 1].focus_neighbor_bottom) as Control
	UiSpatialFocus.wire(chips, false)
	for chip: Control in chips:
		if _neighbor(chip, SIDE_TOP) == chip and up_exit != null:
			chip.focus_neighbor_top = chip.get_path_to(up_exit)
		if _neighbor(chip, SIDE_BOTTOM) == chip and down_exit != null:
			chip.focus_neighbor_bottom = chip.get_path_to(down_exit)
		if _neighbor(chip, SIDE_RIGHT) == chip:
			var target: Control = _nearest_by_height(chip, panel_edge)
			if target != null:
				chip.focus_neighbor_right = chip.get_path_to(target)


## The players panel: up / down by column, left / right keep the row wiring (LobbySeatRow), a row's
## left edge hops to the settings column. Returns the panel's left-edge stops.
func _wire_panel_spatial(panel: Array[Control], settings: Array[Control]) -> Array[Control]:
	var saved_left: Dictionary = {}
	var saved_right: Dictionary = {}
	for control: Control in panel:
		saved_left[control] = control.focus_neighbor_left
		saved_right[control] = control.focus_neighbor_right
	var up_exit: Control = panel[0].get_node_or_null(panel[0].focus_neighbor_top) as Control
	var last: Control = panel[panel.size() - 1]
	var down_exit: Control = last.get_node_or_null(last.focus_neighbor_bottom) as Control
	UiSpatialFocus.wire(panel, false)
	var edge: Array[Control] = []
	for control: Control in panel:
		control.focus_neighbor_left = saved_left[control]
		control.focus_neighbor_right = saved_right[control]
		if _neighbor(control, SIDE_TOP) == control and up_exit != null:
			control.focus_neighbor_top = control.get_path_to(up_exit)
		if _neighbor(control, SIDE_BOTTOM) == control and down_exit != null:
			control.focus_neighbor_bottom = control.get_path_to(down_exit)
		var left: Control = _neighbor(control, SIDE_LEFT)
		# Idempotent: a left that an earlier pass pointed at the settings column is still an edge.
		if left == null or left == control or not panel.has(left):
			edge.append(control)
	for control: Control in edge:
		var target: Control = _nearest_by_height(control, settings)
		if target != null:
			control.focus_neighbor_left = control.get_path_to(target)
	# Up from Add bot reverses the move down from the last row's first control.
	if panel.has(_add_bot_target()):
		var add_bot: Control = _add_bot_target()
		for control: Control in panel:
			if control != add_bot and _neighbor(control, SIDE_BOTTOM) == add_bot and edge.has(control):
				add_bot.focus_neighbor_top = add_bot.get_path_to(control)
	return edge


## True when every control has a real size (the layout pass has run for it).
func _all_laid_out(controls: Array[Control]) -> bool:
	for control: Control in controls:
		if control.size.x <= 0.0 or control.size.y <= 0.0:
			return false
	return true


func _add_bot_target() -> Control:
	return _players_panel.add_bot_button()


func _neighbor(control: Control, side: Side) -> Control:
	var path: NodePath = control.get_focus_neighbor(side)
	if path.is_empty():
		return null
	return control.get_node_or_null(path) as Control


## The stop in [param candidates] whose centre is nearest [param from]'s by height (ties: nearest
## along the row).
func _nearest_by_height(from: Control, candidates: Array[Control]) -> Control:
	var origin: Vector2 = from.get_global_rect().get_center()
	var best: Control = null
	var best_score: float = INF
	for other: Control in candidates:
		if other == from:
			continue
		var delta: Vector2 = other.get_global_rect().get_center() - origin
		var score: float = absf(delta.y) * SPATIAL_HEIGHT_WEIGHT + absf(delta.x)
		if score < best_score:
			best_score = score
			best = other
	return best


## Layout rects settle after the frame that changed the rows / sections: rewire once more then.
func _schedule_spatial_rewire() -> void:
	if _spatial_pending or not is_inside_tree():
		return
	_spatial_pending = true
	# A one-shot connection (not an await) so a lobby freed meanwhile just drops it.
	get_tree().process_frame.connect(_run_spatial_rewire, CONNECT_ONE_SHOT)


func _run_spatial_rewire() -> void:
	_spatial_pending = false
	if is_inside_tree() and not _main_chain.is_empty():
		# Back to the plain loop first, so the spatial pass always starts from list order.
		_wire_loop(_visible_chain(_main_chain))
		_wire_back_button(_visible_chain(_main_chain))
		_wire_spatial()


## Every control the focus loop may visit, in visual order (built by _wire_focus_chain());
## _visible_chain() filters it to what is shown right now.
var _main_chain: Array[Control] = []
## The settings column's stops (the part of _main_chain before the players panel's entries).
var _settings_stops: Array[Control] = []
var _spatial_pending: bool = false


## A control is a focus stop only while it and every ancestor up to
## this screen are visible -- a collapsed section or Advanced block, a hidden
## conditional column (the Reach the Sky toggle outside its mode, the timer column
## the mode does not use, goal flags in a mode without them) and the hidden
## SpinBox/OptionButton sources of truth all drop out, so gamepad focus can never
## land on an invisible control. (Visibility is judged relative to this screen, not
## is_visible_in_tree(), so the loop is the same whatever shows the lobby.)
func _visible_chain(chain: Array[Control]) -> Array[Control]:
	var out: Array[Control] = []
	for control: Control in chain:
		if _is_shown(control):
			out.append(control)
	return out


func _is_shown(control: Control) -> bool:
	var node: Node = control
	while node != null and node != self:
		var item: CanvasItem = node as CanvasItem
		if item != null and not item.visible:
			return false
		node = node.get_parent()
	return true


## Assigns focus_neighbor_top/bottom so [param chain] forms one closed loop,
## wrapping from its last entry back to its first.
func _wire_loop(chain: Array[Control]) -> void:
	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL


## Back is NOT a stop of the vertical loop (a down from Add bot reaching it made players
## back out of the lobby by accident). It is reached deliberately: left from
## the loop's last stop (Start for the host, Ready for a client) or B / Esc. From Back, up / down /
## left / right return to the top of the settings column, so nothing wraps into it.
func _wire_back_button(chain: Array[Control]) -> void:
	if chain.is_empty():
		return
	_back_button.focus_mode = Control.FOCUS_ALL
	var entry_control: Control = chain[0]
	var entry: NodePath = _back_button.get_path_to(entry_control)
	_back_button.focus_neighbor_top = entry
	_back_button.focus_neighbor_bottom = entry
	_back_button.focus_neighbor_left = _back_button.get_path_to(_options_button)
	_back_button.focus_neighbor_right = entry
	_options_button.focus_mode = Control.FOCUS_ALL
	_options_button.focus_neighbor_top = _options_button.get_path_to(entry_control)
	_options_button.focus_neighbor_bottom = _options_button.get_path_to(entry_control)
	_options_button.focus_neighbor_left = _options_button.get_path_to(entry_control)
	_options_button.focus_neighbor_right = _options_button.get_path_to(_back_button)
	var last: Control = chain[chain.size() - 1]
	last.focus_neighbor_left = last.get_path_to(_back_button)


func _connect_control_signals() -> void:
	_card.changed.connect(_on_setting_changed)
	_card.layout_changed.connect(_on_card_layout_changed)
	_card.scrolled.connect(_schedule_spatial_rewire)
	_ai_difficulty_option.item_selected.connect(_on_option_changed)
	_team_mode_option.item_selected.connect(_on_option_changed)
	_player_count_spin.value_changed.connect(_on_value_changed)
	# A seat-count edit can shrink the room left for bots, so this recomputes %AiCountSpin's own
	# max_value on every host edit too, not only on a roster event (_on_roster_changed already covers
	# "a human joined/left"; this covers "the host changed the seat count").
	_player_count_spin.value_changed.connect(func(_v: float) -> void: _clamp_ai_count_to_seats())
	_ai_count_spin.value_changed.connect(_on_value_changed)


## UI button press/hover has no Events signal of its
## own (it isn't gameplay), so this calls Sfx directly -- the one named
## exception to "Sfx listens, nothing calls it" (autoload/Sfx.gd's header).
## Scoped to actual buttons, not every settings control, so dragging a
## slider doesn't spam hover sounds. DECISION: the ready toggle
## is not here -- it has its own ready_on/ready_off cue (no double click).
func _connect_click_and_hover_sounds() -> void:
	var buttons: Array[BaseButton] = [_start_button, _invite_friends_button, _options_button, _back_button]
	for button: BaseButton in buttons:
		button.pressed.connect(_on_sound_button_pressed)
		button.mouse_entered.connect(_on_sound_button_hovered)


func _on_sound_button_pressed() -> void:
	Sfx.play(AudioConfig.EVENT_CLICK)


func _on_sound_button_hovered() -> void:
	Sfx.play(AudioConfig.EVENT_HOVER)


## Mirrors ui/menus/MainMenu.gd's _apply_visual_style(): the
## same cream-card + pastel-pill language, built entirely from ui/theme/
## MenuStyleFactory.gd's StyleBoxFlat helpers on top of the shared
## ui/theme/stackfall_theme.tres Theme (no image assets).
##
## DECISION (ui/lobby/Lobby.gd): mockup 11 shows each column as a
## front card with two peeking mint/apricot "shadow" cards behind it, the
## same triple-stack ui/menus/MainMenu.gd's %ShadowApricot/%ShadowMint achieve via
## a CenterContainer sized to each child's own minimum size. ui/lobby/Lobby.tscn's
## "Settings"/"Players" columns instead need size_flags_horizontal/vertical
## = 3 to fill the available width of their HBoxContainer ("Columns"), which
## a CenterContainer would collapse back down to minimum size -- so this
## keeps a single flat cream PanelContainer card per column (no doubled
## shadow cards) rather than risk breaking that fill layout within the
## remaining verification budget (a known simplification versus the mockup).
##
## DECISION (ui/lobby/Lobby.gd): the header has a real Back pill, since a decorative button
## with no listener would be worse than none. %BackButton emits back_requested (the signal just above start_requested)
## instead of calling into game/main/Main.gd directly -- keeping this file's own "no node paths into
## game/main/Main.gd" rule intact while giving Main.gd something to connect to.
func _apply_visual_style() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	# The Ready toggle (a client's footer control) keeps its chip look until the footer migrates.
	MenuStyleFactory.apply_toggle_chip(
		_ready_check, tuning.pill_cream_color, tuning.pill_cream_hover_color,
		tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
	)
	# A full-size UiBlockButton fills its cell; START MATCH keeps its own height in the bar.
	_start_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Arcade: the lobby sits on the same arena image as the main menu under a
	# full-screen disc-900 scrim (components.md Screens: "over the scrimmed arena"), so the title
	# row is plain cream text and the StatusBadge a flat disc-700 label with a live mint dot.
	(%Scrim as ColorRect).color = Color(arcade.disc_900_color, arcade.scrim_alpha)
	_header_eyebrow.add_theme_color_override("font_color", arcade.cream_color)
	_header_eyebrow.add_theme_font_size_override("font_size", arcade.font_size_button_px)
	_players_panel.apply_visual_style()
	_update_status_badge()


## Gamepad/keyboard shortcuts and back-out:
## - lobby_quick_advanced (Y) opens/closes the Advanced block of the section holding focus
##   (the first section with one when focus is elsewhere or in a section without one);
## - lobby_add_bot (X) adds a bot (host, a seat free); Start / Enter (lobby_confirm) starts or toggles Ready;
## - ui_cancel (Esc / gamepad B) backs out of the lobby, same as %BackButton. (An open
##   OptionButton popup consumes its own ui_cancel before this runs.)
## B backs out even when no popup is open.
func _unhandled_input(event: InputEvent) -> void:
	if _options_menu != null:
		return
	if event.is_action_pressed(&"lobby_options"):
		open_options()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"lobby_quick_advanced"):
		_card.toggle_focused_advanced()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"lobby_add_bot"):
		# DECISION: X / keyboard X adds a bot -- host only, only while a seat is free.
		_run_add_bot_shortcut()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	_on_back_pressed()
	get_viewport().set_input_as_handled()


## Enter / KP Enter / pad Start (lobby_confirm) act from any focus, so it is
## taken in _input, before the focused Button's ui_accept. Left alone while a text field has
## focus or an OptionButton popup is open. Space still activates the focused control.
func _input(event: InputEvent) -> void:
	if _options_menu != null or not is_visible_in_tree() or not event.is_action_pressed(&"lobby_confirm"):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	for option: OptionButton in [_team_mode_option]:
		if option.get_popup().visible:
			return
	_run_start_shortcut()
	get_viewport().set_input_as_handled()


## Host: add a bot when the open seat's button would be usable (visible, enabled), otherwise nothing.
func _run_add_bot_shortcut() -> void:
	if not is_visible_in_tree() or not _is_host_session():
		return
	var add_bot: UiBlockButton = _players_panel.add_bot_button()
	if add_bot.visible and not add_bot.disabled:
		_on_add_bot_requested()


## Host: start when usable (same gate as _on_start_pressed), otherwise nothing.
## DECISION: a client's Start/Enter toggles its own Ready, the same path
## as the ReadyCheck button, so the one shortcut is the lobby's "confirm" for every seat.
func _run_start_shortcut() -> void:
	if _ready_check.visible:
		_ready_check.button_pressed = not _ready_check.button_pressed
	elif _start_button.visible and not _start_button.disabled:
		_on_start_pressed()


## shows the Options screen over the lobby (same build/free pattern as MainMenu).
## Lobby networking keeps running (this node keeps processing); focus outside the overlay is
## suspended so pad / arrows never reach the lobby, and returns to the Options button on close.
func open_options() -> void:
	if _options_menu != null:
		return
	var first_open: bool = _options_cache == null
	if first_open:
		_options_cache = OPTIONS_MENU_SCENE.instantiate() as OptionsMenu
	_options_menu = _options_cache
	if first_open:
		add_child(_options_menu)
	else:
		_options_menu.present()
	_restore_focus = UiFocusTrap.suspend_outside(_options_menu, self)
	if not _options_menu.closed.is_connected(_on_options_closed):
		_options_menu.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	if _options_menu != null:
		_options_menu.dismiss()
		_options_menu = null
	if _restore_focus.is_valid():
		_restore_focus.call()
		_restore_focus = Callable()
	_options_button.grab_focus()


func _on_back_pressed() -> void:
	back_requested.emit()


func _on_option_changed(_index: int) -> void:
	_on_setting_changed()


func _on_value_changed(_value: float) -> void:
	_on_setting_changed()


## The one place a host's edit turns into a publish
func _on_setting_changed() -> void:
	if _applying_remote_data:
		return
	if net_provider == null or not bool(net_provider.is_host()):
		return
	_publish_lobby_data(_config_from_controls())


func _publish_lobby_data(config: MatchConfig) -> void:
	config.sanitize()
	var data: Dictionary = config.to_dict()
	data["roster"] = _players_panel.build_roster(config)
	# The seat table (per-seat colour/team/difficulty) is
	# lobby data next to the roster, not a MatchConfig field; an empty table writes no
	# key, so a lobby without one publishes the exact dict it always did.
	var seats: Dictionary = _players_panel.seats_data()
	if not seats.is_empty():
		data[SEATS_KEY] = seats
	var applies_before: int = _apply_count
	net_provider.set_lobby_data(data)
	# DECISION: the host's Net emits net_lobby_data_changed from set_lobby_data(),
	# which _on_lobby_data_changed() already applied (the same dictionary); applying it a second time
	# only rebuilt the rows again. A provider that does not emit (a test double) still gets its apply.
	if _apply_count == applies_before:
		_apply_data(data)


func _config_from_controls() -> MatchConfig:
	var config: MatchConfig = _card.config()
	config.player_count = int(_player_count_spin.value)
	config.ai_count = int(_ai_count_spin.value)
	config.ai_difficulty = _ai_difficulty_option.selected()
	config.team_mode = _team_mode_option.selected
	config.bot_names = _reconciled_bot_names(config.ai_count)
	return config


## the host's bot names, by bot ordinal. Assigned the moment a bot
## seat exists (so the lobby and the match show the same name), replicated in the
## published MatchConfig.bot_names, and reused by Match.start_match.
var _bot_names: PackedStringArray = PackedStringArray()


## Keeps the names still valid, drops those of removed seats, draws fresh distinct
## ones (not any human's name, not another bot's) for new seats.
func _reconciled_bot_names(bot_count: int) -> PackedStringArray:
	var human_names: PackedStringArray = PackedStringArray()
	if net_provider != null:
		for peer_id: int in net_provider.peer_ids():
			human_names.append(str(net_provider.peer_info(peer_id).get(LobbySeats.FIELD_NAME, "")))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	_bot_names = BotNames.assign(_bot_names, bot_count, human_names, rng)
	return _bot_names.duplicate()



## Applies a Dictionary from Events.net_lobby_data_changed (or the initial
## default) to every control. Always goes through MatchConfig.from_dict() and
## sanitize(), so a value outside its spec 1.9 range is clamped rather than
## trusted, whether it came from the wire or from this instance's own publish.
func _apply_data(data: Dictionary) -> void:
	_apply_count += 1
	var config: MatchConfig = MatchConfig.from_dict(data)
	config.sanitize()
	_last_config = config
	_bot_names = config.bot_names.duplicate()

	_applying_remote_data = true
	_refresh_map_thumbnail()
	_player_count_spin.value = config.player_count
	_ai_count_spin.value = config.ai_count
	_ai_difficulty_option.select(config.ai_difficulty)
	_team_mode_option.selected = config.team_mode
	_applying_remote_data = false
	_card.apply(config)
	_update_host_only_state()
	# Re-bound %AiCountSpin's max after every value assignment above (player_count and ai_count both
	# just moved, possibly from a wire value that predates this clamp); see
	# _clamp_ai_count_to_seats()'s header for why this can't live in _mirror_player_count_to_peers().
	_clamp_ai_count_to_seats()

	# The panel gets the applied config, the dict's roster (null
	# when it carried none: the rows stay) and its seat table ({} when absent or not a
	# Dictionary off the wire).
	var seats_variant: Variant = data.get(SEATS_KEY, {})
	var seats: Dictionary = seats_variant as Dictionary if seats_variant is Dictionary else {}
	_players_panel.apply(config, data["roster"] if data.has("roster") else null, seats)


func _on_lobby_data_changed(data: Dictionary) -> void:
	_apply_data(data)


## The panel's seat table changed (colour, team pick, bot
## difficulty). Republishes like any other host edit, so the dict carries
## _players_panel.seats_data(); a client's edit travels as an intent instead.
func _on_seats_changed() -> void:
	_on_setting_changed()


## The Teams toggle. DECISION (ui/lobby/Lobby.gd): the toggle writes only
## OFF or TEAMS_4 ("on, up to 4 teams") into the hidden %TeamModeOption, the
## source of truth for config.team_mode; older TEAMS_2/3 data stays valid when it
## arrives. Host only: a client's controls are read-only.
## The panel's Teams toggle emits teams_toggled (it re-seeded its team picks first);
## %TeamModeOption stays hidden-but-functional (see the %HiddenSources DECISION above), so
## lobby data carrying a team_mode round-trips unchanged.
func _on_teams_toggled(enabled: bool) -> void:
	if not _is_host_session():
		return
	_team_mode_option.selected = MatchConfig.TeamMode.TEAMS_4 if enabled else MatchConfig.TeamMode.OFF
	_on_setting_changed()


func _on_add_bot_requested() -> void:
	var before: int = int(_ai_count_spin.value)
	_set_bot_count(before + 1)
	if int(_ai_count_spin.value) > before:
		Events.lobby_ui_cue.emit(&"bot_added")


func _on_remove_bot_requested(ordinal: int) -> void:
	# the removed bot's name is freed; later bots keep theirs.
	if ordinal >= 0 and ordinal < _bot_names.size():
		_bot_names.remove_at(ordinal)
	var before: int = int(_ai_count_spin.value)
	_set_bot_count(maxi(0, before - 1))
	if int(_ai_count_spin.value) < before:
		Events.lobby_ui_cue.emit(&"bot_removed")


## Add/remove bot through the hidden spins, so the existing clamps and the one
## publish path stay the only rules. DECISION (ui/lobby/Lobby.gd): the seat
## count follows humans + bots (never below the 2-seat minimum), the same rule
## _mirror_player_count_to_peers() applies on every roster event; a request that
## would exceed the seat cap does nothing. The seat spin moves first when growing
## (so the bot spin's max rises before it is set) and last when shrinking.
func _set_bot_count(new_ai_count: int) -> void:
	if not _is_host_session():
		return
	var humans: int = net_provider.peer_ids().size()
	var seats: int = clampi(humans + new_ai_count, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	if humans + new_ai_count > seats:
		return
	if seats >= int(_player_count_spin.value):
		_player_count_spin.value = seats
		_ai_count_spin.value = new_ai_count
	else:
		_ai_count_spin.value = new_ai_count
		_player_count_spin.value = seats


## The panel rebuilt its rows: feeds mockup 11's bottom-left "Waiting for players *
## 3 of 4 ready" pill, derived from the exact rows just drawn rather than a second
## net_provider query.
func _on_roster_rendered(ready_count: int, row_count: int) -> void:
	# DECISION: the host counts as ready (see LobbyPlayersPanel._render), and once
	# every seat is ready the pill says so instead of "Waiting for players * 2 of 2 ready".
	if row_count > 0 and ready_count >= row_count:
		_waiting_status_pill.text = ALL_READY_TEXT
		return
	_waiting_status_pill.text = READY_COUNT_FORMAT % [ready_count, row_count]


## The panel's focusable controls changed: rewire the loop (only once the first
## wiring exists -- _ready() builds it after every dynamic row).
func _on_players_focus_entries_changed() -> void:
	if not _main_chain.is_empty():
		_wire_focus_chain()


func _is_host_session() -> bool:
	return net_provider != null and bool(net_provider.is_host())


# --- Player list / ready / start --------------------------------------------

## DECISION (ui/lobby/Lobby.gd): Events.net_roster_changed's payload
## is the roster Net just built (autoload/Net.gd's _broadcast_roster() /
## _rpc_roster_update()), so this applies it straight to the rows rather than
## re-deriving one from net_provider.peer_ids()/peer_info() the way
## LobbyPlayersPanel.build_roster() does for the host's own outbound publish — one less round
## trip, and it is the single source of truth for "what does the list show
## right now" (net_lobby_data_changed's own embedded roster only matters for
## the late-joiner snapshot _apply_data() already handles).
## The rows themselves are the players panel's
## (on_roster_changed); the spin mirror and the bot clamp stay here.
func _on_roster_changed(roster: Array[Dictionary]) -> void:
	_mirror_player_count_to_peers(roster.size())
	# A human joining/leaving changes how many seats are left
	# for bots even when the host never touches %PlayerCountSpin itself (e.g.
	# player_count already sits above the connected-peer count to leave bot
	# headroom) -- _mirror_player_count_to_peers() above only republishes the
	# spin when the seat count itself needs to move, so this clamp call is
	# not redundant with it.
	_clamp_ai_count_to_seats()
	_players_panel.on_roster_changed(roster)
	_sync_ready_toggle_from_net()


func _on_peer_joined(_peer_id: int, _slot_id: int, _player_name: String) -> void:
	_republish_roster_if_host()


func _on_peer_left(_peer_id: int, _slot_id: int, _reason: int) -> void:
	_republish_roster_if_host()


func _republish_roster_if_host() -> void:
	if net_provider != null and bool(net_provider.is_host()):
		var republish: MatchConfig = _last_config if _last_config != null else _config_from_controls()
		# bots seeded before the lobby opened (Vs bots) carry no names yet;
		# name them here so the first roster never falls back to "Bot n".
		republish.bot_names = _reconciled_bot_names(republish.ai_count)
		_publish_lobby_data(republish)


## A player_count above the number of connected peers leaves a
## slot nobody holds (see MatchConfig.clamp_to_connected_peers()'s matching
## DECISION); _on_start_pressed() below is the authoritative clamp (it runs
## even if a roster event was somehow missed), so this is display-only —
## keeping the spin from ever *showing* a count the match is about to
## override the moment Start is pressed.
##
## DECISION (ui/lobby/Lobby.gd): the seat count mirrors
## MatchConfig.clamp_to_connected_peers()'s own "humans outrank bots, but an existing
## bot count is preserved if there's room" rule: it only ever grows to admit every
## connected human, and shrinks no further than the greater of the peer count or
## (peers + existing bots). Forcing it to the peer count outright would erase any seat
## headroom a host had set aside for bots (seats == humans => 0 room left) on every
## join/leave.
func _mirror_player_count_to_peers(peer_count: int) -> void:
	if net_provider == null or not bool(net_provider.is_host()):
		return
	var wanted_total: int = clampi(peer_count + int(_ai_count_spin.value), peer_count, MatchConfig.PLAYER_COUNT_MAX)
	var target: int = clampi(wanted_total, MatchConfig.PLAYER_COUNT_MIN, MatchConfig.PLAYER_COUNT_MAX)
	if int(_player_count_spin.value) != target:
		_player_count_spin.value = target


## Without a bound, the bot count could silently exceed the number of empty seats --
## nothing stopped ai_count + connected humans from exceeding player_count.
## Recomputes %AiCountSpin's own max_value from the current seat count minus
## the connected-peer count; Range.set_max() re-clamps a current value above
## the new max on its own (Godot core, `Range::set_max` calls `set_value()`),
## so this is the single place that both bounds future edits and corrects an
## already-too-high value the moment seats shrink or a human joins. Called
## from _mirror_player_count_to_peers()'s own callers (a roster event) and
## from every %PlayerCountSpin edit (_connect_control_signals()) and
## _apply_data() (so a value that arrives over the wire is bounded here too,
## on host and client alike -- harmless on a client since its controls are
## already disabled).
func _clamp_ai_count_to_seats() -> void:
	if net_provider == null:
		return
	var seats: int = int(_player_count_spin.value)
	var humans: int = net_provider.peer_ids().size()
	_ai_count_spin.max_value = maxi(0, seats - humans)


## the Ready toggle is a VIEW of Net's per-peer ready flag, never a second copy
## of it. Net owns the flag (host: set_peer_ready(); client: the host's roster) and the rule that
## clears it when the session returns to the lobby (Net.set_match_in_progress(false));
## this only reads it -- on entry and on every
## roster refresh, host and client alike -- and draws it with set_pressed_no_signal(), so a view
## update is neither a press (no cue) nor a write back into Net (no echo).
## DECISION: the flag read is Net's own peer_info() of the local peer, not the roster payload, so
## the toggle can never differ from what Net itself says. A press whose host confirmation is still
## in flight reads as the old flag until the host's roster lands: the toggle shows what the host
## recorded, not what was asked.
func _sync_ready_toggle_from_net() -> void:
	if net_provider == null:
		return
	var own: Dictionary = net_provider.peer_info(net_provider.local_peer_id())
	_ready_check.set_pressed_no_signal(bool(own.get(LobbySeats.FIELD_READY, false)))


## draws Net's live roster into the players panel on entry. A client's cached
## lobby data (Net.lobby_data()) embeds the roster as it was when the host last published --
## before a match, with that match's ready flags -- and nothing redraws it until the next roster
## event; Net's own peers are never older than that snapshot. Nothing is drawn while Net holds no
## peers (a session still handshaking): the lobby data's roster stays the only source then.
func _show_live_roster() -> void:
	if net_provider == null:
		return
	var live: Array[Dictionary] = []
	for peer_id: int in net_provider.peer_ids():
		live.append(net_provider.peer_info(peer_id))
	if not live.is_empty():
		_players_panel.on_roster_changed(live)


func _on_ready_toggled(pressed: bool) -> void:
	Events.lobby_ui_cue.emit(&"ready_on" if pressed else &"ready_off")
	if net_provider != null:
		net_provider.set_local_ready(pressed)


func _on_start_pressed() -> void:
	if net_provider == null or not bool(net_provider.is_host()) or not bool(net_provider.all_peers_ready()):
		return
	# The Start button is already disabled while
	# the panel names a blocker, but the X shortcut and a direct call skip the
	# button -- so the gate is rechecked here.
	if _players_panel.start_blocker() != "":
		return
	var config: MatchConfig = (
		_last_config if _last_config != null else _config_from_controls()
	).duplicate(true) as MatchConfig
	# DECISION: the numeric experiment parameters in _last_config.qol were copied at the last
	# publish; re-fold the toggles onto the shared resource now so an F4 edit made while the lobby
	# was open takes effect. The start config always carries a non-null qol, so MatchLifecycle
	# keeps the lobby's choice instead of snapshotting F4.
	config.qol = _card.config().qol
	# DECISION (ui/lobby/Lobby.gd): the authoritative peer-count
	# clamp lives here rather than in autoload/Match.gd's start_match() (the
	# spec/plan's stated preference) because Match.start_match() is also the
	# exact call tests/unit/match/test_match_lifecycle.gd drives through
	# game/main/Main.gd's real (peerless) hosted Net session with player_count
	# values chosen to differ from the connected peer count on purpose, to
	# prove the *world-rebuild* dance across repeated starts -- a concern
	# orthogonal to "no phantom slots" that a Match-level clamp would have
	# broken. ui/lobby/Lobby.gd's own Start button is the one call site that both
	# is exclusively the real product path (game/main/Main.gd never calls
	# start_match() for networked play except from here) and already knows
	# how many peers are actually connected, so the clamp runs here and
	# Match.start_match() is left exactly as it was.
	config.clamp_to_connected_peers(net_provider.peer_ids().size())
	# The panel resolves/flattens its seat picks
	# into the start config only AFTER the clamp above -- MatchConfig.sanitize()
	# silently drops team arrays whose length differs from player_count, and the
	# clamp is what settles player_count/ai_count. It reconciles the seat table with
	# Net's CURRENT slot map first (slots move on a lobby leave/kick) and returns the reason
	# when the seats cannot become match slots; the config is then untouched and nothing
	# starts.
	if _players_panel.finalize_start_config(config) != "":
		return
	Sfx.play(AudioConfig.EVENT_START_GAME)
	start_requested.emit(config)


## Opens the Steam overlay's invite dialog.
## `net_provider.invite_friends()` is called here — never a raw Steam call —
## the same discipline every other button handler in this file keeps.
func _on_invite_friends_pressed() -> void:
	if net_provider != null:
		net_provider.invite_friends()


## appends the join-code row under the footer buttons (the footer stays directly under the panel).
func _build_join_code_row() -> void:
	var footer: Node = _invite_friends_button.get_parent()
	var column: Node = footer.get_parent()
	_join_code_row = JoinCodeRow.new()
	_join_code_row.name = "JoinCodeRow"
	column.add_child(_join_code_row)
	_join_code_row.visibility_changed_for_focus.connect(_rewire_focus)


# --- Host/client control gating ----------------------------------------------

func _update_host_only_state() -> void:
	var is_host: bool = net_provider != null and bool(net_provider.is_host())
	for control: Control in _settings_controls:
		_set_control_editable(control, is_host)
	_card.set_editable(is_host)
	_players_panel.set_editable(is_host)
	# A start blocker (e.g. teams on and every
	# seat on one team) disables Start and is shown under the rows (LobbyPlayersPanel); "" when
	# nothing blocks.
	var start_blocker: String = _players_panel.start_blocker() if is_host else ""
	_start_button.visible = is_host
	# DECISION: the host's Start button is its consent -- Net.all_peers_ready()
	# already waits for every OTHER peer only -- so the host's own Ready toggle is redundant and
	# hidden; a client keeps its toggle. Start itself still goes out through start_requested.
	_ready_check.visible = not is_host
	_start_button.disabled = (
		not is_host or not (net_provider != null and bool(net_provider.all_peers_ready())) or start_blocker != ""
	)
	_invite_friends_button.visible = is_host and net_provider != null and bool(net_provider.is_steam_session())
	if _join_code_row != null:
		_join_code_row.refresh(net_provider, is_host)
	# Start and Invite Friends are focus stops only while shown, so
	# the loop is rewired when their visibility flips (a role or transport change), not
	# every frame.
	if (
		_start_button.visible != _start_was_shown or _invite_friends_button.visible != _invite_was_shown
		or _ready_check.visible != _ready_was_shown
	):
		_ready_was_shown = _ready_check.visible
		_start_was_shown = _start_button.visible
		_invite_was_shown = _invite_friends_button.visible
		_rewire_focus()
	_update_status_badge()


const BADGE_VS_BOTS: String = "Vs bots"


## Host edits, client reads: each component family has its own switch (only written when it changes,
## because _process() calls this every frame and a stepper / meter repaints on every write).
func _set_control_editable(control: Control, editable: bool) -> void:
	if control is UiCycler:
		var cycler: UiCycler = control as UiCycler
		if cycler.disabled == editable:
			cycler.disabled = not editable
	elif control is Range:
		control.set("editable", editable)
	elif control is BaseButton:
		(control as BaseButton).disabled = not editable


## Header badge (mockup 11's top-right "Hosting * LAN"
## pill): reads the same net_provider calls _update_host_only_state() above
## already gates on, so it never assumes a transport (CLAUDE.md
## "Multiplayer"). Runs every _update_host_only_state() call (once per
## _process() frame, see that method's own DECISION) -- cheap, a Dictionary-
## free string format on two bools.
func _update_status_badge() -> void:
	if net_provider == null:
		return
	var is_host: bool = bool(net_provider.is_host())
	var is_steam: bool = bool(net_provider.is_steam_session())
	var is_private: bool = net_provider.has_method(&"is_private_session") and bool(net_provider.is_private_session())
	_status_badge.text = status_badge_text(is_host, is_steam, is_private).to_upper()


## The header badge text: "Vs bots" for a private local session, else "Hosting/Joined * Steam/LAN".
static func status_badge_text(is_host: bool, is_steam: bool, is_private: bool) -> String:
	if is_private:
		return BADGE_VS_BOTS
	return "%s %s %s" % ["Hosting" if is_host else "Joined", char(0xB7), "Steam" if is_steam else "LAN"]
