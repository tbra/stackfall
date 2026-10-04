"""Original deterministic impact Foley: damped body modes plus filtered noise."""
from pathlib import Path
import hashlib
import json
import math
import wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/effects/impact_variation_v1'
REVIEW=ROOT/'docs/art_mockups/impact_variation_v1'
RATE=44100
PEAK=10**(-3/20)


def noise_band(rng,n,low,high):
    noise=rng.standard_normal(n)
    f=np.fft.rfftfreq(n,1/RATE)
    band=(1-np.exp(-(f/max(low,1))**4))*np.exp(-(f/high)**4)
    signal=np.fft.irfft(np.fft.rfft(noise)*band,n)
    return signal/max(np.std(signal),1e-9)


def synth(surface,strength,variant):
    level={'soft':0,'medium':1,'hard':2}[strength]
    seed=2100+level*31+variant*7+(101 if surface=='disc' else 0)
    rng=np.random.default_rng(seed)
    duration=[.18,.29,.44][level]+(.025 if surface=='disc' else 0)+variant*.008
    n=round(duration*RATE);t=np.arange(n)/RATE
    base=(122 if surface=='disc' else 148)*(1-level*.075)*(1+(.035 if variant==2 else -.035))
    # Brief downward pitch sweep gives mass without a synthetic long tone.
    phase=2*np.pi*base*(t+.18*.018*(1-np.exp(-t/.018)))
    decay=duration/7.8
    body=np.sin(phase)*np.exp(-t/decay)
    body+=.32*np.sin(phase*1.83+.25)*np.exp(-t/(decay*.68))
    body+=.13*np.sin(phase*3.17+.8)*np.exp(-t/(decay*.34))
    texture=noise_band(rng,n,180,4400+level*400)
    texture*=np.exp(-t/(.024+level*.008))
    snap=noise_band(rng,n,1800,5500)*np.exp(-t/(.006+level*.002))
    signal=.60*body+(.50+level*.10)*texture+(.12+level*.06)*snap
    if surface=='disc':
        signal+=.16*np.sin(2*np.pi*(340+variant*19)*t)*np.exp(-t/.028)
        signal+=.07*np.sin(2*np.pi*713*t)*np.exp(-t/.016)
    # Remove offset, then enforce quiet onset and a fully faded finite tail.
    signal-=signal.mean()
    attack=np.minimum(1,t/.0015)
    fade=np.minimum(1,(duration-t)/.025)
    envelope=np.sin(attack*np.pi/2)**2*np.sin(fade*np.pi/2)**2
    signal*=envelope
    dc_weight=np.exp(-t/.03)*envelope
    signal-=signal.sum()/dc_weight.sum()*dc_weight
    signal[0]=0;signal[-1]=0
    signal*=PEAK/max(abs(signal))
    return np.rint(signal*32767).astype('<i2'),seed,base


def write_wav(path,samples):
    with wave.open(str(path),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE)
        f.writeframes(samples.astype('<i2').tobytes())


def metrics(samples):
    x=samples.astype(float)/32768
    spectral=abs(np.fft.rfft(x*np.hanning(len(x))))
    frequencies=np.fft.rfftfreq(len(x),1/RATE)
    return {'duration_s':round(len(x)/RATE,6),
            'peak_dbfs':round(20*np.log10(max(abs(x))),3),
            'rms_dbfs':round(20*np.log10(np.sqrt(np.mean(x*x))),3),
            'dc_offset':round(float(x.mean()),8),
            'tail_rms_dbfs':round(20*np.log10(max(1e-12,np.sqrt(np.mean(x[-882:]**2)))),3),
            'dominant_hz':round(float(frequencies[spectral.argmax()]),2),
            'spectral_centroid_hz':round(float((frequencies*spectral).sum()/spectral.sum()),2)}


def build():
    OUT.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    (REVIEW/'.gdignore').write_text('')
    entries=[];audio=[]
    for surface in ['block','disc']:
        for strength in ['soft','medium','hard']:
            for variant in [1,2]:
                name='impact_%s_%s_%02d.wav'%(surface,strength,variant)
                pcm,seed,base=synth(surface,strength,variant)
                write_wav(OUT/name,pcm)
                info=metrics(pcm)
                assert info['duration_s']<.6
                assert abs(info['peak_dbfs']+3)<.01
                assert abs(info['dc_offset'])<.00001
                assert info['tail_rms_dbfs']<-48
                assert pcm[0]==0 and pcm[-1]==0
                assert max(abs(pcm.astype(int)))<32767
                # Verify the delivered container, not only the synthesis buffer.
                with wave.open(str(OUT/name),'rb') as w:
                    assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,RATE)
                    assert w.readframes(w.getnframes())==pcm.tobytes()
                entries.append(dict(file=name,surface=surface,strength=strength,variant=variant,
                                    seed=seed,body_mode_hz=round(base,3),sha256=hashlib.sha256((OUT/name).read_bytes()).hexdigest(),**info))
                audio.append(pcm)
    assert len({item['sha256'] for item in entries})==12
    (OUT/'manifest.json').write_text(json.dumps({'sample_rate':RATE,'channels':1,'pcm_bits':16,
       'peak_target_dbfs':-3,'generator':'tools/generate_impact_variations.py',
       'provenance':'Original damped modes and seeded filtered noise; no existing audio samples reused',
       'strength_ranges_normalized':{'soft':[0,1/3],'medium':[1/3,2/3],'hard':[2/3,1]},'cues':entries},indent=2)+'\n')
    silence=np.zeros(round(.7*RATE),dtype='<i2')
    write_wav(REVIEW/'audition.wav',np.concatenate([np.concatenate((pcm,silence)) for pcm in audio]))
    review(entries,audio)
    print('12 mono44100Hz16-bit cues:duration/headroom/DC/tail/container/distinct hashes PASS')
    print('Duration %.3f..%.3fs,peak -3dBFS; review order matches manifest'%
          (min(i['duration_s'] for i in entries),max(i['duration_s'] for i in entries)))


def review(entries,audio):
    from PIL import Image,ImageDraw,ImageFont
    image=Image.new('RGB',(1200,840),'#26323A');draw=ImageDraw.Draw(image)
    font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),15)
    small=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),12)
    for index,(item,pcm) in enumerate(zip(entries,audio)):
        x=index%3*400;y=index//3*210
        draw.rounded_rectangle((x+6,y+6,x+394,y+204),radius=10,fill='#FFFAF0')
        draw.text((x+16,y+15),item['file'],font=font,fill='#26323A')
        signal=pcm.astype(float)/32768
        buckets=np.array_split(signal,360)
        for k,bucket in enumerate(buckets):
            draw.line((x+20+k,y+93-58*float(bucket.max()),x+20+k,y+93-58*float(bucket.min())),fill='#26323A')
        draw.line((x+20,y+93,x+380,y+93),fill='#75CBD1')
        draw.text((x+16,y+159),'%.3fs | peak %.1fdB | tail %.1fdB'%(item['duration_s'],item['peak_dbfs'],item['tail_rms_dbfs']),font=small,fill='#26323A')
        draw.text((x+16,y+180),'body %.0fHz | centroid %.0fHz'%(item['body_mode_hz'],item['spectral_centroid_hz']),font=small,fill='#26323A')
    image.save(REVIEW/'waveform_review.png')


if __name__=='__main__':build()
