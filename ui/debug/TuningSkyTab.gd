class_name TuningSkyTab
extends RefCounted
## The F4 panel's Sky tab model: the sky resources and their section tags, the time-of-day state,
## and the live apply of an edit onto every Skybox in Skybox.TUNING_GROUP. The panel keeps the row
## widgets and calls this for everything else.
## DECISION: the live Skyboxes are found by walking that group (the same seam every F4 live-apply
## uses) rather than the Skybox listening to Resource.changed; a debug tool editing live world nodes
## is accepted, and a tab built in the panel's _ready dies with it, so the tree it holds is never
## stale.

const TIME_RUNNING: String = "running"
const TIME_CUSTOM: String = "custom"
## The three concrete ids are SkyCycleDef.locked_phase_for() keys (MatchConfig.SKY_THEME_IDS).
const TIME_OF_DAY_CHOICES: PackedStringArray = [TIME_RUNNING, "sunset", "dawn", "night", TIME_CUSTOM]
## Custom slider seed when no live cycle can report its phase (0.25 = noon).
const TIME_OF_DAY_DEFAULT_CUSTOM_PHASE: float = 0.25
## A live locked phase within this of a preset's phase reads as that preset.
const TIME_OF_DAY_PHASE_EPSILON: float = 0.001
## Section heading prefixes: the day keyframes by position, the night keyframe, the overlay.
const TAG_DAY_KEYS: PackedStringArray = ["Day key", "Evening key"]
const TAG_NIGHT: String = "Night key"
const TAG_STORM: String = "Storm"
const CYCLE_LENGTH_PROP: String = "cycle_length_seconds"
const LOCKED_PHASE_PROP_PREFIX: String = "cycle_locked_phase"
const NOT_LOCKED: float = -1.0

## The selected Time-of-day choice (a TIME_OF_DAY_CHOICES entry). Session-local, nothing persists.
var time_choice: String = TIME_RUNNING

var _cycle: SkyCycleDef = null
var _overlay: SkyOverlayDef = null
var _tree: SceneTree = null
var _custom_phase: float = TIME_OF_DAY_DEFAULT_CUSTOM_PHASE
## The shipped sky_cycle.tres loaded fresh: the baseline of the cycle's own fields and of its
## keyframes (sub-resources have no file of their own to reload). Cleared by reset().
var _fresh_cycle: SkyCycleDef = null


## `_skybox_config` is accepted for the panel's call shape; the tab edits only the cycle and overlay.
func _init(cycle: SkyCycleDef, overlay: SkyOverlayDef, _skybox_config: SkyboxConfig, tree: SceneTree) -> void:
	_cycle = cycle
	_overlay = overlay
	_tree = tree


## The Sky tab's resources in row order: the cycle, its day keyframes, the night keyframe, the storm
## overlay.
func resources() -> Array[Resource]:
	var found: Array[Resource] = [_cycle]
	for key: SkyKeyframe in _cycle.day_keyframes:
		found.append(key)
	if _cycle.night != null:
		found.append(_cycle.night)
	found.append(_overlay)
	return found


func owns(resource: Resource) -> bool:
	return resource != null and resources().has(resource)


## The heading prefix that tells the day keyframes, the night keyframe and the overlay apart ("" for
## the cycle itself and for a resource the tab does not own).
func section_tag(resource: Resource) -> String:
	if resource == null or resource == _cycle:
		return ""
	if resource == _cycle.night:
		return TAG_NIGHT
	if resource == _overlay:
		return TAG_STORM
	var index: int = _day_key_index(resource)
	if index < 0:
		return ""
	return TAG_DAY_KEYS[index] if index < TAG_DAY_KEYS.size() else "Day key %d" % (index + 1)


