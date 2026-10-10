class_name BotChains
extends RefCounted
## Bot V2 (docs/BOT_AI_REDESIGN.md 2.3 step 2, Bontago-1t5.22): the per-team overlap
## graph of influence circles, rooted at the team's living home flag(s). Answers
## "how much does a cut here remove" (downstream, articulation) and "how far is
## this team's home-connected land from a point" (gap_to). Pure: reads a
## BotWorldView snapshot only. Indices are BotWorldView block-circle indices.
##
## A circle is "connected" when a chain of overlapping same-team circles links it to
## a home circle of its team (TerritorySolver's rule: components without a home circle
## are dropped). Roots are BotWorldView.team_homes (living homes of the viewing team,
## teammates included) and the enemy homes; a dead home is not a root.

var _view: BotWorldView = null
var _count: int = 0
var _adj: Array[PackedInt32Array] = []
var _touch_home: PackedByteArray = PackedByteArray()
var _downstream: PackedInt32Array = PackedInt32Array()
var _connected: PackedByteArray = PackedByteArray()
var _team_connected: Dictionary[int, int] = {}
var _team_homes: Dictionary[int, PackedVector2Array] = {}


## Builds the graph for every team in `view`.
static func build(view: BotWorldView) -> BotChains:
	var chains: BotChains = BotChains.new()
	chains._view = view
	chains._count = view.circle_count()
	chains._index_homes()
	chains._build_graph()
	chains._solve()
	return chains


## Circles lost (the circle itself plus everything that stops being connected to a
## home) if circle `i` were removed; 0 when `i` is not connected. 1 for a leaf.
func downstream(i: int) -> int:
	if i < 0 or i >= _count:
		return 0
	return _downstream[i]


## True when removing circle `i` disconnects at least one other circle from home.
func is_articulation(i: int) -> bool:
	return downstream(i) > 1


## True when circle `i` is linked to a home of its team.
func connected(i: int) -> bool:
	return i >= 0 and i < _count and _connected[i] == 1


## Number of home-connected block circles of `team`.
func connected_count(team: int) -> int:
	return _team_connected.get(team, 0)


## Minimum over the team's home-connected circles (and its home circles) of
## distance to `point` minus radius; negative inside the land, INF when the team has
## neither a home nor a connected circle.
func gap_to(team: int, point: Vector2) -> float:
	var best: float = INF
	var homes: PackedVector2Array = _team_homes.get(team, PackedVector2Array())
	for home: Vector2 in homes:
		best = minf(best, home.distance_to(point) - _view.territory_tuning.home_radius)
	for i: int in range(_count):
		if _view.cteam[i] != team or _connected[i] == 0:
			continue
		best = minf(best, Vector2(_view.cx[i], _view.cz[i]).distance_to(point) - _view.cr[i])
	return best


## Total circles that stop being home-connected if every circle in `removed` is
## taken out (the removed ones count as lost). Unconnected entries are ignored.
## Exact for several simultaneous removals, unlike summing downstream().
func cut_loss(removed: PackedInt32Array) -> int:
	var gone: PackedByteArray = PackedByteArray()
	gone.resize(_count)
	var teams: Dictionary[int, bool] = {}
	for i: int in removed:
		if i >= 0 and i < _count and _connected[i] == 1:
			gone[i] = 1
			teams[_view.cteam[i]] = true
	var lost: int = 0
	for team: int in teams:
		lost += _connected_count_of(team) - _reached_without(team, gone)
	return lost


func _connected_count_of(team: int) -> int:
	return _team_connected.get(team, 0)


func _index_homes() -> void:
	for home: Vector2 in _view.team_homes:
		_add_home(_view.team_id, home)
	for h: int in range(_view.enemy_homes.size()):
		var team: int = _view.enemy_home_teams[h] if h < _view.enemy_home_teams.size() else -1
		_add_home(team, _view.enemy_homes[h])


func _add_home(team: int, position: Vector2) -> void:
	var homes: PackedVector2Array = _team_homes.get(team, PackedVector2Array())
	homes.append(position)
	_team_homes[team] = homes


func _build_graph() -> void:
	_adj.resize(_count)
	_touch_home.resize(_count)
	_downstream.resize(_count)
	_connected.resize(_count)
	var home_r: float = _view.territory_tuning.home_radius
	for i: int in range(_count):
		var ci: Vector2 = Vector2(_view.cx[i], _view.cz[i])
		var homes: PackedVector2Array = _team_homes.get(_view.cteam[i], PackedVector2Array())
		for home: Vector2 in homes:
			var reach_home: float = _view.cr[i] + home_r
			if home.distance_squared_to(ci) <= reach_home * reach_home:
				_touch_home[i] = 1
				break
		for j: int in range(i + 1, _count):
			if _view.cteam[j] != _view.cteam[i]:
				continue
			var reach: float = _view.cr[i] + _view.cr[j]
			if ci.distance_squared_to(Vector2(_view.cx[j], _view.cz[j])) <= reach * reach:
				_adj[i].append(j)
				_adj[j].append(i)


## Lowpoint DFS from a virtual root joined to every home-touching circle; the sum of
## the sizes of a vertex's cut-off child subtrees plus itself is its downstream.
func _solve() -> void:
	var disc: PackedInt32Array = PackedInt32Array()
	var low: PackedInt32Array = PackedInt32Array()
	var size: PackedInt32Array = PackedInt32Array()
	var parent: PackedInt32Array = PackedInt32Array()
	var cut_sum: PackedInt32Array = PackedInt32Array()
	var edge_pos: PackedInt32Array = PackedInt32Array()
	for arr: PackedInt32Array in [disc, low, size, parent, cut_sum, edge_pos]:
		arr.resize(_count)
	disc.fill(-1)
	var timer: int = 0
	for start: int in range(_count):
		if _touch_home[start] == 0 or disc[start] != -1:
			continue
		var stack: PackedInt32Array = PackedInt32Array([start])
		timer += 1
		disc[start] = timer
		low[start] = 0
		size[start] = 1
		parent[start] = -1
		while not stack.is_empty():
			var v: int = stack[stack.size() - 1]
			if edge_pos[v] < _adj[v].size():
				var w: int = _adj[v][edge_pos[v]]
				edge_pos[v] += 1
				if disc[w] == -1:
					timer += 1
					parent[w] = v
					disc[w] = timer
					low[w] = 0 if _touch_home[w] == 1 else timer
					size[w] = 1
					stack.append(w)
				elif w != parent[v]:
					low[v] = mini(low[v], disc[w])
			else:
				stack.remove_at(stack.size() - 1)
				var p: int = parent[v]
				if p >= 0:
					low[p] = mini(low[p], low[v])
					size[p] += size[v]
					if low[v] >= disc[p]:
						cut_sum[p] += size[v]
	for i: int in range(_count):
		if disc[i] == -1:
			continue
		_connected[i] = 1
		_downstream[i] = 1 + cut_sum[i]
		var team: int = _view.cteam[i]
		_team_connected[team] = _team_connected.get(team, 0) + 1


## Circles of `team` still home-connected when those flagged in `gone` are removed.
func _reached_without(team: int, gone: PackedByteArray) -> int:
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(_count)
	var stack: PackedInt32Array = PackedInt32Array()
	for i: int in range(_count):
		if _view.cteam[i] == team and _touch_home[i] == 1 and gone[i] == 0:
			seen[i] = 1
			stack.append(i)
	var reached: int = stack.size()
	while not stack.is_empty():
		var v: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		for w: int in _adj[v]:
			if seen[w] == 0 and gone[w] == 0:
				seen[w] = 1
				reached += 1
				stack.append(w)
	return reached
