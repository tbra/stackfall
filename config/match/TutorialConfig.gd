class_name TutorialConfig
extends Resource
## The five-step tutorial script (spec 1.2 "Tutorial"):
## ui/menus/Tutorial.gd drives, kept as data (CLAUDE.md: no magic numbers/strings
## baked into the state machine) so the wording and step order are a resource
## edit, not a code change.
##
## DECISION (config/match/TutorialConfig.gd): the plan's own sketch nests the step
## type inside this script (`class Step: ...`). `steps` below is
## `Array[TutorialStep]`, a separate top-level Resource script, instead --
## see config/match/TutorialStep.gd's own doc comment for the reproduced .tres
## round-trip bug that rules the nested version out.
##
## `TutorialStep.completion_signal` is a StringName key ui/menus/Tutorial.gd
## switches on, not a Callable -- a Resource cannot @export one.

## Exactly 5 steps:
## specials/throwing, camera -- in that order. Not enforced by size here
## (config/match/tutorial_config.tres is this package's one source of truth for the
## sequence); ui/menus/Tutorial.gd itself only ever needs "a step index into this
## array", never a hardcoded count.
@export var steps: Array[TutorialStep] = []

## The special ui/menus/Tutorial.gd force-queues (Match.debug_queue_special()) for
## the "specials/throwing" step, kept here rather than hardcoded in
## ui/menus/Tutorial.gd so the demo special is a resource edit (CLAUDE.md: no magic
## ids in code). Must be one of config/gifts/specials/*.tres's own ids.
@export var demo_special_id: StringName = &"bomb"

## Seconds of observed camera_orbit/camera_pan_* input the "camera" step
## requires before it completes ("any
## camera_orbit/camera_pan_* input observed for a few seconds").
@export var camera_hold_seconds: float = 2.0
