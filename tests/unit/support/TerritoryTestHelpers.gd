class_name TerritoryTestHelpers
extends RefCounted
## Test-only seam for forcing the genuine "this team owns zero valid cells"
## case PlacementRules.closest_valid_point() needs to return NO_ORIGIN
## (core/rules/PlacementRules.gd, Bontago-xtq.23).
##
## Before a0e9305, a desired point merely far from a team's territory forced
## the burn/throw path, because closest_valid_point()'s ring search gave up
## past auto_drop_search_max_radius. It now falls back to
## _scan_disk_for_closest_valid_point(), a full-disk scan, so distance alone
## can no longer produce NO_ORIGIN: the burn path is reachable only when the
## team truly owns no valid point anywhere on the disk. Tests that want to
## exercise that path (not a relocation) must therefore blank the acting
## team's own owned cells in the live raster first, not merely aim far away.
##
## blank_owned_territory() does this by reading TerritoryRaster.owner_bytes()/
## state_bytes() (the same wire format apply_replicated_state() consumes),
## clearing every cell currently owned by `team_id` to unowned (byte 0), and
## reapplying the result. This only touches ownership: contested/hole/goal-
## zone bits ride through unchanged, and every other team's cells are
## untouched.
##
## Callers must not let Match's territory solve run again before using this:
## it only ever runs from Match._process()'s PLAYING branch
## (autoload/match/MatchTerritory.gd _tick_territory()), so a test that drives
## Match with Match.set_process(false) and calls this right after its own
## _run_countdown() (with no further manual Match._process() calls before the
## request_place()/request_throw() under test) is safe: nothing re-stamps the
## team's cells back before the call this is set up for.
static func blank_owned_territory(raster: TerritoryRaster, team_id: int) -> void:
	var owners: PackedByteArray = raster.owner_bytes().duplicate()
	var states: PackedByteArray = raster.state_bytes().duplicate()
	var owned_byte: int = team_id + 1
	for index: int in range(owners.size()):
		if owners[index] == owned_byte:
			owners[index] = 0
	raster.apply_replicated_state(owners, states)
