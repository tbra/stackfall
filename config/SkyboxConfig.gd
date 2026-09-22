class_name SkyboxConfig
extends Resource
## Tunables for game/Skybox.gd: which placeholder six-face set to use by
## default, the face file names it looks for under a set's folder, and the
## box geometry it draws them on (CLAUDE.md: no magic numbers in code).
##
## The six faces come from the original 2003 Bontago install
## (`Textures/<Set>/{back,bottom,front,left,right,top}.jpg`, see
## tools/install_original_assets.ps1, owned by another package) and are never
## committed to this public repo; game/Skybox.gd falls back to the existing
## ProceduralSkyMaterial when a set or a face is missing.

## Bontago-1en/assets-sky DECISION: "beach" is the calmest, most legible set
## (spec 2.10 presentation) and doubles as MapDef's own default for maps that
## do not specify one and for the two GUT tests below.
@export var default_set: String = "beach"

## File names (without extension) inside a set's folder, matching the original
## install's own naming exactly (Skybox.gd appends ".jpg"). Case-sensitive:
## the install script (owned by another package) already lowercases every
## file it copies, so Skybox.gd does not attempt a case-insensitive lookup
## (see test_skybox.gd's doc comment on this).
@export var face_names: PackedStringArray = PackedStringArray([
	"back", "bottom", "front", "left", "right", "top",
])

## Half the side length of the cube Skybox.gd draws the six faces on, in
## meters. Large enough that no map's field_radius (round_large.tres: 60 m)
## or camera zoom range gets close to it, so the box never visibly clips
## through gameplay geometry or the camera's far plane (Camera3D's default
## far is 4000 m, comfortably beyond 2x this).
@export var box_half_extent: float = 400.0

## Per-face orientation correction, parallel arrays in face_names order
## (back, bottom, front, left, right, top). Found numerically by
## tools/skybox_seam_probe.gd, which loads a real six-face set and picks the
## rotation/flip combination that jointly minimizes the mean colour
## difference across all 12 touching cube edges -- not eyeballed (an earlier
## eyeballed guess left hard seams; see Bontago-1en/assets-sky-seams).
## game/Skybox._apply_face_transform() applies these as: flip_u, then
## flip_v, then rotate by face_rotations[i] quarter turns (matching the
## probe's own search space exactly, so its result is reproducible here).
## Values found on the Beach set and confirmed (tools/skybox_seam_probe.gd
## --verify) to also give a near-zero seam error on Mountain and Lake, which
## share the same exporter/convention (see the package report for the actual
## numbers). Order: back, bottom, front, left, right, top.
@export var face_rotations: PackedInt32Array = PackedInt32Array([0, 3, 0, 0, 0, 1])
@export var face_flip_u: PackedByteArray = PackedByteArray([1, 1, 1, 1, 1, 1])
@export var face_flip_v: PackedByteArray = PackedByteArray([0, 0, 0, 0, 0, 0])

## Set false to always keep the existing ProceduralSkyMaterial (e.g. for a
## screenshot fixture that wants a deterministic sky with no file I/O).
@export var enabled: bool = true
