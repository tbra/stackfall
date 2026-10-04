"""Source-vector gamepad direction/click glyphs and default combo specimens."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
ET.register_namespace('', 'http://www.w3.org/2000/svg')
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/ui/input_glyphs'
INK='#26323A';PAPER='#F5EBD6';WHITE='#FFFAF0';ACCENT='#75CBD1'

def wrap(title,body,width=64):
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s 64" role="img"><title>%s</title>%s</svg>\n'%(width,title,body)

def stick(side,direction):
    label='M28 25v15h10' if side=='left' else 'M26 40V25h7q7 0 7 5q0 5-7 5h-7m8 0 7 5'
    base='<circle cx="32" cy="32" r="21" fill="%s" stroke="%s" stroke-width="3"/><circle cx="32" cy="32" r="15" fill="%s" stroke="%s" stroke-width="2"/><circle cx="32" cy="32" r="11" fill="%s"/><path d="%s" fill="none" stroke="%s" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>'%(PAPER,INK,WHITE,INK,ACCENT,label,INK)
    angle={'up':0,'right':90,'down':180,'left':270}[direction]
    halo='<path transform="rotate(%s 32 32)" d="M32 16V7m-5 5 5-5 5 5" fill="none" stroke="%s" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>'%(angle,PAPER)
    arrow='<path transform="rotate(%s 32 32)" d="M32 16V7m-5 5 5-5 5 5" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'%(angle,INK)
    return base+halo+arrow

def click(side):
    label='M22 25v15h9' if side=='left' else 'M20 40V25h6q6 0 6 5q0 4-6 4h-6m8 0 5 6'
    three='M36 25h4q5 0 5 4q0 3-5 3q6 0 6 4q0 4-6 4h-4'
    return '<circle cx="32" cy="32" r="27" fill="%s" stroke="%s" stroke-width="3"/><circle cx="32" cy="32" r="19" fill="%s" stroke="%s" stroke-width="2"/><circle cx="32" cy="32" r="15" fill="%s"/><path d="%s %s" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'%(PAPER,INK,WHITE,INK,ACCENT,label,three,INK)

def existing(name):
    root=ET.fromstring((OUT/name).read_text());root.remove(root.find('{http://www.w3.org/2000/svg}title'))
    return ''.join(ET.tostring(item,encoding='unicode') for item in root)

def combo(first,second):
    return '<g transform="translate(8 0)">'+existing(first)+'</g><path d="M76 32h8m-4-4v8" fill="none" stroke="%s" stroke-width="6" stroke-linecap="round"/><path d="M76 32h8m-4-4v8" fill="none" stroke="%s" stroke-width="3" stroke-linecap="round"/><g transform="translate(88 0)">'%(PAPER,INK)+existing(second)+'</g>'

catalog=[]
for side in ['left','right']:
    for direction in ['up','down','left','right']:
        name='gamepad_stick_%s_%s.svg'%(side,direction)
        title='%s stick %s'%(side.capitalize(),direction)
        (OUT/name).write_text(wrap(title,stick(side,direction)))
        catalog.append({'file':name,'title':title,'viewbox':[64,64],'kind':'stick_direction','side':side,'direction':direction})
    name='gamepad_stick_%s_click.svg'%side
    title='%s stick click (%s3)'%(side.capitalize(),side[0].upper())
    (OUT/name).write_text(wrap(title,click(side)))
    catalog.append({'file':name,'title':title,'viewbox':[64,64],'kind':'stick_click','side':side})
for name,title,first,second in [('gamepad_combo_rt_right_stick.svg','RT plus right stick','gamepad_rt.svg','gamepad_stick_right.svg'),('gamepad_combo_lb_rb.svg','LB plus RB','gamepad_lb.svg','gamepad_rb.svg')]:
    (OUT/name).write_text(wrap(title,combo(first,second),160))
    catalog.append({'file':name,'title':title,'viewbox':[160,64],'kind':'default_combo_specimen','components':[first,second]})
for item in catalog:ET.parse(OUT/item['file'])
(OUT/'gamepad_motion_catalog.json').write_text(json.dumps({'glyphs':catalog,'height':64,'provenance':'Original vector construction; existing project glyphs compose combo specimens'},indent=2)+'\n')
print('12 SVGs:8 stick directions,2 clicks,2 default combo specimens; XML/catalog PASS')


def review():
    import tempfile
    from PIL import Image,ImageDraw,ImageFont,ImageOps
    rasters=Path(tempfile.gettempdir())/'codex_pad_motion_rasters'
    sheet=Image.new('RGB',(1200,990),INK);draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),14)
    small=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),11)
    seen={size:set() for size in [24,32,48]}
    for index,item in enumerate(catalog):
        x=index%4*300;y=index//4*330
        draw.rounded_rectangle((x+6,y+6,x+294,y+324),radius=12,fill=WHITE)
        draw.text((x+18,y+18),item['title'],font=font,fill=INK)
        for row,color in enumerate([PAPER,INK,'#ededed']):
            draw.rounded_rectangle((x+14,y+52+row*76,x+286,y+118+row*76),radius=8,fill=color)
            for col,size in enumerate([24,32,48]):
                icon=Image.open(rasters/(Path(item['file']).stem+'_%s.png'%size)).convert('RGBA')
                expected=(item['viewbox'][0]*size//64,size)
                assert icon.size==expected,(item['file'],size,icon.size,expected)
                alpha=icon.getchannel('A');bounds=alpha.getbbox()
                assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<icon.width and bounds[3]<icon.height,(item['file'],size,bounds)
                if row==0:
                    assert icon.tobytes() not in seen[size],(item['file'],size)
                    seen[size].add(icon.tobytes())
                    if item['kind']=='default_combo_specimen':
                        assert alpha.crop((0,0,size,size)).getbbox()
                        assert alpha.crop((88*size//64,0,icon.width,size)).getbbox()
                if row==2:
                    icon=ImageOps.grayscale(icon).convert('RGBA');icon.putalpha(alpha)
                cx=x+[54,138,224][col];cy=y+85+row*76
                sheet.paste(icon,(cx-icon.width//2,cy-size//2),icon)
        for col,size in enumerate([24,32,48]):
            draw.text((x+[41,125,211][col],y+302),'%spx'%size,font=small,fill=INK)
    out=ROOT/'docs/art_mockups/pad_motion_glyphs_v1';out.mkdir(parents=True,exist_ok=True)
    (out/'.gdignore').write_text('')
    sheet.save(out/'review.png')
    print('36 native rasters:dimensions,alpha padding,distinct silhouettes,combo components PASS')

if __name__=='__main__':
    import sys
    if '--review' in sys.argv:review()
