class_name TutorialStep
extends Resource
## One step of the tutorial (spec 1.2 "Tutorial"), an element of
## TutorialConfig.steps.
##
## DECISION: a top-level script, not a class nested in TutorialConfig. Godot 4.7.2's
## ResourceSaver cannot round-trip a typed array of an inner Resource class through
## a .tres: it writes the inner class as a `[sub_resource type="GDScript"]` block
## with no source, and loading fails the TypedArray script check and silently
## empties `steps` with no load error. Top-level Resource arrays (SpecialDef,
## MapDef) do not have the problem.

## Not read by ui/menus/Tutorial.gd (which indexes `steps` by position); lets a
## test assert which step is active by name.
@export var id: StringName = &""
## `{action}` / `{a|b}` tokens render the bound action's glyph for the
## active device (ui/hud/InputPromptFlow.gd); never type key or button names here.
## Shown in ui/menus/Tutorial.gd's prompt overlay while this step is active.
@export var prompt_text: String = ""
## One of ui/menus/Tutorial.gd's own SIGNAL_* constants (block_placed,
## orientation_changed, territory_claimed, special_consumed, camera_moved).
## An unrecognized value never completes (fails safe instead of advancing; see
## ui/menus/Tutorial.gd).
@export var completion_signal: StringName = &""
