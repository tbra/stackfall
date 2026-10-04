"""Original tactile UI cues sharing a D5-centred body with the existing select cue."""
from pathlib import Path
import hashlib,json,wave
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/effects/lobby_ui_cues_v1'
REVIEW=ROOT/'docs/art_mockups/lobby_ui_cues_v1'
RATE=44100
# name: (peak target dBFS, [(start seconds, body Hz, length seconds), ...])
CUES={
 'player_joined':(-8,[(0,587.33,.105),(.060,739.99,.110)]),
 'player_left':(-10,[(0,739.99,.090),(.055,587.33,.095)]),
 'ready_on':(-10,[(0,587.33,.080),(.055,880,.095)]),
 'ready_off':(-12,[(0,880,.075),(.050,587.33,.080)]),
 'team_change':(-12,[(0,587.33,.065)]),
 'colour_change':(-13,[(0,739.99,.055)]),
 'bot_added':(-11,[(0,587.33,.050),(.040,659.25,.065)]),
 'bot_removed':(-12,[(0,659.25,.050),(.040,587.33,.065)]),
 'section_expanded':(-16,[(0,1100,.035)]),
 'section_collapsed':(-16,[(0,840,.030)]),
 'all_players_ready':(-6,[(0,587.33,.160),(.070,739.99,.170),(.140,880,.200)]),
}


def voice(rng,frequency,seconds):
    n=round(seconds*RATE);t=np.arange(n)/RATE
    phase=2*np.pi*frequency*(t+.045*.008*(1-np.exp(-t/.008)))
    tonal=.55*np.sin(phase)+.2*np.sin(phase*2.43+.2)+.12*np.sin(phase*5.07+.4)
    f=np.fft.rfftfreq(n,1/RATE)
    response=(1-np.exp(-(f/900)**4))*np.exp(-(f/6000)**4)
    noise=np.fft.irfft(np.fft.rfft(rng.standard_normal(n))*response,n)
    noise/=max(np.std(noise),1e-9)
    envelope=np.sin(np.minimum(1,t/.0012)*np.pi/2)**2*np.exp(-t/(seconds/6))
    envelope*=np.sin(np.minimum(1,(seconds-t)/.010)*np.pi/2)**2
    signal=tonal*envelope+.27*noise*np.exp(-t/.003)*np.sin(np.minimum(1,t/.0005)*np.pi/2)**2
    signal[-1]=0
    return signal


def synth(name,index):
    peak,notes=CUES[name];seed=4100+index*17;rng=np.random.default_rng(seed)
    duration=max(start+length for start,_,length in notes)+.030
    n=round(duration*RATE);t=np.arange(n)/RATE;signal=np.zeros(n)
    for start,hz,length in notes:
        body=voice(rng,hz,length);i=round(start*RATE);signal[i:i+len(body)]+=body
    # Correct DC locally, preserving a quiet onset and faded end.
    weight=np.exp(-t/.025)*np.sin(np.minimum(1,t/.0012)*np.pi/2)**2
    weight*=np.sin(np.minimum(1,(duration-t)/.015)*np.pi/2)**2
    weight[0]=0;weight[-1]=0
    signal-=signal.sum()/weight.sum()*weight
    signal[0]=0;signal[-1]=0
    signal*=10**(peak/20)/abs(signal).max()
    return np.rint(signal*32767).astype('<i2'),seed


def write(path,pcm):
    with wave.open(str(path),'wb') as w:
        w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())


