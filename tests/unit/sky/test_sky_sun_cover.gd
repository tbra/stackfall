extends GutTest
## game/sky/SunCloudCover.gd: the refresh timing and the sea hand-off shared by CloudShadows and
## SunFlare.

const REFRESH_S: float = 0.5
const ORIGIN: Vector3 = Vector3(0.0, 10.0, 0.0)

var _lookups: int = 0


func before_each() -> void:
	_lookups = 0


func _no_sea() -> CloudSea:
	_lookups += 1
	return null


## A sea with one puff right above ORIGIN.
func _sea_over_origin() -> CloudSea:
	var theme: SkyThemeDef = Skybox.load_theme("sunset").duplicate() as SkyThemeDef
	theme.cloud_clump_count = 1
	theme.cloud_bank_count = 0
	theme.proc_far_count = 0
	theme.cloud_puffs_per_clump = 1
	theme.cloud_drift_speed_min_mps = 0.0
	theme.cloud_drift_speed_max_mps = 0.0
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure(theme, 1.0, null, 1)
	return sea


func test_no_sea_hides_nothing_and_is_looked_up_each_refresh() -> void:
	var cover: SunCloudCover = SunCloudCover.new(_no_sea, true)
	assert_eq(cover.query(ORIGIN, Vector3.UP, null, REFRESH_S), 0.0)
	assert_eq(_lookups, 1)
	cover.advance(REFRESH_S * 0.5)
	cover.query(ORIGIN, Vector3.UP, null, REFRESH_S)
	assert_eq(_lookups, 1, "between refreshes the last answer stands")
	cover.advance(REFRESH_S)
	cover.query(ORIGIN, Vector3.UP, null, REFRESH_S)
	assert_eq(_lookups, 2)


func test_immediate_first_query_versus_waiting_a_period() -> void:
	var immediate: SunCloudCover = SunCloudCover.new(_no_sea, true)
	immediate.query(ORIGIN, Vector3.UP, null, REFRESH_S)
	assert_eq(_lookups, 1)
	var waiting: SunCloudCover = SunCloudCover.new(_no_sea, false)
	waiting.query(ORIGIN, Vector3.UP, null, REFRESH_S)
	assert_eq(_lookups, 1, "the first query waits a full period")
	waiting.advance(REFRESH_S)
	waiting.query(ORIGIN, Vector3.UP, null, REFRESH_S)
	assert_eq(_lookups, 2)


func test_cover_matches_the_sea_query_and_holds_between_refreshes() -> void:
	var sea: CloudSea = _sea_over_origin()
	var puffs: PackedFloat32Array = sea.occlusion().puffs
	var centre: Vector3 = Vector3(puffs[0], puffs[1], puffs[2])
	var from: Vector3 = centre - Vector3(0.0, 5.0, 0.0)
	var cover: SunCloudCover = SunCloudCover.new(func() -> CloudSea: return sea, true)
	var expected: float = sea.sun_ray_cloud_occlusion(from, Vector3.UP, null)
	assert_gt(expected, 0.0, "fixture: the ray hits the puff")
	assert_eq(cover.query(from, Vector3.UP, null, REFRESH_S), expected)
	assert_eq(cover.query(from + Vector3(500.0, 0.0, 0.0), Vector3.UP, null, REFRESH_S), expected)
	cover.advance(REFRESH_S)
	assert_eq(cover.query(from + Vector3(500.0, 0.0, 0.0), Vector3.UP, null, REFRESH_S), 0.0)


func test_clear_and_reset() -> void:
	var sea: CloudSea = _sea_over_origin()
	var puffs: PackedFloat32Array = sea.occlusion().puffs
	var from: Vector3 = Vector3(puffs[0], puffs[1] - 5.0, puffs[2])
	var cover: SunCloudCover = SunCloudCover.new(func() -> CloudSea: return sea, true)
	assert_gt(cover.query(from, Vector3.UP, null, REFRESH_S), 0.0)
	cover.clear()
	assert_eq(cover.query(from, Vector3.UP, null, REFRESH_S), 0.0, "cleared answer stands until the refresh")
	cover.reset()
	assert_gt(cover.query(from, Vector3.UP, null, REFRESH_S), 0.0, "reset restores the immediate first query")
