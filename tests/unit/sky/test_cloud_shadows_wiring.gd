extends GutTest
## CloudShadows follows exactly the Skybox that skybox_path names (siblings wired in the scene).

const DELTA_S: float = 0.016
const NOON_PHASE: float = 0.25
const NIGHT_ID: String = "night"

var _root: Node3D = null


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)


func _sky(sky_name: String, phase: float) -> Skybox:
	var skybox: Skybox = SkyTestKit.make_skybox(_root)
	skybox.name = sky_name
	skybox.set_locked_phase(phase)
	return skybox


func _night_phase() -> float:
	return SkyTestKit.cycle().locked_phase_for(NIGHT_ID)


func _shadows(path: NodePath) -> CloudShadows:
	var shadows: CloudShadows = CloudShadows.new()
	shadows.skybox_path = path
	_root.add_child(shadows)
	return shadows


func _visible_decals(shadows: CloudShadows) -> int:
	var count: int = 0
	for child: Node in shadows.get_children():
		if child is Decal and (child as Decal).visible:
			count += 1
	return count


func test_wired_noon_skybox_shows_decals() -> void:
	_sky("Sky", NOON_PHASE)
	var shadows: CloudShadows = _shadows(^"../Sky")
	shadows._process(DELTA_S)
	assert_gt(_visible_decals(shadows), 0, "noon sun of the wired sky casts shadows")


func test_wired_night_skybox_hides_decals() -> void:
	_sky("Sky", _night_phase())
	var shadows: CloudShadows = _shadows(^"../Sky")
	shadows._process(DELTA_S)
	assert_eq(_visible_decals(shadows), 0, "night: no shadows")


func test_decals_follow_the_wired_sky_when_it_changes() -> void:
	var skybox: Skybox = _sky("Sky", _night_phase())
	var shadows: CloudShadows = _shadows(^"../Sky")
	shadows._process(DELTA_S)
	assert_eq(_visible_decals(shadows), 0)
	skybox.set_locked_phase(NOON_PHASE)
	shadows._process(DELTA_S)
	assert_gt(_visible_decals(shadows), 0, "the wired sky's sun drives the decals")


func test_unwired_noon_skybox_is_ignored_when_wired_sky_is_night() -> void:
	_sky("Night", _night_phase())
	var other: Skybox = _sky("Noon", NOON_PHASE)
	assert_true(other.is_in_group(Skybox.OVERCAST_GROUP), "the other sky is a live Skybox")
	var shadows: CloudShadows = _shadows(^"../Night")
	shadows._process(DELTA_S)
	assert_eq(_visible_decals(shadows), 0, "only the wired sky counts")


func test_unwired_night_skybox_does_not_hide_wired_noon_sky() -> void:
	_sky("Night", _night_phase())
	_sky("Noon", NOON_PHASE)
	var shadows: CloudShadows = _shadows(^"../Noon")
	shadows._process(DELTA_S)
	assert_gt(_visible_decals(shadows), 0)


func test_empty_skybox_path_does_nothing_and_raises_no_error() -> void:
	_sky("Noon", NOON_PHASE)
	var shadows: CloudShadows = _shadows(NodePath())
	shadows._process(DELTA_S)
	shadows._process(DELTA_S)
	assert_eq(_visible_decals(shadows), 0, "no wired sky, no shadows even with a noon sky around")


func test_path_to_a_missing_node_does_nothing() -> void:
	var shadows: CloudShadows = _shadows(^"../Nothing")
	shadows._process(DELTA_S)
	assert_eq(_visible_decals(shadows), 0)
