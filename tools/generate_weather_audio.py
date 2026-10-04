"""Original periodic weather beds and finite gust Foley; no sampled audio."""
from pathlib import Path
import hashlib,json,wave
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/effects/weather_ambience_v1'
REVIEW=ROOT/'docs/art_mockups/weather_ambience_v1'
RATE=44100
LOOP_SECONDS=32


def band_noise(rng,n,low,high):
    f=np.fft.rfftfreq(n,1/RATE)
    response=(1-np.exp(-(f/low)**4))*np.exp(-(f/high)**4)
    response[0]=0
    x=np.fft.irfft(np.fft.rfft(rng.standard_normal(n))*response,n)
    return x/max(np.std(x),1e-10)


def stereo(rng,n,low,high):
    shared=band_noise(rng,n,low,high)
    return np.column_stack([.8*shared+.6*band_noise(rng,n,low,high) for _ in range(2)])


def encode(x,target_rms):
    x*=10**(target_rms/20)/np.sqrt(np.mean(x*x))
    cap=10**(-12/20)
    if abs(x).max()>cap:x*=cap/abs(x).max()
    return np.rint(x*32767).astype('<i2')


def loop(kind):
    seed={'rain':3101,'snow':3102,'storm':3103}[kind]
    rng=np.random.default_rng(seed);n=LOOP_SECONDS*RATE;phase=np.arange(n)/n
    low,high,target={'rain':(180,6500,-28),'snow':(550,3300,-37),'storm':(45,1300,-29)}[kind]
    x=stereo(rng,n,low,high)
    envelope=1+.14*np.sin(2*np.pi*phase+.4)+.08*np.cos(6*np.pi*phase+1.2)
    x*=envelope[:,None]
    if kind=='rain':
        # Circular placement keeps droplets crossing the buffer boundary intact.
        count=LOOP_SECONDS*18;length=round(.011*RATE);t=np.arange(length)/RATE
        taper=np.sin(np.minimum(1,t/.0004)*np.pi/2)**2*np.minimum(1,(t[-1]-t)/.002)**2
        for _ in range(count):
            start=int(rng.integers(n));frequency=rng.uniform(1500,3700)
            drop=np.sin(2*np.pi*frequency*t)*np.exp(-t/.0016)*taper
            pan=rng.uniform(.2,.8);level=rng.uniform(.7,1.3)
            ix=(start+np.arange(length))%n
            x[ix,0]+=drop*level*pan;x[ix,1]+=drop*level*(1-pan)
    if kind=='storm':
        x+=stereo(rng,n,240,2100)*(.18+.12*np.cos(4*np.pi*phase+.8))[:,None]
    x-=x.mean(axis=0)
    pcm=encode(x,target)
    # Rotate the periodic signal to a quiet sample/derivative crossing.
    delta=pcm.astype(float)-np.roll(pcm.astype(float),1,axis=0)
    score=np.max(abs(delta),axis=1)+.5*np.max(abs(delta-np.roll(delta,1,axis=0)),axis=1)+.5*np.max(abs(np.roll(delta,-1,axis=0)-delta),axis=1)
    rotation=int(np.argmin(score));pcm=np.roll(pcm,-rotation,axis=0)
    return pcm,seed,rotation,target


def gust(variant):
    seed=3190+variant;rng=np.random.default_rng(seed)
    seconds=[.85,1.25,1.65][variant-1];n=round(seconds*RATE)
    u=np.linspace(0,1,n);env=np.sin(np.pi*u)**1.7
    low=stereo(rng,n,90,1100);high=stereo(rng,n,500,4200)
    sweep=(.25+.5*u)[:,None]
    x=(low*(1-sweep)+high*sweep)*env[:,None]
    x-=x.sum(axis=0)/env.sum()*env[:,None]
    pcm=encode(x,-25);pcm[0]=0;pcm[-1]=0
    return pcm,seed


def write(path,pcm):
    with wave.open(str(path),'wb') as w:
        w.setnchannels(2);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())


def metrics(pcm,is_loop):
    x=pcm.astype(float)/32768;result={
      'duration_s':len(x)/RATE,'peak_dbfs':round(20*np.log10(abs(x).max()),3),
      'rms_dbfs':round(20*np.log10(np.sqrt(np.mean(x*x))),3),
      'max_dc_offset':float(abs(x.mean(axis=0)).max()),
      'stereo_correlation':round(float(np.corrcoef(x.T)[0,1]),5),
      'mono_loss_db':round(20*np.log10(np.sqrt(np.mean(x.mean(axis=1)**2))/np.sqrt(np.mean(x*x))),3)}
    assert result['peak_dbfs']<=-11.99
    assert result['max_dc_offset']<1e-5
    assert .25<result['stereo_correlation']<.95
    assert result['mono_loss_db']>-3
    if is_loop:
        first=np.diff(x,axis=0);second=np.diff(x,n=2,axis=0)
        jump=abs(x[0]-x[-1]);p99=np.percentile(abs(first),99,axis=0)
        curvature=np.maximum(abs(x[1]-2*x[0]+x[-1]),abs(x[0]-2*x[-1]+x[-2]))
        p99curv=np.percentile(abs(second),99,axis=0)
        assert np.all(jump<=p99) and np.all(curvature<=p99curv)
        rms_start=np.sqrt(np.mean(x[:RATE]**2));rms_end=np.sqrt(np.mean(x[-RATE:]**2))
        difference=20*np.log10(rms_start/rms_end);assert abs(difference)<3
        result.update(loop_begin_frame=0,loop_end_frame_exclusive=len(x),
            seam_jump=[float(v) for v in jump],internal_difference_p99=[float(v) for v in p99],
            seam_curvature=[float(v) for v in curvature],internal_curvature_p99=[float(v) for v in p99curv],
            seam_level_difference_db=round(float(difference),4))
    else:
        assert np.all(pcm[0]==0) and np.all(pcm[-1]==0)
        tail=np.sqrt(np.mean(x[-882:]**2));result['tail_20ms_rms_dbfs']=round(20*np.log10(max(tail,1e-12)),3)
        assert result['tail_20ms_rms_dbfs']<-48
    return result


