# Notes from the original Bontãgo (2003/2004 build)

Extracted 2026-09-20 from the installed original at `C:\Program Files (x86)\Bontago`
(`Bontago.exe` dated 2004-03-08, Tokamak physics, Circular Logic). Everything below is
quoted or paraphrased from the executable's own tutorial, help and options strings, plus
the shipped asset list. No code was decompiled. Where the owner's 2026-09-20 rule
clarifications in `docs/SPEC.md` differ, the owner's text wins; the differences are
flagged at the end so they can be decided consciously.

## Tutorial text (rules as the original states them)

- "The objective of Bont~go is to expand the player's controlled area (the shaded area on
  the field) to encircle all of the white flags."
- "Controlled area is increased by placing blocks in the connected area."
- "Connected areas are denoted with a bright border around the rim of the shaded area."
- "Blocks placed high up will generate larger influences than blocks placed near the board."
- "Blocks placed where connected areas from different teams overlap will sink through the
  board."
- "The minimap displays a top-down view of the controlled areas."
- "The next block and the timer are located in the preview window."
- "When the timer runs out the cursor block will drop to the field."
- "Blocks can be dropped before then, but will have to wait for the timer to run out to
  place the next block."
- "Blocks cannot be placed outside of the player's influence."
- "The cursor block is black and translucent when it cannot be placed."
- "When in a team game players can build in their own and teammates influences."
- Option "Require flag connection": "When set, influences must connect with player flag
  to allow dropping."

## Controls (from the tutorial and the key-binding option names)

- "Basic Movement": the mouse positions the block; a bound key/button drops it; the mouse
  wheel raises and lowers the block ("will raise the block" / "will lower your block").
- "Camera Control": while holding the camera-mode key, "movement keys change where the
  camera is facing"; quickly clicking the zoom keys zooms the camera in/out.
- "Block Rotation": while holding the rotation-mode key, "the movement keys change the
  orientation of the block"; a key snap-rotates the block; another returns it to its
  default rotation.
- Named bindings: Drop Block, Default Rotation, Rotation Mode, Camera Mode, "Locks block
  to vertical movement only", Chat (Enter), Reset Tilt, Clear Blocks, Special Toggle,
  "Press and hold TAB for the SandBar" (in-game status bar).
- Sensitivity sliders: block rotation, camera rotation, block movement.
- Throwing: "To throw a special block that has been picked up, move the mouse in the
  desired direction, then drop."

## Specials (gifts)

- "Occasionally special blocks will fall to the field." "Special blocks can be picked up
  by encircling them with a connected influence." "Special blocks are activated by hitting
  them with a significant force."
- DaBomb — "Massive explosion."
- Volcano — "Erupts, spewing explosive lava rocks."
- Earthquake — "Shakes and helps to level a tilted field."
- Propeller — "Slowly lifts upward, tilting the field."
- Anvil — "Places a weight on the field which cause it to tilt."
- Rocket — "Block that blasts off into the air and explodes when its fuel is used up."
- Jumping Bean — "Block that randomly jumps around the board. Between hops, a hole is
  created in the field around the block."
- Sound effects shipped: Boing, Bomb, Breakage, Creak, Propeller, Quake2, Rocket, Thud1–5,
  Volcano, Whoosh, NO, Click/Click2/MouseOver.

## Match settings (lobby options)

Gravity ("Gravity of the world"), block timer ("Amount of time before each player receives
a new block"), Flag Count ("Number of world flags on the table required to win"), Field
Size, Gift Spawning Probability ("Chance a gift will be spawned each turn"), per-gift
chances (Bomb, Rocket, Volcano, Earthquake, Anvil, Propeller, Jumping Bean), "Gifts
Height", Require flag connection, teams and colours per slot, "Use averaged choices"
(average every player's settings), Practice Game, Sandbox ("a freeform area of the game,
where there are no rules or limits": dominoes, throwing blocks, stacking blocks).

## Block shapes (model files)

`1x1x1`, `2x2x2`, `3x3x3`, bars `1x2x1` … `1x5x1`, plates `2x1x2` … `5x1x5`, slabs
`3x2x1`, `4x2x1`, `5x2x1`, columns `2x2x3`, `2x2x4`, `2x2x5`, `3x3x2`; plus the field
top/bottom/rim, a flag pole and a "specialty" model. Textures are skyboxes only (Arctic,
Beach, Dawn, Desert, Lake, Mist, Mountain, Sunset).

## Differences from the owner's 2026-09-20 clarifications (to decide, not decided here)

1. **Overlap holes.** The original's tutorial says blocks placed where different teams'
   connected areas overlap "sink through the board" — the original did have floor holes
   from contested territory. The owner's clarification removes them from the default rules
   (kept as a future mode) and makes the goal-flag no-build zone the "hole" mechanic.
2. **Next-block cadence.** In the original a dropped-early block does not bring the next
   block sooner: "will have to wait for the timer to run out to place the next block". The
   owner's clarification issues a new block immediately after a placement (with a ~1 s
   anti-spam gap requested separately).
3. **Camera.** The original's camera is attached to the held block: moving the mouse moves
   the block and the camera follows; the wheel changes block height; a held modifier
   switches the movement keys to camera facing or block rotation. The remake currently has
   a free orbit camera with the block following a ground raycast.
