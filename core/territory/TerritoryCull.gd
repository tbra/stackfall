class_name TerritoryCull
extends RefCounted
## One cull for the territory solve: drops every non-home circle that a larger
## kept same-team circle fully contains (plan TERRITORY_CLEANUP 2.1).
##
## Homes are never dropped and never act as containers. Input is not mutated;
## the survivors keep the input order. Pure logic: no scene tree (CLAUDE.md).
##
## STUB (P5-S): returns the input unchanged until P5-1 lands the cull body.


## Returns the circles that survive the containment cull.
static func drop_contained(circles: Array[InfluenceCircle]) -> Array[InfluenceCircle]:
	return circles
