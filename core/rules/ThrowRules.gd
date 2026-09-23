class_name ThrowRules
extends RefCounted
## Whether a thrown special's release point lands inside the throwing
## player's own territory (spec 2.5: "release point inside own territory").
##
## Delegates the actual point test to PlacementRules.validate_point()
## (core/rules/PlacementRules.gd:268-283, the v2 single-raycast point check)
## rather than re-deriving raster.team_at()/is_contested() itself -- one
## source of truth for what "your own territory" means at a point
## (docs/M4_P2_PACKAGES.md P2c re-cut, decision 2). A throw uses the exact
## same raycast-then-point-test MatchPlacement.request_place() already runs;
## only the reason a bad point is refused with differs (see reason_for()
## below).
##
## Pure logic: no scene tree (CLAUDE.md). Static, like PlacementRules, so the
## host calls it without keeping an instance around.

## Raised by MatchPlacement.request_throw(), not by this file: the acting
## slot has no pending special queued at all (Match.held_special(slot_id) ==
## &""), so there is nothing to throw (spec 2.6's "your next fed block
## becomes a special" contract). Kept here, next to REASON_OUTSIDE_TERRITORY,
## so every REASON_* a throw can return lives in one place.
const REASON_NOT_A_SPECIAL: StringName = &"not_a_special"

## Spec 2.5 gives a throw a single "outside your own territory" release-point
## failure, not PlacementRules' several distinguishable reasons (contested,
## hole, off-disk, goal zone) -- reason_for() below collapses every non-VALID
## PlacementRules.Result into this one constant. Aliased to PlacementRules'
## own constant (not a new StringName literal) so MatchNet/HUD code that
## already switches on PlacementRules.REASON_OUTSIDE_TERRITORY recognizes a
## throw's refusal without a second case.
const REASON_OUTSIDE_TERRITORY: StringName = PlacementRules.REASON_OUTSIDE_TERRITORY


## Spec 2.5's release-point check for a throw: exactly PlacementRules' v2
## point check, reused rather than re-derived so a throw and a placement can
## never disagree about what "your own territory" means at a given point.
## `point` is disk-local (x, z), already converted by the caller, exactly
## like PlacementRules.validate_point()'s own contract.
static func validate_release_point(
	point: Vector2, raster: TerritoryRaster, team_id: int
) -> PlacementRules.Result:
	return PlacementRules.validate_point(point, raster, team_id)


## Collapses every non-VALID PlacementRules.Result into REASON_OUTSIDE_
## TERRITORY -- spec 2.5 gives a throw only one release-point failure
## message, unlike placement's several distinguishable REASON_* reasons.
## REASON_NOT_A_SPECIAL is never produced here; MatchPlacement.request_throw()
## returns it directly, before a point is ever tested.
static func reason_for(result: PlacementRules.Result) -> StringName:
	if result == PlacementRules.Result.VALID:
		return PlacementRules.REASON_OK
	return REASON_OUTSIDE_TERRITORY
