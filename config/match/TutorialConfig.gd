class_name TutorialConfig
extends Resource
## The tutorial script (spec 1.2 "Tutorial") that ui/menus/Tutorial.gd drives, kept
## as data so wording and step order are a resource edit, not a code change.
##
## DECISION: `steps` is `Array[TutorialStep]`, a top-level Resource script, not a
## nested class; see TutorialStep.gd for the .tres round-trip bug that rules the
## nested version out.
##
## `TutorialStep.completion_signal` is a StringName key ui/menus/Tutorial.gd
## switches on, not a Callable -- a Resource cannot @export one.

## The steps in order (five in config/match/tutorial_config.tres). The size is not
## enforced; ui/menus/Tutorial.gd only needs a step index into this array.
@export var steps: Array[TutorialStep] = []

## The special ui/menus/Tutorial.gd force-queues (Match.debug_queue_special()) for
## the "specials/throwing" step. Must be one of config/gifts/specials/*.tres's ids.
@export var demo_special_id: StringName = &"bomb"

## Seconds of observed camera_orbit/camera_pan_* input the "camera" step requires
## before it completes.
@export var camera_hold_seconds: float = 2.0
