# Loading arena backgrounds

Three PNG plates: the round arena in sunset, night and dawn. Every plate is
1920 x 1080 and uses the actual medium arena resource and game renderer. No baked
text, loading card or HUD.

Bontago-fca.75 (owner decision fca.74 = B) removed the oval, ring, twin and cross
shapes and their plates; round is the only map shape. The tool that rendered the
plates (tools/render_loading_shapes.*) was removed with them; `manifest.json`
records the remaining plates' map resource, theme, file name, dimensions and
camera setup so they can be re-rendered through the sandbox shot helper
(tools/sandbox_shot.tscn) if the sky changes significantly.

## Integration

Select by resolved sky theme; `sunset` is the fallback for an unknown theme and
`round` for any unknown map variant. Random or Cycle can use the resolved phase's
closest plate. Size presets share one illustration; these are decorative
backgrounds, not exact previews of player layouts.

Display with a fullscreen `TextureRect`, `EXPAND_IGNORE_SIZE` and
`STRETCH_KEEP_ASPECT_COVERED`, centered cropping, linear filtering and one shared
UI scale. Apply dimming separately.
