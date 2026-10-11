class_name GraphicsPreset
extends Resource
## One selectable graphics quality tier (spec 3.1). autoload/Settings.gd
## loads one of config/graphics_presets/{low,medium,high}.tres by id;
## Settings itself never applies these fields to a Viewport/Environment --
## that's game/Main.gd's job (Bontago-xtq.26, M7 P1): Settings only persists
## the choice and emits graphics_preset_changed so a consumer can react.
##
## SSIL intentionally absent -- that render feature doesn't exist yet (a
## later M7 package adds it); a preset that named it today would be a promise
## this milestone cannot keep. volumetric_fog_enabled below is the owner's M7
## art-direction performance budget (docs/M7_ART_DIRECTION.md §3): Low drops the cloud-deck
## FogVolume P3 adds to the field; Medium/High keep it.

@export var id: StringName
@export var ssr_enabled: bool = true
@export var msaa_3d: Viewport.MSAA = Viewport.MSAA_2X
@export var shadow_atlas_size: int = 4096
@export var volumetric_fog_enabled: bool = true
## Bontago-adt.1: fraction (0..1) of the theme's 3D cloud-puff clumps
## (vfx/CloudSea.gd) to draw; 0 hides them and leaves only the sky panorama's
## far cloud sea. Low draws a sparse set.
@export var cloud_puff_density: float = 1.0
## Bontago-1pi.11.6: icosphere subdivisions of each cloud puff hull (1 = 80 tris, 2 = 320).
## The shader carves the silhouette per pixel, so 1 looks the same at a quarter of the
## ~1.2M-primitive cloud-sea cost.
@export_range(1, 2) var cloud_puff_subdivisions: int = 2
## Bontago-1pi.11.67 (fix 2a): cloud clumps whose rest position lies at least this far (m) from the
## disc axis draw as camera-facing hexagon impostors (4 triangles) instead of 80-triangle hulls; the
## puff shader carves the same lumpy silhouette on either. 0 = every puff keeps its hull.
@export var cloud_billboard_distance_m: float = 0.0
## Bontago-adt.1: distant animated bird flocks (vfx/DistantBirds.gd); off on Low.
@export var birds_enabled: bool = true
## Bontago-adt.3: cosmetic ambient life (perching birds, fireflies); off on Low.
@export var ambient_life_enabled: bool = true
## Bontago-1pi.11.2: sun DirectionalLight3D cascade count (DirectionalLight3D.ShadowMode;
## 2 = 4 splits, 1 = 2 splits, 0 = one orthogonal split). Shadow pass cost grows with
## block count.
@export_enum("Orthogonal:0", "PSSM 2 Splits:1", "PSSM 4 Splits:2") var sun_shadow_mode: int = 2
## Bontago-1pi.11.2: sun shadow max distance in metres (engine default 100).
@export var sun_shadow_max_distance: float = 100.0

## Bontago-1pi.11.67: how the ReflectionProbe over the disc is refreshed (game/Skybox.gd).
## OFF hides it (the disc then mirrors only the sky radiance); ONCE renders at match start
## and after a sky/theme/time-of-day/map change; INTERVAL also re-renders every
## reflection_probe_interval_s while blocks moved; ALWAYS is the engine's UPDATE_ALWAYS
## (six faces every frame, ~2.5 ms on a 3060 at 3440x1440).
enum ReflectionProbeMode { OFF, ONCE, INTERVAL, ALWAYS }
@export var reflection_probe_mode: ReflectionProbeMode = ReflectionProbeMode.INTERVAL
## Seconds between INTERVAL re-renders (only when the block layout changed).
@export_range(0.1, 60.0) var reflection_probe_interval_s: float = 0.5
## Bontago-1pi.11.67: Environment glow (bloom) pass; off on Low.
@export var glow_enabled: bool = true

