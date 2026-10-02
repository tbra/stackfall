class_name MenuVisualTuning
extends Resource
## M7 P7 (docs/M7_PLAN.md "P7 -- Main menu / lobby reskin", Bontago-xtq.32):
## every tunable the menu's layered-pastel look draws from -- the 2D paper-cut
## backdrop (ui/MenuBackdrop.gd), the live 3D diorama island (ui/MenuDiorama.gd),
## and the pastel pill/well Theme styles (ui/theme/MenuStyleFactory.gd) -- so no
## menu-facing color or size is a magic number in script (CLAUDE.md "No magic
## numbers"). Redone against docs/art_mockups/10-main-menu-layered-pastel.png
## and 11-lobby-layered-pastel.png after the owner rejected the first pass
## (Bontago-xtq.32: "absolutely not, it looks awful and nothing like the mockup").

## -- Diorama framing: the SubViewportContainer is reframed into a small,
## framed rectangle in the right third of the screen (gap item 1), instead of
## filling the whole background. Fractions of the parent Control's rect. -----
@export var diorama_anchor_left: float = 0.48
@export var diorama_anchor_top: float = 0.05
@export var diorama_anchor_right: float = 0.99
@export var diorama_anchor_bottom: float = 0.82

## -- Diorama island (a floating layered-plate disk, not a plain sand disk) ---
@export var disk_radius_m: float = 3.6
@export var disk_thickness_m: float = 0.35
@export var disk_color: Color = Color(0.22, 0.30, 0.34, 1.0)
@export var island_rim_color: Color = Color(0.86, 0.90, 0.88, 1.0)
@export var island_rim_height_m: float = 0.05
## -- Two-tier disc + ground shadow (review r1, item 7) -----------------------
@export var disk_lower_tier_color: Color = Color(0.14, 0.20, 0.24, 1.0)
@export var disk_lower_tier_radius_scale: float = 0.94
@export var disk_lower_tier_height_scale: float = 2.2
## review r2 item (a): lighter (was 0.28), bigger and softer via a radial
## fade texture, and dropped much further below the disc (drop_m) so it reads
## as a ground shadow, not a halo hugging the rim.
@export var disk_ground_shadow_color: Color = Color(0.10, 0.12, 0.14, 0.20)
@export var disk_ground_shadow_radius_scale: float = 1.35
@export var disk_ground_shadow_drop_m: float = 1.1

## -- Diorama sky/lighting (the live-3D half of the split background) --------
@export var sky_top_color: Color = Color(0.53, 0.72, 0.86, 1.0)
@export var sky_horizon_color: Color = Color(0.93, 0.78, 0.62, 1.0)
@export var ground_horizon_color: Color = Color(0.42, 0.34, 0.30, 1.0)
@export var sun_color: Color = Color(1.0, 0.94, 0.84, 1.0)
@export var sun_energy: float = 1.1
@export var ambient_energy: float = 0.9

## -- Diorama orbiting camera --------------------------------------------------
@export var camera_height_m: float = 2.6
@export var camera_radius_m: float = 5.0
@export var camera_orbit_period_s: float = 24.0
@export var camera_orbit_drift_fraction: float = 0.38
@export var camera_orbit_drift_period_s: float = 9.0
@export var camera_fov_deg: float = 42.0
## Orthographic span relative to island radius and miniature prop proportions.
@export var camera_span_radii: float = 2.5
@export var camera_start_yaw_degrees: float = 55.0
@export var miniature_block_scale: float = 0.28
@export var miniature_home_scale: float = 0.35
@export var miniature_goal_scale: float = 0.25
@export var stack_beacon_offset_m: float = 0.65

