class_name MainMenuTuning
extends Resource
## Bontago-hfa.3 (UI reskin P1, docs/UI_RESKIN_PLAN.md): every tunable of the Stackfall Arcade
## main menu that is not a shared design token (those live in config/ArcadeVisualTuning.gd): the
## left column and scrim geometry (ui/MainMenu.gd) and the live-arena orbit backdrop
## (ui/MenuArena.gd, owner answer Q1 b: "a slow orbit over a live arena, reusing the real arena
## mesh and beacons at menu quality, no physics").

## -- Left column ---------------------------------------------------------------------------
## Width of the left button column in logical (1280x720 base) pixels.
@export var column_width_px: float = 368.0
## Gap between the screen's left edge and the column.
@export var column_left_margin_px: float = 48.0
## Height of the Stackfall lockup in the column.
@export var lockup_height_px: float = 52.0
## Minimum height of a full-width block (Host, Join, Play offline, local-page options).
@export var block_height_px: float = 52.0
## Minimum height of the small blocks (Options, Quit, Back) and compact join-page rows.
@export var block_small_height_px: float = 40.0
## Gap between stacked blocks in addition to the ledge (design: space-3 + drop).
@export var block_gap_px: int = 12
## Extra gap between the lockup/tagline and the first field.
@export var section_gap_px: float = 16.0
## Gap between a section label (NAME) and its field.
@export var label_gap_px: int = 4

## -- Left scrim ----------------------------------------------------------------------------
## Width of the disc-dark gradient that keeps the column readable over the arena.
@export var scrim_width_px: float = 700.0
## Fraction of the scrim width that stays fully opaque before it fades out.
@export var scrim_solid_fraction: float = 0.5
## Resolution of the generated gradient texture.
@export var scrim_texture_width_px: int = 128

## -- Arena backdrop (ui/MenuArena.gd) ------------------------------------------------------
## Map the orbit arena is built from (the real MapDef, so the real disc mesh is reused).
@export var arena_map: MapDef = null
## Players whose beacons and claimed ground are shown.
@export var arena_slot_count: int = 4
## Radius, in cells, of the claimed ground disc around each beacon.
@export var territory_radius_cells: float = 11.0
## Blocks of the still life per beacon.
@export var blocks_per_slot: int = 16
## Blocks stacked around each beacon never come closer than this to it (metres).
@export var block_ring_min_m: float = 2.5
## ...nor further than this.
@export var block_ring_max_m: float = 6.5
## Highest layer of a stack (0 = floor only).
@export var block_max_layer: int = 2
## Seed of the still life, so the backdrop is identical on every launch.
@export var layout_seed: int = 20261010
## Chance that a block of the still life rests on top of another one.
@export var block_stack_chance: float = 0.45
## Shapes the still life draws from.
@export var block_shapes: Array[BlockShape] = []

## -- Orbit camera --------------------------------------------------------------------------
@export var camera_fov_deg: float = 40.0
## Distance from the arena centre to the camera on the ground plane (metres).
@export var camera_radius_m: float = 36.0
@export var camera_height_m: float = 8.0
## Height of the point the camera looks at.
@export var camera_target_height_m: float = 2.0
## Horizontal frustum shift (metres) that moves the arena towards the right of the screen,
## away from the column.
@export var camera_h_offset_m: float = -8.0
## Seconds per full orbit.
@export var orbit_period_s: float = 150.0
@export var orbit_start_yaw_deg: float = 215.0
## Camera far clip, metres.
@export var camera_far_m: float = 400.0

## -- Rendering cost ------------------------------------------------------------------------
## SubViewportContainer.stretch_shrink: 2 renders the arena at half resolution.
@export var render_shrink: int = 1
## FXAA stands in for MSAA (the arena draws once per frame behind a scrim).
@export var use_fxaa: bool = true

## -- Sky and light (golden hour; the UI takes none of its colour from the sky) -----------------
@export var sky_top_color: Color = Color("#8c7fa6")
@export var sky_horizon_color: Color = Color("#ffd2a3")
@export var ground_horizon_color: Color = Color("#b08f94")
@export var ground_bottom_color: Color = Color("#3a3040")
@export var ambient_energy: float = 1.1
@export var sun_color: Color = Color("#ffd9a6")
@export var sun_energy: float = 1.5
@export var sun_rotation_deg: Vector3 = Vector3(-24.0, -52.0, 0.0)
@export var fog_color: Color = Color("#e8b99a")
@export var fog_density: float = 0.004
@export var fog_sky_affect: float = 0.0
