"""Bontago-59o.20: builds the sky cloud-card atlas.

Run headless (Blender 4.5):
    blender -b --python tools/blender/make_cloud_cards.py -- <outdir> [seed]

Eight cumulus/altocumulus/strata shapes are modelled as clusters of
intersecting spheres (cauliflower look, flattened underside), each viewed
side-on from slightly below with an orthographic camera and rendered with an
emission shader that writes packed shading data instead of colour:
    R = camera-space normal x * 0.5 + 0.5
    G = camera-space normal y * 0.5 + 0.5  (up = toward the zenith)
    B = ambient openness (1 = open, 0 = crevice), from the AO node
    A = coverage
The sky shader (shaders/sunset_clouds.gdshader) rebuilds n.z = sqrt(1 - x^2 - y^2)
and cel-shades with the live sun direction and sky palette. The cards are
packed into a 4x2 atlas (cloud_cards_atlas.png) of CARD_PX tiles, row 0 = top.
"""
import math
import os
import random
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

CARD_PX = 512
ATLAS_COLS = 4
ATLAS_ROWS = 2
ICO_SUBDIV = 4
SATELLITES_PER_SPHERE = 6
FLOOR_SQUASH = 0.10
ORTHO_SCALE = 2.3
CAMERA_PITCH_DEG = 6.0  # looks slightly up: undersides read as down-facing normals
RENDER_SAMPLES = 40
AO_DISTANCE = 0.35
AO_SAMPLES = 24
CAMERA_DIST = 10.0
FRAME_CENTER_Z = 0.5


def spheres_tower(rng):
    out = []
    z = 0.0
    width = 0.75
    while width > 0.22:
        for _ in range(3):
            r = width * rng.uniform(0.35, 0.55)
            out.append((rng.uniform(-width, width) * 0.55, z + r * 0.6, r, 1.0))
        z += width * 0.42
        width *= 0.78
    return out


def spheres_bank(rng):
    out = []
    x = -0.95
    while x < 0.95:
        r = rng.uniform(0.14, 0.27) * (1.0 - 0.35 * abs(x))
        out.append((x, r * 0.7 + 0.08 * math.sin(x * 4.0) + rng.uniform(0.0, 0.12), r, 1.0))
        if rng.random() < 0.6:
            r2 = r * rng.uniform(0.5, 0.8)
            out.append((x + rng.uniform(-0.1, 0.1), r * 1.35 + r2 * 0.3, r2, 1.0))
        x += r * 1.0
    return out


def spheres_puffs(rng):
    out = []
    for cx in (-0.55, 0.05, 0.6):
        for _ in range(4):
            r = rng.uniform(0.12, 0.22)
            out.append((cx + rng.uniform(-0.2, 0.2), r * 0.8 + rng.uniform(0.0, 0.2), r, 1.0))
    return out


def spheres_broad(rng):
    out = []
    for _ in range(34):
        x = rng.uniform(-0.9, 0.9)
        r = rng.uniform(0.09, 0.19)
        out.append((x, r * 0.6 + rng.uniform(0.0, 0.14) * (1.0 - abs(x)), r, 1.0))
    return out


def spheres_alto(rng):
    out = []
    for _ in range(46):
        x = rng.uniform(-0.95, 0.95)
        z = rng.uniform(0.02, 0.45) * (1.0 - 0.6 * abs(x))
        r = rng.uniform(0.04, 0.09)
        out.append((x, z + r * 0.5, r, 1.0))
    return out


def spheres_streak(rng):
    out = []
    x = -0.95
    while x < 0.95:
        r = rng.uniform(0.07, 0.12) * (1.0 - 0.5 * abs(x))
        out.append((x, r * 0.4 + 0.03 * math.sin(x * 3.0), r, 0.45))
        x += r * 1.1
    return out


def spheres_anvil(rng):
    out = spheres_tower(rng)
    top = max(s[1] + s[2] for s in out)
    for i in range(10):
        x = -0.85 + i * 0.19
        r = rng.uniform(0.1, 0.17)
        out.append((x, top - 0.08 + rng.uniform(-0.03, 0.04), r, 0.6))
    return out


def spheres_wisp(rng):
    out = []
    for _ in range(6):
        r = rng.uniform(0.1, 0.2)
        out.append((rng.uniform(-0.3, 0.3), r * 0.7 + rng.uniform(0.0, 0.1), r, 0.9))
    return out


CARD_KINDS = [spheres_tower, spheres_bank, spheres_puffs, spheres_broad,
              spheres_alto, spheres_streak, spheres_anvil, spheres_wisp]


