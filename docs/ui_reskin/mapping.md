# Old tunable → Arcade token mapping (P0 starting point)

| Old (file: tunable) | Old value | Arcade token | New value |
|---|---|---|---|
| stackfall_theme.tres: Panel bg | #f5ebd6fa | disc-800 | #1f1a26 |
| stackfall_theme.tres: field bg | #fffaf0 | disc-900 (well) | #16121c |
| stackfall_theme.tres: border | #c7ad85 | disc-400 | #6e6478 |
| stackfall_theme.tres / MenuVisualTuning: ink_color, Label font_color | #26323a | cream (text on disc) / ink (text on bright faces) | #fff6ea / #16121c |
| CaptionLabel font_color, label_muted_color | #667078 | dust | #a89aa8 |
| Button normal / pill_coral_color | #eb6b5c | flare | #ff5a3d |
| Button hover / pill_coral_hover_color | #f28c7a | flare mixed 15 % white | — |
| Button pressed / pill_coral_pressed_color | #cc5247 | flare-lip | #c23a22 |
| Button font_color (on coral) | #faf5f0 | ink | #16121c |
| Button disabled | #c7bdad | face at opacity 0.45, no ledge | — |
| focus StyleBox border | 3 px #26323a | 3 px cream, 3 px outside | #fff6ea |
| pill_cream / pill_mint / pill_powder_blue / pill_dark_slate | pastels | disc-600 secondary block (all) ; mint only for Ready | #383040 / #59cc66 |
| well_color / well_border_color | #e0d6c2 / #d1ccbf | disc-900 / disc-400 | |
| card_cream / card_shadow_mint / card_shadow_apricot | pastels | removed (single disc-800 panel, shadow-panel) | |
| pill_corner_radius_px 26, well 22, card 28, panel 18, button 16, field 10 | | radius-block 8, radius-panel 12, radius-chip 5, radius-cell 3 | |
| HUDVisualTuning.panel_background_color / surface_color | rgba dark 0.78 / 0.42 | disc-900 @ hud-plate 0.86 | |
| HUDVisualTuning.ink_color / muted_ink_color | #f5f2e6 / #ccd1d6e6 | cream / sand | |
| HUDVisualTuning.hud_share_bar_track_color | #0f0f17 @ .55 | disc-700 + 10 % ticks in disc-900 | |
| HUDVisualTuning.minimap_frame_color | #d9dee6 @ .85 | rim, 3 px, + glow | #ffc65a |
| HUDVisualTuning.toast_fill_color / toast_reject_accent_color | dark / #f26b5c | Callout faces: alert / mint / rim with ink text | |
| HUDVisualTuning.countdown_go_text "Go!" | | "GO" in rim, Bungee 128 px | |
| MatchConfig.player_colors | unchanged | player-1…8 | unchanged |
| Manrope-Regular.ttf (wght 640/700/800) | | Rubik variable (500/700/800) + Bungee | |
