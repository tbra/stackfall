# Native island review

Multiview, LOD comparison, camera GIF and haze/palette contact sheet use the
actual exported meshes and cel shader in an isolated Godot stage. All original
frames are in native/. This stage contains simple3D cloud-shaped occluders and
example environment colors, not the queued game sky. Final integration remains
with Claude. Geometry and comparison results are in verification.json.
Logs: TEMP/codex-horizon-islands-native/{native.log,import.log,wrappers.log};
TEMP/codex-horizon-islands-blender-final.log. No full suite was run.
