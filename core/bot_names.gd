class_name BotNames
extends RefCounted
## Bontago-1pi.62: the owner's themed bot-name lists plus pure picking rules (no
## scene tree). The host assigns each bot seat one name, distinct from every other
## bot and from every human's name, and replicates it in MatchConfig.bot_names.


## Only when the pool is exhausted.
const FALLBACK_FORMAT: String = "Bot %d"

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

## Theme arrays in the owner's order (get_themed_name's theme_index).
static func themes() -> Array[Array]:
	return [TACTICIANS, SMASHERS, BALANCERS, ARCADE, TERRITORY]


## Every name of every theme.
static func all_names() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for theme: Array in themes():
		for entry: Variant in theme:
			result.append(String(entry))
	return result


static func get_random_name() -> String:
	return get_random_name_with(_shared_rng())


static func get_themed_name(theme_index: int) -> String:
	var all_themes: Array[Array] = themes()
	if theme_index < 0 or theme_index >= all_themes.size():
		return get_random_name()
	var theme: Array = all_themes[theme_index]
	return String(theme[_shared_rng().randi_range(0, theme.size() - 1)])


## One name from the whole pool using `rng` (deterministic for a seeded rng).
static func get_random_name_with(rng: RandomNumberGenerator) -> String:
	var pool: PackedStringArray = all_names()
	return pool[rng.randi_range(0, pool.size() - 1)]


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
			result[index] = FALLBACK_FORMAT % (index + 1)
			continue
		var pick: int = rng.randi_range(0, free.size() - 1)
		result[index] = free[pick]
		free.remove_at(pick)
	return result


static func _shared_rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	return rng
