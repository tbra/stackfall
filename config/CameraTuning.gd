class_name CameraTuning
extends Resource
## Camera rig tunables (spec 2.5 camera row). Keeps CameraRig.gd free of
## magic numbers per CLAUDE.md.

## -- Orbit --------------------------------------------------------------
## Radians of yaw/pitch per pixel of mouse motion while camera_orbit_hold.
@export var mouse_orbit_speed: float = 0.006
## Radians per second at full gamepad stick deflection.
@export var pad_orbit_speed: float = 2.4
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = -5.0

## -- Zoom -----------------------------------------------------------------
@export var zoom_min: float = 8.0
@export var zoom_max: float = 100.0
## Distance change per discrete zoom step (wheel tick, key press, or trigger
## pull; spec 2.5 scopes wheel/trigger zoom to "while not holding a block").
@export var zoom_step: float = 4.0

## -- Pan --------------------------------------------------------------------
## Meters per second the orbit target moves at full input.
@export var pan_speed: float = 18.0
## Meters of orbit-target movement per pixel of mouse motion while panning
## with Space + drag.
@export var mouse_pan_speed: float = 0.03

## -- Follow-block mode (Bontago-mv0.14: original's camera is attached to the
## held block, spec 1.5, docs/ORIGINAL_BONTAGO_NOTES.md "Controls") ----------
## true (default): the rig's pivot tracks the held ghost's position every
## frame (smoothed by follow_lag_seconds below); camera_mode orbits, pan and
## camera_snap_home/goal are no-ops (there is nothing to pan away from).
## false: the pre-mv0.14 free-orbit camera (manual pan, snap-to-home/goal,
## a fixed target) -- kept so a test can pin the old behaviour deliberately
## by constructing a CameraTuning with this set to false.
@export var follow_block: bool = true
## Seconds for the follow target to mostly catch up to the ghost's position
## (an exponential approach, not a hard snap); 0 tracks it exactly every
## frame.
@export var follow_lag_seconds: float = 0.15

## -- Snap (spec 2.5 "Snap camera to home / goal") ----------------------------
@export var snap_pitch_deg: float = -35.0
@export var snap_distance: float = 30.0
@export var snap_duration: float = 0.35