## -- Diorama props: two home flags + goal flag + per-owner block stacks ------
@export var home_flag_a_color: Color = Color(0.92, 0.42, 0.36, 1.0)
@export var home_flag_b_color: Color = Color(0.55, 0.72, 0.86, 1.0)
@export var block_color: Color = Color(0.62, 0.82, 0.66, 1.0)
@export var stack_block_count: int = 3
@export var stack_block_spacing_m: float = 0.34
@export var falling_block_interval_s: float = 7.0
@export var falling_block_duration_s: float = 1.4
@export var falling_block_height_m: float = 2.0
@export var falling_block_bounce_m: float = 0.16
@export var territory_patch_color_a: Color = Color(0.92, 0.42, 0.36, 0.35)
@export var territory_patch_color_b: Color = Color(0.55, 0.72, 0.86, 0.35)
@export var territory_patch_radius_m: float = 0.85

## -- 2D paper-cut backdrop (ui/MenuBackdrop.gd): sky, layered sun, cloud
## strata and ground bands drawn flat behind the 3D diorama, which is itself
## reframed to the right third of the screen (gap item 1, mockup 10). -------
@export var backdrop_sky_top_color: Color = Color(0.62, 0.80, 0.90, 1.0)
@export var backdrop_sky_horizon_color: Color = Color(0.88, 0.92, 0.90, 1.0)
## Number of horizontal gradient bands ui/MenuBackdrop.gd's _draw_sky() lerps
## between the two sky colors across -- review finding #4 (Bontago-xtq.32
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
@export var card_shadow_mint_color: Color = Color(0.75, 0.87, 0.78, 1.0)
@export var card_shadow_apricot_color: Color = Color(0.95, 0.80, 0.64, 1.0)
@export var card_offset_px: float = 14.0
@export var card_corner_radius_px: float = 18.0
@export var card_shadow_alpha: float = 0.9
## The rest of ui/theme/MenuStyleFactory.gd's make_card() -- review finding
## #4: these were bare literals despite that file's own "every color/size it
## draws from comes from config/MenuVisualTuning.gd" docstring.
## card_shadow_base_alpha is the shadow's alpha at card_shadow_alpha == 1.0;
## the drawn alpha is their product, exactly reproducing make_card()'s
## previous `0.12 * tuning.card_shadow_alpha` literal.
@export var card_shadow_base_alpha: float = 0.12
@export var card_shadow_size_px: float = 6.0
## DECISION (config/MenuVisualTuning.gd, Bontago-1pi.9a): 20 -> 26. Owner
## playtest ("too big and crammed, needs to be more airy and calm") --
## MenuStyleFactory.make_card() reads this as every card's inner padding
## (ui/MainMenu.gd's %Panel, ui/Lobby.gd's %SettingsCard/%PlayersCard/
## %AdvancedPopupCard), so a single bump gives every card more breathing room
## around its content without touching per-screen layout code.
@export var card_content_margin_px: float = 26.0

## DECISION (Bontago-mp0.11): viewport limits keep menu cards inside short
## windows while preserving readable type and the same control focus chain.
@export var menu_edge_margin_px: float = 18.0
## Bontago-mp0.18: minimum gap between the left window edge and the main card.
@export var menu_card_left_margin_px: float = 48.0
@export var menu_max_width_px: float = 960.0
@export var menu_card_width_px: float = 420.0
@export var menu_separation_px: int = 13
@export var menu_lan_list_height_px: float = 92.0
@export var menu_steam_list_height_px: float = 61.0
@export var menu_compact_height_px: float = 600.0
@export var menu_compact_card_margin_px: float = 12.0
@export var menu_compact_list_height_px: float = 50.0
@export var menu_compact_separation_px: int = 7
@export var menu_compact_button_height_px: float = 42.0
@export var menu_wide_width_px: float = 2400.0
@export var menu_wide_card_width_px: float = 540.0
@export var menu_wide_anchor_left: float = 0.22
@export var menu_wide_anchor_right: float = 0.68

