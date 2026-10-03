"""Generate a compact fractured-earth earthquake gift and review render."""

from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/earthquake_v1"
SOURCE = ROOT / "source_art/earthquake_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color):
    values = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in values]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    node = mat.node_tree.nodes.get("Principled BSDF")
    node.inputs["Base Color"].default_value = (*rgb, 1)
    node.inputs["Roughness"].default_value = 0.8
    return mat


slate = material("Charcoal slate", "#2F3944")
edge = material("Broken slate edge", "#18242D")
gold = material("Weathered brass surface", "#C89448")
coral = material("Hot coral fault", "#F35D4C")
floor_mat = material("Preview blue floor", "#435765")
model = bpy.data.collections.new("Earthquake gift export")
bpy.context.scene.collection.children.link(model)


def prism(name, points, bottom, top, top_mat, side_mat):
    n = len(points)
    verts = [(x, y, bottom) for x, y in points] + [(x, y, top) for x, y in points]
    faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(top_mat)
    mesh.materials.append(side_mat)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    model.objects.link(obj)
    for poly in mesh.polygons:
        poly.material_index = 0 if poly.index == 1 else 1
    return obj


rim = [(-0.44, -0.34), (0.38, -0.34), (0.45, -0.22), (0.43, 0.30),
       (0.28, 0.36), (-0.37, 0.32), (-0.46, 0.19)]
prism("Earthquake / underlying slab", rim, -0.28, -0.15, slate, edge)

# Complementary sawtooth edges leave a wide readable fault through the tablet.
left = [(-0.43, -0.31), (-0.14, -0.31), (-0.10, -0.22), (-0.16, -0.12),
        (-0.06, -0.01), (-0.14, 0.09), (-0.05, 0.20), (-0.10, 0.31),
        (-0.36, 0.31), (-0.44, 0.18)]
right = [(0.00, -0.31), (0.38, -0.31), (0.43, -0.22), (0.42, 0.28),
         (0.28, 0.35), (0.04, 0.30), (0.09, 0.20), (0.01, 0.09),
         (0.11, -0.02), (0.01, -0.13), (0.06, -0.22)]
left_plate = prism("Earthquake / lifted left plate", left, -0.135, 0.015, gold, slate)
right_plate = prism("Earthquake / right plate", right, -0.145, -0.005, gold, slate)

fault = [(-0.14, -0.31), (-0.10, -0.22), (-0.16, -0.12), (-0.06, -0.01),
         (-0.14, 0.09), (-0.05, 0.20), (-0.10, 0.31), (0.04, 0.30),
         (0.09, 0.20), (0.01, 0.09), (0.11, -0.02), (0.01, -0.13),
         (0.06, -0.22), (0.00, -0.31)]
prism("Earthquake / glowing zigzag fault", fault, -0.145, -0.126, coral, coral)

# Small offshoots make the fissure visible from oblique views without making it a spike.
prism("Earthquake / left branch", [(-0.13, 0.07), (-0.28, 0.17), (-0.25, 0.18), (-0.09, 0.10)],
      0.016, 0.022, coral, coral)
prism("Earthquake / right branch", [(0.05, -0.12), (0.26, -0.22), (0.29, -0.20), (0.08, -0.08)],
      -0.004, 0.002, coral, coral)

# A short, gentle quake loop moves the fault plates, leaving the slab fixed.
for obj, xs, zs in ((left_plate, (0, -0.018, 0.012, 0), (0, 0.013, -0.006, 0)),
                    (right_plate, (0, 0.015, -0.010, 0), (0, -0.006, 0.008, 0))):
    for frame, x, z in zip((1, 9, 18, 25), xs, zs):
        obj.location.x = x
        obj.location.z = z
        obj.keyframe_insert(data_path="location", frame=frame)
    action = obj.animation_data.action
    track = obj.animation_data.nla_tracks.new()
    track.name = "quake_pulse_1s"
    track.strips.new("quake_pulse_1s", 1, action)
    obj.animation_data.action = None

scene = bpy.context.scene
scene.render.fps = 24
scene.frame_start = 1
scene.frame_end = 25
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.40))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.5, -2.3, 1.7))
camera = bpy.context.object
camera.rotation_euler = (Vector((0, 0, -0.08)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.55
scene.camera = camera
for name, pos, energy in (("Review / key", (1, -2, 2), 260), ("Review / rim", (-1.3, 1.4, 1.8), 170)):
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
scene.render.filepath = str(OUT / "earthquake_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "earthquake_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = left_plate
bpy.ops.export_scene.gltf(filepath=str(OUT / "earthquake_v1.glb"), export_format="GLB",
                          use_selection=True, export_cameras=False, export_lights=False,
                          export_animations=True, export_animation_mode="NLA_TRACKS")
scene.frame_set(1)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'earthquake_v1.glb'} and preview")
