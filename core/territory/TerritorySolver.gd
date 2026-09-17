class_name TerritorySolver
extends RefCounted
## Turns a flat list of influence circles into connected, home-anchored groups
## (spec 2.2, 3.3).
##
## **Algorithm.** Union-find over pairs of overlapping circles, with a spatial
## hash so it is not all-pairs. Two circles are united only when they overlap
## **and share a team**, which is exactly spec 2.2's two rules at once: "your
## territory is the union of all circles connected... to your home circle",
## and "Teams: territories of teammates never create holes between them, they
## merge". Free-for-all is the same code path, because MatchConfig gives every
## player their own team.
##
## After the union pass, a component is kept only if it contains at least one
## circle with `is_home` set. Everything else is discarded, which is the
## cut-off rule: "Circles that aren't connected to your home give no
## territory. If a tower is cut off, its influence is gone."
##
## **Spatial hash.** Each circle is inserted into every hash cell its bounding
## box covers, at TerritoryTuning.hash_cell_size (see the DECISION there for
## why that is not the spec's literal `influence_max`). Candidate pairs are
## circles sharing a hash cell, deduplicated by (lower index, higher index).
##
## Pure logic: no scene tree (CLAUDE.md). Stateless between calls apart from
## reused scratch buffers, so one solver instance is reused at 10 Hz without
## allocating.

var _tuning: TerritoryTuning = null


func _init(tuning: TerritoryTuning) -> void:
	_tuning = tuning


func tuning() -> TerritoryTuning:
	return _tuning


## The whole solver. `circles` mixes block circles and home circles in any
## order; home circles are the ones with is_home set. Order is preserved, so
## the indices in the returned groups index straight back into `circles`.
##
## Costs O(n + pairs) with the hash; the raster consumes the result directly.
@warning_ignore_start("unused_parameter")
func solve(circles: Array[InfluenceCircle]) -> TerritoryGroups:
	return TerritoryGroups.new()


## True when circle `index` ended up in a home-anchored group. Valid only
## after the matching solve() call; used by tests and by the block shader's
## "glows brighter when contributing influence" flag (spec 2.10).
func is_connected(index: int) -> bool:
	return false


## The group a circle landed in, or TerritoryGroups.NO_GROUP. Same validity
## rule as is_connected().
func group_of_circle(index: int) -> int:
	return TerritoryGroups.NO_GROUP


## Candidate overlapping pairs the spatial hash produced for the last solve().
## Exposed so a unit test can assert the hash is not silently degenerating
## into all-pairs as radii grow.
func last_pair_count() -> int:
	return 0
@warning_ignore_restore("unused_parameter")
