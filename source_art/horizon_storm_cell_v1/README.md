# Horizon storm cell isolated review project

This minimal project mirrors only the standalone candidate scene, its rain shader, and the capture script. `tools/sync_horizon_storm_cell_review.py` copies those files from their runtime paths and can verify the copies with `--check`. The renderer excludes the game's autoloads and unrelated missing local assets.

To preview, copy `project.godot.review` to `project.godot` in this folder, then run the `storm_cell_preview.tscn` scene with `-- --capture`. It writes three same-camera silhouette variants and a horizon-distance lightning view. Run `python tools/compose_horizon_storm_silhouettes.py` to create the labeled comparison sheet. The regular `project.godot` is a temporary local file and is not part of the deliverable.
