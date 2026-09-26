class_name Skybox
extends Node3D
## Runtime-loaded six-face placeholder skybox from the original 2003 Bontago
## install (spec 2.10, presentation). The faces are third-party assets and
## never shipped in this public repo (CLAUDE.md); tools/install_original_assets.ps1
## (owned by another package) copies them to
## `res://assets/original/textures/<set>/<face>.jpg` for local testing, and
## load_set() falls back to the existing ProceduralSkyMaterial untouched
## whenever that folder or a face inside it is missing.
##
## DECISION (game/Skybox.gd, Bontago-1en/assets-sky): six unshaded quads on a
## big inverted box, not a `shader_type sky` sampling a Cubemap. The box does
## not follow the camera -- box_half_extent (400 m) is far larger than any
## map's field_radius (60 m max) or the camera's zoom range
## (config/camera_tuning.tres: zoom_max 100 m), so the parallax from orbiting
## within the field is invisible in practice, at zero extra cost.
##
## DECISION (game/Skybox.gd, Bontago-xtq.8, owner 2026-09-23: "it reflects
## whatever light source you've put in but not the skybox we added
## recently"): the box alone was never enough -- the WorldEnvironment's own
## Sky resource is a separate thing the render server samples for reflections
## and ambient light (Main.tscn: ambient_light_source = AMBIENT_SOURCE_SKY),
## and drawing a box in front of the camera does not change what that
## resource shows. load_set() success now ALSO installs a `shader_type sky`
## ShaderMaterial (shaders/cubemap_sky.gdshader) onto `environment.sky.
## sky_material`, sampling the same six face textures with the same
## SkyboxConfig.face_rotations/face_flip_u/face_flip_v correction the box
## uses (shaders/cubemap_sky.gdshader's own doc has the per-face direction
## algebra, derived by inverting Skybox._face_corners()' corner mapping and
## checked against all four UV corners of all six faces). Reflections/ambient
## now show the loaded set's horizon instead of the ProceduralSkyMaterial
## gradient; a missing/failed set restores the original ProceduralSkyMaterial
## on the Sky resource exactly as it restores the box's fallback.
##
## The box mesh itself is deliberately kept rather than dropped now that the
## sky shader exists: the box is the one part of this system whose
## correctness was verified pixel-by-pixel (tools/skybox_seam_probe.gd's
## measured seam error) and is trivially checkable by eye in a single
## screenshot; the sky shader's face-selection math (its sky() function) was
## checked algebraically against all six faces' corners (see
## shaders/cubemap_sky.gdshader) and
## against two live camera yaws (docs/sky-reflection-before.png/-after.png),
## but a shader bug that only shows up at a grazing reflection angle this
## package's screenshots did not happen to catch would otherwise have no
## direct-view fallback to catch it visually during play. Once the sky
## shader has more mileage (e.g. the seam probe or an equivalent check is
## extended to score it the same way it scores the box), dropping the box and
## letting the sky alone draw the background is a safe, mechanical follow-up.
##
## Bontago-xtq.28 (M7 P3, docs/M7_ART_DIRECTION.md's sunset/atmosphere lines):
## two more pieces layer on top of the above, both applied only while
## `fallback_active` (the six-face box/shader are a separate, self-contained
## look and are left untouched by either):
##   - apply_theme() writes `theme`'s (config/SkyThemeDef.gd) sky/ground
##     colours onto `_fallback_sky_material` *in place*, its fog colour/
##     density onto the wired Environment's basic depth fog, and its
##     volumetric_fog_density/volumetric_fog_albedo onto that same
##     Environment's global ambient volumetric-fog fields (fix round 2 --
##     see SkyThemeDef.volumetric_fog_density's own doc for why the ambient
##     floor has to be set too, not just the FogVolume cloud deck below) --
##     called once from _ready(), so a later load_set() fallback restores the
##     themed colours automatically (see _restore_fallback_sky()) rather than
##     the material's own untouched defaults.
##   - a single FogVolume "cloud deck" child (_spawn_fog_volume()) is always
##     created, its `visible` flag alone tracking
##     GraphicsPreset.volumetric_fog_enabled (Settings.graphics_preset_changed,
##     the same read-only-preset pattern Main.gd's own P1 package
##     establishes) -- dropped from view entirely on Low, present on
##     Medium/High, per docs/M7_ART_DIRECTION.md's performance budget.

