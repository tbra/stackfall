# Prerendered loading arena

Three candidate 1920 x 1080 PNG backgrounds: sunset, night and dawn. They use
the real medium round arena, normal beacon/territory/disc materials, and four
small stacks made with the gameplay block factory and current match block size.
Stacks are frozen for art capture. The arena sits below the center, leaving sky
behind the loading card. No text or UI is baked into the backgrounds.

## Suggested integration

Use a fullscreen `TextureRect` behind the existing loading content with
`EXPAND_IGNORE_SIZE` and `STRETCH_KEEP_ASPECT_COVERED`. Keep centered cropping and
one shared UI scale. A separate dark overlay can dim the art; the review uses
the existing background color at 0.58 alpha. Preserve the card, progress and
ready gate. Select a plate after the sky theme resolves, with sunset as a
fallback. These plates show the round arena and should not be presented as an
exact preview of every arena shape or live player layout.

The source images have no mipmaps requirement for static fullscreen use. At
large or ultrawide resolutions they are scaled up; use linear filtering. See
`docs/art_mockups/loading_arena_v1` for the actual loading UI composition and
centered cover crop proofs at 1280x720, 1920x1080, 2560x1440, 3440x1440 and
720x1280. Those proofs check artwork framing; they do not certify live UI resize
behavior. Final loading screen wiring remains for integration.

## Reproduce

The capture scene owns its camera, static stack arrangement and three theme
captures. It also inserts the texture behind an instance of the current
`LoadingScreen` solely to produce the composition evidence. No live UI scene or
script is changed.

```powershell
godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/render_loading_arena.tscn -- --agent-probe --render-size=1920x1080
python tools/review_loading_arena.py
```

The code base and visual checks are recorded in Bontago-mp0.96. Sky rendering
may change during concurrent work; rerender from the accepted integrated base
if its appearance differs. No performance benchmark or full suite is needed
for the image package.

## Capture limitation

The images and loading composition render successfully, but the capture tool
reports resource and RID leaks at engine shutdown when the loading proof is
included. This remained after explicit overlay cancellation and rendered-frame
cleanup within the three-window validation budget. Follow-up: Bontago-fca.21.
The PNGs themselves import independently of that tool.
