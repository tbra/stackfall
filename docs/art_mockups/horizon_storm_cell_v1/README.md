# Horizon storm cell silhouette options

Three standalone storm-cell silhouettes for horizon option D, each using the same animated hanging rain curtain, short forked lightning ribbon, and brief cool flash light. The scene has no references to `Skybox`, `CloudSea`, sky theme resources, or the ambient wind-trail presenter; a later sky change can place or discard the scene without changing its source.

Option 1 is the original broad anvil, option 2 has a centered five-tower profile, and option 3 uses two offset main towers with smaller irregular shoulders. Each spans about 56 m. Its 30 m rain curtain starts beneath the cloud base. Rain is a single 160-instance MultiMesh animated in the vertex shader. Flashing uses one small unshadowed OmniLight and an emissive forked ribbon, with a double pulse every 2.5-6 seconds after the first 1.2-second delay.

## Review

Open `vfx/weather/horizon_storm_cell_v1/storm_cell_preview.tscn` for the isolated preview. To capture the three silhouette views and distant lightning view at 1600x900:

```powershell
godot --path . --windowed --resolution 1600x900 --audio-driver Dummy res://vfx/weather/horizon_storm_cell_v1/storm_cell_preview.tscn -- --capture
```

The capture script writes `storm_silhouette_1.png` through `storm_silhouette_3.png` and `storm_cell_lightning.png` here. Run `python tools/compose_horizon_storm_silhouettes.py` to rebuild `silhouette_options.png`. The owner approved all three variants for Claude review; scene integration remains pending. This review scene is a dusk lighting stand-in and does not represent the final sky composition or establish parallax, occlusion, weather scheduling, or in-game performance.