## -- Varied pastel pill buttons + sunken wells (gap items 4, 5, 6) -----------
@export var pill_coral_color: Color = Color(0.92, 0.42, 0.36, 1.0)
@export var pill_coral_hover_color: Color = Color(0.95, 0.55, 0.48, 1.0)
@export var pill_coral_pressed_color: Color = Color(0.80, 0.32, 0.28, 1.0)
@export var pill_cream_color: Color = Color(0.93, 0.89, 0.80, 1.0)
@export var pill_cream_hover_color: Color = Color(0.97, 0.94, 0.87, 1.0)
@export var pill_mint_color: Color = Color(0.62, 0.82, 0.66, 1.0)
@export var pill_mint_hover_color: Color = Color(0.72, 0.88, 0.75, 1.0)
@export var pill_powder_blue_color: Color = Color(0.55, 0.72, 0.86, 1.0)
@export var pill_powder_blue_hover_color: Color = Color(0.68, 0.81, 0.91, 1.0)
@export var pill_dark_slate_color: Color = Color(0.24, 0.28, 0.32, 1.0)
@export var pill_dark_slate_hover_color: Color = Color(0.32, 0.37, 0.42, 1.0)
## Bontago-mp0.3.5 (lobby popup pass): a true near-white for the Players
## card's raised row pills (mockup 11) -- pill_cream_hover_color is the exact
## same value as card_cream_color, so a row painted with it reads as
## invisible against its own card (the review r2 "no pill background" bug).
## Not registered in config/tuning_panel_hints.tres: MenuVisualTuning has no
## F4 tab yet (ui/TuningPanel.gd's own "MenuVisualTuning is not merged yet
## and has no tab" comment), so the hints-file rule doesn't apply here.
@export var pill_white_color: Color = Color(1.0, 0.995, 0.98, 1.0)
@export var well_color: Color = Color(0.88, 0.84, 0.76, 1.0)
@export var well_border_color: Color = Color(0.78, 0.68, 0.52, 1.0)
@export var well_corner_radius_px: float = 10.0
## The rest of ui/theme/MenuStyleFactory.gd's make_well() (review finding #4).
@export var well_border_width_px: float = 2.0
## DECISION (config/MenuVisualTuning.gd, Bontago-1pi.9a): 8 -> 10, the same
## "airier, calmer" pass as card_content_margin_px above -- make_well()/
## make_flat_list() read this for every sunken list/field's own inner padding
## (the LAN/Steam game lists, the direct-IP field, the block-timer/gravity/
## special-frequency slider tracks).
@export var well_content_margin_px: float = 10.0
@export var label_ink_light_color: Color = Color(0.97, 0.95, 0.92, 1.0)
## Small-caps-style grey field captions ("NAME", "LAN GAMES", gap item 3).
@export var label_muted_color: Color = Color(0.55, 0.52, 0.48, 1.0)
@export var pill_corner_radius_px: float = 16.0
@export var pill_margin_x_px: float = 16.0
@export var pill_margin_y_px: float = 8.0
## apply_pill()'s "pressed" state darkens hover_color by this amount
## (Color.darkened()'s own 0.0..1.0 fraction) -- review finding #4: this was
## a bare `0.12` literal in MenuStyleFactory.gd.
@export var pill_pressed_darken_amount: float = 0.12

## -- Shared panel/focus palette ----------------------------------------------
@export var panel_border_color: Color = Color(0.78, 0.68, 0.52, 1.0)
@export var focus_outline_color: Color = Color(0.149, 0.196, 0.227, 1.0)
@export var ink_color: Color = Color(0.149, 0.196, 0.227, 1.0)

## -- Title treatment (Bontago-mp0.3.5 review r1): a soft offset shadow copy
## behind "Stackfall" / "Lobby" -- ui/MainMenu.gd's %TitleShadow RichTextLabel
## and ui/Lobby.gd's %HeaderTitle shadow override both read this.
@export var title_shadow_color: Color = Color(0.95, 0.80, 0.64, 1.0)
@export var title_shadow_offset_px: Vector2 = Vector2(3.0, 4.0)
