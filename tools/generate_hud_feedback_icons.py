"""Extend existing32px HUD source art; original SVG and native raster review."""
import argparse,hashlib,json
from pathlib import Path
from PIL import Image,ImageDraw,ImageOps
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/ui/hud/feedback_icons_v1';SRC=ROOT/'source_art/hud_feedback_icons_v1';REVIEW=ROOT/'docs/art_mockups/hud_feedback_icons_v1'
INK='#26323A';TEAL='#75CBD1';CORAL='#EB6B5C';BRASS='#E8B85D';PAPER='#F5EBD6'
def cube(x,y,size=12):
    # Compact cel block, with two planes and an ink silhouette.
    a=size/2;b=size/4
    return f'<path d="M{x} {y+b} l{a} -{b} l{a} {b} v{a} l-{a} {b} l-{a} -{b} Z" fill="{TEAL}" stroke="{INK}" stroke-width="2" stroke-linejoin="round"/><path d="M{x} {y+b} l{a} {b} l{a} -{b} M{x+a} {y+2*b} v{a}" fill="none" stroke="{INK}" stroke-width="1.5" stroke-linejoin="round"/>'

ICONS={
 'held_block_height':('Held block height',cube(5,6,12)+'<path d="M4 26h15 M25 6v20 M22 9l3-3 3 3 M22 23l3 3 3-3" fill="none" stroke="'+INK+'" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>','Current held block height above the surface; separate from the tallest placed tower'),
 'goal_capture':('Goal capture','<circle cx="16" cy="16" r="6" fill="'+BRASS+'" stroke="'+INK+'" stroke-width="2"/><circle cx="16" cy="16" r="2" fill="'+PAPER+'"/><path d="M16 4v4 M13 5l3 3 3-3 M5 25l4-3 M5 21l4 1-1 4 M27 25l-4-3 M27 21l-4 1 1 4" fill="none" stroke="'+INK+'" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>','Supplement the actual goal capture indicator; does not encode a progress fraction'),
 'placement_rejected':('Placement rejected',cube(4,5,14)+'<circle cx="23" cy="23" r="6" fill="'+CORAL+'" stroke="'+INK+'" stroke-width="2"/><path d="M20.5 20.5l5 5 M25.5 20.5l-5 5" stroke="'+PAPER+'" stroke-width="2" stroke-linecap="round"/>','A rejected placement that did not happen; retain the actual reason text'),
 'placement_relocated':('Placement relocated',cube(4,4,11)+'<ellipse cx="23" cy="25" rx="5" ry="3" fill="'+TEAL+'" stroke="'+INK+'" stroke-width="2"/><path d="M18 8 C26 8 28 13 24 20 M21 17l3 3 4-2" fill="none" stroke="'+INK+'" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>','Placement happened at an automatic valid point in own territory; not rejected')
}
def generate():
 for p in (OUT,SRC,REVIEW):p.mkdir(parents=True,exist_ok=True)
 for p in (SRC,REVIEW):(p/'.gdignore').write_text('')
 records=[]
 for name,(title,body,usage) in ICONS.items():
  svg='<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32" role="img" aria-label="%s"><title>%s</title>%s</svg>'%(title,title,body)
  (OUT/(name+'.svg')).write_text(svg,encoding='utf8');records.append({'id':name,'file':name+'.svg','label':title,'intended_usage':usage})
 (OUT/'catalog.json').write_text(json.dumps({'version':1,'nominal_size':[32,32],'palette':{'ink':INK,'teal':TEAL,'coral':CORAL,'brass':BRASS,'paper':PAPER},'icons':records},indent=2)+'\n')
 print('4 original HUD feedback icon SVGs generated')
def review(native):
 hashes=[]
 for name in ICONS:
  for size in (16,24,32,48):
   img=Image.open(native/('%s_%d.png'%(name,size))).convert('RGBA');assert img.size==(size,size)
   alpha=img.getchannel('A');bbox=alpha.getbbox();assert bbox
   for edge in ((0,0,size,1),(0,size-1,size,size),(0,0,1,size),(size-1,0,size,size)):
    assert max(alpha.crop(edge).getdata())==0,(name,size)
   if size==32:hashes.append(hashlib.sha256(alpha.tobytes()).hexdigest())
 assert len(set(hashes))==4
 sheet=Image.new('RGB',(1200,900),(23,29,43));d=ImageDraw.Draw(sheet)
 d.text((24,16),'HUD FEEDBACK ART | existing32px ink/paper/cel family | labels retained',fill='white')
 contexts=[('Paper panel',(245,235,214),False),('Field card on dark HUD',(255,250,240),False),('Grayscale panel',(245,235,214),True)]
 for row,(label,color,gray) in enumerate(contexts):
  y=54+row*265;d.text((24,y),label,fill='white')
  for col,(name,(title,_,usage)) in enumerate(ICONS.items()):
   x=24+col*293
   tile=Image.new('RGB',(272,214),color);td=ImageDraw.Draw(tile)
   td.text((14,14),title,fill=(38,50,58))
   for k,size in enumerate((16,24,32,48)):
    icon=Image.open(native/('%s_%d.png'%(name,size))).convert('RGBA')
    tile.paste(icon,(14+k*60,56+(48-size)//2),icon)
    td.text((14+k*60,113),str(size)+'px',fill=(38,50,58))
   td.line((14,144,258,144),fill=(199,173,133),width=1)
   td.text((14,159),['Block: 2.5 m','Capturing goal','Rejected: outside territory','Moved to own territory'][col],fill=(38,50,58))
   if gray:tile=ImageOps.grayscale(tile).convert('RGB')
   sheet.paste(tile,(x,y+28))
 sheet.save(REVIEW/'review.png')
 report={'checks':'4distinct alpha silhouettes;16native rasters16/24/32/48px;exactdimensions/nonemptyalpha/clearouteredges','silhouette_sha256':hashes}
 (REVIEW/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
 print(report['checks']+' PASS')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--review-native',type=Path);a=p.parse_args();review(a.review_native) if a.review_native else generate()
