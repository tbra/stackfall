class_name BotCandidateGen
extends RefCounted
## Bot V2 targeted site generator (docs/BOT_AI_REDESIGN.md 2.3 step 4): sites are built where
## territory is actually won, not sampled uniformly.
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

const SHIPPED_TUNING: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
## BotCandidate.site_kind values (0 = BotThink.SITE_NONE, unset).
const SITE_TIP: int = 1
const SITE_STACK: int = 2
const SITE_STRIKE: int = 3
const SITE_FILL: int = 4
## a wide, flat piece on the ground at a new base after a collapse.
const SITE_FOUNDATION: int = 5


## Sites for the held piece under `intent`, at most `profile.candidate_count`.
static func sites(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> Array[BotCandidate]:
	var job: SiteJob = begin(view, intent, profile, rng, tuning)
	while not job.fill_step(job.attempts_left()):
		pass
	return job.out


## Resumable form of `sites`: the targeted TIP / STACK sites are built here;
## the uniform FILL (the costly part: hundreds of rejected validate_point draws) is then run in
## `SiteJob.fill_step` slices. The RNG draw order is identical to `sites`, so a fixed seed gives
## the same sites whatever the slice size.
static func begin(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> SiteJob:
	var out: Array[BotCandidate] = []
	var job: SiteJob = SiteJob.new()
	job.out = out
	if view == null or view.held == null or view.raster == null or view.grid == null:
		return job
	var t: BotGenTuning = tuning if tuning != null else SHIPPED_TUNING
	var infos: Array[BotStatics.OrientationInfo] = BotStatics.orientation_infos(view.held, t)
	if infos.is_empty():
		return job
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
		# DECISION: a tier with a FILL share (Easy) scales the targeted
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
	if intent.new_base:
		# after a collapse the share of the stack sites goes to the new base's
		# foundation. a site may sit beside or on the old tower's debris, but
		# only on the disc or on faces flat against it whose pile holds the piece (no clearance).
		gen.flat_supports_only = true
		gen.add_foundation_sites(intent.target, mini(t.foundation_site_count, total))
		gen.add_tip_sites(_target_for(view, intent, threat_kind), tip_kind, tip_quota)
	else:
		gen.add_tip_sites(_target_for(view, intent, threat_kind), tip_kind, tip_quota)
		gen.add_stack_sites(_target_for(view, intent, threat_kind), stack_quota)
	job.start_fill(gen, rng, total, profile.fill_share <= 0.0)
	return job


## Where the intent wants to go: its target, or the focus enemy circle's centre when
## the intent is a strike / defence on a known circle.
static func _target_for(view: BotWorldView, intent: BotIntent, threat_kind: bool) -> Vector2:
	if threat_kind and intent.focus_circle >= 0 and intent.focus_circle < view.circle_count():
		return Vector2(view.cx[intent.focus_circle], view.cz[intent.focus_circle])
	return intent.target


## An in-flight site generation; `out` is complete once `fill_step` returns true.
class SiteJob:
	extends RefCounted
	var out: Array[BotCandidate] = []
	var _gen: _Gen = null
	var _rng: RandomNumberGenerator = null
	var _allowed: Array[BotStatics.OrientationInfo] = []
	var _attempts: int = 0
	## Site count at which the fill stops (the budget).
	var _stop_at: int = 0
	## true when this job is the zero-targeted-sites FILL fallback (a capped profile that
	## found no targeted site), so the cost report can count how often the fallback runs.
	var fallback_ran: bool = false

	func start_fill(gen: _Gen, rng: RandomNumberGenerator, budget: int, capped: bool = false) -> void:
		_gen = gen
		_rng = rng
		var needed: int = budget - out.size()
		if needed <= 0:
			return
		_stop_at = budget
		# DECISION (option d): a profile with no FILL share (every V2 tier) never
		# picked a FILL site in the scripted tower scenes (24 of 24 thinks picked a TIP site), yet the
		# top-up of every targeted shortfall (60-90 sites) cost ~15-24 % of a think in FILL plus the
		# probe/rank of those sites. FILL is now only a fallback for ZERO targeted sites.
		# fill_share > 0 is unchanged.
		if capped and not out.is_empty():
			return
		fallback_ran = capped
		_allowed = gen.fill_orientations()
		_attempts = needed * maxi(gen.t.fill_attempts_per_site, 1)

	func attempts_left() -> int:
		return _attempts

	## Runs at most `max_attempts` fill draws; true once the fill is finished.
	func fill_step(max_attempts: int) -> bool:
		if _gen == null:
			return true
		var left: int = maxi(max_attempts, 1)
		while left > 0 and _attempts > 0 and not _gen.is_full() and out.size() < _stop_at:
			left -= 1
			_attempts -= 1
			_gen.fill_one(_rng, _allowed)
		return _attempts <= 0 or _gen.is_full() or out.size() >= _stop_at


## Per-call generation state (keeps the static entry point short).
class _Gen:
	extends RefCounted
	const _FOUNDATION_DIRECTIONS: int = 8
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
	## replaces the 1t5.54 debris clearance: a site must rest on the disc or on block faces
	## flat against it whose pile holds the piece in the analysed snapshot (_rests_flat).
	var flat_supports_only: bool = false

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

	## P4: `infos` already holds only orientations whose own centre of mass stands on their contact
	## squares (BotStatics.orientation_infos); the stability model judges each site in PROBE, so generation only
	## offers a spread. Tip: highest reach, then widest own margin, then largest grip. Stack: flattest first.
	func _rank_orientations() -> void:
		var tip: Array[BotStatics.OrientationInfo] = infos.duplicate()
		tip.sort_custom(func(a: BotStatics.OrientationInfo, b: BotStatics.OrientationInfo) -> bool:
			var ra: float = _reach(a)
			var rb: float = _reach(b)
			if not is_equal_approx(ra, rb):
				return ra > rb
			if not is_equal_approx(a.self_margin, b.self_margin):
				return a.self_margin > b.self_margin
			if a.contact_area != b.contact_area:
				return a.contact_area > b.contact_area
			return a.index < b.index
		)
		_tip_orientations = tip.slice(0, maxi(t.tip_orientation_variants, 1))
		var stack: Array[BotStatics.OrientationInfo] = infos.duplicate()
		stack.sort_custom(func(a: BotStatics.OrientationInfo, b: BotStatics.OrientationInfo) -> bool:
			if a.height != b.height:
				return a.height < b.height
			if a.contact_area != b.contact_area:
				return a.contact_area > b.contact_area
			if not is_equal_approx(a.self_margin, b.self_margin):
				return a.self_margin > b.self_margin
			return a.index < b.index
		)
		_stack_orientations = stack.slice(0, maxi(t.stack_orientation_variants, 1))
		_add_tall_stack_orientations()

	## bots always laid bars flat: Reach the Sky also offers the
	## tallest orientations after the flattest ones; any eligible orientation may stand on a sound top.
	## DECISION: Reach the Sky only; other modes keep their flat-first stack orientations (and candidate sets).
	func _add_tall_stack_orientations() -> void:
		if view.mode != MatchConfig.GameMode.REACH_THE_SKY or t.stack_tall_variants <= 0:
			return
		var tall: Array[BotStatics.OrientationInfo] = []
		for info: BotStatics.OrientationInfo in infos:
			if not _stack_orientations.has(info):
				tall.append(info)
		tall.sort_custom(func(a: BotStatics.OrientationInfo, b: BotStatics.OrientationInfo) -> bool:
			if a.height != b.height:
				return a.height > b.height
			if a.top_area != b.top_area:
				return a.top_area > b.top_area
			if not is_equal_approx(a.self_margin, b.self_margin):
				return a.self_margin > b.self_margin
			return a.index < b.index
		)
		for info: BotStatics.OrientationInfo in tall.slice(0, t.stack_tall_variants):
			if info.height > _stack_orientations[0].height:
				_stack_orientations.append(info)

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
		# a site beyond the shrunk disc would fall; drop it (no-op unshrunk).
		if view.is_shrunk() and point.length() > view.live_radius:
			return false
		return PlacementRules.validate_point(point, view.raster, view.team_id) == PlacementRules.Result.VALID

	## Tallest own circles first, each with the centre and jittered neighbours.
	func add_stack_sites(target: Vector2, quota: int) -> void:
		var start: int = out.size()
		var tops: Array[Dictionary] = []
		for i: int in view.indices_of_team(view.team_id):
			var top: float = view.top_height(i)
			if top >= t.stack_min_height_m and _usable_top(i, top):
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

	## false when the snapshot knows circle `i`'s block and it is unsound (a leaning
	## block, or one carrying such a block); an unmatched circle or no snapshot keeps the old behaviour.
	func _usable_top(i: int, top: float) -> bool:
		var stack: BotStack = view.stack
		# DECISION (1t5.54 review): only Reach the Sky skips unsound tops; the other modes keep the old
		# sites until the E3 Classic screen says otherwise.
		if view.mode != MatchConfig.GameMode.REACH_THE_SKY or stack == null or not stack.is_analysed():
			return true
		var body: int = stack.body_near(
			Vector2(view.cx[i], view.cz[i]), BotEvaluator.stack_tuning.circle_match_radius_m, top
		)
		return body < 0 or stack.is_usable_top(body)

	## FOUNDATION sites at the new base and around it (jitter in the eight directions),
	## widest contact area first, then widest own margin, then lowest height.
	func add_foundation_sites(base: Vector2, quota: int) -> void:
		var start: int = out.size()
		var ranked: Array[BotStatics.OrientationInfo] = infos.duplicate()
		ranked.sort_custom(func(a: BotStatics.OrientationInfo, b: BotStatics.OrientationInfo) -> bool:
			if a.contact_area != b.contact_area:
				return a.contact_area > b.contact_area
			if not is_equal_approx(a.self_margin, b.self_margin):
				return a.self_margin > b.self_margin
			if a.height != b.height:
				return a.height < b.height
			return a.index < b.index
		)
		var variants: Array[BotStatics.OrientationInfo] = ranked.slice(0, maxi(t.stack_orientation_variants, 1))
		var jitters: Array[Vector2] = [Vector2.ZERO]
		for step: int in range(_FOUNDATION_DIRECTIONS):
			jitters.append(Vector2.from_angle(TAU * float(step) / float(_FOUNDATION_DIRECTIONS)))
		for jitter: Vector2 in jitters:
			for orientation: BotStatics.OrientationInfo in variants:
				if out.size() - start >= quota or is_full():
					return
				_try_add(base + jitter * t.foundation_jitter_m, orientation, SITE_FOUNDATION, false, 0.0)

	## Orientations the uniform fill may use: every eligible one.
	func fill_orientations() -> Array[BotStatics.OrientationInfo]:
		return infos

	## One uniform sample of the disk; a site is added when it is own, valid territory.
	func fill_one(rng: RandomNumberGenerator, allowed: Array[BotStatics.OrientationInfo]) -> void:
		var angle: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * view.field_radius
		var point: Vector2 = Vector2(cos(angle), sin(angle)) * dist
		var orientation: BotStatics.OrientationInfo = allowed[rng.randi() % allowed.size()]
		# Cheap reject first: a draw outside the team's own territory can never
		# be VALID, and most draws are, so the full validate_point chain runs only for the rest.
		# Inlined CellGrid.world_to_cell (identical arithmetic; ~1000 draws a think).
		var grid: CellGrid = view.grid
		var cell: Vector2i = Vector2i(
			floori((point.x + grid.half_extent) / grid.cell_size),
			floori((point.y + grid.half_extent) / grid.cell_size)
		)
		if view.raster.team_at(cell.x, cell.y) != view.team_id:
			return
		_try_add(point, orientation, SITE_FILL, false, 0.0)

	## true when the piece with its pivot at `origin` rests on the disc, or on block faces flat
	## against it whose pile keeps the centre of mass inside every support (BotStack.rest_margin >= 0); true
	## without an analysed snapshot. DECISION: the model probes every bottom cube, not the tier's
	## stability_raycast_count (that cap limits real rays; a snapshot lookup is cheap), and the piece's mass is
	## its cube count times the shipped cube mass.
	func _rests_flat(origin: Vector2, orientation: BotStatics.OrientationInfo) -> bool:
		var stack: BotStack = view.stack
		if stack == null or not stack.is_analysed():
			return true
		var points: PackedVector2Array = PackedVector2Array()
		for offset: Vector2 in orientation.contact:
			points.append(origin + offset * view.cube_size)
		var mass: float = BotWorldView.SHIPPED_PHYSICS_TUNING.cube_mass * float(view.held.cells.size())
		return stack.rest_margin(points, origin + orientation.com * view.cube_size, mass) >= 0.0

	## Adds the site when placeable and not a duplicate; true when added.
	func _try_add(
		point: Vector2, orientation: BotStatics.OrientationInfo, kind: int, on_stack: bool, stack_top: float
	) -> bool:
		# `point` is where the piece's footprint centre should land; the origin is
		# the pivot the host tests (centre_shift is 0 for yaw-only orientations).
		var origin: Vector2 = point - orientation.center_shift * view.cube_size
		if not _placeable(origin):
			return false
		if flat_supports_only and not _rests_flat(origin, orientation):
			return false
		var key: Vector3i = Vector3i(
			roundi(origin.x / t.distinct_quantum_m), roundi(origin.y / t.distinct_quantum_m), orientation.index
		)
		if _seen.has(key):
			return false
		_seen[key] = true
		var candidate: BotCandidate = BotCandidate.new()
		candidate.origin = origin
		candidate.orientation_index = orientation.index
		candidate.site_kind = kind
		candidate.support_height = stack_top if on_stack else 0.0
		candidate.shape_height = orientation.height
		candidate.top_height = candidate.support_height + candidate.shape_height
		candidate.top_area = orientation.top_area
		candidate.footprint_cells = BotStatics.footprint_cells_of(
			view.held, orientation, candidate.origin, view.cube_size, view.grid
		)
		out.append(candidate)
		return true
