class_name HudPlayerLookup
extends RefCounted
## Slot and team lookups for the HUD (colour, name, team, elimination). With no match config every slot is its own team.

## The match read port; the HUD reassigns it when its own match_context changes.
var context: MatchContext
var _palette: PackedColorArray
var _roster_name: Callable


func _init(match_context: MatchContext, palette: PackedColorArray, roster_name: Callable) -> void:
	context = match_context
	_palette = palette
	_roster_name = roster_name


## Null-safe mirror of MatchConfig.team_of_slot(): no config (no match built yet) means every slot
## is its own team, the TeamMode.OFF answer.
func team_of_slot(slot_id: int) -> int:
	var running_config: MatchConfig = context.config()
	if running_config == null:
		return slot_id
	return running_config.team_of_slot(slot_id)


## MatchConfig.team_numbers when the lobby teams are host-resolved, else empty (labels fall back to
## team id + 1).
func resolved_team_numbers() -> PackedInt32Array:
	var running_config: MatchConfig = context.config()
	if running_config == null or not running_config.teams_resolved():
		return PackedInt32Array()
	return running_config.team_numbers


## Colour of TEAM `team_id`. With host-resolved lobby teams a team shows territory_colors()[team]
## (its lowest slot's colour); otherwise team id t is slot t.
func color_for_team(team_id: int) -> Color:
	var running_config: MatchConfig = context.config()
	if running_config != null and running_config.teams_resolved():
		var colors: PackedColorArray = running_config.territory_colors()
		if team_id >= 0 and team_id < colors.size():
			return colors[team_id]
	return color_for_slot(team_id)


func color_for_slot(slot_id: int) -> Color:
	var live_color: Variant = null
	var slot: PlayerSlot = context.slot(slot_id)
	if slot != null:
		live_color = slot.color
	return SlotColors.resolve(slot_id, live_color, _palette)


## There is no "home flag lost" signal, so this reads PlayerSlot.home_flag_alive off the port.
func is_slot_eliminated(slot_id: int) -> bool:
	var slot: PlayerSlot = context.slot(slot_id)
	return slot != null and not slot.home_flag_alive


## Resolved lobby teams: out when every slot of the team has lost its home flag; otherwise
## "slot t is team t".
func is_team_eliminated(team_id: int) -> bool:
	var running_config: MatchConfig = context.config()
	if running_config == null or not running_config.teams_resolved():
		return is_slot_eliminated(team_id)
	var found: bool = false
	for slot_id: int in range(running_config.player_count):
		if running_config.team_of_slot(slot_id) != team_id:
			continue
		found = true
		if not is_slot_eliminated(slot_id):
			return false
	return found


## PlayerSlot.display_name when a slot is built, otherwise the "Player N" fallback. A human seat's
## replicated roster name wins over the slot label; bots keep theirs.
func name_for_slot(slot_id: int) -> String:
	var peer_name: String = String(_roster_name.call(slot_id))
	var slot: PlayerSlot = context.slot(slot_id)
	if slot != null:
		return PlayerNames.label_for_slot(slot_id, slot.display_name, slot.is_bot, peer_name)
	return PlayerNames.label_for_slot(slot_id, "", false, peer_name)


## Every member's name joined with " & " in a team match; otherwise the slot of the same number.
func name_for_team(team_id: int) -> String:
	var running_config: MatchConfig = context.config()
	if running_config != null:
		var members: PackedStringArray = PackedStringArray()
		for slot_id: int in range(running_config.player_count):
			if running_config.team_of_slot(slot_id) == team_id:
				members.append(name_for_slot(slot_id))
		if not members.is_empty():
			return " & ".join(members)
	return name_for_slot(team_id)