## Bontago-1pi.11.42: the swirl animation (noise, per-pixel) of the hole void
## on the disc. Off on Low: the void is then a flat deep colour with its rim.
@export var hole_void_animated: bool = true
## Bontago-1pi.11.67 fix2b: the rivets and brushed streaks of the procedural disc
## plating (shaders/territory.gdshader disc_fine_detail), its two costliest per-pixel
## details. Off on Low: plates, seams, lips, hatches and the sheen stay.
@export var disc_fine_detail_enabled: bool = true
## Bontago-1pi.11.67 fix2b: the inverted-hull block outline (shaders/block_outline.gdshader,
## the next_pass of every block material; game/BlockFactory.gd). Off on Low.
@export var block_outline_enabled: bool = true
## Bontago-1pi.11.42: the noise dissolve + rim glow on a block eaten by a hole
## (game/BlockDissolveFx.gd). Off on Low: the block simply vanishes on time.
@export var block_dissolve_effect_enabled: bool = true
## Bontago-mp0.23: the persistent per-crate OmniLight3D on a landed gift
## (game/GiftCrate.gd). Off on Low: only the brief spawn flash remains.
@export var gift_idle_glow_enabled: bool = true
## Bontago-mp0.127: moving cloud shadows on the arena and the sun dimming under clouds
## (vfx/CloudShadows.gd). Off on Low.
@export var cloud_shadows_enabled: bool = true
## Bontago-mp0.129: the night-sky aurora borealis curtains (shaders/include/cloud_common.gdshaderinc,
## game/Skybox.gd). Off on Low: the sky keeps its stars and moon.
@export var aurora_enabled: bool = true
## Bontago-1pi.11.49: how Engine.max_fps is chosen while a match runs (core/FrameCapRule.gd).
## DECISION (owner/orchestrator 2026-10-07): the default on every preset is the display's
## refresh rate, so a 144 Hz monitor still gets 144 fps but nothing renders uncapped
## (a 245 fps uncapped match held a 3060 at ~60% at 4K; 144 = 39%, 60 = 28%).
enum FrameCap { DISPLAY_REFRESH, FIXED, UNCAPPED }
@export var frame_cap_mode: FrameCap = FrameCap.DISPLAY_REFRESH
## Used by the FIXED mode.
@export_range(1, 360) var fixed_fps: int = 60
## Used by DISPLAY_REFRESH when the display reports no refresh rate (<= 0).
@export_range(1, 360) var fallback_fps: int = 60
## Bontago-1pi.11.51: seconds between checks that the window's screen/refresh changed.
@export_range(0.1, 10.0) var screen_check_interval_s: float = 1.0

## Bontago-1pi.11.37: the fields below are all-default on every shipped preset; only
## the adaptive quality governor (core/QualityGovernor.gd) lowers them, on a duplicate
## handed out by Settings.current_graphics_preset(). The stored .tres never changes.
## Multiplies the block-effect burst caps and particle amounts (1 = unchanged).
@export_range(0.0, 1.0) var particle_budget_scale: float = 1.0
## Multiplies the rain / snow / storm-mote density (1 = unchanged).
@export_range(0.0, 1.0) var weather_density_scale: float = 1.0
## Viewport.scaling_3d_scale (1 = native resolution).
@export_range(0.25, 1.0) var render_scale_3d: float = 1.0
## Bontago-1pi.11.67 (fix 2a): Viewport.Scaling3DMode used while render_scale_3d < 1 (0 bilinear,
## 1 FSR 1.0, 2 FSR 2.2). Ignored at native resolution.
@export_range(0, 2) var render_scale_3d_mode: int = 0


## Bontago-1pi.11.86: the one table of what each user-editable field may be set to. The Options
## Graphics tab builds its option lists / slider ranges from LIMITS and Settings sanitizes every
## override (live edit and load from a hand-edited settings.cfg) against it. Bools: no entry.
const MSAA_3D: Dictionary = {"values": [0, 1, 2]}
const RENDER_SCALE_3D: Dictionary = {"min": 0.5, "max": 1.0, "step": 0.05}
const RENDER_SCALE_3D_MODE: Dictionary = {"values": [0, 1, 2]}
const SHADOW_ATLAS_SIZE: Dictionary = {"values": [1024, 2048, 4096, 8192]}
const SUN_SHADOW_MODE: Dictionary = {"values": [0, 1, 2]}
const SUN_SHADOW_MAX_DISTANCE: Dictionary = {"min": 30.0, "max": 150.0, "step": 10.0}
const REFLECTION_PROBE_MODE: Dictionary = {"values": [0, 1, 2, 3]}
const CLOUD_PUFF_DENSITY: Dictionary = {"min": 0.0, "max": 1.0, "step": 0.05}
const FRAME_CAP_MODE: Dictionary = {"values": [0, 1, 2]}
const FIXED_FPS: Dictionary = {"min": 30.0, "max": 360.0, "step": 10.0}

