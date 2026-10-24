class_name InfluenceCircle
extends RefCounted
## One node of the territory graph (spec 1.5, 2.5): a circle on the disk that
## a settled block, or a home flag, projects.
##
## Spec 1.5, [RECONSTRUCTED]: "Each of your blocks that is settled produces an
## influence circle... centered on the block's center of mass, projected onto
## the disk plane... r = influence_base + h * tan(40 deg), where h is the
## height of the block's highest point above the disk surface, measured along
## the disk's normal", capped at influence_max_fraction * field_radius.
##
## Spec "Still open" 3 records that it is unknown whether the original drew a
## circle per block or one circle per player; the spec's stated default, and
## what this class implements, is a circle per block.
##
## Pure logic: no scene tree (CLAUDE.md).

## Half-angle of the territory cone (SPEC 1.5); the radius grows by
## tan(this) metres per metre of block height.
const CONE_HALF_ANGLE_DEGREES: float = 40.0

## Disk-local (x, z) center, see CellGrid for the convention.
var center: Vector2 = Vector2.ZERO
var radius: float = 0.0
## Circles only ever connect to circles of the same team (spec 1.5, "Teams").
var team_id: int = -1
## Which player placed the block. Kept for HUD attribution and the bot's
## "which enemy tower contributes most influence" query; connectivity ignores
## it, because teammates' circles do connect.
var slot_id: int = -1
## Home circles anchor a connected group (spec 1.5: "Your territory is the
## union of all circles connected... to your home circle").
var is_home: bool = false
## Physics id of the block this came from, or -1 for a home circle. Lets the
## field wake exactly the right bodies when a cell under them opens.
var body_id: int = -1


func _init(
	p_center: Vector2 = Vector2.ZERO,
	p_radius: float = 0.0,
	p_team_id: int = -1,
	p_slot_id: int = -1,
	p_is_home: bool = false,
	p_body_id: int = -1
) -> void:
	center = p_center
	radius = p_radius
	team_id = p_team_id
	slot_id = p_slot_id
	is_home = p_is_home
	body_id = p_body_id


## Metres of radius per metre of height: tan(CONE_HALF_ANGLE_DEGREES).
static func cone_slope() -> float:
	return tan(deg_to_rad(CONE_HALF_ANGLE_DEGREES))


## Spec 1.5's radius formula. `height` is the block's highest point above the
## disk surface along the disk normal; `field_radius` supplies the cap.
static func radius_for_height(
	height: float, tuning: TerritoryTuning, field_radius: float
) -> float:
	var raw: float = tuning.influence_base + cone_slope() * maxf(height, 0.0)
	return minf(raw, tuning.influence_max_fraction * field_radius)


## Builds a home flag's circle (spec 1.5: "Home circle: radius home_radius = 6.
## It always exists while the flag is on the disk").
static func for_home(
	flag_position: Vector2, team_id: int, slot_id: int, tuning: TerritoryTuning
) -> InfluenceCircle:
	return InfluenceCircle.new(
		flag_position, tuning.home_radius, team_id, slot_id, true, -1
	)


## Spec 2.5: "two circles are connected if they overlap". Touching exactly
## counts as overlapping, so a hand-built test case sitting at r1 + r2 apart
## is connected rather than sitting on a floating-point knife edge.
func overlaps(other: InfluenceCircle) -> bool:
	var reach: float = radius + other.radius
	return center.distance_squared_to(other.center) <= reach * reach