def build():
    OUT.mkdir(parents=True,exist_ok=True);REVIEW.mkdir(parents=True,exist_ok=True)
    (REVIEW/'.gdignore').write_text('');items=[];signals=[]
    for index,name in enumerate(CUES):
        pcm,seed=synth(name,index);x=pcm.astype(float)/32768
        peak=20*np.log10(abs(x).max());tail=20*np.log10(max(1e-12,np.sqrt(np.mean(x[-882:]**2))))
        duration=len(x)/RATE
        spectrum=abs(np.fft.rfft(x*np.hanning(len(x))))
        frequencies=np.fft.rfftfreq(len(x),1/RATE)
        assert duration<.5 and abs(peak-CUES[name][0])<.01
        assert abs(x.mean())<1e-5 and tail<-48 and pcm[0]==0 and pcm[-1]==0
        assert max(abs(pcm.astype(int)))<32767
        name_file=name+'.wav';write(OUT/name_file,pcm)
        with wave.open(str(OUT/name_file),'rb') as w:
            assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,RATE)
            assert w.readframes(w.getnframes())==pcm.tobytes()
        items.append(dict(file=name_file,seed=seed,duration_s=round(duration,6),
            peak_target_dbfs=CUES[name][0],peak_dbfs=round(float(peak),3),
            rms_dbfs=round(20*np.log10(np.sqrt(np.mean(x*x))),3),
            dc_offset=float(x.mean()),tail_20ms_rms_dbfs=round(float(tail),3),
            dominant_hz=round(float(frequencies[spectrum.argmax()]),2),
            spectral_centroid_hz=round(float((frequencies*spectrum).sum()/spectrum.sum()),2),
            sha256=hashlib.sha256((OUT/name_file).read_bytes()).hexdigest(),
            notes=[dict(start_s=start,body_hz=hz,duration_s=length) for start,hz,length in CUES[name][1]]))
        signals.append(pcm)
    assert len({i['sha256'] for i in items})==11
    (OUT/'manifest.json').write_text(json.dumps({'sample_rate':RATE,'channels':1,'pcm_bits':16,
        'generator':'tools/generate_lobby_ui_cues.py','provenance':'Original damped modes and seeded filtered noise; existing sounds analyzed only, not sampled','cues':items},indent=2)+'\n')
    silence=np.zeros(round(.7*RATE),dtype='<i2');audio=[];timeline=[];position=0
    for item,pcm in zip(items,signals):
        timeline.append({'file':item['file'],'start_s':round(position/RATE,3),'end_s':round((position+len(pcm))/RATE,3)})
        audio.extend([pcm,silence]);position+=len(pcm)+len(silence)
    write(REVIEW/'audition.wav',np.concatenate(audio))
    (REVIEW/'audition_timeline.json').write_text(json.dumps(timeline,indent=2)+'\n')
    review(items,signals)
    print('11 mono UI cues:container/duration/headroom/DC/endpoints/tails/unique hashes PASS')
    print('Durations %.3f..%.3fs; peaks -16..-6dBFS'%(min(i['duration_s'] for i in items),max(i['duration_s'] for i in items)))


def review(items,signals):
    from PIL import Image,ImageDraw,ImageFont
    image=Image.new('RGB',(1200,840),'#26323A');draw=ImageDraw.Draw(image)
    font=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),16)
    small=ImageFont.truetype(str(ROOT/'assets/ui/fonts/Manrope-Regular.ttf'),12)
    for index,(item,pcm) in enumerate(zip(items,signals)):
        x=index%3*400;y=index//3*210
        draw.rounded_rectangle((x+6,y+6,x+394,y+204),radius=10,fill='#FFFAF0')
        draw.text((x+16,y+15),item['file'],font=font,fill='#26323A')
        samples=pcm.astype(float)/32768
        for k,bucket in enumerate(np.array_split(samples,360)):
            draw.line((x+20+k,y+97-110*float(bucket.max()),x+20+k,y+97-110*float(bucket.min())),fill='#26323A')
        draw.line((x+20,y+97,x+380,y+97),fill='#75CBD1')
        draw.text((x+16,y+163),'%.3fs | peak %.1fdBFS'%(item['duration_s'],item['peak_dbfs']),font=small,fill='#26323A')
        draw.text((x+16,y+182),'Tail20ms %.1fdBFS'%item['tail_20ms_rms_dbfs'],font=small,fill='#26323A')
    image.save(REVIEW/'waveform_review.png')

if __name__=='__main__':build()
