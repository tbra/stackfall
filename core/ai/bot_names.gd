class_name BotNames
extends RefCounted
## the owner's themed bot-name lists plus pure picking rules (no
## scene tree). The host assigns each bot seat one name, distinct from every other
## bot and from every human's name, and replicates it in MatchConfig.bot_names.


## Only when the pool is exhausted. Alias of the single owner (PlayerNames.BOT_FALLBACK_FORMAT).
const FALLBACK_FORMAT: String = PlayerNames.BOT_FALLBACK_FORMAT

const TACTICIANS: Array[String] = [
	"Tetra", "Vertex", "Apex", "Cantilever", "Fulcrum", "PlumbLine", "Keystone",
	"Gable", "Strut", "Truss", "Orthogonal", "Obtuse", "Isosceles", "Facet",
	"Monolith", "Ziggurat", "Pylon", "Mortar", "Gantry", "Obelisk"
]

const SMASHERS: Array[String] = [
	"Tremor", "Quake", "Impact", "Avalanche", "Anvil", "Crush", "WreckingBall",
	"Landslide", "Rubble", "Sledge", "Cataclysm", "Faultline", "Bedrock",
	"Tectonic", "Caldera", "Goliath", "Titan", "Juggernaut", "Breaker", "Tumble"
]

const BALANCERS: Array[String] = [
	"Equilibrium", "Gravity", "Friction", "Torque", "Inertia", "Vector", "Velocity",
	"Mass", "Plumb", "Ballast", "Pivot", "Gyro", "Counterweight", "Levity",
	"Static", "Momentum", "Axis", "Centroid", "Zenith"
]

const ARCADE: Array[String] = [
	"BlockHead", "StackBot", "SirStackALot", "Brick", "Cube", "Tumbleweed", "Wobble",
	"Tilt", "Gizmo", "Sprocket", "Widget", "Pixel", "Clinker", "Chippy",
	"Rusty", "Bolts", "Gearhead", "Matrix", "Flux", "Clunk"
]

const TERRITORY: Array[String] = [
	"Radius", "Horizon", "Nexus", "Vortex", "Orbit", "Eclipse", "Domain",
	"Sector", "Cosmos", "Quasar", "Nebula", "Void", "Chroma", "Grid",
	"Spectrum", "Prism", "Beacon", "Aura"
]

## Theme arrays in the owner's order.
static func themes() -> Array[Array]:
	return [TACTICIANS, SMASHERS, BALANCERS, ARCADE, TERRITORY]


## Every name of every theme.
static func all_names() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for theme: Array in themes():
		for entry: Variant in theme:
			result.append(String(entry))
	return result


## `count` bot names. `existing` entries are kept in place while still valid (not
## empty, not a repeat, not in `taken`), so a bot keeps its name across matches;
## the rest are drawn from the pool by `rng`, avoiding `taken` (the humans' names)
## and each other, compared case-insensitively. Fewer free names than `count`
## (not reachable with 8 seats) falls back to "Bot N".
static func assign(existing: PackedStringArray, count: int, taken: PackedStringArray, rng: RandomNumberGenerator) -> PackedStringArray:
	var used: Dictionary = {}
	for name_taken: String in taken:
		used[name_taken.to_lower()] = true
	var result: PackedStringArray = PackedStringArray()
	result.resize(maxi(count, 0))
	for index: int in range(result.size()):
		if index < existing.size() and existing[index] != "" and not used.has(existing[index].to_lower()):
			result[index] = existing[index]
			used[existing[index].to_lower()] = true
	var free: PackedStringArray = PackedStringArray()
	for candidate: String in all_names():
		if not used.has(candidate.to_lower()):
			free.append(candidate)
	for index: int in range(result.size()):
		if result[index] != "":
			continue
		if free.is_empty():
			result[index] = PlayerNames.bot_fallback(index + 1)
			continue
		var pick: int = rng.randi_range(0, free.size() - 1)
		result[index] = free[pick]
		free.remove_at(pick)
	return result
