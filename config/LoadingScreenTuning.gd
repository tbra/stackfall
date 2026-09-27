class_name LoadingScreenTuning
extends Resource
## Tunables for ui/LoadingScreen.gd (Bontago-1pi.8, owner playtest 2026-09-27:
## "add a proper loading screen instead" of the idle centre-beacon camera
## shot between Start Match and the countdown).
##
## Not one of the F4 tuning panel's six resource classes (CameraTuning,
## GhostTuning, PhysicsTuning, TerritoryTuning, TerritoryVisuals,
## BlockFeedConfig -- docs/AGENT_WORKFLOW.md's "New tunables" note), so these
## exports do not need a config/tuning_panel_hints.tres entry.

## Opaque overlay color while loading -- must fully hide the 3D disk/camera
## behind it (CLAUDE.md "no magic numbers": every tunable lives in a
## Resource).
@export var background_color: Color = Color(0.06, 0.07, 0.09, 0.96)

## How long ui/LoadingScreen.gd's fade-to-transparent tween runs once it
## starts (see LoadingScreen.fade_out()'s own doc for why that start is
## itself delayed by warmup_frames below).
@export var fade_out_duration_s: float = 0.35

## Seconds between one "Loading." / "Loading.." / "Loading..." frame and the
## next.
@export var spinner_interval_s: float = 0.35

## Rendered frames LoadingScreen.fade_out() holds the overlay up once called,
## before starting the actual fade -- see that function's own DECISION doc.
@export var warmup_frames: int = 3
