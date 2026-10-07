"""White-source lobby icons on a24-unit grid; no fonts or external artwork."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/ui/icons/lobby_v1'
ART={
 'section_game':('Game section','<path d="M7 8h10q3 0 4 10q0 3-3 2l-4-3h-4l-4 3q-3 1-3-2q1-10 4-10Z"/><path d="M7 11v5m-2.5-2.5h5"/><circle cx="16" cy="12" r=".8" fill="#fff" stroke="none"/><circle cx="18" cy="15" r=".8" fill="#fff" stroke="none"/>'),
 'section_round':('Round section','<circle cx="12" cy="12" r="8"/><path d="M12 7v5l4 2M9 3h6"/>'),
 'section_gifts':('Gifts section','<rect x="4" y="10" width="16" height="4" rx="1"/><path d="M5 14v7h14v-7M12 10v11"/><path d="M12 10C3 10 5 2 9 5l3 5c9 0 7-8 3-5Z"/>'),
 'section_experiments':('Experiments section','<path d="M9 3h6m-5 0v7l-6 8q-2 3 2 3h12q4 0 2-3l-6-8V3M7 15h10"/><circle cx="10" cy="18" r=".7" fill="#fff" stroke="none"/><circle cx="14" cy="17" r=".7" fill="#fff" stroke="none"/>'),
 'bot_add':('Add bot','<rect x="3" y="8" width="12" height="11" rx="3"/><path d="M9 5v3M6 16h6M18.5 15v6M15.5 18h6"/><circle cx="6.5" cy="12" r=".8" fill="#fff" stroke="none"/><circle cx="11.5" cy="12" r=".8" fill="#fff" stroke="none"/>'),
 'bot_remove':('Remove bot','<path d="M4 4l16 16M20 4L4 20"/>'),
 'teams':('Teams','<circle cx="8" cy="7" r="3"/><circle cx="17" cy="7" r="3"/><path d="M3 20v-4q0-4 5-4t5 4v4M13 13q2-2 4-1q4 0 4 4v4"/>'),
 'difficulty_easy':('Easy bot difficulty','<rect x="10" y="14" width="4" height="7" rx="1" fill="#fff" stroke="none"/>'),
 'difficulty_normal':('Normal bot difficulty','<rect x="7" y="13" width="4" height="8" rx="1" fill="#fff" stroke="none"/><rect x="13" y="8" width="4" height="13" rx="1" fill="#fff" stroke="none"/>'),
 'difficulty_hard':('Hard bot difficulty','<rect x="4" y="14" width="4" height="7" rx="1" fill="#fff" stroke="none"/><rect x="10" y="9" width="4" height="12" rx="1" fill="#fff" stroke="none"/><rect x="16" y="4" width="4" height="17" rx="1" fill="#fff" stroke="none"/>'),
 'team_random':('Random team','<rect x="3" y="3" width="18" height="18" rx="3"/><circle cx="7" cy="7" r="1.3" fill="#fff" stroke="none"/><circle cx="12" cy="12" r="1.3" fill="#fff" stroke="none"/><circle cx="17" cy="17" r="1.3" fill="#fff" stroke="none"/>'),
 'colour_swap':('Swap colours','<path d="M4 8h15m-4-4 4 4-4 4M20 16H5m4-4-4 4 4 4"/>'),
 'advanced_open':('Advanced section expanded','<path d="M6 9l6 6 6-6"/>'),
 'host_crown':('Host','<path d="M4 18L3 8l5 4 4-7 4 7 5-4-1 10ZM5 21h14"/>'),
 'advanced_closed':('Advanced section collapsed','<path d="M9 6l6 6-6 6"/>'),
}

def build():
 OUT.mkdir(parents=True,exist_ok=True);catalog=[]
 for name,(title,body) in ART.items():
  svg='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" role="img"><title>%s</title><g fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>\n'%(title,body)
  ET.fromstring(svg);(OUT/(name+'.svg')).write_text(svg)
  catalog.append({'id':name,'file':name+'.svg','title':title})
 (OUT/'catalog.json').write_text(json.dumps({'viewbox':[24,24],'source_color':'white','tint':'MenuStyleFactory.apply_ink','icons':catalog},indent=2)+'\n')
 print('15 white-source lobby SVGs:XML/catalog PASS')

if __name__=='__main__':build()


def review():
 import tempfile
 import numpy as np
 from PIL import Image,ImageDraw,ImageFont
 rasters=Path(tempfile.gettempdir())/'codex_lobby_icon_rasters'
 sheet=Image.new('RGB',(1200,1000),'#26323A');draw=ImageDraw.Draw(sheet)
 font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),14)
 small=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),11)
 seen={size:set() for size in [16,24,32]}
 for index,(name,(title,_)) in enumerate(ART.items()):
  x=index%4*300;y=index//4*250
  draw.rounded_rectangle((x+6,y+6,x+294,y+244),radius=10,fill='#FFFAF0')
  draw.text((x+16,y+16),title,font=font,fill='#26323A')
  for row,(background,tint) in enumerate([('#F5EBD6','#26323A'),('#26323A','#F5EBD6'),('#ededed','#303030')]):
   draw.rounded_rectangle((x+14,y+49+row*57,x+286,y+100+row*57),radius=8,fill=background)
   for col,size in enumerate([16,24,32]):
    source=Image.open(rasters/('%s_%s.png'%(name,size))).convert('RGBA')
    assert source.size==(size,size)
    pixels=np.array(source);alpha=source.getchannel('A');bounds=alpha.getbbox()
    assert bounds and bounds[0]>0 and bounds[1]>0 and bounds[2]<size and bounds[3]<size,(name,size,bounds)
    assert np.all(pixels[pixels[:,:,3]>0,:3]==255),(name,size,'non-white source')
    if row==0:
     assert alpha.tobytes() not in seen[size],(name,size,'duplicate shape')
     seen[size].add(alpha.tobytes())
    icon=Image.new('RGBA',source.size,tint);icon.putalpha(alpha)
    cx=x+[57,145,233][col];cy=y+75+row*57
    sheet.paste(icon,(cx-size//2,cy-size//2),icon)
  for col,size in enumerate([16,24,32]):
   draw.text((x+[45,133,221][col],y+225),'%spx'%size,font=small,fill='#26323A')
 out=ROOT/'docs/art_mockups/lobby_icons_v1';out.mkdir(parents=True,exist_ok=True)
 (out/'.gdignore').write_text('');sheet.save(out/'review.png')
 print('42 native rasters:dimensions/alpha padding/unique shapes/white-only RGB PASS')

if __name__=='__main__':
 import sys
 if '--review' in sys.argv:review()
