class_name CameraTuning
extends Resource
## Camera rig tunables (spec 1.3 camera row). Keeps CameraRig.gd free of
## magic numbers per CLAUDE.md.

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
## Feel report ("Scrolling up/down should be a bit faster"):
## briefly raised x1.5 here, then reverted -- the coordinator clarified the
## owner's "scrolling" means the *default* mouse wheel (block hover height,
## GhostTuning.hover_wheel_step, out of this resource entirely), not the
## camera zoom this field only drives while camera_orbit/camera_mode is held
## or via the dedicated Z/X keys/gamepad triggers. See config/blocks/tuning/GhostTuning.gd's
## own hover_wheel_step/hover_manual_adjust_speed for the actual fix.
@export var zoom_step: float = 4.0
## (spec 1.3 "Camera orbit (hold+drag)... mouse wheel zooms
## while held" [ORIGINAL]): distance change per wheel
## notch while camera_mode/camera_orbit is held (CameraRig.zoom_by_orbit_step()),
## tuned separately from zoom_step above so the held-orbit wheel can feel
## different from the dedicated Z/X zoom keys.
## Not the "scrolling" the owner meant either -- see zoom_step's
## own DECISION above; reverted to its original value.
@export var orbit_zoom_step: float = 2.0
## Controller update (feedback/controller-update.md, re-confirmed
## "LT held + left stick up/down = zoom camera in (stick up) /
## out (stick down), continuous"): distance change per second at full
## left-stick deflection while camera_zoom_modifier (LT) is held
## (game/player/CameraRig.gd's zoom_continuous(), game/player/PlayerController.gd's
## _drive_gamepad_zoom()). Distinct from zoom_step/orbit_zoom_step above,
## which are both fixed per-notch/per-press steps, not a continuous per-second
## rate -- this is the analog equivalent, the same "own tunable per gesture"
## precedent orbit_zoom_step already set against zoom_step.
@export var gamepad_trigger_zoom_speed: float = 15.0

## -- Pan --------------------------------------------------------------------
## Meters per second the orbit target moves at full input.
@export var pan_speed: float = 18.0
## Meters of orbit-target movement per pixel of mouse motion while panning
## with Space + drag.
@export var mouse_pan_speed: float = 0.03

## -- Follow-block mode (camera attached to the
## held block) ----------
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
## feel report 1: 0.15 s read as noticeably laggy
## behind the held block; 0.05 s keeps the smoothing (still not a hard snap)
## while tracking much closer to instantly.
## after re-testing against the original
## Bontago: a hard snap (0.0) matches the original's feel best -- any
## remaining smoothing still read as lag once compared side by side.
@export var follow_lag_seconds: float = 0.0
## Feel report ("Camera always jumps up after block drops or
## when clicking the drop button"). ROOT CAUSE (see game/player/CameraRig.gd's
## begin_follow_transition() doc comment for the full writeup): every
## set_follow_position() update is hard-snapped when follow_lag_seconds == 0
## above -- correct for the small, continuous per-frame ghost motion that
## reads as instant tracking, but wrong
## discontinuous re-target game/player/PlayerController.gd's own
## _apply_spawn_clearance() produces: raising the newly issued ghost's
## manual_hover_offset (so its followed height) the instant the next piece
## would otherwise spawn inside the block just placed -- the common case of
## building on your own stack. begin_follow_transition() eases into that one
## re-target over this many seconds (an exponential approach, the same shape
## follow_lag_seconds above already uses) instead of snapping to it, without
## softening ordinary movement at all.
## DECISION (config/player/CameraTuning.gd): 0.2 s is a simple, short value in the
## same neighbourhood as follow_lag_seconds' own pre-mv0.21 tuning (0.05-0.15s)
## -- long enough to read as a smooth catch-up, short enough not to feel like
## the camera is lagging behind on the very next ordinary ghost move.
@export var drop_recover_seconds: float = 0.2
## Camera distance and pitch while following the held block. The original
## (a reference screenshot of the original game) frames the block from a few metres away at a
## shallow angle so the block fills the lower half of the view and the disk
## edge stays visible; a field-radius-scaled distance (the free-camera default)
## puts the block "a billion miles away".
@export var follow_distance: float = 9.0
## after re-testing against the original
## Bontago: steepened from -28 to -35 to match the original's shallower
## downward view.
@export var follow_pitch_deg: float = -35.0

## -- Snap (spec 1.3 "Snap camera to home / goal") ----------------------------
## snap to home/goal is switched off (and its Options rows hidden)
## until it is reworked. CameraRig ignores camera_snap_home/goal
## while this is false; the actions and their bindings stay in the Input Map.
@export var snap_enabled: bool = false
@export var snap_pitch_deg: float = -35.0
@export var snap_distance: float = 30.0
@export var snap_duration: float = 0.35

## -- Focus home/goal:
## the default follow camera's camera_snap_home/camera_snap_goal actions now
## do both a tap-to-TURN and a hold-to-PEEK gesture instead of one instant
## snap (spec 1.3) -----------------------------------------------------------
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
## from snap_distance/snap_pitch_deg (the legacy free-camera's own instant
## snap) so the follow camera's PEEK framing can be tuned independently.
@export var focus_peek_distance: float = 16.0
@export var focus_peek_pitch_deg: float = -30.0

## -- Lens ("is there a fish-eye effect? add a
## slider") ------------------------------------------------------------------
## DECISION (config/player/CameraTuning.gd): default matches Camera3D's own engine
## default (75 deg), which is what game/player/CameraRig.tscn's Camera3D used before
## this tunable existed (no fov override was set there). Applied in both
## CameraRig._ready() and apply_follow_tuning() so the F4 panel's slider
## (config/ui/tuning_panel_hints.tres, range 40..100) takes effect live.
@export var fov_deg: float = 75.0
## the player-facing Options > Game "Field of view" slider spans this range
## (Settings stores an optional override of fov_deg; the F4 fov_deg stays the default baseline).
@export var fov_min_deg: float = 40.0
@export var fov_max_deg: float = 100.0
## degrees per cell on that slider (5 deg/step = 12 cells over 40..100).
@export var fov_step_deg: float = 5.0


## -- Match-start view (
## feedback/051026/3.png) -----------------------------------------------------
## The camera has no countdown pose: when the ready gate opens it takes this
## pitch and distance (the low, wide angle of the owner's screenshot 3) and the
## normal ghost-follow runs from the first frame, through the 3-2-1 and GO.
## Distance from the followed block in metres. Derived from screenshot 3 (field
## of view 75 deg): the home territory circle is ~0.92 of its width in the
## follow-pose screenshot 4 (9 m), so the camera sits ~11 m back (probe-checked against the screenshot).
@export var start_distance_m: float = 11.2
## Camera pitch of the match-start view (negative looks down). Derived from
## screenshot 3: the horizon sits ~120 px above centre of an 837 px frame.
@export var start_pitch_deg: float = -12.7