@export var config: SkyboxConfig = preload("res://config/skybox_config.tres")

## Bontago-xtq.28 (M7 P3): the sky/ground/fog palette applied onto the
## fallback ProceduralSkyMaterial whenever `fallback_active` is true -- see
## apply_theme() below and the class doc's new paragraph on it. Optional (null
## in a fixture that only cares about the box/fallback_active state); the game
## itself never overrides this from `preload`'s default, the same one-field/
## one-instance convention `config`/`visuals` above already use.
@export var theme: SkyThemeDef = preload("res://config/sky_themes/sunset.tres")
## The live Environment resource Main.tscn's WorldEnvironment displays
## (wired there by a plain node-property reference to the same sub-resource,
## not a node path -- CLAUDE.md's "no deep node paths" is about get_node()
## chains, not sharing one Resource two nodes both already own a reference
## to). Optional (null in a fixture test that only cares about the box/
## fallback_active state, e.g. most of tests/unit/test_skybox.gd): every sky-
## material write below is skipped when this or its .sky is unset.
@export var environment: Environment = null

## Bontago-xtq.12 (owner: "isn't very reflective, like at all"): Forward+
## never reflects dynamic scene geometry (the placed blocks) without a
## ReflectionProbe or SSR, so the disk's high metallic/low roughness
## (config/TerritoryVisuals.gd) only ever showed the sky's own smooth
## gradient -- reads as a dull tint, not a mirror. NodePath, not a typed Node
## export, matching game/PlayerController.gd's camera_rig_path/ghost_path
## convention elsewhere in this codebase. Wired in Main.tscn to a sibling
## ReflectionProbe over the disc; left empty in every test fixture below
## (most of tests/unit/test_skybox.gd), so configure_reflection_probe() must
## no-op cleanly with nothing wired, the same optionality `environment` above
## already has.
@export var reflection_probe_path: NodePath = NodePath("")
## config/TerritoryVisuals.gd's reflection_probe_* fields; defaulted the same
## way `environment` is optional above, but never actually null in practice
## (every real scene shares config/territory_visuals.tres, same as
## game/Field.gd's own `visuals` export).
@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")

const SKY_SHADER: Shader = preload("res://shaders/cubemap_sky.gdshader")
## Vertical position of the probe's box center, in meters above the disk
## surface (which sits at world y == 0 -- game/Field.gd positions its
## TerritoryOverlay at `-map_def.disk_height * 0.5`, negligible next to this
## scale). A small local constant, not a TerritoryVisuals field: it is a
## derived placement detail of reflection_probe_height_m right below, not an
## independent tunable a playtester would ever need to move on its own.
const PROBE_GROUND_CLEARANCE_M: float = 4.0

## Bontago-xtq.28 fix round: the cloud deck's box footprint/thickness/height
## are per-theme now (SkyThemeDef.cloud_deck_size_m/cloud_deck_height_m), not
## local constants here -- the previous candidate's centred-at-y40 box (y
## 10..70) enclosed the entire play volume up to NetConfig.pos_max_y (72.0)
## and the gameplay camera itself, which read as a uniform haze with no
## sunset gradient visible. See SkyThemeDef.gd's doc on those two fields for
## the corrected placement (well below the disk, clear of the stacking
## volume).

## The Sky's own material before this node ever touched it (Main.tscn's
## ProceduralSkyMaterial, captured once in _ready()) -- restored whenever
## load_set() falls back, the same moment the box itself is hidden.
var _fallback_sky_material: Material = null

## True whenever no textured box is showing (initial state, a missing
## set/face, or config.enabled == false) -- the existing ProceduralSkyMaterial
## is what's visible in every one of those cases. Read by tests and by a
## manual tester checking print() output.
var fallback_active: bool = true

