class_name BotCandidateGen
extends RefCounted
## Bot V2 targeted site generator (docs/BOT_AI_REDESIGN.md 2.3 step 4). Replaces the
## legacy uniform sampler: sites are built where territory is actually won.
##   TIP    own circles' frontier points at r - inset toward the intent target (best
##          anchors plus lateral / depth offsets); orientation maximises reach subject
##          to BotStatics.
##   STRIKE the same frontier toward the threat when the intent is STRIKE / DEFEND /
##          SIEGE (own edge facing the enemy).
##   STACK  own stack tops (tall circles) and jittered neighbours; flattest orientation.
##   FILL   a few uniform samples.
## Every site is PlacementRules.validate_point-valid at its origin, sites are distinct
## by (origin quantum, orientation), and no physics is touched: support heights are
## estimates (0 on the ground, the circle's top on a stack) until the caller probes.
## Pure: no scene tree.

const SHIPPED_TUNING: BotGenTuning = preload("res://config/bot_gen_tuning.tres")
## BotCandidate.site_kind values (0 = BotThink.SITE_LEGACY).
const SITE_TIP: int = 1
const SITE_STACK: int = 2
const SITE_STRIKE: int = 3
const SITE_FILL: int = 4


## Sites for the held piece under `intent`, at most `profile.candidate_count`.
static func sites(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> Array[BotCandidate]:
	var out: Array[BotCandidate] = []
	if view == null or view.held == null or view.raster == null or view.grid == null:
		return out
	var t: BotGenTuning = tuning if tuning != null else SHIPPED_TUNING
	var infos: Array[BotStatics.OrientationInfo] = BotStatics.orientation_infos(view.held, t)
	if infos.is_empty():
		return out
	var total: int = maxi(profile.candidate_count, 0)
	var gen: _Gen = _Gen.new(view, t, infos, out, total)
	var tip_share: float = t.tip_share
	var stack_share: float = t.stack_share
	match intent.kind:
		BotIntent.Kind.ANCHOR, BotIntent.Kind.FINISH, BotIntent.Kind.HOLD:
			tip_share = t.tower_tip_share
			stack_share = t.tower_stack_share
		BotIntent.Kind.AREA:
			tip_share = t.area_tip_share
			stack_share = t.area_stack_share
	var targeted_scale: float = 1.0
	if profile.fill_share > 0.0 and tip_share + stack_share > 0.0:
		# DECISION (Bontago-1t5.23): a tier with a FILL share (Easy) scales the targeted
		# quotas so the uniform FILL sites fill exactly that share of the budget.
		targeted_scale = (1.0 - clampf(profile.fill_share, 0.0, 1.0)) / (tip_share + stack_share)
	var tip_quota: int = roundi(tip_share * targeted_scale * float(total))
	var stack_quota: int = roundi(stack_share * targeted_scale * float(total))
	var threat_kind: bool = (
		intent.kind == BotIntent.Kind.STRIKE
		or intent.kind == BotIntent.Kind.DEFEND
		or intent.kind == BotIntent.Kind.SIEGE
	)
	var tip_kind: int = SITE_STRIKE if threat_kind else SITE_TIP
	gen.add_tip_sites(_target_for(view, intent, threat_kind), tip_kind, tip_quota)
	gen.add_stack_sites(_target_for(view, intent, threat_kind), stack_quota)
	gen.add_fill_sites(rng, total)
	return out


## Where the intent wants to go: its target, or the focus enemy circle's centre when
## the intent is a strike / defence on a known circle.
static func _target_for(view: BotWorldView, intent: BotIntent, threat_kind: bool) -> Vector2:
	if threat_kind and intent.focus_circle >= 0 and intent.focus_circle < view.circle_count():
		return Vector2(view.cx[intent.focus_circle], view.cz[intent.focus_circle])
	return intent.target


## Per-call generation state (keeps the static entry point short).
class _Gen:
	extends RefCounted
	var view: BotWorldView
	var t: BotGenTuning
	var infos: Array[BotStatics.OrientationInfo]
	var out: Array[BotCandidate]
	var total: int
	var _seen: Dictionary = {}
	## Own circles: centre and radius (the home circle is included).
	var _own_centers: PackedVector2Array = PackedVector2Array()
	var _own_radii: PackedFloat32Array = PackedFloat32Array()
	## View index of each own circle (-1 for the home circle).
	var _own_index: PackedInt32Array = PackedInt32Array()
	var _tip_orientations: Array[BotStatics.OrientationInfo] = []
	var _stack_orientations: Array[BotStatics.OrientationInfo] = []

	func _init(
		view_value: BotWorldView, tuning: BotGenTuning, infos_value: Array[BotStatics.OrientationInfo],
		out_value: Array[BotCandidate], total_value: int
	) -> void:
		view = view_value
		t = tuning
		infos = infos_value
		out = out_value
		total = total_value
		_collect_own_circles()
		_rank_orientations()

	func _collect_own_circles() -> void:
		if view.has_home:
			_own_centers.append(view.own_home)
			_own_radii.append(view.territory_tuning.home_radius)
			_own_index.append(-1)
		for i: int in view.indices_of_team(view.team_id):
			_own_centers.append(Vector2(view.cx[i], view.cz[i]))
			_own_radii.append(view.cr[i])
			_own_index.append(i)

	## Tip: highest reach (InfluenceCircle radius of the piece's top) under the risk cap,
	## then lowest risk, then largest grip. Stack: lowest risk, then lowest height.
	func _rank_orientations() -> void:
		var tip: Array[BotStatics.OrientationInfo] = []
		for info: BotStatics.OrientationInfo in infos:
			if info.flat_risk <= t.tip_risk_max:
				tip.append(info)
		if tip.is_empty():
			tip.append(_least_risky())
		tip.sort_custom(func(a: BotStatics.OrientationInfo, b: BotStatics.OrientationInfo) -> bool:
			var ra: float = _reach(a)
			var rb: float = _reach(b)
			if not is_equal_approx(ra, rb):
				return ra > rb
			if not is_equal_approx(a.flat_risk, b.flat_risk):
				return a.flat_risk < b.flat_risk
			if a.contact_area != b.contact_area:
				return a.contact_area > b.contact_area
			return a.index < b.index
		)
		_tip_orientations = tip.slice(0, maxi(t.tip_orientation_variants, 1))
		var stack: Array[BotStatics.OrientationInfo] = infos.duplicate()
		stack.sort_custom(func(a: BotStatics.OrientationInfo, b: BotStatics.OrientationInfo) -> bool:
			if not is_equal_approx(a.flat_risk, b.flat_risk):
				return a.flat_risk < b.flat_risk
			if a.height != b.height:
				return a.height < b.height
			if a.contact_area != b.contact_area:
				return a.contact_area > b.contact_area
			return a.index < b.index
		)
		_stack_orientations = stack.slice(0, maxi(t.stack_orientation_variants, 1))

	func _least_risky() -> BotStatics.OrientationInfo:
		var best: BotStatics.OrientationInfo = infos[0]
		for info: BotStatics.OrientationInfo in infos:
			if info.flat_risk < best.flat_risk:
				best = info
		return best

	func _reach(info: BotStatics.OrientationInfo) -> float:
		return InfluenceCircle.radius_for_height(info.height, view.territory_tuning, view.field_radius)

	func is_full() -> bool:
		return out.size() >= total

	## Frontier sites toward `target`; stops once `quota` sites (or the budget) are met.
	func add_tip_sites(target: Vector2, kind: int, quota: int) -> void:
		var start: int = out.size()
		var anchors: Array[Dictionary] = _tip_anchors(target)
		var offsets: Array[Vector2i] = _tip_offsets()
		for offset: Vector2i in offsets:
			for orientation: BotStatics.OrientationInfo in _tip_orientations:
				for anchor: Dictionary in anchors:
					if out.size() - start >= quota or is_full():
						return
					var point: Vector2 = _offset_point(anchor, offset)
					_try_add(point, orientation, kind, false, 0.0)

	## Lateral (x) and depth (y) steps ordered by distance from the anchor.
	func _tip_offsets() -> Array[Vector2i]:
		var offsets: Array[Vector2i] = []
		for row: int in range(maxi(t.tip_depth_rows, 1)):
			for lateral: int in range(-t.tip_lateral_steps, t.tip_lateral_steps + 1):
				offsets.append(Vector2i(lateral, row))
		offsets.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var ca: int = absi(a.x) + a.y
			var cb: int = absi(b.x) + b.y
			if ca != cb:
				return ca < cb
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
		)
		return offsets

	func _offset_point(anchor: Dictionary, offset: Vector2i) -> Vector2:
		var dir: Vector2 = anchor["dir"] as Vector2
		var perpendicular: Vector2 = Vector2(-dir.y, dir.x)
		return (anchor["point"] as Vector2) \
			+ perpendicular * (float(offset.x) * t.tip_lateral_step_m) \
			- dir * (float(offset.y) * t.tip_depth_step_m)

	## Best frontier points: for each own circle the edge point (minus inset) toward the
	## target, dropped when buried in another own circle, backed off to a valid spot, sorted
	## by remaining distance to the target and thinned by minimum spacing.
	func _tip_anchors(target: Vector2) -> Array[Dictionary]:
		var raw: Array[Dictionary] = []
		for i: int in range(_own_centers.size()):
			var center: Vector2 = _own_centers[i]
			var to_target: Vector2 = target - center
			if to_target.length_squared() <= 0.0:
				continue
			var dir: Vector2 = to_target.normalized()
			var point: Vector2 = center + dir * maxf(_own_radii[i] - t.tip_inset_m, 0.0)
			if _buried(point, i):
				continue
			point = _back_off(center, dir, point)
			if point.x == INF:
				continue
			raw.append({"point": point, "dir": dir, "gap": point.distance_to(target)})
		raw.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["gap"] as float) < (b["gap"] as float)
		)
		var anchors: Array[Dictionary] = []
		for candidate: Dictionary in raw:
			if anchors.size() >= t.tip_anchor_count:
				break
			var crowded: bool = false
			for kept: Dictionary in anchors:
				if (kept["point"] as Vector2).distance_to(candidate["point"] as Vector2) < t.tip_min_spacing_m:
					crowded = true
					break
			if not crowded:
				anchors.append(candidate)
		return anchors

	func _buried(point: Vector2, own: int) -> bool:
		for j: int in range(_own_centers.size()):
			if j != own and point.distance_to(_own_centers[j]) < _own_radii[j] - t.tip_frontier_margin_m:
				return true
		return false

	## `point` itself when placeable, else the first placeable point walking back toward
	## `center`; Vector2(INF, INF) when none is.
	func _back_off(center: Vector2, dir: Vector2, point: Vector2) -> Vector2:
		var candidate: Vector2 = point
		for step: int in range(t.tip_backoff_max_steps + 1):
			candidate = point - dir * (float(step) * t.tip_backoff_step_m)
			if (candidate - center).dot(dir) < 0.0:
				break
			if _placeable(candidate):
				return candidate
		return PlacementRules.NO_ORIGIN

	func _placeable(point: Vector2) -> bool:
		return PlacementRules.validate_point(point, view.raster, view.team_id) == PlacementRules.Result.VALID

	## Tallest own circles first, each with the centre and jittered neighbours.
	func add_stack_sites(target: Vector2, quota: int) -> void:
		var start: int = out.size()
		var tops: Array[Dictionary] = []
		for i: int in view.indices_of_team(view.team_id):
			var top: float = view.top_height(i)
			if top >= t.stack_min_height_m:
				var center: Vector2 = Vector2(view.cx[i], view.cz[i])
				tops.append({"center": center, "top": top, "gap": center.distance_to(target)})
		tops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if not is_equal_approx(a["top"] as float, b["top"] as float):
				return (a["top"] as float) > (b["top"] as float)
			return (a["gap"] as float) < (b["gap"] as float)
		)
		var picked: Array[Dictionary] = tops.slice(0, maxi(t.stack_site_count, 0))
		var jitters: Array[Vector2] = [
			Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP
		]
		for jitter: Vector2 in jitters:
			for orientation: BotStatics.OrientationInfo in _stack_orientations:
				for entry: Dictionary in picked:
					if out.size() - start >= quota or is_full():
						return
					var point: Vector2 = (entry["center"] as Vector2) + jitter * t.stack_jitter_m
					_try_add(point, orientation, SITE_STACK, true, entry["top"] as float)

	## Uniform samples of own territory until the budget is met or attempts run out.
	func add_fill_sites(rng: RandomNumberGenerator, budget: int) -> void:
		var needed: int = budget - out.size()
		if needed <= 0:
			return
		var allowed: Array[BotStatics.OrientationInfo] = []
		for info: BotStatics.OrientationInfo in infos:
			if info.flat_risk <= t.fill_risk_max:
				allowed.append(info)
		if allowed.is_empty():
			allowed.append(_least_risky())
		var attempts: int = needed * maxi(t.fill_attempts_per_site, 1)
		while not is_full() and attempts > 0:
			attempts -= 1
			var angle: float = rng.randf() * TAU
			var dist: float = sqrt(rng.randf()) * view.field_radius
			var point: Vector2 = Vector2(cos(angle), sin(angle)) * dist
			var orientation: BotStatics.OrientationInfo = allowed[rng.randi() % allowed.size()]
			_try_add(point, orientation, SITE_FILL, false, 0.0)

	## Adds the site when placeable and not a duplicate; true when added.
	func _try_add(
		point: Vector2, orientation: BotStatics.OrientationInfo, kind: int, on_stack: bool, stack_top: float
	) -> bool:
		if not _placeable(point):
			return false
		var key: Vector3i = Vector3i(
			roundi(point.x / t.distinct_quantum_m), roundi(point.y / t.distinct_quantum_m), orientation.index
		)
		if _seen.has(key):
			return false
		_seen[key] = true
		var candidate: BotCandidate = BotCandidate.new()
		candidate.origin = point
		candidate.orientation_index = orientation.index
		candidate.site_kind = kind
		candidate.support_height = stack_top if on_stack else 0.0
		candidate.on_top_of_own_stack = on_stack
		candidate.shape_height = orientation.height
		candidate.top_height = candidate.support_height + candidate.shape_height
		candidate.tip_risk = orientation.flat_risk
		candidate.footprint_cells = PlacementRules.footprint_cells(
			view.held.cells, BlockOrientations.get_basis(orientation.index), point, view.cube_size, view.grid
		)
		out.append(candidate)
		return true
