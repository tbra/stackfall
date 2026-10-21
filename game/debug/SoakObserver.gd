class_name SoakObserver
extends RefCounted
## Reads live game state (Match, Net, the block registry, the intent counters, the sampler) into
## the observation objects SoakCheck takes. Internal to SoakMonitor; read-only.

const _PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const _BYTES_PER_MB: float = 1048576.0
const _NO_FOREIGN: float = -1.0

var _sampler: PerfSampler = null
# Per slot: the seconds-clock reading when its home cell first read foreign, -1 while it does not.
var _foreign_since: Dictionary = {}
# Per slot: [sent, accepted, refused] at the previous intents() call.
var _prev_counts: Dictionary = {}
var _blocks: Array[Block] = []


func _init(sampler: PerfSampler) -> void:
	_sampler = sampler


## Every tracked block; also the list `body_lines` dumps.
func bodies() -> Array[SoakCheck.BodyObs]:
	var found: Array[SoakCheck.BodyObs] = []
	_blocks = []
	var registry: BlockRegistry = Match.registry() as BlockRegistry
	if registry == null:
		return found
	_blocks = registry.all_blocks()
	for block: Block in _blocks:
		var obs: SoakCheck.BodyObs = SoakCheck.BodyObs.new()
		obs.id = block.net_id
		obs.transform = block.global_transform if block.is_inside_tree() else block.transform
		obs.owner_slot = block.owner_slot
		found.append(obs)
	return found


## Blocks awake, as the sampler's last window counted them (0 before its first window).
func awake_blocks() -> int:
	return int(_sampler.latest.get("blocks_awake", 0)) if _sampler != null else 0


## Static memory in megabytes, the one conversion the monitor and the sample line share.
static func static_mem_mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / _BYTES_PER_MB


func kill_plane_y() -> float:
	return _PHYSICS_TUNING.kill_plane_y


## The SOAK_BODY lines of the last bodies() call.
func body_lines(role: StringName, epoch: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	for block: Block in _blocks:
		if not is_instance_valid(block):
			continue
		var pose: Transform3D = block.global_transform if block.is_inside_tree() else block.transform
		lines.append(SoakLine.body(
			role, epoch, block.net_id, pose.origin, pose.basis.get_rotation_quaternion(),
			block.sleeping
		))
	return lines


## The raster as shares and recounted owned cells. `fresh_solve` runs the uncached re-solve.
func territory(fresh_solve: bool) -> SoakCheck.TerritoryObs:
	var obs: SoakCheck.TerritoryObs = SoakCheck.TerritoryObs.new()
	var raster: TerritoryRaster = Match.raster()
	if raster == null:
		return obs
	var teams: int = team_count()
	obs.shares.resize(teams)
	obs.owned_cells.resize(teams)
	for team: int in teams:
		obs.shares[team] = raster.team_share(team)
	var owners: PackedByteArray = raster.owner_bytes()
	var cells: PackedInt32Array = raster.grid().in_disk_cells()
	obs.in_disk_cells = cells.size()
	for index: int in cells:
		var team: int = int(owners[index]) - 1
		if team >= 0 and team < teams:
			obs.owned_cells[team] += 1
	if fresh_solve:
		obs.fresh_solve_checked = true
		obs.fresh_solve_matches = Match.fresh_solve_matches_live()
	return obs


## Living home flags and how long each has sat on another team's cell; `now_s` is any
## monotonic seconds clock.
func homes(now_s: float) -> Array[SoakCheck.HomeObs]:
	var found: Array[SoakCheck.HomeObs] = []
	var raster: TerritoryRaster = Match.raster()
	if raster == null:
		return found
	for slot_id: int in Match.slot_count():
		var slot: PlayerSlot = Match.slot(slot_id)
		if slot == null or not slot.home_flag_alive:
			continue
		var cell: Vector2i = raster.grid().world_to_cell(slot.home_position)
		var owner_team: int = raster.team_at(cell.x, cell.y)
		var obs: SoakCheck.HomeObs = SoakCheck.HomeObs.new()
		obs.slot = slot_id
		obs.team = Match.team_of(slot_id)
		if owner_team >= 0 and owner_team != obs.team:
			if not _foreign_since.has(slot_id):
				_foreign_since[slot_id] = now_s
			obs.foreign_for_s = now_s - float(_foreign_since[slot_id])
		else:
			_foreign_since.erase(slot_id)
		found.append(obs)
	return found


## Host only: the intent counters of every remote-driven slot against the previous call.
func intents() -> Array[SoakCheck.IntentObs]:
	var found: Array[SoakCheck.IntentObs] = []
	if not Net.is_host():
		return found
	var counters: NetCounters = MatchNet.counters
	for slot_id: int in Match.slot_count():
		var slot: PlayerSlot = Match.slot(slot_id)
		# DECISION: only slots a remote peer drives. The M3a identity (blocks_placed == accepted +
		# auto_drops) holds for intents that pass through MatchIntentGateway; a host-local human
		# places through Match directly and has no gateway counters.
		if not _is_remote_driven(slot):
			continue
		var obs: SoakCheck.IntentObs = SoakCheck.IntentObs.new()
		obs.slot = slot_id
		obs.sent = counters.sent_count(slot_id)
		obs.accepted = counters.accepted_count(slot_id)
		obs.refused = counters.refused_count(slot_id)
		obs.auto_drops = int(counters.auto_drops.get(slot_id, 0))
		obs.blocks_placed = Match.stats().blocks_placed(slot_id)
		var prev: Array = _prev_counts.get(slot_id, [0, 0, 0])
		obs.prev_sent = int(prev[0])
		obs.prev_accepted = int(prev[1])
		obs.prev_refused = int(prev[2])
		_prev_counts[slot_id] = [obs.sent, obs.accepted, obs.refused]
		found.append(obs)
	return found


## The first non-bot slot owned by a remote peer, which the fuzzer drives; -1 when none.
func fuzz_slot() -> int:
	for slot_id: int in Match.slot_count():
		var slot: PlayerSlot = Match.slot(slot_id)
		if _is_remote_driven(slot):
			return slot_id
	return -1


func _is_remote_driven(slot: PlayerSlot) -> bool:
	return slot != null and not slot.is_bot and not slot.is_local


func team_count() -> int:
	var teams: int = 0
	for slot_id: int in Match.slot_count():
		teams = maxi(teams, Match.team_of(slot_id) + 1)
	return teams


## The SOAK_SAMPLE keys that are plain reads of the live state.
func sample_fields(bodies_count: int, territory_obs: SoakCheck.TerritoryObs) -> Dictionary:
	var scores: Dictionary = {}
	for slot_id: int in Match.slot_count():
		scores[slot_id] = Match.stats().blocks_placed(slot_id)
	var raster: TerritoryRaster = Match.raster()
	return {
		"state": Match.State.find_key(Match.state()),
		"bodies": bodies_count,
		"awake": awake_blocks(),
		"shares": territory_obs.shares,
		"raster_hash": raster.ownership_hash() if raster != null else 0,
		"timer": Match.match_timer_left(),
		"scores": scores,
		"mem_mb": static_mem_mb(),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"bytes_total": SnapshotSync.snapshot_bytes_total(),
	}
