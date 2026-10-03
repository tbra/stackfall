"""Native vector gift atlas; --review assembles Godot-rasterized size proofs."""
from pathlib import Path
import json
import sys
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/ui/gift_pictograms_v1"
TEMP = Path(tempfile.gettempdir()) / "codex_gift_pictogram_rasters"
INK,PAPER,FIELD = "#26323A","#F5EBD6","#FFFAF0"
CORAL,TEAL,BRASS = "#EB6B5C","#75CBD1","#E8B85D"


def path(d,fill=PAPER,stroke=INK,width=4):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>'


def circle(x,y,r,fill=PAPER,stroke=INK,width=4):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="{width}"/>'


def rect(x,y,w,h,fill=PAPER,r=3):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" stroke="{INK}" stroke-width="4"/>'


ART = {
    "anvil": path("M8 17H54V27H40L37 40H45V50H19V40H26L23 28H18L8 23Z")+path("M20 51H46",CORAL,CORAL,5),
    "black_hole": circle(32,32,16,INK,PAPER,4)+f'<ellipse cx="32" cy="32" rx="26" ry="9" transform="rotate(-25 32 32)" fill="none" stroke="{TEAL}" stroke-width="6"/>'+circle(32,32,10,INK,INK,0),
    "bomb": path("M37 17C37 9 46 8 47 16", "none",INK,4)+circle(30,36,20,CORAL)+path("M22 25Q17 27 16 34","none",FIELD,4)+path("M48 9L49 7M53 13L56 11", "none",BRASS,4),
    "cat": path("M12 14L25 21Q32 17 39 21L52 14L50 43Q48 54 32 54Q16 54 14 43Z")+circle(24,34,2,INK,INK,0)+circle(40,34,2,INK,INK,0)+path("M28 41H36L32 46Z",TEAL,INK,3)+path("M7 39L18 41M46 41L57 39","none",INK,3),
    "earthquake": path("M8 23L30 17L56 25V46L33 53L8 44Z",PAPER)+path("M33 19L25 29L38 34L28 44L33 51","none",CORAL,5)+path("M7 15L11 11M53 15L57 19","none",INK,4),
    "freeze": path("M23 52L20 19L32 6L44 19L41 52Z",TEAL)+path("M20 19L32 26L44 19M32 26V52","none",FIELD,3)+path("M8 51L5 32L14 22L22 52Z",PAPER)+path("M42 52L50 23L59 34L56 51Z",PAPER),
    "glue": rect(19,7,26,10,BRASS)+path("M23 17H41L48 26V52H16V26Z")+path("M32 28C29 32 25 36 25 40A7 7 0 0 0 39 40C39 36 35 32 32 28Z",TEAL,INK,3),
    "jumping_bean": path("M40 9C55 11 53 25 41 33C32 38 43 48 30 52C17 57 8 45 14 33C21 23 21 6 40 9Z",TEAL)+path("M28 14Q37 12 41 17","none",FIELD,4)+path("M8 17L6 12M52 48L58 50","none",INK,4),
    "magnet": path("M10 10H24V33Q24 42 32 42Q40 42 40 33V10H54V34Q54 57 32 57Q10 57 10 34Z",CORAL)+rect(10,8,14,13,FIELD,1)+rect(40,8,14,13,FIELD,1),
    "paintball": path("M14 23L8 13L20 17L27 7L33 18L47 10L45 23L57 28L47 34L54 49L41 45L35 57L27 47L13 52L17 38L6 32Z",CORAL)+circle(32,32,16,TEAL)+path("M24 23Q19 25 19 31","none",FIELD,4),
    "propeller": path("M28 27C15 9 24 4 32 9C40 15 36 22 35 27C57 22 61 32 52 39C45 43 37 36 35 34C29 55 18 58 14 47C12 38 23 31 28 27Z",TEAL)+circle(32,31,7,BRASS)+path("M32 39V56","none",INK,5),
    "rocket": path("M22 39L11 43L10 55L25 49Z",TEAL)+path("M40 22L49 15L55 25L47 36Z",TEAL)+path("M17 45L25 25Q36 12 53 8Q54 25 40 39L23 49Z",PAPER)+path("M40 13Q48 9 53 8Q54 16 50 23Z",CORAL)+circle(34,29,5,TEAL,INK,3)+path("M14 50L6 58M20 54L17 59","none",BRASS,4),
    "stackfall": rect(8,39,21,17,TEAL,2)+rect(31,39,24,17,PAPER,2)+f'<g transform="rotate(16 37 19)">{rect(26,9,22,18,CORAL,2)}</g>'+path("M10 10V23M5 18L10 24L15 18","none",INK,4),
    "volcano": path("M6 55L24 24H40L58 55Z",PAPER)+path("M24 24H40L39 37L34 34L31 43L27 34L21 39Z",CORAL,INK,3)+path("M27 17Q20 12 25 7Q29 3 34 8Q41 5 43 11Q45 17 37 19","none",INK,5),
}