var _face_textures: Dictionary = {}
var _face_meshes: Dictionary = {}

## Bontago-xtq.28: the FogVolume _spawn_fog_volume() created, or null when
## `theme` was unset in _ready() (see that method's own doc).
var _fog_volume: FogVolume = null

## Bontago-xtq.12 step 2 (F4 tuning panel live-apply, same idiom
## game/CameraRig.gd's own TUNING_GROUP doc explains): every Skybox adds
## itself to this group in _ready() so ui/TuningPanel.gd's
## refresh_territory_visuals_live() can push a live SSR/reflection-probe edit
## onto whichever Skybox is actually in the tree, the same way it already
## reaches every live CameraRig/Block, without needing its own reference to
## this node wired first.
const TUNING_GROUP: StringName = &"tuning_skybox"

## Bontago-xtq.22: the id apply_set()/list_available_sets() use for "no
## textured set -- keep the procedural sky", i.e. the empty string. Matches
## config.default_set's own type (String) so ui/TuningPanel.gd's dropdown can
## carry it as one more item alongside every real set name, with no separate
## sentinel enum/type to keep in sync between the two files.
const PROCEDURAL_SET_ID: String = ""


func _ready() -> void:
	add_to_group(TUNING_GROUP)
	if environment != null and environment.sky != null:
		_fallback_sky_material = environment.sky.sky_material
	for face_name: String in config.face_names:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.name = face_name.capitalize()
		mesh_instance.visible = false
		# The box is static and much larger than the play field (see class
		# doc), so there is nothing worth frustum-culling per frame against a
		# camera that is always deep inside it.
		mesh_instance.extra_cull_margin = config.box_half_extent
		add_child(mesh_instance)
		_face_meshes[face_name] = mesh_instance
	configure_reflection_probe()
	configure_ssr()
	apply_theme(theme)
	_spawn_fog_volume()
	_apply_fog_volume_visibility(Settings.current_graphics_preset())
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


## Public re-apply seam ui/TuningPanel.gd calls (via TUNING_GROUP above)
## whenever the owner edits a reflection tunable live in the F4 panel --
## configure_reflection_probe()/configure_ssr() otherwise only ever run once,
## at boot. Also the one place tools/screenshot_xtq11_disk_opaque.gd's
## `--mirror-mode=`/`--reflection-mode=` overrides re-apply their duplicated
## TerritoryVisuals after swapping `visuals` out from under an already-ready
## Skybox.
func refresh_from_visuals() -> void:
	configure_reflection_probe()
	configure_ssr()


## Bontago-xtq.12 step 2 (owner: "the disc isn't very reflective, like at
## all?" -- step 1's ReflectionProbe alone only ever showed a faint, blurred
## sky gradient): Forward+'s screen-space reflections trace the actual
## rendered depth/color buffer per pixel, so a block that is currently on
## screen shows up in the disk's reflection at roughly its true screen
## position -- the probe's own blurred, periodically-snapshotted cubemap
## cannot do that on its own. Written onto the wired Environment directly
## (not the ReflectionProbe node): SSR is a WorldEnvironment-level effect,
## the same as the sky/ambient the class doc's Bontago-xtq.8 DECISION
## explains. A no-op when no `environment` was wired or `visuals` is unset,
## matching configure_reflection_probe()'s own contract.
func configure_ssr() -> void:
	if visuals == null or environment == null:
		return
	environment.ssr_enabled = visuals.ssr_enabled
	environment.ssr_max_steps = visuals.ssr_max_steps
	environment.ssr_fade_in = visuals.ssr_fade_in
	environment.ssr_fade_out = visuals.ssr_fade_out
	environment.ssr_depth_tolerance = visuals.ssr_depth_tolerance


