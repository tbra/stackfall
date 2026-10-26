class_name GraphicsApplier
extends Node
## STUB (P7 plan section 2.1): null-object bodies, nothing wired; the filler package P7-Igfx implements it.
## Applies a GraphicsPreset (sun, sky, frame cap). Child of Main; sun and skybox are
## set before add_child.

var sun: DirectionalLight3D = null
var skybox: Skybox = null
## Existing test seams, kept: no display headless.
var frame_cap_in_headless: bool = false
var refresh_rate_provider: Callable = Callable()
var vsync_applier: Callable = Callable()


func apply(_preset: GraphicsPreset) -> void:
	pass