def build():
    OUT.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    (REVIEW/'.gdignore').write_text('')
    entries=[];signals=[]
    for kind in ['rain','snow','storm']:
        pcm,seed,rotation,target=loop(kind);name=kind+'_loop.wav'
        entries.append(dict(file=name,kind='loop',weather=kind,seed=seed,
            circular_rotation_frames=rotation,target_rms_dbfs=target,**metrics(pcm,True)));signals.append(pcm)
    for variant in [1,2,3]:
        pcm,seed=gust(variant);name='gust_%02d.wav'%variant
        entries.append(dict(file=name,kind='one_shot',variant=variant,seed=seed,**metrics(pcm,False)));signals.append(pcm)
    for item,pcm in zip(entries,signals):
        write(OUT/item['file'],pcm)
        with wave.open(str(OUT/item['file']),'rb') as w:
            assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(2,2,RATE)
            assert w.readframes(w.getnframes())==pcm.tobytes()
        item['sha256']=hashlib.sha256((OUT/item['file']).read_bytes()).hexdigest()
    assert len({item['sha256'] for item in entries})==6
    (OUT/'manifest.json').write_text(json.dumps({'sample_rate':RATE,'channels':2,'pcm_bits':16,
       'generator':'tools/generate_weather_audio.py','provenance':'Original periodic Fourier noise, circular droplets and finite noise sweeps; no sampled audio',
       'cues':entries},indent=2)+'\n')
    audition=[];timeline=[];position=0;silence=np.zeros((round(.8*RATE),2),dtype='<i2')
    for item,pcm in zip(entries,signals):
        piece=np.concatenate((pcm[-3*RATE:],pcm[:3*RATE])) if item['kind']=='loop' else pcm
        timeline.append({'file':item['file'],'start_s':round(position/RATE,3),
           'seam_s':round(position/RATE+3,3) if item['kind']=='loop' else None,
           'end_s':round((position+len(piece))/RATE,3)})
        audition.extend([piece,silence]);position+=len(piece)+len(silence)
    write(REVIEW/'audition.wav',np.concatenate(audition))
    (REVIEW/'audition_timeline.json').write_text(json.dumps(timeline,indent=2)+'\n')
    review(entries,signals)
    print('3 stereo32s loops +3 gusts:format/headroom/DC/mono/seams/endpoints/distinct hashes PASS')
    for item in entries:print(item['file'],item['duration_s'],'s',item['rms_dbfs'],'dB RMS',item['peak_dbfs'],'dB peak')


def review(entries,signals):
    from PIL import Image,ImageDraw,ImageFont
    image=Image.new('RGB',(1200,960),'#26323A');draw=ImageDraw.Draw(image)
    font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),18)
    small=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),13)
    for i,(item,pcm) in enumerate(zip(entries,signals)):
        x=i%2*600;y=i//2*320
        draw.rounded_rectangle((x+8,y+8,x+592,y+312),radius=12,fill='#FFFAF0')
        draw.text((x+20,y+20),item['file'],font=font,fill='#26323A')
        signal=pcm.astype(float)/32768;scale=max(abs(signal).max(),1e-9)
        for channel,color in [(0,'#26323A'),(1,'#75CBD1')]:
            for k,bucket in enumerate(np.array_split(signal[:,channel],540)):
                draw.line((x+30+k,y+113-52*float(bucket.max())/scale,x+30+k,y+113-52*float(bucket.min())/scale),fill=color)
        draw.text((x+20,y+177),'%.2fs | RMS %.1fdBFS | peak %.1fdBFS'%(item['duration_s'],item['rms_dbfs'],item['peak_dbfs']),font=small,fill='#26323A')
        draw.text((x+20,y+201),'Stereo correlation %.2f | mono loss %.2fdB'%(item['stereo_correlation'],item['mono_loss_db']),font=small,fill='#26323A')
        if item['kind']=='loop':
            label='Seam delta %.5f / %.5f | level difference %.3fdB'%(*item['seam_jump'],item['seam_level_difference_db'])
        else:label='Fade endpoints zero | final20ms RMS %.1fdBFS'%item['tail_20ms_rms_dbfs']
        draw.text((x+20,y+225),label,font=small,fill='#26323A')
        draw.text((x+20,y+278),'Plot scaled per cue; numeric dB levels are authoritative',font=small,fill='#26323A')
    image.save(REVIEW/'signal_review.png')

if __name__=='__main__':build()