const LIMITS: Dictionary = {
	&"msaa_3d": MSAA_3D,
	&"render_scale_3d": RENDER_SCALE_3D,
	&"render_scale_3d_mode": RENDER_SCALE_3D_MODE,
	&"shadow_atlas_size": SHADOW_ATLAS_SIZE,
	&"sun_shadow_mode": SUN_SHADOW_MODE,
	&"sun_shadow_max_distance": SUN_SHADOW_MAX_DISTANCE,
	&"reflection_probe_mode": REFLECTION_PROBE_MODE,
	&"cloud_puff_density": CLOUD_PUFF_DENSITY,
	&"frame_cap_mode": FRAME_CAP_MODE,
	&"fixed_fps": FIXED_FPS,
}


static func limits_for(field: StringName) -> Dictionary:
	return LIMITS.get(field, {}) as Dictionary


## `value` (already coerced to the field's type) made valid for `field`: an enum value outside the
## option set returns null (drop it); a number is clamped to [min, max] and, for an int field,
## stays an int. Unlimited fields return `value` unchanged.
static func sanitize(field: StringName, value: Variant) -> Variant:
	var limits: Dictionary = limits_for(field)
	if limits.has("values"):
		return value if (limits["values"] as Array).has(value) else null
	if limits.has("min"):
		var clamped: float = clampf(float(value), float(limits["min"]), float(limits["max"]))
		return roundi(clamped) if typeof(value) == TYPE_INT else clamped
	return value


## Bontago-1pi.153: the Graphics tab's combined rows (Shadows, Reflections, Environment detail) write
## several fields at once from a tier. The tier list is the shipped presets, in this order.
const TIER_PRESET_PATHS: Array[String] = [
	"res://config/graphics_presets/low.tres",
	"res://config/graphics_presets/medium.tres",
	"res://config/graphics_presets/high.tres",
]
## Shadows: one quality row over the atlas size, cascade count and range, taken from each preset.
const SHADOW_FIELDS: Array[StringName] = [&"shadow_atlas_size", &"sun_shadow_mode", &"sun_shadow_max_distance"]
## Environment detail: the cosmetic ambience fields, taken from each preset.
const ENVIRONMENT_FIELDS: Array[StringName] = [
	&"cloud_puff_density", &"cloud_shadows_enabled", &"aurora_enabled", &"birds_enabled",
	&"ambient_life_enabled", &"disc_fine_detail_enabled", &"hole_void_animated",
	&"gift_idle_glow_enabled", &"block_dissolve_effect_enabled",
]
## Reflections: Off / Low / High. DECISION (1pi.153): the presets cannot supply this (Medium and High
## share one reflection setup), so the three tiers are fixed: Off = no probe and no SSR, Low = the
## interval-refreshed probe only, High = probe plus screen-space reflections.
const REFLECTION_TIERS: Array[Dictionary] = [
	{&"reflection_probe_mode": ReflectionProbeMode.OFF, &"ssr_enabled": false},
	{&"reflection_probe_mode": ReflectionProbeMode.INTERVAL, &"ssr_enabled": false},
	{&"reflection_probe_mode": ReflectionProbeMode.INTERVAL, &"ssr_enabled": true},
]


## Tier `tier`'s value for each of `fields`, read from the shipped preset of that tier.
static func tier_values(fields: Array[StringName], tier: int) -> Dictionary:
	var values: Dictionary = {}
	var preset: GraphicsPreset = load(TIER_PRESET_PATHS[clampi(tier, 0, TIER_PRESET_PATHS.size() - 1)]) as GraphicsPreset
	for field: StringName in fields:
		values[field] = preset.get(field)
	return values


## The tiers of a preset-derived group, one field->value Dictionary per shipped preset.
static func preset_tiers(fields: Array[StringName]) -> Array[Dictionary]:
	var tiers: Array[Dictionary] = []
	for tier: int in range(TIER_PRESET_PATHS.size()):
		tiers.append(tier_values(fields, tier))
	return tiers


## Index of the first tier whose every value equals `read.call(field)`, or -1 (shown as "Custom").
static func matching_tier(tiers: Array[Dictionary], read: Callable) -> int:
	for index: int in range(tiers.size()):
		var tier: Dictionary = tiers[index]
		var matches: bool = true
		for field: StringName in tier:
			if not _values_equal(tier[field], read.call(field)):
				matches = false
				break
		if matches:
			return index
	return -1


static func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b