def build_cloud(spheres, rng):
    bm = bmesh.new()
    parts = []
    for cx, cz, r, zs in spheres:
        parts.append((cx, cz, r, zs))
        # Satellite bumps on the upper hemisphere give the cauliflower rim.
        for _ in range(SATELLITES_PER_SPHERE):
            a = rng.uniform(0.0, math.pi)
            b = rng.uniform(-0.3, 1.0)
            parts.append((cx + math.cos(a) * r * 0.85, cz + b * r * 0.85, r * rng.uniform(0.3, 0.45), zs))
    for cx, cz, r, zs in parts:
        mat = Matrix.Translation(Vector((cx, rng.uniform(-0.15, 0.15) * r, cz))) @ Matrix.Diagonal(Vector((r, r * 0.8, r * zs, 1.0)))
        bmesh.ops.create_icosphere(bm, subdivisions=ICO_SUBDIV, radius=1.0, matrix=mat)
    for v in bm.verts:
        if v.co.z < 0.0:
            v.co.z *= FLOOR_SQUASH
    for f in bm.faces:
        f.smooth = True
    mesh = bpy.data.meshes.new("cloud")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("cloud", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def make_material():
    mat = bpy.data.materials.new("pack")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    xf = nt.nodes.new("ShaderNodeVectorTransform")
    xf.vector_type = "NORMAL"
    xf.convert_from = "WORLD"
    xf.convert_to = "CAMERA"
    nt.links.new(geo.outputs["Normal"], xf.inputs["Vector"])
    remap = nt.nodes.new("ShaderNodeVectorMath")
    remap.operation = "MULTIPLY_ADD"
    remap.inputs[1].default_value = (0.5, 0.5, 0.5)
    remap.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(xf.outputs["Vector"], remap.inputs[0])
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(remap.outputs["Vector"], sep.inputs["Vector"])
    ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
    ao.inputs["Distance"].default_value = AO_DISTANCE
    ao.samples = AO_SAMPLES
    comb = nt.nodes.new("ShaderNodeCombineXYZ")
    nt.links.new(sep.outputs["X"], comb.inputs["X"])
    nt.links.new(sep.outputs["Y"], comb.inputs["Y"])
    nt.links.new(ao.outputs["AO"], comb.inputs["Z"])
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(comb.outputs["Vector"], emit.inputs["Color"])
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


def setup_scene():
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = RENDER_SAMPLES
    scn.cycles.use_denoising = False
    scn.cycles.filter_width = 1.5
    scn.render.film_transparent = True
    scn.render.resolution_x = CARD_PX
    scn.render.resolution_y = CARD_PX
    scn.render.resolution_percentage = 100
    scn.view_settings.view_transform = "Raw"
    scn.view_settings.look = "None"
    scn.render.image_settings.file_format = "PNG"
    scn.render.image_settings.color_mode = "RGBA"
    scn.render.image_settings.color_depth = "8"
    scn.render.dither_intensity = 0.0
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ORTHO_SCALE
    cam = bpy.data.objects.new("cam", cam_data)
    scn.collection.objects.link(cam)
    pitch = math.radians(90.0 + CAMERA_PITCH_DEG)
    cam.location = (0.0, -CAMERA_DIST, FRAME_CENTER_Z - CAMERA_DIST * math.tan(math.radians(CAMERA_PITCH_DEG)))
    cam.rotation_euler = (pitch, 0.0, 0.0)
    scn.camera = cam
    return scn


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    outdir = os.path.abspath(argv[0] if argv else "assets/sky/cloud_cards")
    seed = int(argv[1]) if len(argv) > 1 else 59020
    os.makedirs(outdir, exist_ok=True)
    tmpdir = os.path.join(outdir, "_tmp")
    os.makedirs(tmpdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = setup_scene()
    mat = make_material()
    rng = random.Random(seed)
    atlas = np.zeros((CARD_PX * ATLAS_ROWS, CARD_PX * ATLAS_COLS, 4), dtype=np.float32)
    atlas[..., 0] = 0.5
    atlas[..., 1] = 0.5
    atlas[..., 2] = 1.0
    for index, kind in enumerate(CARD_KINDS):
        obj = build_cloud(kind(rng), rng)
        obj.data.materials.append(mat)
        path = os.path.join(tmpdir, "card_%d.png" % index)
        scn.render.filepath = path
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(obj)
        img = bpy.data.images.load(path)
        img.colorspace_settings.name = "Non-Color"
        img.alpha_mode = "CHANNEL_PACKED"
        px = np.array(img.pixels[:], dtype=np.float32).reshape(CARD_PX, CARD_PX, 4)
        bpy.data.images.remove(img)
        clear = px[..., 3] < 0.01
        px[clear, 0] = 0.5
        px[clear, 1] = 0.5
        px[clear, 2] = 1.0
        col = index % ATLAS_COLS
        row_top = index // ATLAS_COLS
        row = ATLAS_ROWS - 1 - row_top  # pixels are stored bottom-up
        atlas[row * CARD_PX:(row + 1) * CARD_PX, col * CARD_PX:(col + 1) * CARD_PX] = px
        os.remove(path)
    os.rmdir(tmpdir)
    out = bpy.data.images.new("atlas", CARD_PX * ATLAS_COLS, CARD_PX * ATLAS_ROWS, alpha=True)
    out.colorspace_settings.name = "Non-Color"
    out.alpha_mode = "CHANNEL_PACKED"
    out.pixels.foreach_set(atlas.ravel())
    out.filepath_raw = os.path.join(outdir, "cloud_cards_atlas.png")
    out.file_format = "PNG"
    out.save()
    print("CLOUD_CARDS_WRITTEN", out.filepath_raw)


main()