## The shipped value source for a resource that has no file of its own (the cycle and its keyframes:
## sub-resources of sky_cycle.tres). Null for every other resource.
func shipped_counterpart(resource: Resource) -> Resource:
	if resource == null or not _is_cycle_part(resource):
		return null
	if _fresh_cycle == null:
		_fresh_cycle = ResourceLoader.load(_cycle.resource_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SkyCycleDef
	if _fresh_cycle == null:
		return null
	if resource == _cycle:
		return _fresh_cycle
	if resource == _cycle.night:
		return _fresh_cycle.night
	var index: int = _day_key_index(resource)
	if index < _fresh_cycle.day_keyframes.size():
		return _fresh_cycle.day_keyframes[index]
	return null


func has_running_cycle() -> bool:
	for skybox: Skybox in _live_skyboxes():
		if skybox.is_cycle_active():
			return true
	return false


## The phase the Custom slider shows for the current choice.
func displayed_phase() -> float:
	var phase: float = _phase_for(time_choice)
	return phase if phase >= 0.0 else _custom_phase


## Selects a Time-of-day `choice` on every live cycle Skybox: running unlocks, sunset/dawn/night lock
## at the cycle's preset phase, custom locks where the cycle is now. False for an unknown choice.
func apply_time_of_day(choice: String) -> bool:
	if not TIME_OF_DAY_CHOICES.has(choice):
		return false
	time_choice = choice
	if choice == TIME_CUSTOM:
		var live: float = _live_cycle_phase()
		if live >= 0.0:
			_custom_phase = live
	_push_locked_phase(_phase_for(choice))
	return true


## The Custom slider: locks every live cycle Skybox at `phase` (clamped 0..1).
func apply_custom_time_of_day(phase: float) -> void:
	time_choice = TIME_CUSTOM
	_custom_phase = clampf(phase, 0.0, 1.0)
	_push_locked_phase(_custom_phase)


## Applies an edit of `resource.prop` onto the live skies. True when the edit was the tab's own.
func on_field_changed(resource: Resource, prop: String) -> bool:
	if not owns(resource):
		return false
	# The day/night cycle length is a rate, not a look: it goes through its own seam so the time of
	# day stays put.
	if resource == _cycle and prop == CYCLE_LENGTH_PROP:
		for skybox: Skybox in _live_skyboxes():
			skybox.set_cycle_length_seconds(_cycle.cycle_length_seconds)
		return true
	_apply_sky_def_live()
	# Editing a preset's locked phase moves the sky now when that preset is the selected time of day.
	if resource == _cycle and prop.begins_with(LOCKED_PHASE_PROP_PREFIX) and time_choice != TIME_CUSTOM:
		_push_locked_phase(_phase_for(time_choice))
	return true


## Reloads the shipped values of the cycle, its keyframes, the night keyframe and the storm overlay
## onto the same live instances, then re-applies them to the live skies.
func reset() -> void:
	_fresh_cycle = null
	for resource: Resource in resources():
		var shipped: Resource = shipped_counterpart(resource)
		if shipped == null:
			TuningOverrides.reset_resource(resource)
			continue
		for prop: Dictionary in resource.get_property_list():
			var type: int = int(prop.get("type", TYPE_NIL))
			# Sub-resources and the keyframe array stay the live objects; only plain values reload.
			if TuningOverrides.is_exported_field(prop) and type != TYPE_OBJECT and type != TYPE_ARRAY:
				var prop_name: String = str(prop.get("name", ""))
				resource.set(prop_name, shipped.get(prop_name))
	_apply_sky_def_live()


func _is_cycle_part(resource: Resource) -> bool:
	return resource == _cycle or resource == _cycle.night or _day_key_index(resource) >= 0


func _day_key_index(resource: Resource) -> int:
	if resource is SkyKeyframe:
		return _cycle.day_keyframes.find(resource as SkyKeyframe)
	return -1


func _live_skyboxes() -> Array[Skybox]:
	var found: Array[Skybox] = []
	for node: Node in _tree.get_nodes_in_group(Skybox.TUNING_GROUP):
		var skybox: Skybox = node as Skybox
		if skybox != null:
			found.append(skybox)
	return found


## Copies the cycle's plain fields onto every live Skybox's own sky_def copy (the keyframes, night
## and materials are shared sub-resources) and asks each Skybox to re-evaluate, so a palette edit
## shows on the next tick.
func _apply_sky_def_live() -> void:
	for skybox: Skybox in _live_skyboxes():
		if skybox.sky_def != null and skybox.sky_def != _cycle:
			_copy_plain_fields(_cycle, skybox.sky_def)
		skybox.refresh_sky_def()


func _copy_plain_fields(from: Resource, to: Resource) -> void:
	for prop: Dictionary in from.get_property_list():
		if not TuningOverrides.is_exported_field(prop):
			continue
		var type: int = int(prop.get("type", TYPE_NIL))
		if type == TYPE_BOOL or type == TYPE_INT or type == TYPE_FLOAT or type == TYPE_COLOR:
			var prop_name: String = str(prop.get("name", ""))
			to.set(prop_name, from.get(prop_name))


## The phase `choice` locks the cycle at; NOT_LOCKED for running (and for an unresolvable preset,
## which then leaves the cycle running).
func _phase_for(choice: String) -> float:
	if choice == TIME_RUNNING:
		return NOT_LOCKED
	if choice == TIME_CUSTOM:
		return _custom_phase
	return _cycle.locked_phase_for(choice)


func _push_locked_phase(phase: float) -> void:
	for skybox: Skybox in _live_skyboxes():
		if skybox.is_cycle_active():
			skybox.set_locked_phase(phase)


## The phase of the first live cycle Skybox (NOT_LOCKED when none runs one).
func _live_cycle_phase() -> float:
	for skybox: Skybox in _live_skyboxes():
		if skybox.is_cycle_active():
			return skybox.current_cycle_phase()
	return NOT_LOCKED


## Seeds the state from the first live cycle Skybox (a match may have locked it from the lobby):
## running, a preset whose phase matches, or custom. The panel calls it when it builds the row.
func sync_from_live() -> void:
	for skybox: Skybox in _live_skyboxes():
		if not skybox.is_cycle_active():
			continue
		var locked: float = skybox.locked_phase()
		var current: float = skybox.current_cycle_phase()
		if current >= 0.0:
			_custom_phase = current
		if locked < 0.0:
			time_choice = TIME_RUNNING
			return
		_custom_phase = locked
		time_choice = _choice_for_phase(locked)
		return


func _choice_for_phase(phase: float) -> String:
	for choice: String in TIME_OF_DAY_CHOICES:
		var preset: float = _cycle.locked_phase_for(choice)
		if preset >= 0.0 and absf(preset - phase) <= TIME_OF_DAY_PHASE_EPSILON:
			return choice
	return TIME_CUSTOM
