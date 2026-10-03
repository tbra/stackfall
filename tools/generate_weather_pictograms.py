"""Compact weather mode symbols and native Godot raster review."""
from pathlib import Path
import json
import re
import sys
import tempfile
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/ui/weather_pictograms_v1'
TEMP = Path(tempfile.gettempdir()) / 'codex_weather_pictogram_rasters'
INK, PAPER, FIELD = '#26323A', '#F5EBD6', '#FFFAF0'
CORAL, TEAL, BRASS = '#EB6B5C', '#75CBD1', '#E8B85D'

def path(d, fill='none', stroke=INK, width=4):
    return '<path d="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % (d,fill,stroke,width)

def circle(x,y,r,fill=PAPER,stroke=INK,width=4):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s" stroke="%s" stroke-width="%s"/>' % (x,y,r,fill,stroke,width)

def cloud():
    return path('M15 35C7 35 7 22 16 22C19 11 35 10 41 22C52 19 58 25 55 32C53 36 48 37 44 37H15Z',PAPER)

ART = {
    'OFF': circle(32,32,22)+path('M18 46L46 18',stroke=CORAL,width=6),
    'STORM': cloud()+path('M33 30L24 44H33L29 56L45 37H36L40 30Z',BRASS),
    'RAIN': cloud()+''.join(path('M%s 43C%s 48 %s 51 %s 54C%s 56 %s 54 %s 51Z' % (x,x-4,x-5,x,x+5,x+5,x+3),TEAL,width=3) for x in (18,32,46)),
    'SNOW': cloud()+path('M32 40V57M24 44L40 53M24 53L40 44',stroke=TEAL,width=4)+path('M29 42L32 45L35 42M29 55L32 52L35 55',stroke=INK,width=2),
    'FOG': path('M9 28L22 13L33 26L43 17L55 29Z',PAPER)+path('M10 35H54M14 44H50M10 53H54',stroke=TEAL,width=5),
    'RANDOM': '<rect x="11" y="11" width="42" height="42" rx="8" fill="%s" stroke="%s" stroke-width="4"/>' % (PAPER,INK)+''.join(circle(x,y,3,INK,INK,0) for x,y in ((22,22),(42,22),(32,32),(22,42),(42,42))),
    'CHANGING': path('M12 22C19 7 43 7 52 22',stroke=TEAL,width=5)+path('M44 22H53V13',stroke=TEAL,width=5)+path('M52 43C43 58 20 58 12 43',stroke=CORAL,width=5)+path('M12 52V43H21',stroke=CORAL,width=5)+circle(32,28,7,BRASS,width=3)+path('M25 41C20 41 20 33 25 33C27 27 36 28 38 34C45 33 45 41 39 41Z',PAPER,width=3),
}

def generate():
    source = (ROOT/'config/MatchConfig.gd').read_text()
    body = re.search(r'enum WeatherMode\s*\{([^}]+)\}',source).group(1)
    modes = [name.strip() for name in body.split(',')]
    assert set(modes)==set(ART), (modes,list(ART))
    OUT.mkdir(parents=True,exist_ok=True)
    parts=['<svg xmlns="http://www.w3.org/2000/svg" width="256" height="128" viewBox="0 0 256 128"><title>Stackfall weather mode pictograms</title>']
    regions={}
    for index,mode in enumerate(modes):
        x,y=index%4*64,index//4*64
        regions[mode]=[x,y,64,64]
        parts.append('<g id="%s" transform="translate(%s %s)"><title>%s weather mode</title>%s</g>' % (mode.lower(),x,y,mode.capitalize(),ART[mode]))
    parts.append('</svg>\n')
    svg=''.join(parts);ET.fromstring(svg)
    (OUT/'atlas.svg').write_text(svg,encoding='utf-8')
    (OUT/'regions.json').write_text(json.dumps({'atlas':'atlas.svg','atlas_size':[256,128],'tile_size':64,'modes':modes,'regions_xywh':regions},indent=2)+'\n')
    print('Exact MatchConfig.WeatherMode coverage: 7 symbols PASS')

def review():
    from PIL import Image,ImageDraw,ImageFont,ImageOps
    modes=json.loads((OUT/'regions.json').read_text())['modes']
    atlases={size:Image.open(TEMP/('atlas_%s.png'%size)).convert('RGBA') for size in (24,32,48)}
    for size,atlas in atlases.items():
        assert atlas.size==(size*4,size*2)
        for index in range(8):
            x,y=index%4*size,index//4*size
            bounds=atlas.crop((x,y,x+size,y+size)).getchannel('A').getbbox()
            if index==7: assert bounds is None
            else:
                assert bounds is not None
                assert bounds[0]>0 and bounds[1]>0 and bounds[2]<size and bounds[3]<size, (size,modes[index],bounds)
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
    print('Native dimensions/alpha padding/one empty cell at24/32/48px PASS')

if __name__=='__main__':
    review() if '--review' in sys.argv else generate()
