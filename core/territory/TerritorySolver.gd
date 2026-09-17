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

## Scratch, reused across solves: solve() runs at solve_hz forever, so nothing
## in the hot path may allocate a fresh container per call. Every one of these
## is a Packed*Array with exactly one owner, so element writes happen in place
## rather than triggering a copy-on-write duplicate.
var _parent: PackedInt32Array = PackedInt32Array()
var _rank: PackedInt32Array = PackedInt32Array()
## 1 while a circle survives the max_circles cap, 0 once it has been dropped.
var _kept: PackedByteArray = PackedByteArray()
var _group_of: PackedInt32Array = PackedInt32Array()
var _roots: PackedInt32Array = PackedInt32Array()
var _root_anchored: PackedByteArray = PackedByteArray()
var _root_group: PackedInt32Array = PackedInt32Array()

## Each circle's hash-cell range, in absolute hash coordinates. The min corner
## is what the pair de-duplication needs (see _collect_pairs); the max corner
## saves recomputing the division on the second insertion pass.
var _cell_x0: PackedInt32Array = PackedInt32Array()
var _cell_y0: PackedInt32Array = PackedInt32Array()
var _cell_x1: PackedInt32Array = PackedInt32Array()
var _cell_y1: PackedInt32Array = PackedInt32Array()

## The spatial hash is a dense grid covering the circles' bounding box rather
## than a Dictionary of buckets: at ~400 circles the dictionary hashing and the
## per-bucket Array objects cost more than the pair tests they index. Bucket b
## holds _bucket_items[_bucket_starts[b] .. _bucket_starts[b + 1]].
var _hash_origin_x: int = 0
var _hash_origin_y: int = 0
var _hash_w: int = 0
var _hash_h: int = 0
var _bucket_starts: PackedInt32Array = PackedInt32Array()
var _bucket_items: PackedInt32Array = PackedInt32Array()
var _bucket_cursor: PackedInt32Array = PackedInt32Array()

var _pair_count: int = 0


func _init(tuning: TerritoryTuning) -> void:
	_tuning = tuning


func tuning() -> TerritoryTuning:
	return _tuning


## The whole solver. `circles` mixes block circles and home circles in any
## order; home circles are the ones with is_home set. Order is preserved, so
## the indices in the returned groups index straight back into `circles`.
##
## Costs O(n + pairs) with the hash; the raster consumes the result directly.
func solve(circles: Array[InfluenceCircle]) -> TerritoryGroups:
	var count: int = circles.size()
	_pair_count = 0
	_group_of.resize(count)
	_group_of.fill(TerritoryGroups.NO_GROUP)

	var groups: TerritoryGroups = TerritoryGroups.new()
	if count == 0:
		return groups

	_select_kept(circles)

	_parent.resize(count)
	_rank.resize(count)
	for i: int in range(count):
		_parent[i] = i
		_rank[i] = 0

	_build_hash(circles)
	_collect_pairs(circles)
	_build_groups(circles, groups)
	return groups


## True when circle `index` ended up in a home-anchored group. Valid only
## after the matching solve() call; used by tests and by the block shader's
## "glows brighter when contributing influence" flag (spec 2.10).
##
## CONTRACT CHANGE (was `is_connected` in the M2 stub commit): TerritorySolver
## extends RefCounted, so `is_connected` collides with the native
## Object.is_connected(StringName, Callable) -> bool. Declaring it is a hard
## parse error ("The function signature doesn't match the parent"), plus a
## NATIVE_METHOD_OVERRIDE warning this project escalates to an error. The stub
## only ever compiled because nothing referenced TerritorySolver yet; the
## first package to touch the class breaks the whole build. The semantics are
## unchanged, only the name. Callers can equally use
## `group_of_circle(i) != TerritoryGroups.NO_GROUP`.
func is_circle_connected(index: int) -> bool:
	return group_of_circle(index) != TerritoryGroups.NO_GROUP


## The group a circle landed in, or TerritoryGroups.NO_GROUP. Same validity
## rule as is_circle_connected().
func group_of_circle(index: int) -> int:
	if index < 0 or index >= _group_of.size():
		return TerritoryGroups.NO_GROUP
	return _group_of[index]


## Candidate overlapping pairs the spatial hash produced for the last solve().
## Exposed so a unit test can assert the hash is not silently degenerating
## into all-pairs as radii grow.
func last_pair_count() -> int:
	return _pair_count


## -- max_circles safety valve ------------------------------------------------