## Bontago-xtq.12: sizes and enables the ReflectionProbe wired via
## reflection_probe_path (Main.tscn), once at boot -- not per-match, unlike
## TerritoryOverlay's own configure() (see reflection_probe_margin_m's
## DECISION comment in config/TerritoryVisuals.gd for why). A no-op when
## nothing is wired (path empty or the node doesn't resolve) or `visuals` is
## unset, so every existing fixture in tests/unit/test_skybox.gd -- none of
## which wire this -- is unaffected.
func configure_reflection_probe() -> void:
	if visuals == null or reflection_probe_path.is_empty():
		return
	var probe: ReflectionProbe = get_node_or_null(reflection_probe_path) as ReflectionProbe
	if probe == null:
		return
	probe.visible = visuals.reflection_probe_enabled
	probe.update_mode = (
		ReflectionProbe.UPDATE_ALWAYS if visuals.reflection_probe_update_always
		else ReflectionProbe.UPDATE_ONCE
	)
	var half_width: float = MapDef.RADIUS_LARGE + visuals.reflection_probe_margin_m
	var height: float = visuals.reflection_probe_height_m
	probe.size = Vector3(half_width * 2.0, height, half_width * 2.0)
	probe.position = Vector3(0.0, height * 0.5 - PROBE_GROUND_CLEARANCE_M, 0.0)
	# Box-corrected reflections: the disk is a large flat static surface, so
	# aligning reflected rays to the probe's own box (rather than treating it
	# as infinitely far away, ReflectionProbe's default) keeps the mirrored
	# blocks positioned correctly instead of drifting as the camera orbits.
	probe.box_projection = true
	# DECISION (game/Skybox.gd, Bontago-xtq.20, owner 2026-09-23: "graphics
	# flickering"): exclude TerritoryOverlay's own disc from this probe's
	# cull_mask, the same DiscMirror.MIRROR_CULL_MASK its planar mirror camera
	# already uses -- found by re-reading game/DiscMirror.gd's own class doc,
	# which explains exactly why its mirror camera cannot see the disc (a
	# one-frame-stale nested reflection) but never applied that same reasoning
	# here. It applies doubly for a ReflectionProbe: the disc's own shader
	# samples SCREEN_UV of game/DiscMirror.gd's SubViewport (rendered for the
	# main camera's projection), but a cubemap face capture is a *different*
	# camera/projection entirely, so a probe that could see the disc would
	# bake an incoherent, per-face-mismatched sample of that texture into its
	# cubemap -- recomputed every frame under
	# reflection_probe_update_always's default UPDATE_ALWAYS, which is what
	# reads as general flicker (an incoherent image changing every frame),
	# not just a mis-reflected disc.
	probe.cull_mask = DiscMirror.MIRROR_CULL_MASK


## Called once per match/scene start (game/Main.gd) with the map's chosen set
## (config/MapDef.gd's skybox_set). `root_override` lets tests point this at a
## temp directory instead of the real asset root. Returns true and shows the
## textured box on success; returns false, prints one info line, and leaves
## the box hidden (so the ProceduralSkyMaterial fallback shows through) on
## any failure -- never a Godot error for the ordinary "assets not installed"
## case, since both existence checks below run before any file is opened.
##
## Face lookup is exact-case (FileAccess.file_exists() against
## config.face_names, which are lowercase): tools/install_original_assets.ps1
## (owned by another package) already lowercases every face file it copies,
## so this never needs to special-case the original install's mixed-case
## source names itself (see tests/unit/test_skybox.gd's DECISION on why that
## is not separately tested here).
func load_set(set_name: String, root_override: String = "") -> bool:
	_face_textures.clear()
	if not config.enabled:
		fallback_active = true
		_hide_faces()
		return false

	var root: String = root_override if root_override != "" else _resolve_asset_root()
	var set_dir: String = root.path_join(set_name)
	if not DirAccess.dir_exists_absolute(set_dir):
		fallback_active = true
		_hide_faces()
		print("Skybox: set '%s' not found at %s -- using procedural sky" % [set_name, set_dir])
		return false

	for face_name: String in config.face_names:
		var file_path: String = set_dir.path_join(face_name + ".jpg")
		if not FileAccess.file_exists(file_path):
			fallback_active = true
			_hide_faces()
			print("Skybox: face '%s' missing for set '%s' at %s -- using procedural sky" % [
				face_name, set_name, file_path,
			])
			return false
		# Load through an absolute filesystem path: Image.load_from_file on a
		# res:// path prints an engine warning about bypassing the import
		# pipeline (GUT counts it as an error) and the editor would import the
		# gitignored jpgs; assets/original carries a .gdignore for the same
		# reason (tools/install_original_assets.ps1 writes it).
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(file_path))
		if image == null:
			fallback_active = true
			_hide_faces()
			print("Skybox: face '%s' for set '%s' failed to decode -- using procedural sky" % [
				face_name, set_name,
			])
			return false
		_face_textures[face_name] = ImageTexture.create_from_image(image)

	fallback_active = false
	_build_faces()
	return true


