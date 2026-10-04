# Block impact variation candidates

Twelve original short mono Foley cues:soft/medium/hard xblock-on-block/block-on-disc
xtwo variants. Reproduce with python tools/generate_impact_variations.py.
Source construction uses damped modal bodies,brief pitch settling and seeded
filtered noise. No existing audio samples are copied or transformed. Existing
thud1-4.wav were analyzed only for short-transient character:roughly0.17..0.56s,
dominant body134..251Hz and spectral centroid1.49..2.71kHz after stereo downmix.
This candidate spans0.188..0.481s,body100..153Hz and centroid2.00..2.52kHz.

All files:mono,44100Hz,16-bitPCM,no loops/reverb,long tails or embedded metadata.
Peak target-3dBFS preserves mixer headroom. Strength affects timbre/length;
callers retain existing speed-driven gain instead of relying on file peak changes.
Block cues have a tighter mid-frequency body;disc cues add brief platform modes.
manifest.json records seed,format,hash and actual encoded-signal metrics.

## Cue selection proposal

Retain the existing impact gate and scheduler. Compute normalized strength using
current AudioConfig values:t=clamp((speed-impact_speed_min)/(impact_speed_loud-
impact_speed_min),0,1). Use the fallback span guard already used by AudioConfig.

| Tier | Normalized strength | Default speed range (min1m/s,loud8m/s) |
| --- | --- | --- |
| Soft | 0<=t<1/3 | 1..less than3.333m/s |
| Medium | 1/3<=t<2/3 | 3.333..less than5.667m/s |
| Hard | 2/3<=t<=1 | 5.667m/s and above |

Choose block/disc from the existing contact-surface information;do not infer it
from loudness. Alternate/randomize the two variants without immediate repeat
where possible. Keep AudioConfig.impact_volume_db(speed),distance attenuation,
Master/SFX and existing impact rate limits. Sounds below the existing minimum
remain suppressed. This is an integration proposal,not implemented runtime code.
No Sfx/AudioConfig/Block/replication files are changed.

## Review and limitations

See docs/art_mockups/impact_variation_v1/{waveform_review.png,audition.wav,README.md}.
Technical validation:12unique WAV hashes,container roundtrip,mono/rate/bit depth,
<0.6sduration,-3dBFSpeak,no clipped samples,zero first/last samples,DC<1e-5,
final20msRMS below-48dBFS,and identical hashes after deterministic regeneration.
Waveforms visually inspected;subjective timbre and actual in-game mix remain
Claude/owner listening acceptance. No game tests,Godot windows or audio autoplay.
Claude reviews and integrates these asset-only candidates and any later wiring.