def generate():
    OUT.mkdir(parents=True,exist_ok=True)
    ids = sorted(ART)
    installed = {path.stem for path in (ROOT / "config/specials").glob("*.tres")}
    assert set(ids)==installed, f"Gift coverage differs: {set(ids)^installed}"
    regions = {}
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">',
             '<title>Stackfall compact gift pictograms</title>']
    for index,id in enumerate(ids):
        x,y=index%4*64,index//4*64
        regions[id]=[x,y,64,64]
        parts.append(f'<g id="{id}" transform="translate({x} {y})"><title>{id.replace("_"," ")}</title>{ART[id]}</g>')
    parts.append('</svg>\n')
    svg=''.join(parts)
    ET.fromstring(svg)
    (OUT / "atlas.svg").write_text(svg,encoding="utf-8")
    (OUT / "regions.json").write_text(json.dumps({"atlas":"atlas.svg","atlas_size":[256,256],
        "tile_size":64,"gift_ids":ids,"regions_xywh":regions},indent=2)+"\n")
    print(f"Generated vector atlas with {len(ids)} gifts; registry coverage exact")


def review():
    from PIL import Image,ImageDraw,ImageFont
    metadata=json.loads((OUT / "regions.json").read_text())
    ids=metadata["gift_ids"]
    font=ImageFont.truetype(str(ROOT / "assets/ui/fonts/Manrope-Regular.ttf"),15)
    small=ImageFont.truetype(str(ROOT / "assets/ui/fonts/Manrope-Regular.ttf"),11)
    atlases={size:Image.open(TEMP / f"atlas_{size}.png").convert("RGBA") for size in (24,32,48)}
    assert all(image.size==(size*4,size*4) for size,image in atlases.items())
    for size,atlas in atlases.items():
        for index in range(16):
            tx,ty=index%4*size,index//4*size
            bounds=atlas.crop((tx,ty,tx+size,ty+size)).getchannel("A").getbbox()
            if index>=len(ids):
                assert bounds is None, "Trailing atlas cells must be empty"
            else:
                assert bounds is not None, ids[index]
                assert bounds[0]>0 and bounds[1]>0 and bounds[2]<size and bounds[3]<size, (size,ids[index],bounds)
    print("Native alpha bounds: 14 padded symbols and 2 empty cells at all 3 sizes PASS")
    sheet=Image.new("RGB",(1200,752),INK)
    draw=ImageDraw.Draw(sheet)
    for index,id in enumerate(ids):
        x,y=index%4*300,index//4*188
        draw.rounded_rectangle((x+6,y+6,x+294,y+182),radius=12,fill=FIELD)
        draw.text((x+18,y+14),id.replace("_"," ").capitalize(),font=font,fill=INK)
        for row,color in enumerate((PAPER,INK)):
            draw.rounded_rectangle((x+16,y+43+row*61,x+284,y+101+row*61),radius=8,fill=color)
            for column,size in enumerate((24,32,48)):
                tx,ty=index%4*size,index//4*size
                icon=atlases[size].crop((tx,ty,tx+size,ty+size))
                assert icon.getbbox(),id
                cx=x+58+column*92
                sheet.paste(icon,(cx-size//2,y+72+row*61-size//2),icon)
        for column,size in enumerate((24,32,48)):
            draw.text((x+49+column*92,y+165),str(size)+"px",font=small,fill=INK)
    sheet.save(OUT / "review.png")
    print("Native SVG review assembled at24/32/48px on paper and ink")


if __name__=="__main__":
    review() if "--review" in sys.argv else generate()