## Test/inspection seam: the ImageTexture load_set() produced for one face,
## or null if load_set() has not succeeded for that face (fallback or not yet
## called).
func get_face_texture(face_name: String) -> ImageTexture:
	return _face_textures.get(face_name) as ImageTexture


## Static (Bontago-xtq.22): list_available_sets() below calls this from a
## static context too (building ui/TuningPanel.gd's dropdown does not need a
## live Skybox instance), and the body never read `self` to begin with.
static func _resolve_asset_root() -> String:
	if OS.has_feature("editor"):
		return "res://assets/original/textures"
	return OS.get_executable_path().get_base_dir().path_join("assets/original/textures")


## Bontago-xtq.22 (owner: "add an option to F4 to change the skybox"): every
## subfolder of the resolved asset root (or `root_override`, the same test
## seam load_set() already has), sorted -- the F4 dropdown's own list of real
## sets, built by ui/TuningPanel.gd alongside its fixed "Procedural / none"
## entry. Returns an empty array (never an error) when the root itself does
## not exist -- the ordinary "original assets not installed" case (CLAUDE.md/
## docs/AGENT_WORKFLOW.md: this repo never ships the third-party textures),
## so a CI machine's dropdown just shows the procedural entry alone.
static func list_available_sets(root_override: String = "") -> PackedStringArray:
	var root: String = root_override if root_override != "" else _resolve_asset_root()
	var sets: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return sets
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != ".." and dir.current_is_dir():
			sets.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	sets.sort()
	return sets


## Bontago-xtq.22 (owner: disc reflectivity is "hard to judge with that
## texture -- add an option to F4 to change the skybox"): the live-switch
## entry point ui/TuningPanel.gd's new Skybox dropdown calls on every Skybox
## in TUNING_GROUP. `set_name == PROCEDURAL_SET_ID` (the dropdown's
## "Procedural / none" item) turns the textured box/sky off by setting
## `config.enabled = false` -- load_set()'s own first check already falls
## back to the existing ProceduralSkyMaterial whenever that flag is off, so
## this needs no separate fallback path of its own. Any other name is
## remembered onto config.default_set (see that field's own DECISION for why
## reusing it, rather than a second field, is enough for the F4 override
## save/load path to pick it up) and re-enables the box before delegating to
## load_set() -- which prints its own one-line fallback notice and leaves the
## box hidden, exactly as an owner-typed unknown name already does today, for
## an unknown/missing set. `root_override` mirrors load_set()'s own test seam
## so tests/unit/test_skybox.gd can drive this against a temp fixture root
## instead of the real (gitignored) asset root.
func apply_set(set_name: String, root_override: String = "") -> bool:
	if set_name == PROCEDURAL_SET_ID:
		config.enabled = false
		return load_set(set_name, root_override)
	config.default_set = set_name
	config.enabled = true
	return load_set(set_name, root_override)


func _hide_faces() -> void:
	for mesh_instance: MeshInstance3D in _face_meshes.values():
		mesh_instance.visible = false
	_restore_fallback_sky()


func _build_faces() -> void:
	for face_name: String in config.face_names:
		var mesh_instance: MeshInstance3D = _face_meshes.get(face_name) as MeshInstance3D
		if mesh_instance == null:
			continue
		mesh_instance.mesh = _build_face_mesh(face_name)
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# CULL_DISABLED: the box's faces face inward toward the camera, and
		# with this set the triangle winding below does not have to be
		# reasoned about at all -- both sides render regardless.
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.albedo_texture = _face_textures.get(face_name)
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.visible = true
	_install_sky_material()