## Marks which circles take part in this solve. Home circles always survive:
## they anchor whole groups, so dropping one would erase a player's entire
## territory rather than trimming its edge. The rest of the budget is handed
## out round-robin over the teams, widest circle first, so one player's forest
## of tall towers cannot starve everyone else out of the raster.
func _select_kept(circles: Array[InfluenceCircle]) -> void:
	var count: int = circles.size()
	_kept.resize(count)
	_kept.fill(1)

	var cap: int = _tuning.max_circles
	if cap <= 0 or count <= cap:
		return

	var by_team: Dictionary[int, Array] = {}
	var budget: int = cap
	for i: int in range(count):
		var circle: InfluenceCircle = circles[i]
		if circle.is_home:
			budget -= 1
			continue
		_kept[i] = 0
		if not by_team.has(circle.team_id):
			by_team[circle.team_id] = []
		var queue: Array = by_team[circle.team_id]
		queue.append(i)

	if budget <= 0:
		return

	for team: int in by_team:
		var queue: Array = by_team[team]
		queue.sort_custom(
			func(a: int, b: int) -> bool: return circles[a].radius > circles[b].radius
		)

	var teams: Array = by_team.keys()
	teams.sort()
	var round_index: int = 0
	while budget > 0:
		var handed_out: int = 0
		for team: int in teams:
			var queue: Array = by_team[team]
			if round_index >= queue.size():
				continue
			var i: int = queue[round_index]
			_kept[i] = 1
			handed_out += 1
			budget -= 1
			if budget <= 0:
				break
		if handed_out == 0:
			break
		round_index += 1


## -- Spatial hash ------------------------------------------------------------

## Inserts every kept circle into each hash cell its bounding box covers. See
## TerritoryTuning.hash_cell_size for why the cell is much smaller than spec
## 3.3's literal `influence_max`.
##
## The grid spans only the circles' own bounding box, which stays close to the
## disk: circles come from settled blocks resting on it, and their radii are
## capped at influence_max_fraction * field_radius. A block on its way off the
## map is not settled and so never reaches here.
func _build_hash(circles: Array[InfluenceCircle]) -> void:
	var count: int = circles.size()
	_cell_x0.resize(count)
	_cell_y0.resize(count)
	_cell_x1.resize(count)
	_cell_y1.resize(count)

	var size: float = maxf(_tuning.hash_cell_size, 0.001)
	var min_x: int = 0
	var min_y: int = 0
	var max_x: int = 0
	var max_y: int = 0
	var any: bool = false
	for i: int in range(count):
		if _kept[i] == 0:
			continue
		var circle: InfluenceCircle = circles[i]
		var x0: int = floori((circle.center.x - circle.radius) / size)
		var y0: int = floori((circle.center.y - circle.radius) / size)
		var x1: int = floori((circle.center.x + circle.radius) / size)
		var y1: int = floori((circle.center.y + circle.radius) / size)
		_cell_x0[i] = x0
		_cell_y0[i] = y0
		_cell_x1[i] = x1
		_cell_y1[i] = y1
		if any:
			min_x = mini(min_x, x0)
			min_y = mini(min_y, y0)
			max_x = maxi(max_x, x1)
			max_y = maxi(max_y, y1)
		else:
			min_x = x0
			min_y = y0
			max_x = x1
			max_y = y1
			any = true

	if not any:
		_hash_w = 0
		_hash_h = 0
		_bucket_starts.resize(1)
		_bucket_starts[0] = 0
		_bucket_items.resize(0)
		return

	_hash_origin_x = min_x
	_hash_origin_y = min_y
	_hash_w = max_x - min_x + 1
	_hash_h = max_y - min_y + 1

	var bucket_count: int = _hash_w * _hash_h
	_bucket_starts.resize(bucket_count + 1)
	_bucket_starts.fill(0)

	# Counting sort, pass 1: how many circles land in each bucket, tallied one
	# slot to the right so the prefix sum below turns counts into starts.
	var total: int = 0
	for i: int in range(count):
		if _kept[i] == 0:
			continue
		for cy: int in range(_cell_y0[i], _cell_y1[i] + 1):
			var row: int = (cy - min_y) * _hash_w - min_x
			for cx: int in range(_cell_x0[i], _cell_x1[i] + 1):
				_bucket_starts[row + cx + 1] += 1
				total += 1

	for b: int in range(1, bucket_count + 1):
		_bucket_starts[b] += _bucket_starts[b - 1]

	# Pass 2: scatter. Walking i upwards leaves every bucket sorted by circle
	# index, which _collect_pairs relies on for its (lower, higher) ordering.
	_bucket_cursor = _bucket_starts.duplicate()
	_bucket_items.resize(total)
	for i: int in range(count):
		if _kept[i] == 0:
			continue
		for cy: int in range(_cell_y0[i], _cell_y1[i] + 1):
			var row: int = (cy - min_y) * _hash_w - min_x
			for cx: int in range(_cell_x0[i], _cell_x1[i] + 1):
				var b: int = row + cx
				_bucket_items[_bucket_cursor[b]] = i
				_bucket_cursor[b] += 1


