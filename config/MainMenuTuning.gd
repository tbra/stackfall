class_name MainMenuTuning
extends Resource
## Bontago-hfa.3 (UI reskin P1, docs/UI_RESKIN_PLAN.md): every tunable of the Stackfall Arcade
## main menu that is not a shared design token (those live in config/ArcadeVisualTuning.gd): the
## left column and scrim geometry (ui/MainMenu.gd). The backdrop is a static image
## (assets/ui/menu_backdrop.png, Bontago-1pi.144), set on the scene's BackdropImage node.

## -- Left column ---------------------------------------------------------------------------
## Width of the left button column in logical (1280x720 base) pixels.
@export var column_width_px: float = 368.0
## Gap between the screen's left edge and the column.
@export var column_left_margin_px: float = 48.0
## Height of the Stackfall lockup in the column.
@export var lockup_height_px: float = 46.0
## Minimum height of a full-width block (Host, Join, Play offline, local-page options).
@export var block_height_px: float = 46.0
## Minimum height of the small blocks (Options, Quit, Back) and compact join-page rows.
@export var block_small_height_px: float = 36.0
## Gap between stacked blocks in addition to the ledge (design: space-3 + drop).
@export var block_gap_px: int = 10
## Extra gap between the lockup/tagline and the first field.
@export var section_gap_px: float = 10.0
## Gap between a section label (NAME) and its field.
@export var label_gap_px: int = 4

## -- Left scrim ----------------------------------------------------------------------------
## Width of the disc-dark gradient that keeps the column readable over the arena.
@export var scrim_width_px: float = 700.0
## Fraction of the scrim width that stays fully opaque before it fades out.
@export var scrim_solid_fraction: float = 0.5
## Resolution of the generated gradient texture.
@export var scrim_texture_width_px: int = 128
