class_name FrameCapRule
extends RefCounted
## Bontago-1pi.11.49: pure rule for the in-match Engine.max_fps. No scene tree.

## Returns the Engine.max_fps value (0 = uncapped) for a GraphicsPreset.FrameCap mode.
## refresh_hz is the display's reported rate (<= 0 when unknown).
static func resolve(mode: int, fixed_fps: int, refresh_hz: float, fallback_fps: int) -> int:
	match mode:
		GraphicsPreset.FrameCap.UNCAPPED:
			return 0
		GraphicsPreset.FrameCap.FIXED:
			return maxi(fixed_fps, 0)
		_:
			return roundi(refresh_hz) if refresh_hz > 0.0 else maxi(fallback_fps, 0)


static func resolve_for_preset(preset: GraphicsPreset, refresh_hz: float) -> int:
	return resolve(preset.frame_cap_mode, preset.fixed_fps, refresh_hz, preset.fallback_fps)