## Bontago-xtq.28: applies `applied_theme`'s sky/ground colours onto
## `_fallback_sky_material` *in place* (so a later load_set() failure's
## _restore_fallback_sky() restores the themed colours, not the material's own
## untouched defaults) and its fog colour/density onto the wired Environment's
## basic depth fog. A no-op when `applied_theme` is unset or no
## `environment`/`environment.sky` was wired, matching every other
## Environment-touching method above's contract.
func apply_theme(applied_theme: SkyThemeDef) -> void:
	if applied_theme == null or environment == null or environment.sky == null:
		return
	var procedural: ProceduralSkyMaterial = _fallback_sky_material as ProceduralSkyMaterial
	if procedural != null:
		procedural.sky_top_color = applied_theme.sky_top_color
		procedural.sky_horizon_color = applied_theme.sky_horizon_color
		procedural.ground_bottom_color = applied_theme.ground_bottom_color
		procedural.ground_horizon_color = applied_theme.ground_horizon_color
		# DECISION (game/Skybox.gd, Bontago-xtq.28): ProceduralSkyMaterial only
		# exposes one sun_angle_max float, not a min/max pair -- write the
		# wider/softer glow edge (sun_angle_min_max.y) since that is the value
		# that actually controls the visible glow size onscreen; .x is kept on
		# SkyThemeDef only as a design range a future per-theme sun animation
		# could draw from (see that field's own doc in config/SkyThemeDef.gd).
		procedural.sun_angle_max = applied_theme.sun_angle_min_max.y
	environment.fog_enabled = true
	environment.fog_light_color = applied_theme.fog_color
	environment.fog_density = applied_theme.fog_density
	# Bontago-xtq.28 fix round: the previous candidate never set this, so it
	# silently sat at the Environment engine default (1.0), which fully
	# replaces the rendered sky background with flat fog_light_color and
	# masked the ProceduralSkyMaterial's sunset gradient regardless of
	# fog_density. See SkyThemeDef.fog_sky_affect's own doc.
	environment.fog_sky_affect = applied_theme.fog_sky_affect
	# Bontago-xtq.28 fix round 2 (decisive finding): Environment.volumetric_fog_
	# density defaults to 0.05 on a fresh Environment and was never written
	# here, so the whole frustum showed a uniform grey haze regardless of
	# _spawn_fog_volume()'s FogVolume placement -- a FogVolume only adds density
	# on top of this ambient global floor, it cannot remove it. See
	# SkyThemeDef.volumetric_fog_density's own doc.
	environment.volumetric_fog_density = applied_theme.volumetric_fog_density
	environment.volumetric_fog_albedo = applied_theme.volumetric_fog_albedo


## Bontago-xtq.28: creates this Skybox's own FogVolume "cloud deck" child --
## Skybox and Field are sibling nodes under Main.tscn (game/Skybox.gd's
## Bontago-xtq.28 class-doc paragraph), so this is the only owned-file path to
## add it; game/Field.tscn itself is left untouched (DECISION, this method):
## a NodePath from Field to a Skybox-owned node, or vice versa, would need a
## wire in Main.tscn, which this package does not own. Always created (so
## _on_graphics_preset_changed() below only ever has to flip `visible`, never
## construct/destroy) with `theme`'s fog colour/density shared onto its
## FogMaterial, so the depth fog apply_theme() sets above and this volumetric
## deck read as one coherent colour instead of two independently tuned
## effects. A no-op (no node created, get_fog_volume() stays null) when
## `theme` is unset.
func _spawn_fog_volume() -> void:
	if theme == null:
		return
	var fog_volume: FogVolume = FogVolume.new()
	fog_volume.name = "CloudDeck"
	fog_volume.size = theme.cloud_deck_size_m
	fog_volume.position = Vector3(0.0, theme.cloud_deck_height_m, 0.0)
	var fog_material: FogMaterial = FogMaterial.new()
	fog_material.density = theme.fog_density
	fog_material.albedo = theme.fog_color
	fog_volume.material = fog_material
	add_child(fog_volume)
	_fog_volume = fog_volume


