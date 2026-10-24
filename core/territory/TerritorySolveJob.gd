class_name TerritorySolveJob
extends RefCounted
## P-ASYNC: one territory solve step as a self-contained job.
## The main thread fills the inputs (the scene reads: collect, source signature),
## then run() executes either inline (synchronous path) or inside
## a WorkerThreadPool task. run() touches only this job, its fill raster and a
## solver, never the scene tree, Events or a shared Resource, so the outcome is
## the same on any thread. Pure logic (CLAUDE.md): nothing here reads the tree.

# --- Inputs (main thread, before run()) ---
var circles: Array[InfluenceCircle] = []
var cache_hit: bool = false
var cached_groups: TerritoryGroups = null
var holes_enabled: bool = false
## Used when `solver` is null (async path: a fresh solver on a tuning snapshot).
var solver_tuning: TerritoryTuning = null
## Optional shared solver for the synchronous path (keeps its exact behaviour).
var solver: TerritorySolver = null
var fill_raster: TerritoryRaster = null

# --- Main-thread bookkeeping carried to apply (never read by run()) ---
var delta: float = 0.0
var sources: Dictionary = {}
var kickoff_config: Dictionary = {}
var alive_before: int = 0
var task_id: int = -1

# --- Outputs ---
var out_circles: Array[InfluenceCircle] = []
var groups: TerritoryGroups = null
var render: Dictionary = {}


func run() -> void:
	out_circles = circles
	if cache_hit:
		groups = cached_groups
	else:
		# Same-team circles fully inside a larger one go BEFORE the solver's
		# max_circles budget, so redundant circles never spend budget.
		out_circles = TerritoryCull.drop_contained(circles)
		var active_solver: TerritorySolver = solver if solver != null else TerritorySolver.new(solver_tuning)
		groups = active_solver.solve(out_circles)
	fill_raster.fill_ownership(out_circles, groups, holes_enabled)
	if not cache_hit:
		render = build_render_list(out_circles, groups)


## The analytic circle list the overlay and the replication wire use: only the
## home-anchored circles a group kept, sorted by team then largest radius first.
static func build_render_list(circles: Array[InfluenceCircle], groups: TerritoryGroups) -> Dictionary:
	# Native lexicographic sort on [team, -radius, sequence]; the sequence tiebreak makes
	# equal (team, radius) entries keep insertion order.
	var entries: Array = []
	var sequence: int = 0
	for group: int in range(groups.group_count()):
		var team: int = groups.team_of(group)
		for circle_index: int in groups.circles_of(group):
			var circle: InfluenceCircle = circles[circle_index]
			entries.append([team, -circle.radius, sequence, circle.radius, circle.center.x, circle.center.y])
			sequence += 1
	entries.sort()

	var count: int = entries.size()
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	xs.resize(count)
	zs.resize(count)
	radii.resize(count)
	teams.resize(count)
	for i: int in range(count):
		var entry: Array = entries[i]
		teams[i] = entry[0]
		radii[i] = entry[3]
		xs[i] = entry[4]
		zs[i] = entry[5]
	return {"xs": xs, "zs": zs, "radii": radii, "teams": teams}
