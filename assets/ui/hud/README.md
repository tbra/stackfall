# HUD vector frames

Asset-only Stackfall HUD elements. These five SVGs use the colors, edges and radii in the candidate `docs/ART_DESIGN_SYSTEM.md`. The live HUD is unchanged.

| Source | Intrinsic size | Intended composition |
| --- | ---: | --- |
| `frame_panel.svg` | 320×112 | Wide information card; leave a 20 px content inset |
| `frame_gift.svg` | 96×96 | Gift preview frame; place the gift art over its inner field |
| `frame_score.svg` | 192×64 | Dark score plate; put dynamic player mark and score above it |
| `meter_track.svg` | 256×32 | Meter base with three quarter marks |
| `meter_fill.svg` | 240×16 | Coral fill; place at the track's 8 px inset and clip to value |

Keep dynamic labels, values and progress in the UI layer. The sources deliberately contain no text or numbers. At 1080p the panel and score plate can render at their intrinsic sizes; check scale at 720p and ultrawide before production use. For a resized panel, use 18 px nine-patch corners. For a meter, clip the fill to progress; stretching it horizontally changes the cap and highlight geometry.

The SVGs use simple fills and strokes, no fonts, filters, embedded bitmaps or external references. Colors are not intended for automatic tinting. See `docs/art_mockups/hud_frames_v1.png` for the asset review sheet.
