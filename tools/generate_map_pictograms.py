"""Compact arena shape symbols and native Godot raster review."""
from pathlib import Path
import json
import re
import sys
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/ui/map_pictograms_v1'
TEMP = Path(tempfile.gettempdir()) / 'codex_map_pictogram_rasters'
INK, PAPER, FIELD = '#26323A', '#F5EBD6', '#FFFAF0'
CORAL, TEAL, BRASS = '#EB6B5C', '#75CBD1', '#E8B85D'

def path(d, fill='none', stroke=INK, width=4):
    return '<path d="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % (d,fill,stroke,width)

def circle(x,y,r,fill=PAPER,stroke=INK,width=4):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="%s"/>' % (x,y,r,fill,stroke,width)

ART = {
    'ROUND': circle(32,32,22),
    'OVAL': '<ellipse cx="32" cy="32" rx="24" ry="15" fill="%s" stroke="%s" stroke-width="4"/>' % (PAPER,INK),
    'RING': '<path d="M54 32A22 22 0 1 1 10 32A22 22 0 1 1 54 32ZM41 32A9 9 0 1 0 23 32A9 9 0 1 0 41 32Z" fill="%s" fill-rule="evenodd" stroke="%s" stroke-width="4"/>' % (PAPER,INK),
    'TWIN': path('M32 20C21 8 8 17 8 32C8 47 21 56 32 44C43 56 56 47 56 32C56 17 43 8 32 20Z',PAPER),
    'CROSS': path('M25 9H39V25H55V39H39V55H25V39H9V25H25Z',PAPER),
}


def generate():
    source = (ROOT/'config/MatchConfig.gd').read_text()
    body = re.search(r'enum MapVariant\s*\{([^}]+)\}',source).group(1)
    modes = [name.strip() for name in body.split(',')]
    assert set(modes)==set(ART), (modes,list(ART))
    OUT.mkdir(parents=True,exist_ok=True)
    parts=['<svg xmlns="http://www.w3.org/2000/svg" width="256" height="128" viewBox="0 0 256 128"><title>Stackfall arena shape pictograms</title>']
    regions={}
    for index,mode in enumerate(modes):
        x,y=index%4*64,index//4*64
        regions[mode]=[x,y,64,64]
        parts.append('<g id="%s" transform="translate(%s %s)"><title>%s arena shape</title>%s</g>' % (mode.lower(),x,y,mode.capitalize(),ART[mode]))
    parts.append('</svg>\n')
    svg=''.join(parts);ET.fromstring(svg)
    (OUT/'atlas.svg').write_text(svg,encoding='utf-8')
    (OUT/'regions.json').write_text(json.dumps({'atlas':'atlas.svg','atlas_size':[256,128],'tile_size':64,'shapes':modes,'regions_xywh':regions},indent=2)+'\n')
    print('Exact MatchConfig.MapVariant coverage: 5 symbols PASS')

def review():
    from PIL import Image,ImageDraw,ImageFont,ImageOps
    modes=json.loads((OUT/'regions.json').read_text())['shapes']
    atlases={size:Image.open(TEMP/('atlas_%s.png'%size)).convert('RGBA') for size in (24,32,48)}
    for size,atlas in atlases.items():
        assert atlas.size==(size*4,size*2)
        distinct=set()
        for index in range(8):
            x,y=index%4*size,index//4*size
            tile=atlas.crop((x,y,x+size,y+size))
            alpha=tile.getchannel('A')
            bounds=alpha.getbbox()
            if index>=len(modes): assert bounds is None
            else:
                assert bounds is not None
                assert bounds[0]>0 and bounds[1]>0 and bounds[2]<size and bounds[3]<size, (size,modes[index],bounds)
                assert tile.tobytes() not in distinct
                distinct.add(tile.tobytes())
                if modes[index]=='RING': assert alpha.getpixel((size//2,size//2))==0
                else: assert alpha.getpixel((size//2,size//2))>0
    font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),16)
    small=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),11)
    sheet=Image.new('RGB',(1200,600),INK);draw=ImageDraw.Draw(sheet)
    for index,mode in enumerate(modes):
        x,y=index%4*300,index//4*300
        draw.rounded_rectangle((x+6,y+6,x+294,y+294),radius=12,fill=FIELD)
        draw.text((x+18,y+15),mode.capitalize(),font=font,fill=INK)
        for row,color in enumerate((PAPER,INK,'#ededed')):
            draw.rounded_rectangle((x+16,y+48+row*73,x+284,y+112+row*73),radius=8,fill=color)
            for col,size in enumerate((24,32,48)):
                tx,ty=index%4*size,index//4*size
                icon=atlases[size].crop((tx,ty,tx+size,ty+size))
                if row==2:
                    alpha=icon.getchannel('A');icon=ImageOps.grayscale(icon).convert('RGBA');icon.putalpha(alpha)
                sheet.paste(icon,(x+58+col*92-size//2,y+80+row*73-size//2),icon)
        for col,size in enumerate((24,32,48)):
            draw.text((x+49+col*92,y+269),'%spx'%size,font=small,fill=INK)
    draw.text((918,331),'Paper / Ink / Grayscale',font=font,fill=PAPER)
    draw.text((918,361),'Native Godot SVG raster',font=small,fill=PAPER)
    sheet.save(OUT/'review.png')
    print('Native dimensions/alpha padding/three empty cells at24/32/48px PASS')

if __name__=='__main__':
    review() if '--review' in sys.argv else generate()