## autoload/Settings.gd's graphics_preset_changed handler, connected in
## _ready() and disconnected in _exit_tree() above.
func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_apply_fog_volume_visibility(preset)


## Bontago-xtq.28: the FogVolume's only gating -- `visible` alone, never
## created/destroyed (see _spawn_fog_volume()'s own doc on why). Matches
## docs/M7_ART_DIRECTION.md's performance budget: dropped from view entirely
## on Low (config/graphics_presets/low.tres: volumetric_fog_enabled == false),
## present on Medium/High. A no-op when no FogVolume exists yet (`theme` was
## unset in _ready()) or `preset` is unset.
func _apply_fog_volume_visibility(preset: GraphicsPreset) -> void:
	if _fog_volume == null or preset == null:
		return
	_fog_volume.visible = preset.volumetric_fog_enabled


## Test/inspection seam: the FogVolume _spawn_fog_volume() created, or null if
## `theme` was unset in _ready().
func get_fog_volume() -> FogVolume:
	return _fog_volume


## Restores the Environment's Sky to whatever material it carried before this
## node ever touched it (Main.tscn's ProceduralSkyMaterial) -- a no-op when no
## `environment` was wired (most of tests/unit/test_skybox.gd) or _ready()
## never captured one (environment.sky was null at the time).
func _restore_fallback_sky() -> void:
	if environment == null or environment.sky == null or _fallback_sky_material == null:
		return
	environment.sky.sky_material = _fallback_sky_material


## Bontago-xtq.8: installs shaders/cubemap_sky.gdshader onto the Environment's
## Sky, with the same six face textures and the same SkyboxConfig.
## face_rotations/face_flip_u/face_flip_v the box's own quads use -- see the
## class doc and the shader's doc for why the two are the same convention
## read two different ways. A no-op when no `environment` was wired.
func _install_sky_material() -> void:
	if environment == null or environment.sky == null:
		return
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SKY_SHADER
	for index: int in range(config.face_names.size()):
		var face_name: String = config.face_names[index]
		var rotation: int = config.face_rotations[index] if index < config.face_rotations.size() else 0
		var flip_u: bool = index < config.face_flip_u.size() and config.face_flip_u[index] != 0
		var flip_v: bool = index < config.face_flip_v.size() and config.face_flip_v[index] != 0
		material.set_shader_parameter(face_name + "_tex", _face_textures.get(face_name))
		material.set_shader_parameter(face_name + "_rotation", rotation)
		material.set_shader_parameter(face_name + "_flip_u", flip_u)
		material.set_shader_parameter(face_name + "_flip_v", flip_v)
	environment.sky.sky_material = material
	# DECISION (game/Skybox.gd): PROCESS_MODE_QUALITY, not the default
	# AUTOMATIC/INCREMENTAL. Reflections/ambient are read from the sky's own
	# radiance/irradiance maps, not the background pixels directly --
	# INCREMENTAL mode (meant for a sky that keeps changing, e.g. a day/night
	# cycle) spreads that recompute over many frames, so a freshly-loaded set
	# would keep showing the *previous* sky's (or the fallback gradient's)
	# stale reflection for a visible stretch of play. QUALITY recomputes fully
	# on the next frame instead; this skybox only ever changes at
	# load_set() (once per match/map), so the one-frame cost is negligible.
	environment.sky.process_mode = Sky.PROCESS_MODE_QUALITY


