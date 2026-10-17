class_name CameraTuning
extends Resource
## Camera rig tunables (spec 1.3 camera row), read by CameraRig.gd.

## -- Orbit --------------------------------------------------------------
## Radians of yaw/pitch per pixel of mouse motion while camera_orbit_hold.
@export var mouse_orbit_speed: float = 0.006
## Radians per second at full gamepad stick deflection.
@export var pad_orbit_speed: float = 2.4
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = 60.0

## -- Zoom -----------------------------------------------------------------
@export var zoom_min: float = 4.0
@export var zoom_max: float = 100.0
## Distance change per discrete zoom step (wheel tick, key press, or trigger
## pull; spec 1.3 scopes wheel/trigger zoom to "while not holding a block").
## DECISION: the default mouse wheel changes block hover height instead
## (GhostTuning.hover_wheel_step); this step only drives camera zoom while
## camera_orbit/camera_mode is held or via the dedicated zoom keys/triggers.
@export var zoom_step: float = 4.0
## (spec 1.3 "Camera orbit (hold+drag)... mouse wheel zooms while held"
## [ORIGINAL]): distance change per wheel notch while camera_mode/camera_orbit is
## held (CameraRig.zoom_by_orbit_step()), tuned separately from zoom_step so the
## held-orbit wheel can feel different from the dedicated zoom keys.
@export var orbit_zoom_step: float = 2.0
## LT held + left stick up/down zooms in/out continuously: distance change per second
## at full left-stick deflection while camera_zoom_modifier (LT) is held
## (CameraRig.zoom_continuous(), PlayerController._drive_gamepad_zoom()). The
## analog counterpart of the fixed per-notch zoom_step/orbit_zoom_step.
@export var gamepad_trigger_zoom_speed: float = 15.0

## -- Pan --------------------------------------------------------------------
## Meters per second the orbit target moves at full input.
@export var pan_speed: float = 18.0
## Meters of orbit-target movement per pixel of mouse motion while panning
## with Space + drag.
@export var mouse_pan_speed: float = 0.03

## -- Follow-block mode (camera attached to the held block) ----------
## true (default): the rig's pivot tracks the held ghost's position every
## frame (smoothed by follow_lag_seconds below); camera_mode orbits, pan and
## camera_snap_home/goal are no-ops (there is nothing to pan away from).
## false: the free-orbit camera (manual pan, snap-to-home/goal, a fixed target),
## which tests pin by constructing a CameraTuning with this set to false.
@export var follow_block: bool = true
## Seconds for the follow target to mostly catch up to the ghost's position
## (an exponential approach, not a hard snap); 0 tracks it exactly every
## frame. A hard snap (0.0) matches the original game's feel best; any smoothing
## read as lag.
@export var follow_lag_seconds: float = 0.0
## With follow_lag_seconds == 0 every set_follow_position() update hard-snaps, which
## is right for small per-frame ghost motion but makes the camera jump on the
## discontinuous re-target PlayerController._apply_spawn_clearance() produces
## (raising the new ghost's manual_hover_offset when the next piece would spawn
## inside the block just placed). CameraRig.begin_follow_transition() eases into
## that one re-target over this many seconds (exponential approach) without
## softening ordinary movement.
## DECISION: 0.2 s is long enough to read as a smooth catch-up, short enough not to
## feel like lag on the next ordinary ghost move.
@export var drop_recover_seconds: float = 0.2
## Camera distance and pitch while following the held block. The original game
## frames the block from a few metres away at a shallow angle so it fills the lower
## half of the view and the disk edge stays visible; a field-radius-scaled distance
## (the free-camera default) puts the block far away.
@export var follow_distance: float = 9.0
## Matches the original game's downward view.
@export var follow_pitch_deg: float = -35.0

## -- Snap (spec 1.3 "Snap camera to home / goal") ----------------------------
## Snap to home/goal is switched off (and its Options rows hidden) until it is
## reworked. CameraRig ignores camera_snap_home/goal
## while this is false; the actions and their bindings stay in the Input Map.
@export var snap_enabled: bool = false
@export var snap_pitch_deg: float = -35.0
@export var snap_distance: float = 30.0
@export var snap_duration: float = 0.35

## -- Focus home/goal: the follow camera's camera_snap_home/camera_snap_goal actions
## are a tap-to-TURN and a hold-to-PEEK gesture (spec 1.3) -----------------------
## Seconds camera_snap_home/goal must be held before the gesture becomes a
## PEEK (glide to frame the target while held) instead of a TURN (a quick
## tap: tween yaw only, so the target ends up dead ahead of the held block).
@export var focus_hold_threshold_s: float = 0.3
## How long the TURN gesture's yaw tween takes.
@export var focus_turn_duration_s: float = 0.35
## How long PEEK's glide to the target framing -- and its glide back to the
## normal follow framing on release -- each take. One tunable for both
## directions: a symmetric glide reads as one continuous motion rather than
## two differently-paced ones.
@export var focus_peek_transition_s: float = 0.35
## Camera distance and pitch while PEEK holds on the focus target. Separate
## from snap_distance/snap_pitch_deg (the free camera's own instant
## snap) so the follow camera's PEEK framing can be tuned independently.
@export var focus_peek_distance: float = 16.0
@export var focus_peek_pitch_deg: float = -30.0

## -- Lens -------------------------------------------------------------------
## DECISION: default matches Camera3D's own engine default (75 deg), which
## game/player/CameraRig.tscn's Camera3D uses without an override. Applied in both
## CameraRig._ready() and apply_follow_tuning() so the F4 panel's slider
## (config/ui/tuning_panel_hints.tres, range 40..100) takes effect live.
@export var fov_deg: float = 75.0
## The player-facing Options > Game "Field of view" slider spans this range
## (Settings stores an optional override of fov_deg; the F4 fov_deg stays the default baseline).
@export var fov_min_deg: float = 40.0
@export var fov_max_deg: float = 100.0
## Degrees per cell on that slider (5 deg/step = 12 cells over 40..100).
@export var fov_step_deg: float = 5.0


## -- Match-start view ----------------------------------------------------------
## The camera has no countdown pose: when the ready gate opens it takes this pitch
## and distance (a low, wide angle) and the normal ghost-follow runs from the first
## frame, through the 3-2-1 and GO.
## Distance from the followed block in metres, derived from a reference shot at
## field of view 75 deg.
@export var start_distance_m: float = 11.2
## Camera pitch of the match-start view (negative looks down).
@export var start_pitch_deg: float = -12.7
