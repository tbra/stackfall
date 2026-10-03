Standalone SVG review/raster helper (Codex, Bontago-mp0.90).
The main project warns about nested project.godot files, so it is stored as
project.godot.review. To rerun: copy it to project.godot in this folder, then
  godot --headless --path source_art/gift_pictograms_v1 -s rasterize.gd -- <atlas.svg> <out_dir>
