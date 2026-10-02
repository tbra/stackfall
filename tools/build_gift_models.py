"""Author the thirteen small, fixed-palette gift scenes from primitive parts.

Run with ``python tools/build_gift_models.py`` when changing their silhouettes.
Coordinates are in one cube cell; the camera sees the positive Z face.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "assets/gifts/held"
INK = "0.055, 0.065, 0.095"
CREAM = "0.96, 0.88, 0.69"
STEEL = "0.31, 0.43, 0.53"
LIGHT = "0.71, 0.82, 0.86"
CORAL = "0.95, 0.29, 0.24"
GOLD = "1.0, 0.68, 0.21"
MINT = "0.27, 0.78, 0.64"
BLUE = "0.27, 0.56, 0.91"
PURPLE = "0.62, 0.43, 0.85"


def part(name, kind, color, pos=(0, 0, 0), size=(1, 1, 1), rotation=0):
    return name, kind, color, pos, size, rotation


B = lambda n, c, p, s: part(n, "BoxMesh", c, p, s)
S = lambda n, c, p, s: part(n, "SphereMesh", c, p, s)
C = lambda n, c, p, s: part(n, "CylinderMesh", c, p, s)
K = lambda n, c, p, s: part(n, "CapsuleMesh", c, p, s)
P = lambda n, c, p, s: part(n, "PrismMesh", c, p, s)

MODELS = {
    "anvil": [B("Foot", INK, (0,-.38,0),(.64,.13,.42)), B("Waist", STEEL,(0,-.18,0),(.3,.31,.3)), B("Face", STEEL,(-.09,.07,0),(.57,.23,.4)), C("Horn",STEEL,(.28,.06,0),(.32,.28,.28)), B("FaceHighlight",LIGHT,(-.12,.2,0),(.52,.035,.35))],
    "bomb": [S("Shell",INK,(0,-.09,0),(.7,.7,.7)), C("FuseSocket",STEEL,(0,.25,0),(.22,.14,.22)), C("Fuse",CREAM,(.04,.4,0),(.055,.18,.055)), S("Spark",GOLD,(.07,.49,0),(.14,.14,.14)), S("Glint",LIGHT,(-.19,.07,.27),(.11,.09,.035))],
    "cat": [K("SittingBody",PURPLE,(0,-.2,0),(.47,.53,.43)), S("Head",PURPLE,(0,.15,.04),(.51,.43,.43)), P("LeftEar",PURPLE,(-.18,.38,.04),(.16,.21,.18)), P("RightEar",PURPLE,(.18,.38,.04),(.16,.21,.18)), S("LeftEye",GOLD,(-.1,.18,.245),(.07,.08,.035)), S("RightEye",GOLD,(.1,.18,.245),(.07,.08,.035)), S("Nose",CORAL,(0,.065,.27),(.07,.05,.03)), K("Tail",PURPLE,(.25,-.26,-.1),(.12,.46,.12))],
    "earthquake": [B("Ground",INK,(0,-.27,0),(.78,.13,.65)), B("LeftPlate",GOLD,(-.23,-.15,0),(.31,.12,.54)), B("RightPlate",GOLD,(.23,-.15,0),(.31,.12,.54)), P("Rift",CORAL,(0,.01,.05),(.17,.61,.15))],
    "freeze": [B("IceCore",BLUE,(0,0,0),(.59,.59,.59)), P("Crown",LIGHT,(0,.37,0),(.35,.23,.35)), P("LeftCrystal",LIGHT,(-.33,.05,0),(.23,.5,.23)), P("RightCrystal",LIGHT,(.33,.05,0),(.23,.5,.23)), B("FrostMark",CREAM,(0,0,.305),(.09,.42,.025)), B("CrossMark",CREAM,(0,0,.32),(.37,.08,.025))],
    "glue": [C("Jar",MINT,(0,-.12,0),(.53,.6,.53)), C("Lid",INK,(0,.22,0),(.61,.13,.61)), B("Label",CREAM,(0,-.1,.28),(.34,.3,.025)), S("Drop",MINT,(0,-.1,.31),(.17,.23,.04)), S("OozeLeft",MINT,(-.22,-.39,.04),(.19,.14,.18)), S("OozeRight",MINT,(.22,-.39,-.05),(.19,.14,.18))],
    "jumping_bean": [S("BeanLower",MINT,(-.08,-.2,0),(.5,.5,.45)), S("BeanUpper",MINT,(.1,.12,0),(.51,.52,.45)), S("EyeLeft",INK,(-.05,.17,.235),(.055,.075,.035)), S("EyeRight",INK,(.17,.17,.235),(.055,.075,.035)), S("Cheek",CORAL,(-.22,-.02,.2),(.08,.045,.025)), S("Smile",INK,(.07,.01,.24),(.12,.035,.026)), K("Spring",GOLD,(0,-.43,0),(.13,.13,.13))],
    "magnet": [B("LeftArm",CORAL,(-.29,-.02,0),(.23,.66,.24)), B("RightArm",CORAL,(.29,-.02,0),(.23,.66,.24)), C("Crown",CORAL,(0,.31,0),(.75,.2,.25)), B("LeftPole",LIGHT,(-.29,-.39,0),(.25,.14,.26)), B("RightPole",LIGHT,(.29,-.39,0),(.25,.14,.26))],
    "paintball": [S("PaintSphere",BLUE,(0,-.05,0),(.61,.61,.61)), S("SplashTop",CORAL,(-.18,.32,0),(.22,.22,.22)), S("SplashRight",GOLD,(.36,.04,0),(.17,.17,.17)), S("SplashLeft",MINT,(-.38,-.11,0),(.15,.15,.15)), S("PaintSpot",CORAL,(0,.02,.31),(.3,.23,.04)), S("PaintSpotSmall",GOLD,(.17,-.16,.29),(.11,.1,.04))],
    "propeller": [C("Hub",STEEL,(0,0,0),(.24,.65,.24)), B("BladeLeft",CREAM,(-.26,.32,0),(.48,.08,.15)), B("BladeRight",CREAM,(.26,.32,0),(.48,.08,.15)), C("Cap",GOLD,(0,.39,0),(.22,.12,.22)), C("Base",INK,(0,-.36,0),(.39,.11,.39))],
    "rocket": [C("Fuselage",CREAM,(0,-.06,0),(.39,.6,.39)), C("Nose",CORAL,(0,.34,0),(.39,.23,.39)), B("FinLeft",CORAL,(-.25,-.33,0),(.23,.29,.12)), B("FinRight",CORAL,(.25,-.33,0),(.23,.29,.12)), B("FinBack",CORAL,(0,-.33,-.25),(.12,.29,.23)), C("Nozzle",INK,(0,-.42,0),(.22,.13,.22)), S("Window",BLUE,(0,.07,.21),(.16,.16,.04))],
    "stackfall": [B("Lower",BLUE,(-.19,-.29,0),(.38,.31,.43)), B("Middle",GOLD,(.14,-.04,0),(.43,.31,.43)), B("Upper",CORAL,(-.07,.24,0),(.4,.31,.43)), B("TopMark",CREAM,(-.07,.405,.03),(.16,.035,.22))],
    "volcano": [C("Cone",STEEL,(0,-.13,0),(.77,.58,.77)), C("Crater",INK,(0,.19,0),(.37,.13,.37)), S("Lava",CORAL,(0,.25,0),(.3,.07,.3)), S("Eruption",GOLD,(0,.4,0),(.22,.23,.22)), S("DropletLeft",CORAL,(-.16,.31,0),(.12,.12,.12)), S("DropletRight",CORAL,(.16,.31,0),(.11,.11,.11))],
}


def fmt(v):
    return ", ".join(f"{x:g}" for x in v)


for gift, parts in MODELS.items():
    colors = list(dict.fromkeys(p[2] for p in parts))
    # Each palette colour is one scene subresource, reused by all its parts.
    lines = [f'[gd_scene load_steps={len(parts)+len(colors)+2} format=3]', '',
             '[ext_resource type="Material" path="res://assets/gifts/gift_outline.tres" id="outline"]', '']
    for i, color in enumerate(colors):
        lines += [f'[sub_resource type="StandardMaterial3D" id="c{i}"]',
                  'diffuse_mode = 2', 'specular_mode = 2',
                  f'albedo_color = Color({color}, 1)', 'roughness = 0.78',
                  'next_pass = ExtResource("outline")', '']
    for i, (_, kind, _, _, size, _) in enumerate(parts):
        lines.append(f'[sub_resource type="{kind}" id="mesh_{i}"]')
        if kind in ("BoxMesh", "PrismMesh"):
            lines.append(f'size = Vector3({fmt(size)})')
        elif kind == "CylinderMesh":
            lines += [f'top_radius = {size[0]/2:g}', f'bottom_radius = {size[0]/2:g}',
                      f'height = {size[1]:g}', 'radial_segments = 10', 'rings = 1']
        elif kind == "SphereMesh":
            lines += [f'radius = {size[0]/2:g}', f'height = {size[1]:g}',
                      'radial_segments = 12', 'rings = 6']
        else:
            lines += [f'radius = {size[0]/2:g}', f'height = {size[1]:g}',
                      'radial_segments = 10', 'rings = 3']
        lines.append('')
    lines += [f'[node name="{gift.title().replace("_", "")}" type="Node3D"]',
              '']
    for i, (name, _, color, pos, size, _) in enumerate(parts):
        # Mesh scale handles nonuniform silhouettes while the mesh resource stays simple.
        sx = 1 if parts[i][1] in ("BoxMesh", "PrismMesh") else size[0]/max(size[0], .0001)
        sz = 1 if parts[i][1] in ("BoxMesh", "PrismMesh") else size[2]/max(size[0], .0001)
        lines += [f'[node name="{name}" type="MeshInstance3D" parent="."]',
                  f'transform = Transform3D({sx:g}, 0, 0, 0, 1, 0, 0, 0, {sz:g}, {fmt(pos)})',
                  f'mesh = SubResource("mesh_{i}")',
                  f'surface_material_override/0 = SubResource("c{colors.index(color)}")',
                  'cast_shadow = 0', '']
    (ROOT / f'{gift}.tscn').write_text("\n".join(lines), encoding="utf-8")
