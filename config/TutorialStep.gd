class_name TutorialStep
extends Resource
## docs/M6_PLAN.md package B3 (spec 2.7 "Tutorial"): one step of
## config/TutorialConfig.gd's own `steps` array.
##
## DECISION (config/TutorialStep.gd): the plan's own sketch nests this class
## inside TutorialConfig.gd (`class Step: extends Resource ...`). Reproduced
## while building config/tutorial_config.tres: Godot 4.7.2's ResourceSaver
## cannot round-trip a typed `Array[TutorialConfig.Step]` of an *inner*
## Resource class through a saved .tres -- it writes the inner class's own
## `[sub_resource type="GDScript"]` block with no source body, and loading the
## file back then fails the TypedArray's own script check ("Attempted to
## assign an object into a TypedArray, that does not inherit from
## 'GDScript'"), silently emptying `steps` to size 0 with no load error
## surfaced anywhere else. A top-level script has none of that problem --
## the same pattern every other Resource array in this project already uses
## (config/specials/*.tres's SpecialDef, config/maps/*.tres's MapDef) -- so
## this file exists instead of the nested class the plan sketched.

## Not read by ui/Tutorial.gd itself (which only ever indexes `steps` by
## position) -- for the inspector/a future step list UI, and so a test can
## assert on which step is active by name rather than a bare int.
@export var id: StringName = &""
## Shown verbatim in ui/Tutorial.gd's prompt overlay while this step is
## active. Placeholder wording (docs/M6_PLAN.md package B3: "no art
## direction decisions -- plain placeholder styling").
@export var prompt_text: String = ""
## One of ui/Tutorial.gd's own SIGNAL_* constants (block_placed,
## orientation_changed, territory_claimed, special_consumed, camera_moved).
## An unrecognized value simply never completes -- see ui/Tutorial.gd's own
## doc comment on why that fails safe rather than silently advancing.
@export var completion_signal: StringName = &""
