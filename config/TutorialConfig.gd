class_name TutorialConfig
extends Resource
## docs/M6_PLAN.md package B3 (spec 2.7 "Tutorial"): the five-step script
## ui/Tutorial.gd drives, kept as data (CLAUDE.md: no magic numbers/strings
## baked into the state machine) so the wording and step order are a resource
## edit, not a code change.
##
## DECISION (config/TutorialConfig.gd): the plan's own sketch nests the step
## type inside this script (`class Step: ...`). `steps` below is
## `Array[TutorialStep]`, a separate top-level Resource script, instead --
## see config/TutorialStep.gd's own doc comment for the reproduced .tres
## round-trip bug that rules the nested version out.
##
## `TutorialStep.completion_signal` is a StringName key ui/Tutorial.gd
## switches on, not a Callable -- a Resource cannot @export one.

## Exactly 5 steps (docs/M6_PLAN.md package B3): placing, rotating, territory,
## specials/throwing, camera -- in that order. Not enforced by size here
## (config/tutorial_config.tres is this package's one source of truth for the
## sequence); ui/Tutorial.gd itself only ever needs "a step index into this
## array", never a hardcoded count.
@export var steps: Array[TutorialStep] = []

## The special ui/Tutorial.gd force-queues (Match.debug_queue_special()) for
## the "specials/throwing" step, kept here rather than hardcoded in
## ui/Tutorial.gd so the demo special is a resource edit (CLAUDE.md: no magic
## ids in code). Must be one of config/specials/*.tres's own ids.
@export var demo_special_id: StringName = &"bomb"

## Seconds of observed camera_orbit/camera_pan_* input the "camera" step
## requires before it completes (docs/M6_PLAN.md package B3: "any
## camera_orbit/camera_pan_* input observed for a few seconds").
@export var camera_hold_seconds: float = 2.0
