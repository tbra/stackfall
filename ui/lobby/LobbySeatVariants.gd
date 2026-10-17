class_name LobbySeatVariants
extends RefCounted
## The lobby players row's switchable looks. One shared LobbySeatRow
## builds every look for BOTH the vs-bots and the hosted lobby; the panel arranges the rows
## (flat list, team groups, a two-column card grid). Only CLASSIC ships: the others are chosen
## from the debug-only "Row style" dropdown at the top of the Players panel (DebugMode on).

enum Style { CLASSIC, SLOT, GROUPED, CARDS }

const NAMES: Array[String] = ["Classic row", "Slot (state right)", "Team groups", "Seat cards"]

## The look chosen this session (the dropdown writes it; a panel rebuilt on re-entering the lobby keeps it).
# DECISION: a static session value, not a saved setting: the switch is a
# comparison tool, so it costs nothing to persist and the shipped default stays CLASSIC.
static var chosen: int = Style.CLASSIC


## The switch (and every non-classic look) exists only with debug mode on.
static func switch_available() -> bool:
	return DebugMode.is_enabled()


## The look in effect: the chosen one while debug mode is on, else CLASSIC.
static func current() -> int:
	return chosen if switch_available() else Style.CLASSIC
