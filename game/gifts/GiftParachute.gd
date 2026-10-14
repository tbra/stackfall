class_name GiftParachute
extends Node3D
## The parachute a gift crate wears while it descends (Bontago-mp0.139).
## Cosmetic, client-side visuals only: GiftCrate.set_falling() -- which MatchGifts
## calls on the host when a crate spawns/lands and on a client when the
## replicated flight/landing events arrive -- starts deploy()/collapse(), and
## every pose value comes from core/gifts/ParachuteAnim.gd (pure, deterministic).
## Nothing here touches host physics, descent speed, claims or the network.
##
## Node layout (origin = the riser point, `chute_riser_height_m` above the
## crate's top face):
##   Parachute            this node; placement only
##     Body               sinks while collapsing
##       Harness          four lines riser -> crate top corners (fixed)
##       Sway             pendulum lean about the riser
##         Inflate        non-uniform scale: canopy + rim lines inflate together
##           Canopy       gore dome (vertex colours, double-sided)
##           RimLines     rim seams -> riser
##
## release_to() hands a still-visible parachute to another parent so it can
## finish collapsing after its crate was claimed (the crate node is freed the
## same tick), then frees itself.

var _config: GiftConfig = null
var _anim: ParachuteAnim = ParachuteAnim.new()
var _body: Node3D = null
var _sway: Node3D = null
var _inflate: Node3D = null
var _canopy_material: StandardMaterial3D = null
var _line_material: StandardMaterial3D = null
var _fade_mode: bool = false
var _free_when_hidden: bool = false


## Builds the model. `crate_top_y` is the crate's top face in the parent's
## space; the node sits `chute_riser_height_m` above it.
func setup(config: GiftConfig, crate_top_y: float) -> void:
	_config = config
	_anim.configure(config)
	position = Vector3(0.0, crate_top_y + config.chute_riser_height_m, 0.0)

	_canopy_material = ParachuteMesh.canopy_material()
	_line_material = ParachuteMesh.line_material(config)

	_body = Node3D.new()
	_body.name = &"Body"
	add_child(_body)
	_add_mesh(_body, &"Harness", ParachuteMesh.build_harness_lines(config), _line_material, false)
	_sway = Node3D.new()
	_sway.name = &"Sway"
	_body.add_child(_sway)
	_inflate = Node3D.new()
	_inflate.name = &"Inflate"
	_sway.add_child(_inflate)
	_add_mesh(_inflate, &"Canopy", ParachuteMesh.build_canopy(config), _canopy_material, true)
	_add_mesh(_inflate, &"RimLines", ParachuteMesh.build_rim_lines(config), _line_material, false)
	_apply()


func _process(delta: float) -> void:
	advance(delta)


## Advances the animation by `delta` seconds and re-poses the nodes. Public so
## tests (and any caller without a running tree) can step it deterministically.
func advance(delta: float) -> void:
	_anim.advance(delta)
	_apply()
	if _free_when_hidden and not _anim.is_visible() and is_inside_tree():
		queue_free()


func set_phase_seed(seed_value: float) -> void:
	_anim.set_phase_seed(seed_value)


## Crate started falling: inflate. No-op while already falling.
func deploy() -> void:
	_anim.deploy()
	_apply()


## Crate landed: deflate, sink and fade. No-op when nothing is showing.
func collapse() -> void:
	_anim.collapse()
	_apply()


func phase() -> ParachuteAnim.Phase:
	return _anim.phase


## Anything is showing (deploying, open or collapsing).
func is_active() -> bool:
	return _anim.is_visible()


func anim() -> ParachuteAnim:
	return _anim


## Whether the fade-out material mode (alpha) is currently on; tests read it.
func is_fading() -> bool:
	return _fade_mode


## Detaches this parachute from its crate, keeps its world pose, starts the
## collapse if it was still falling, and frees it once it has fully faded.
## Call this from a claim handler, before the crate node is freed.
func release_to(new_parent: Node3D) -> void:
	if new_parent == null or not is_inside_tree():
		return
	_free_when_hidden = true
	collapse()
	reparent(new_parent, true)
	reset_physics_interpolation()


func _apply() -> void:
	visible = _anim.is_visible()
	if not visible or _body == null:
		return
	var tilt: Vector2 = _anim.tilt()
	_sway.rotation = Vector3(tilt.x, 0.0, tilt.y)
	var radius: float = _anim.radius_scale()
	_inflate.scale = Vector3(radius, _anim.height_scale(), radius)
	_body.position = Vector3(0.0, _anim.drop_offset(), 0.0)
	_sync_fade(_anim.alpha())


## The canopy stays opaque while open (an alpha-blended double-sided dome would
## sort its own triangles wrongly); only the fade-out switches to the depth
## pre-pass alpha mode, which blends cleanly without sorting.
func _sync_fade(alpha: float) -> void:
	var fading: bool = alpha < 1.0
	if fading != _fade_mode:
		_fade_mode = fading
		var mode: BaseMaterial3D.Transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS \
			if fading else BaseMaterial3D.TRANSPARENCY_DISABLED
		_canopy_material.transparency = mode
		_line_material.transparency = mode
	if fading:
		_canopy_material.albedo_color = Color(Color.WHITE, alpha)
		_line_material.albedo_color = Color(_config.chute_line_color, alpha)
	elif _canopy_material.albedo_color.a < 1.0 or _line_material.albedo_color.a < 1.0:
		_canopy_material.albedo_color = Color.WHITE
		_line_material.albedo_color = _config.chute_line_color


## Only the canopy casts a shadow: it grounds the falling crate on the disc,
## while sixteen hair-thin lines would just add noise to the shadow map.
func _add_mesh(parent: Node3D, label: StringName, mesh: ArrayMesh, material: StandardMaterial3D,
		casts_shadow: bool) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	if not casts_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
