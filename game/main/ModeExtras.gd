class_name ModeExtras
extends RefCounted
## What a non-lobby mode adds on top of the one match world builder: data only,
## no scene dependency. Main attaches the matching node after the world is built.

enum Kind { SANDBOX, TUTORIAL }

var kind: Kind = Kind.SANDBOX
## Gift demo / tower topple preset, or null for a plain sandbox.
var sandbox_preset: SandboxConfig = null
## `--force-special=<id>`; also keeps F9 across an F5 rebuild. &"" is off.
var forced_special: StringName = &""


static func sandbox(preset: SandboxConfig, forced_special_id: StringName) -> ModeExtras:
	var extras: ModeExtras = ModeExtras.new()
	extras.kind = Kind.SANDBOX
	extras.sandbox_preset = preset
	extras.forced_special = forced_special_id
	return extras


static func tutorial() -> ModeExtras:
	var extras: ModeExtras = ModeExtras.new()
	extras.kind = Kind.TUTORIAL
	return extras


## The sandbox starts at once; the tutorial keeps the loading screen.
func skips_loading_screen() -> bool:
	return kind == Kind.SANDBOX
