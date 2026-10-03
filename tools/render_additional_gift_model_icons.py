"""Blender: render GLB icon candidates. Python --sheet: build review sheet."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/gift_model_previews/additional_v1"
GIFTS = ("black_hole", "cat", "freeze", "glue", "magnet", "paintball", "stackfall")


def sheet():
    from PIL import Image, ImageDraw
    canvas = Image.new("RGB", (1024, 592), "#263742")
    draw = ImageDraw.Draw(canvas)
    for index, name in enumerate(GIFTS):
        x, y = (index % 4) * 256, (index // 4) * 296
        icon = Image.open(OUT / f"{name}.png").convert("RGBA")
        icon.thumbnail((232, 232), Image.Resampling.LANCZOS)
        canvas.paste(icon, (x + 12, y + 12), icon)
        # A light-background inset makes alpha fringe problems visible.
        mini = icon.copy()
        mini.thumbnail((54, 54), Image.Resampling.LANCZOS)
        draw.rectangle((x + 192, y + 236, x + 247, y + 291), fill="#ECE6D8")
        canvas.paste(mini, (x + 193, y + 237), mini)
        draw.text((x + 12, y + 264), name.replace("_", " "), fill="#ECE6D8")
    canvas.save(OUT / "additional_gifts_contact_sheet.png")


def render():
    import bpy
    from mathutils import Vector
    OUT.mkdir(parents=True, exist_ok=True)
    for name in GIFTS:
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/models/{name}_v1/{name}_v1.glb"))
        scene = bpy.context.scene
        scene.frame_set(1)
        points = [obj.matrix_world @ Vector(corner) for obj in scene.objects
                  if obj.type == "MESH" for corner in obj.bound_box]
        assert points, f"No geometry for {name}"
        low = Vector([min(p[i] for p in points) for i in range(3)])
        high = Vector([max(p[i] for p in points) for i in range(3)])
        center = (low + high) * .5
        bpy.ops.object.camera_add(location=center + Vector((8, -8, 6)))
        camera = bpy.context.object
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.type = "ORTHO"
        matrix = camera.rotation_euler.to_matrix()
        right, up = matrix @ Vector((1, 0, 0)), matrix @ Vector((0, 1, 0))
        xs, ys = [p.dot(right) for p in points], [p.dot(up) for p in points]
        camera.location += right * ((min(xs)+max(xs))*.5-center.dot(right))
        camera.location += up * ((min(ys)+max(ys))*.5-center.dot(up))
        camera.data.ortho_scale = max(max(xs)-min(xs), max(ys)-min(ys)) / .80
        scene.camera = camera
        radius = max(high-low)
        for position, energy in (((1, -2, 3), 220), ((-2, 1, 2), 130)):
            bpy.ops.object.light_add(type="AREA", location=center+Vector(position)*radius)
            lamp = bpy.context.object
            lamp.data.energy = energy * radius**2
            lamp.data.size = 2.5 * radius
            lamp.rotation_euler = (center-lamp.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.engine = "BLENDER_EEVEE_NEXT"
        scene.render.resolution_x = 384
        scene.render.resolution_y = 384
        scene.render.resolution_percentage = 100
        scene.render.film_transparent = True
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA"
        scene.view_settings.view_transform = "Standard"
        scene.render.filepath = str(OUT / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"ICON_RENDERED {name}", flush=True)


if __name__ == "__main__":
    if "--sheet" in sys.argv:
        sheet()
    else:
        render()
