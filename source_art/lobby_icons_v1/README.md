# Native lobby icon review helper

The source project is stored as project.godot.review to avoid a nested project
warning during game imports. Copy it to TEMP as project.godot and copy
rasterize.gd beside it. Arguments: the absolute assets/ui/icons/lobby_v1 folder,
then a TEMP output folder named codex_lobby_icon_rasters. The helper rasterizes
14 SVGs at 16/24/32 px and exits. Run the generator's --review mode afterwards.
