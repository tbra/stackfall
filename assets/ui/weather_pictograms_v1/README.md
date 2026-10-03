# Weather mode pictograms

Seven original vector symbols matching `MatchConfig.WeatherMode`:

| Mode | Shape cue |
| --- | --- |
| OFF | Slashed circle |
| STORM | Cloud and lightning bolt |
| RAIN | Cloud and three droplets |
| SNOW | Cloud and snowflake |
| FOG | Mountain behind horizontal fog bands |
| RANDOM | Five-dot die |
| CHANGING | Sun/cloud inside opposing cycle arrows |

The die denotes the mode that chooses one weather type at match start; the
arrows denote scheduled changing weather. Keep localized mode labels or tooltips
beside these symbols. They are supplemental art, with no live UI wiring.

## Atlas

`atlas.svg` is a transparent 256 x 128 vector image with eight 64 x 64 cells.
Seven cells follow the enum's order; the eighth is empty. `regions.json` records
exact uppercase enum names and `[x,y,width,height]` regions. Use `AtlasTexture`
with the corresponding `Rect2`. Retain default SVG import scale, or scale all
region coordinates equally if changing it. Small HUD usage should disable atlas
mipmaps to avoid blending adjacent cells.

Shapes use the shared ink/paper/coral/teal/brass palette and 4-unit master
outlines (2 pixels when displayed at 32 pixels). `review.png` contains actual
Godot SVG rasters at 24, 32 and 48 pixels on paper and ink, plus a grayscale row.
Ink details blend into the ink panel; paper/accent silhouettes remain visible.
Final visual acceptance and the intended panel background belong to review.

## Reproduce

```powershell
python tools/generate_weather_pictograms.py
$weatherRasterOutput = Join-Path $env:TEMP 'codex_weather_pictogram_rasters'
godot --headless --path source_art/weather_pictograms_v1 --script rasterize.gd -- "$PWD/assets/ui/weather_pictograms_v1/atlas.svg" $weatherRasterOutput
python tools/generate_weather_pictograms.py --review
```

The generator reads the actual weather enum and checks exact coverage. Review
assembly checks native dimensions and alpha bounds: every symbol has a
transparent outer border, and the unused cell is empty at each size. The
isolated raster project is ignored by the game importer. No game window or full
suite is required for this art package.
