# Horizon concepts v1 — Bontago-59o.22

Five painted design previews made with the built-in image_gen tool, using the
existing `feedback/horizon_mockups/reference_morning.png` as the edit target.
The afternoon and Cycle strip were also inspected for the game's palette and
cloud style. Claude's live Beads notes supersede the old in-engine-probe brief:
these are owner-choice concept images. No game code is changed.

## Options

- A: towering, irregular cumulus bank joining the cloud sea to the upper layer.
- B: quiet horizontal stratus streaks and haze filling the empty horizon gap.
- C: three distant floating islands, their roots submerged in the cloud sea.
- D: one localized distant storm cell with rain curtains and restrained lightning.
- E: two outer cumulus towers plus thin stratus bands, keeping the sun area open.

`contact_sheet.png` shows the original followed by A–E. The five full PNGs are
1672x941; the original is1280x720. Full-size generated files are copied byte-for-
byte from tool outputs. The sheet only lays out and resizes whole images for
comparison; it does not retouch the paintings. The game HUD is AI-preserved
approximately, not a pixel-exact UI result.

## Review and next action

A has the strongest vertical bridge; E combines that bridge with a less crowded
horizontal transition. B is the calmest option. C introduces rock assets and D
adds localized weather scenery, so their integration scope differs from clouds.
The owner chooses a direction before environment implementation.

These single-view morning concepts do not prove a360-degree panorama, moving-
camera parallax, world scale, sun/cloud occlusion, a seamless looping background,
night/storm palette handling or performance. If selected, build the forms as
world/sky geometry or procedural layers and verify those behaviors in-game.
No choice is treated as approved by this handoff.

## Provenance and recovery

`provenance.json` records the exact five prompts, original edit target, source
image paths, verified Git base and reference hash. Generation used built-in
image_gen, not CLI/API fallback. Generated art is not bit-reproducible; the
prompts and preserved reference permit a new request with the same brief.
`verification.json` records the final dimensions and hashes.

`python tools/review_horizon_concepts.py` re-copies the preserved original tool
outputs, verifies them and recreates the mechanical contact sheet. It needs
Python3.8+ and Pillow plus the recorded local source files. It makes no API calls.
The final preview package is also copied to the owner's ignored feedback folder
at `feedback/horizon_mockups/generated_v1/`; that folder is for immediate review.
The worktree version is the durable candidate Claude can stage.

Checks: five valid distinct near16:9 PNGs; worktree copies identical to original
tool output bytes; all source/manifest inputs present; comparison sheet viewed;
Python syntax and git diff --check. No Godot run, full suite, benchmark, commit,
merge, push or game change was made.
