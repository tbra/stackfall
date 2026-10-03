# Loading arena backgrounds: all shapes

Fifteen candidate PNG plates: round, oval, ring, twin and cross, each in sunset,
night and dawn. Every plate is 1920 x 1080 and uses the actual medium arena
resource and game renderer. For ring, twin and cross, this art tool substitutes
analytic visual meshes using the existing game materials: the current game's
visible bodies are round despite its correctly shaped collision maps. These
plates illustrate the configured shape, rather than the current visual fallback.
Four frozen stacks use the gameplay block factory
and match tuning; stack centers are checked against solid map ground. There is
no baked text, loading card or HUD.

This extends the round-only Bontago-mp0.96 set. Round is refreshed from the same
base as the other shapes to keep the sky and materials coherent. Prefer one
complete set during integration. `manifest.json` records shape enum values,
map resource paths, theme IDs, file names, native dimensions and camera setup.

## Integration

Select by map variant and resolved sky theme. `sunset` is the fallback for an
unknown theme; use `round` for an unknown shape. Random or Cycle can use the
resolved phase's closest plate. Size presets share one illustration per shape;
these are decorative backgrounds, not exact previews of player layouts or
small/large geometry.

Display with a fullscreen `TextureRect`, `EXPAND_IGNORE_SIZE` and
`STRETCH_KEEP_ASPECT_COVERED`, centered cropping, linear filtering and one shared
UI scale. Apply dimming separately; the prior mp0.96 package shows an actual
loading card over artwork at 0.58 dark-overlay alpha. No live UI file is changed
by this package.

`docs/art_mockups/loading_arena_v2/all_shapes.png` compares every source plate.
`crop_review.png` shows each sunset shape at 1280x720, 1920x1080, 2560x1440,
3440x1440 and 720x1280 using
the same centered cover rule. Artwork may crop at screen edges. These checks
prove art framing, not runtime UI resize behavior. Above 1080p, images scale up.

## Reproduce

```powershell
godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/render_loading_shapes.tscn -- --agent-probe --render-size=1920x1080
python tools/review_loading_shapes.py
```

The capture builds each map through the normal sandbox config path and asserts
the resulting Field's shape before exporting its three themes. It tears down
each world before the next shape. The review script checks exact enum/theme
coverage, native dimensions, map provenance and unique image hashes. It excludes
the loading overlay proof whose cleanup is separately tracked in Bontago-fca.21.
Validation and accepted base belong to Bontago-mp0.99. Rerender after significant
integrated sky changes if needed.

## Candidate verification

Two offscreen capture runs were used. The second produced all fifteen corrected
plates with no runtime script/shader errors; it reported seven Texture RIDs at
shutdown. This is a capture cleanup warning; image output and visual inspection
passed. Do not treat this as a clean engine shutdown. The review checks all
fifteen native images, five shape enum IDs, resource paths, geometry provenance,
unique image hashes and the five centered-cover sizes listed above.
