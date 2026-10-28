class_name LobbySeatVariants
extends RefCounted
## The lobby players row's switchable looks. One shared LobbySeatRow
## builds every look for BOTH the vs-bots and the hosted lobby; the panel arranges the rows
## (flat list, a zebra table with a header, a tile grid, team lanes side by side). Only CLASSIC ships: the others are chosen
## from the debug-only "Row style" dropdown at the top of the Players panel (DebugMode on).

enum Style { CLASSIC, TILES, TABLE, BOARD, TILES_CAP, TILES_TEAM, TILES_WASH, TILES_BIG }

const NAMES: Array[String] = ["Classic row", "Roster tiles", "Table", "Versus board",
	"Tiles A: team cap", "Tiles B: team colour", "Tiles C: stronger wash", "Tiles D: big hero"]

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


## The roster-tile family: today's tiles and the round-4 refinements share one row layout and one grid.
static func is_tiles(style: int) -> bool:
	return style == Style.TILES or style >= Style.TILES_CAP


## Tiles that deal the seats team by team (a team's seats sit side by side).
static func sorts_by_team(style: int) -> bool:
	return style == Style.TILES_CAP or style == Style.TILES_TEAM
