"""Build a low-poly bomb gift model and neutral preview in Blender 4.5."""

from math import cos, pi, sin
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/bomb_v1"
SOURCE = ROOT / "source_art/bomb_v1"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE.mkdir(parents=True, exist_ok=True)
(SOURCE / ".gdignore").touch()
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, value):
    color = [int(value[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    color = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in color]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = 0.76
    return mat


shell = material("Charcoal shell", "#253440")
socket = material("Blue gray fuse socket", "#647D8D")
paper = material("Warm fuse cord", "#F2D8A6")
ember = material("Coral ember", "#F46B50")
spark = material("Golden spark", "#FFD06B")
floor_mat = material("Preview blue floor", "#435765")
model = bpy.data.collections.new("Bomb gift export")
bpy.context.scene.collection.children.link(model)


def add(obj, name, mat):
    obj.name = name
    obj.data.materials.append(mat)
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    model.objects.link(obj)
    return obj


def cylinder(name, center, r1, r2, depth, mat, vertices=10):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=r1, radius2=r2,
                                    depth=depth, location=center)
    return add(bpy.context.object, name, mat)


bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.35, location=(0, 0, -0.10))
body = add(bpy.context.object, "Bomb / faceted dark shell", shell)
body.scale = (1, 1, 0.95)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

cylinder("Bomb / socket collar", (0, 0, 0.245), 0.132, 0.114, 0.095, socket, 12)
cylinder("Bomb / socket cap", (0, 0, 0.304), 0.087, 0.087, 0.028, shell, 12)

# A thick, curved fuse remains visible from a rotating held-gift camera.
curve_data = bpy.data.curves.new("Curved fuse", "CURVE")
curve_data.dimensions = "3D"
curve_data.resolution_u = 1
curve_data.bevel_depth = 0.026
curve_data.bevel_resolution = 1
spline = curve_data.splines.new("POLY")
points = [(0, 0, 0.31), (0.012, -0.006, 0.39), (0.050, -0.004, 0.455),
          (0.105, 0.002, 0.492)]
spline.points.add(len(points) - 1)
for point, pos in zip(spline.points, points):
    point.co = (*pos, 1)
fuse = bpy.data.objects.new("Bomb / bent warm fuse", curve_data)
model.objects.link(fuse)
fuse.data.materials.append(paper)
bpy.context.view_layer.objects.active = fuse
fuse.select_set(True)
bpy.ops.object.convert(target="MESH")
fuse.select_set(False)

bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.060,
                                      location=(0.105, 0.002, 0.505))
add(bpy.context.object, "Bomb / coral ember core", ember)

# Four diamond rays make the ignition unmistakable even at icon scale.
for index, direction in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
    dx, dz = direction
    center = (0.105 + dx * 0.085, -0.002, 0.505 + dz * 0.085)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1, location=center)
    ray = add(bpy.context.object, f"Bomb / spark ray {index}", spark)
    ray.scale = (0.047 if dx else 0.022, 0.018, 0.047 if dz else 0.022)

scene = bpy.context.scene
scene.render.fps = 24
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, -0.49))
floor = bpy.context.object
floor.name = "Review / floor"
floor.dimensions = (200, 200, 0.08)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
floor.data.materials.append(floor_mat)
bpy.ops.object.camera_add(location=(1.7, -2.5, 1.55))
camera = bpy.context.object
camera.rotation_euler = (Vector((0.02, 0, 0.02)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.55
scene.camera = camera
for name, pos, power in (("Review / key", (1, -2, 2), 250),
                         ("Review / rim", (-1.3, 1.4, 1.8), 180)):
    lamp = bpy.data.lights.new(name, "AREA")
    obj = bpy.data.objects.new(name, lamp)
    scene.collection.objects.link(obj)
    obj.location = pos
    obj.rotation_euler = (Vector((0, 0, 0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    lamp.energy = power
    lamp.shape = "DISK"
    lamp.size = 2.8

scene.render.engine = "BLENDER_EEVEE_NEXT"
scene.render.resolution_x = 960
scene.render.resolution_y = 720
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT / "bomb_v1_preview.png")
scene.view_settings.view_transform = "Standard"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / "bomb_v1.blend"))
bpy.ops.object.select_all(action="DESELECT")
for obj in model.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.export_scene.gltf(filepath=str(OUT / "bomb_v1.glb"), export_format="GLB",
                          use_selection=True, export_cameras=False, export_lights=False)
bpy.ops.render.render(write_still=True)
print(f"Built {OUT / 'bomb_v1.glb'} and preview")
