class_name UiScale
extends RefCounted
## Bontago-1pi.23 / 1pi.26: the ONE UI scaling rule.
##
## The project stretch (display/window/stretch/mode = canvas_items, aspect =
## expand, base size = display/window/size/viewport_width x _height, written
## by tools/bootstrap_project.gd) is the only thing that scales the UI: the
## whole canvas is multiplied by min(window.x / base.x, window.y / base.y) and
## the other axis exposes extra logical canvas. No screen, HUD cluster, font or
## icon may apply its own scale factor, read the window or display size, or use
## a size relative to anything but the logical (visible-rect) viewport; layout
## is anchors and containers. Pure statics so tests and AgentProbe's
## SubViewport emulation use exactly the engine's rule.


static func base_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))


## Bontago-1pi.150: the player's UI scale (autoload/Settings.gd, applied by Settings to the root
## window) multiplies this stretch. Its effective factor (base scale x the stored
## relative value) is what the engine adds on top of the stretch; AgentProbe viewports and layout
## tests use it too, so they lay out exactly like the real window.
static func user_factor() -> float:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	return tuning.effective_factor(UiScaleTuning.runtime_scale())


## The multiplier the project stretch alone applies for a window of `window_size` pixels.
static func stretch_factor(window_size: Vector2) -> float:
	var base: Vector2 = base_size()
	if window_size.x <= 0.0 or window_size.y <= 0.0 or base.x <= 0.0 or base.y <= 0.0:
		return 1.0
	return minf(window_size.x / base.x, window_size.y / base.y)


## Stretch times the user scale: the total multiplier from logical to window pixels.
static func factor(window_size: Vector2) -> float:
	return stretch_factor(window_size) * user_factor()


## The logical canvas (what Viewport.get_visible_rect() reports) for the window.
static func logical_size(window_size: Vector2) -> Vector2i:
	var scale_factor: float = factor(window_size)
	if scale_factor <= 0.0:
		return Vector2i(window_size)
	return Vector2i(roundi(window_size.x / scale_factor), roundi(window_size.y / scale_factor))


## A SubViewport of `window_size` pixels that lays out and scales its UI exactly
## like a real window of that size (used by AgentProbe captures and layout tests).
static func make_viewport(window_size: Vector2i) -> SubViewport:
	var vp: SubViewport = SubViewport.new()
	vp.size = window_size
	if window_size.x > 0 and window_size.y > 0:
		vp.size_2d_override = logical_size(Vector2(window_size))
		vp.size_2d_override_stretch = true
	return vp
