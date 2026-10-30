class_name LobbyProbe
extends RefCounted
## What a test observes of a Lobby through its public surface: the dictionary a host Lobby last
## published through its FakeNet, the seat rows drawn on screen and the gift chips, found by
## class and unique name instead of the Lobby's private fields.


## The last dictionary the host Lobby published through Net.set_lobby_data().
static func published(lobby: Lobby) -> Dictionary:
	var calls: Array[Dictionary] = (lobby.net_provider as FakeNet).set_lobby_data_calls
	return calls[calls.size() - 1] if not calls.is_empty() else {}


## The config half of that publish, as a client would read it.
static func published_config(lobby: Lobby) -> MatchConfig:
	return MatchConfig.from_dict(published(lobby))


## Every seat row drawn in the roster, in tree (visual) order.
static func seat_rows(lobby: Lobby) -> Array[LobbySeatRow]:
	var rows: Array[LobbySeatRow] = []
	for node: Node in lobby.find_children("*", "LobbySeatRow", true, false):
		rows.append(node as LobbySeatRow)
	return rows


## The gift chips of the GIFTS Advanced block, in the order they are listed.
static func gift_chips(lobby: Lobby) -> Array[UiChipToggle]:
	var chips: Array[UiChipToggle] = []
	for node: Node in (lobby.find_child("SpecialsChecklist", true, false) as Node).get_children():
		var chip: UiChipToggle = node as UiChipToggle
		if chip != null and not chip.is_queued_for_deletion():
			chips.append(chip)
	return chips


## Every Label text drawn inside the named settings section (header caption and one-line summary).
static func section_text(lobby: Lobby, section_name: String) -> String:
	var section: Node = lobby.find_child(section_name, true, false)
	var parts: PackedStringArray = []
	for node: Node in section.find_children("*", "Label", true, false):
		parts.append((node as Label).text)
	return " ".join(parts)