## Unions every pair of overlapping same-team circles the hash brings together.
##
## Two circles that share one hash cell usually share several, so a naive scan
## would test the same pair many times. Each pair is instead handled only in
## its canonical cell: the min corner of the two bounding boxes' overlap, which
## is (max(x0), max(y0)) and is always itself a shared cell. That is the
## "deduplicated by (lower index, higher index)" contract without a set of
## pairs to allocate and look up.
func _collect_pairs(circles: Array[InfluenceCircle]) -> void:
	var bucket_count: int = _hash_w * _hash_h
	for b: int in range(bucket_count):
		var start: int = _bucket_starts[b]
		var end: int = _bucket_starts[b + 1]
		if end - start < 2:
			continue
		var cell_x: int = b % _hash_w + _hash_origin_x
		var cell_y: int = b / _hash_w + _hash_origin_y
		for a: int in range(start, end - 1):
			var i: int = _bucket_items[a]
			var first: InfluenceCircle = circles[i]
			var first_team: int = first.team_id
			var i_x0: int = _cell_x0[i]
			var i_y0: int = _cell_y0[i]
			for c: int in range(a + 1, end):
				var j: int = _bucket_items[c]
				if maxi(i_x0, _cell_x0[j]) != cell_x:
					continue
				if maxi(i_y0, _cell_y0[j]) != cell_y:
					continue
				_pair_count += 1
				var second: InfluenceCircle = circles[j]
				# Spec 2.2: circles merge only within a team. Across teams an
				# overlap is a contest, which is the raster's business.
				if first_team != second.team_id:
					continue
				if first.overlaps(second):
					_union(i, j)


## -- Union-find --------------------------------------------------------------

func _find(index: int) -> int:
	var root: int = index
	while _parent[root] != root:
		root = _parent[root]
	var walk: int = index
	while _parent[walk] != root:
		var next: int = _parent[walk]
		_parent[walk] = root
		walk = next
	return root


func _union(a: int, b: int) -> void:
	var root_a: int = _find(a)
	var root_b: int = _find(b)
	if root_a == root_b:
		return
	if _rank[root_a] < _rank[root_b]:
		var swap: int = root_a
		root_a = root_b
		root_b = swap
	_parent[root_b] = root_a
	if _rank[root_a] == _rank[root_b]:
		_rank[root_a] += 1


## -- Group assembly ----------------------------------------------------------

## Keeps only components holding at least one home circle, which is spec 2.2's
## cut-off rule, and writes them out with ascending member indices.
func _build_groups(circles: Array[InfluenceCircle], groups: TerritoryGroups) -> void:
	var count: int = circles.size()

	# Resolve every circle's component once. Roots are circle indices, so the
	# per-root bookkeeping below is a flat array rather than a Dictionary.
	_roots.resize(count)
	_root_anchored.resize(count)
	_root_anchored.fill(0)
	var any_anchor: bool = false
	for i: int in range(count):
		if _kept[i] == 0:
			_roots[i] = -1
			continue
		var root: int = _find(i)
		_roots[i] = root
		if circles[i].is_home:
			_root_anchored[root] = 1
			any_anchor = true
	if not any_anchor:
		return

	_root_group.resize(count)
	_root_group.fill(TerritoryGroups.NO_GROUP)
	var group_teams: PackedInt32Array = PackedInt32Array()
	var group_sizes: PackedInt32Array = PackedInt32Array()
	var member_total: int = 0
	for i: int in range(count):
		var root: int = _roots[i]
		if root < 0 or _root_anchored[root] == 0:
			continue
		var group: int = _root_group[root]
		if group == TerritoryGroups.NO_GROUP:
			group = group_teams.size()
			_root_group[root] = group
			group_teams.append(circles[i].team_id)
			group_sizes.append(0)
		_group_of[i] = group
		group_sizes[group] += 1
		member_total += 1

	# Counting sort by group. `members` has a single owner, so the element
	# writes below happen in place instead of copying the array each time, and
	# walking i upwards leaves every group's slice already ascending.
	var group_count: int = group_teams.size()
	var starts: PackedInt32Array = PackedInt32Array()
	starts.resize(group_count + 1)
	var offset: int = 0
	for group: int in range(group_count):
		starts[group] = offset
		offset += group_sizes[group]
	starts[group_count] = offset

	var cursor: PackedInt32Array = starts.duplicate()
	var members: PackedInt32Array = PackedInt32Array()
	members.resize(member_total)
	for i: int in range(count):
		var group: int = _group_of[i]
		if group == TerritoryGroups.NO_GROUP:
			continue
		members[cursor[group]] = i
		cursor[group] += 1

	for group: int in range(group_count):
		groups.add_group(group_teams[group], members.slice(starts[group], starts[group + 1]))