## One quad per face of a box_half_extent-sided cube, in Skybox-local space
## (this node sits at the world origin -- see class doc on why it does not
## follow the camera). Built directly rather than from BoxMesh/QuadMesh so
## each face's UV orientation is an explicit, checkable base mapping (see
## _face_corners()) with a per-face correction on top of it
## (config.face_rotations/face_flip_u/face_flip_v, applied by
## _apply_face_transform() below) -- the base mapping alone ("front" unrotated
## with back/left/right as the 90-degree turns around it, top/bottom attached
## to front's edges unrotated) turned out NOT to match the original install's
## own per-face orientation for any of the six files; every face needs its
## correction. See tools/skybox_seam_probe.gd, which found that correction
## numerically, for why and the measured seam error.
func _build_face_mesh(face_name: String) -> ArrayMesh:
	var corners: Dictionary = _face_corners(StringName(face_name), config.box_half_extent)
	if corners.is_empty():
		return null

	var index: int = config.face_names.find(face_name)
	var rotation: int = config.face_rotations[index] if index >= 0 and index < config.face_rotations.size() else 0
	var flip_u: bool = index >= 0 and index < config.face_flip_u.size() and config.face_flip_u[index] != 0
	var flip_v: bool = index >= 0 and index < config.face_flip_v.size() and config.face_flip_v[index] != 0

	var positions: PackedVector3Array = PackedVector3Array([
		corners["p00"], corners["p10"], corners["p01"], corners["p11"],
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		_apply_face_transform(0.0, 0.0, flip_u, flip_v, rotation),
		_apply_face_transform(1.0, 0.0, flip_u, flip_v, rotation),
		_apply_face_transform(0.0, 1.0, flip_u, flip_v, rotation),
		_apply_face_transform(1.0, 1.0, flip_u, flip_v, rotation),
	])
	var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 1, 2, 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Applies (in order) an optional horizontal flip, an optional vertical
## flip, then `rotation` quarter turns (each turn: (u,v) -> (v, 1-u)) to a
## face's base UV coordinate. Shared, as a static method, with
## tools/skybox_seam_probe.gd so the probe's search space and Skybox's actual
## render are provably the same transform -- the probe's printed table is
## meaningless otherwise. rotation is taken mod 4 (any int is accepted so a
## config value never has to be pre-clamped).
static func _apply_face_transform(u: float, v: float, flip_u: bool, flip_v: bool, rotation: int) -> Vector2:
	var uu: float = 1.0 - u if flip_u else u
	var vv: float = 1.0 - v if flip_v else v
	var turns: int = ((rotation % 4) + 4) % 4
	for _i: int in range(turns):
		var next_u: float = vv
		var next_v: float = 1.0 - uu
		uu = next_u
		vv = next_v
	return Vector2(uu, vv)


## p00/p10/p01/p11 are this face's UV (0,0)/(1,0)/(0,1)/(1,1) corners in
## world space (h = box_half_extent), before any face_rotations/flip
## correction is applied (that happens in _build_face_mesh() above via
## _apply_face_transform()). See the class/method doc above for the
## convention these follow. Static (and called that way by the seam probe
## too) since it is a pure function of face + h, with no instance state.
static func _face_corners(face: StringName, h: float) -> Dictionary:
	match face:
		&"front":
			return {
				"p00": Vector3(-h, h, -h), "p10": Vector3(h, h, -h),
				"p01": Vector3(-h, -h, -h), "p11": Vector3(h, -h, -h),
			}
		&"back":
			return {
				"p00": Vector3(h, h, h), "p10": Vector3(-h, h, h),
				"p01": Vector3(h, -h, h), "p11": Vector3(-h, -h, h),
			}
		&"right":
			return {
				"p00": Vector3(h, h, -h), "p10": Vector3(h, h, h),
				"p01": Vector3(h, -h, -h), "p11": Vector3(h, -h, h),
			}
		&"left":
			return {
				"p00": Vector3(-h, h, h), "p10": Vector3(-h, h, -h),
				"p01": Vector3(-h, -h, h), "p11": Vector3(-h, -h, -h),
			}
		&"top":
			return {
				"p00": Vector3(-h, h, h), "p10": Vector3(h, h, h),
				"p01": Vector3(-h, h, -h), "p11": Vector3(h, h, -h),
			}
		&"bottom":
			return {
				"p00": Vector3(-h, -h, -h), "p10": Vector3(h, -h, -h),
				"p01": Vector3(-h, -h, h), "p11": Vector3(h, -h, h),
			}
		_:
			return {}
