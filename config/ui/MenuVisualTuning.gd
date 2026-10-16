class_name MenuVisualTuning
extends Resource
## Main menu and lobby reskin:
## every tunable the menu's layered-pastel look draws from -- the 2D paper-cut
## backdrop (ui/menus/MenuBackdrop.gd)
## and the pastel pill/well Theme styles (ui/theme/MenuStyleFactory.gd) -- so no
## menu-facing color or size is a magic number in script (CLAUDE.md "No magic
## numbers"). Redone against docs/art_mockups/10-main-menu-layered-pastel.png
## and 11-lobby-layered-pastel.png after the owner rejected the first pass
## ("absolutely not, it looks awful and nothing like the mockup").

## -- Menu render budget: while a menu/lobby backdrop is in
## the tree the full-screen opaque backdrop hides the match world, so the root
## viewport skips its 3D pass and the frame rate is capped (0 = no cap). Never
## applied in a match; the player's vsync choice is untouched. --------------
## DECISION (~25% GPU idling in the menu): 60 -> 30. The
## menu is a static paper-cut backdrop, UI cards and; 30 fps
## halves every idle GPU/CPU cost (present, UI redraw) with no visible change.
@export var menu_max_fps: int = 30
@export var menu_disable_world_3d: bool = true

## -- 2D paper-cut backdrop (ui/menus/MenuBackdrop.gd): sky, layered sun, cloud
## strata and ground bands. -------
@export var backdrop_sky_top_color: Color = Color(0.62, 0.80, 0.90, 1.0)
@export var backdrop_sky_horizon_color: Color = Color(0.88, 0.92, 0.90, 1.0)
## Number of horizontal gradient bands ui/menus/MenuBackdrop.gd's _draw_sky() lerps
## between the two sky colors across -- review finding #4 (
## redo #3): this used to be a bare `const SKY_BAND_COUNT` in MenuBackdrop.gd
## itself, contradicting that file's own "every color, count and layout
## fraction it draws from is a MenuVisualTuning export" docstring.
@export var backdrop_sky_band_count: int = 24
## Sun gradient (review r1, item 7): 3-stop core->ring->halo instead of a
## flat 2-color alternation, so the sun reads orange/peach, not yellow.
@export var backdrop_sun_color: Color = Color(0.95, 0.55, 0.22, 1.0)
@export var backdrop_sun_ring_color: Color = Color(0.98, 0.75, 0.55, 1.0)
@export var backdrop_sun_halo_color: Color = Color(0.99, 0.92, 0.85, 0.55)
@export var backdrop_sun_ring_count: int = 4
@export var backdrop_sun_radius_fraction: float = 0.16
@export var backdrop_sun_pos_x_fraction: float = 0.74
@export var backdrop_sun_pos_y_fraction: float = 0.20
@export var backdrop_cloud_color: Color = Color(1.0, 1.0, 1.0, 0.75)
@export var backdrop_cloud_count: int = 4
## The rest of _draw_clouds()'s layout, as fractions of the backdrop's own
## size (review finding #4: these were bare literals in MenuBackdrop.gd).
@export var backdrop_cloud_width_fraction: float = 0.16
@export var backdrop_cloud_height_fraction: float = 0.05
@export var backdrop_cloud_base_y_fraction: float = 0.34
## How far every other cloud is nudged down, as a fraction of cloud height.
@export var backdrop_cloud_offset_fraction: float = 0.8
@export var ground_band_apricot_color: Color = Color(0.95, 0.80, 0.64, 1.0)
@export var ground_band_mint_color: Color = Color(0.75, 0.87, 0.78, 1.0)
@export var ground_band_height_fraction: float = 0.16

## -- Offset triple-card panel stack (gap item 2): a cream front card with a
## mint and an apricot "shadow" card peeking out from behind it. -------------
@export var card_cream_color: Color = Color(0.97, 0.94, 0.87, 1.0)
@export var card_offset_px: float = 14.0
@export var card_shadow_size_px: float = 6.0

## DECISION: viewport limits keep menu cards inside short
## windows while preserving readable type and the same control focus chain.
@export var menu_edge_margin_px: float = 18.0
@export var menu_max_width_px: float = 960.0
@export var menu_lan_list_height_px: float = 92.0
@export var menu_steam_list_height_px: float = 61.0
@export var menu_compact_list_height_px: float = 50.0
@export var menu_compact_separation_px: int = 7

## -- Varied pastel pill buttons + sunken wells (gap items 4, 5, 6) -----------
@export var pill_cream_color: Color = Color(0.93, 0.89, 0.80, 1.0)
@export var pill_cream_hover_color: Color = Color(0.97, 0.94, 0.87, 1.0)
@export var pill_mint_color: Color = Color(0.62, 0.82, 0.66, 1.0)
@export var pill_mint_hover_color: Color = Color(0.72, 0.88, 0.75, 1.0)
## DECISION (config/ui/MenuVisualTuning.gd.9a): 8 -> 10, the same
## "airier, calmer" pass as card_content_margin_px above -- make_well()/
## make_flat_list() read this for every sunken list/field's own inner padding
## (the LAN/Steam game lists, the direct-IP field, the block-timer/gravity/
## special-frequency slider tracks).
@export var well_content_margin_px: float = 10.0
## the minimum WCAG-style contrast ratio (1.0 = identical,
## 21.0 = black on white; MenuStyleFactory.contrast_ratio()) between a menu
## button's icon colour and the stylebox it is drawn on, in every draw state
## (normal, focus, hover, pressed, disabled). tests/unit/ui/test_menu_icons.gd
## walks the menu scenes against it. Icons are white-source SVGs tinted by the
## Button icon_*_color theme items MenuStyleFactory sets to the pill's label
## ink, so an icon always follows its caption colour.
## DECISION: 2.0, not WCAG's 3.0 for graphics. The shipped
## light-ink-on-coral pairing (Host/Bots/Resume) measures 2.1..2.8 across its
## states (dark ink would give 4.2..5.5); 2.0 rejects the reported bug class
## (white/light icon on a cream/mint/blue pill = 1.0..1.9) without restyling
## the primary coral buttons. Raise to 3.0 together with a dark-ink coral pill.
@export var icon_min_contrast_ratio: float = 2.0

## -- Shared panel/focus palette ----------------------------------------------
@export var focus_outline_color: Color = Color(0.149, 0.196, 0.227, 1.0)
@export var ink_color: Color = Color(0.149, 0.196, 0.227, 1.0)

## -- Title treatment (review r1): a soft offset shadow copy
