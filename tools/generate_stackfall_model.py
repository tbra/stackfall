"""Build a three-block animated Stackfall gift model and neutral preview."""

from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/stackfall_v1"
SOURCE = ROOT / "source_art/stackfall_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, hex_color):
    values = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1)
    bsdf.inputs["Roughness"].default_value = 0.78
    return mat


blue = material("Stackfall blue", "#488FD9")
amber = material("Stackfall amber", "#E9AD50")
coral = material("Stackfall coral", "#EC6959")
cream = material("Warm top mark", "#F5E4BD")
floor_mat = material("Preview blue floor", "#435765")
model = bpy.data.collections.new("Stackfall gift export")
bpy.context.scene.collection.children.link(model)


def cube(name, location, scale, mat, parent=None, bevel=0.03):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.object
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new("Single bevel edge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.name = name
    obj.data.materials.append(mat)
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    model.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


def pivot(name, location):
    obj = bpy.data.objects.new(name, None)
    model.objects.link(obj)
    obj.location = location
    return obj


lower = pivot("Stackfall / lower block pivot", (-0.18, 0, -0.29))
cube("Stackfall / blue lower block", (0, 0, 0), (0.42, 0.43, 0.30), blue, lower, 0.045)
middle = pivot("Stackfall / middle block pivot", (0.14, 0, -0.02))
cube("Stackfall / amber middle block", (0, 0, 0), (0.45, 0.43, 0.31), amber, middle, 0.045)
upper = pivot("Stackfall / upper block pivot", (-0.07, 0, 0.25))
cube("Stackfall / coral upper block", (0, 0, 0), (0.43, 0.43, 0.31), coral, upper, 0.045)
cube("Stackfall / cream top tile", (0, -0.02, 0.170), (0.19, 0.23, 0.033), cream, upper, 0.008)

# Three staggered pivots create a barely perceptible precarious motion.
for obj, keys in (
    (lower, ((1, 0), (17, 0.025), (33, 0), (49, -0.018), (65, 0))),
    (middle, ((1, 0), (17, -0.050), (33, 0.014), (49, 0.045), (65, 0))),
    (upper, ((1, 0), (17, 0.070), (33, -0.035), (49, -0.065), (65, 0))),
):
    for frame, angle in keys:
        obj.rotation_euler.y = angle
        obj.keyframe_insert(data_path="rotation_euler", frame=frame)
    action = obj.animation_data.action
    track = obj.animation_data.nla_tracks.new()
    track.name = "stack_sway_2_7s"
    track.strips.new("stack_sway_2_7s", 1, action)
    obj.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 65
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.52))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.6, -2.4, 1.4))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, 0)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.60
scene.camera = camera
for name, pos, energy in (("Review / key", (1, -2, 2), 260),
                          ("Review / rim", (-1.3, 1.4, 1.8), 170)):
    lamp = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, lamp)
    scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    lamp.energy = energy
    lamp.shape = "DISK"
    lamp.size = 2.8

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "stackfall_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "stackfall_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = upper
bpy.ops.export_scene.gltf(filepath=str(OUT / "stackfall_v1.glb"), export_format="GLB",
                          use_selection=True, export_cameras=False, export_lights=False,
                          export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'stackfall_v1.glb'} and preview")
