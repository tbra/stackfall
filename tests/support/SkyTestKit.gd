class_name SkyTestKit
extends RefCounted
## Shared sky test set-up: tests build a Skybox on the shipped cycle and edit a fresh
## SkyCycleDef. No scene tree.

const CYCLE_PATH: String = "res://config/sky/sky_cycle.tres"
const STORM_PATH: String = "res://config/sky/storm_overlay.tres"
const GOLDEN_PATH: String = "res://tests/unit/sky/fixtures/sky_cycle_golden.json"
const SKYBOX_CONFIG_PATH: String = "res://config/sky/skybox_config.tres"
const PROBE_STEP_M: float = 4.0
const PROBE_START_M: float = 5000.0
const PROBE_PRECISION_M: float = 0.001
const PROBE_HIDDEN: float = 0.5


## A fresh load of the shipped cycle (CACHE_MODE_IGNORE), so a test may edit it freely.
static func cycle() -> SkyCycleDef:
	return ResourceLoader.load(CYCLE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyCycleDef


## A fresh load of the shipped storm overlay definition.
static func storm_overlay() -> SkyOverlayDef:
	return ResourceLoader.load(STORM_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyOverlayDef


## The parsed golden fixture. Empty when the file is missing or does not parse to a Dictionary.
static func golden() -> Dictionary:
	var text: String = FileAccess.get_file_as_string(GOLDEN_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## The cycle phase a locked sky id shows (SkyCycleDef.locked_phase_for on a fresh cycle).
static func locked_phase(sky_id: String) -> float:
	return cycle().locked_phase_for(sky_id)


## A Skybox on the shipped cycle with a duplicated SkyboxConfig, added to `parent`.
static func make_skybox(parent: Node) -> Skybox:
	var skybox: Skybox = Skybox.new()
	var shipped_config: SkyboxConfig = ResourceLoader.load(SKYBOX_CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyboxConfig
	skybox.config = shipped_config.duplicate() as SkyboxConfig
	skybox.sky_def = cycle()
	parent.add_child(skybox)
	return skybox


## The dome's ShaderMaterial as installed on the environment's sky; null without an environment.
static func sky_material(skybox: Skybox) -> ShaderMaterial:
	if skybox.environment == null or skybox.environment.sky == null:
		return null
	return skybox.environment.sky.sky_material as ShaderMaterial


## The material the sea's puffs draw with: the first live (not queued for deletion) puff instance's
## override; null when the sea has built none.
static func puff_material(sea: CloudSea) -> ShaderMaterial:
	for child: Node in sea.get_children():
		if child is MultiMeshInstance3D and not child.is_queued_for_deletion():
			return (child as MultiMeshInstance3D).material_override as ShaderMaterial
	return null


## The centre of a single-puff sea's puff, in the frame sun_ray_cloud_occlusion uses. Found by
## querying that public occlusion (the MultiMesh transforms read back as zero under the headless
## renderer): x and z are the middle of the puff's hidden width, y the middle of its hidden
## height at that column (a flat-base puff's true centre sits higher than this by its cut).
static func puff_centre(sea: CloudSea) -> Vector3:
	var box: AABB = (sea.get_node("Puffs") as MultiMeshInstance3D).custom_aabb
	var hit: Vector2 = Vector2.INF
	var z: float = box.position.z
	while hit == Vector2.INF and z <= box.end.z:
		var y: float = box.position.y
		while y <= box.end.y:
			if _hidden(sea, Vector3(0.0, y, z), Vector3.RIGHT):
				hit = Vector2(y, z)
				break
			y += PROBE_STEP_M
		z += PROBE_STEP_M
	if hit == Vector2.INF:
		return Vector3.INF
	var centre_z: float = _middle(sea, Vector3(0.0, hit.x, hit.y), Vector3.RIGHT, Vector3.BACK)
	var centre_y: float = _middle(sea, Vector3(0.0, hit.x, centre_z), Vector3.RIGHT, Vector3.UP)
	var x: float = box.position.x
	while x <= box.end.x and not _hidden(sea, Vector3(x, centre_y, 0.0), Vector3.BACK):
		x += PROBE_STEP_M
	var centre_x: float = _middle(sea, Vector3(x, centre_y, 0.0), Vector3.BACK, Vector3.RIGHT)
	return Vector3(centre_x, centre_y, centre_z)


## Whether a ray along `dir` through `at` (started far behind `at`) is mostly hidden.
static func _hidden(sea: CloudSea, at: Vector3, dir: Vector3) -> bool:
	var from: Vector3 = at - dir * (at.dot(dir) + PROBE_START_M)
	return sea.sun_ray_cloud_occlusion(from, dir, null, Vector2.ZERO) > PROBE_HIDDEN


## The middle of the hidden span along `axis`, starting from a hidden point `at`.
static func _middle(sea: CloudSea, at: Vector3, dir: Vector3, axis: Vector3) -> float:
	var edges: Array[float] = []
	for sign: float in [-1.0, 1.0]:
		var inside: float = 0.0
		var outside: float = PROBE_STEP_M * sign
		while _hidden(sea, at + axis * outside, dir):
			inside = outside
			outside *= 2.0
		while absf(outside - inside) > PROBE_PRECISION_M:
			var mid: float = (inside + outside) * 0.5
			if _hidden(sea, at + axis * mid, dir):
				inside = mid
			else:
				outside = mid
		edges.append(inside)
	return ((at + axis * (edges[0] + edges[1]) * 0.5) * axis.abs()).dot(Vector3.ONE)


## Moves the shared clock to `clock_s` and runs one radiance interval, so a running cycle advances to it.
## The caller installs and restores the match context.
static func run_to_clock(skybox: Skybox, context: FakeMatchContext, clock_s: float) -> void:
	context.shared_clock_seconds_value = clock_s
	skybox._process(1.0 / skybox.radiance_config.radiance_hz)


## The once-per-frame flush of queued weather requests.
static func settle(skybox: Skybox) -> void:
	skybox._process(0.0)
