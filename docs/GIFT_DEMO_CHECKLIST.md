# Gift effects: owner demo checklist

Source: `docs/GIFT_EFFECTS_PLAN.md` section 6 (Bontago-1pi.85.17). Automated coverage:
`tools/run_gift_fx_enet.ps1` (four-peer ENet: Bomb blink and explosion, Black hole and
Volcano visuals on clients, despawn; round 2, Bontago-1pi.85.36: in-place Volcano/Stackfall/
Earthquake leave no carrier or extra block on clients, a released Anvil is 5x on clients, an
upward Rocket keeps rising with its nose along its velocity, Black hole captures the cubes
beside it, a thrown Magnet leaves with the host-computed velocity). Everything below needs a human, a window and, for the
last section, a second PC or Steam.

## Start
1. `godot --path .` with debug mode on, Main Menu, Debug page, **Gift demo**.
   (Sandbox with `config/sandbox_gift_demo.tres`: 4 players, pre-placed opponent towers,
   gift frequency 100.)
2. Cycle the forced gift with **Left / Right** (pad: LB / RB). Tab (pad Back) changes seat.
3. For each gift, tick the line. Throwable gifts: hold the throw button, drag, release.

## Per gift
- [ ] **Bomb**: drop it next to a tower. It blinks for about 3 s, speeding up, then blocks
      fly away from the blast.
- [ ] **Rocket**: throw it. It flies the fixed arc (same every throw, whatever your drag)
      and explodes on the first thing it hits.
- [ ] **Volcano**: a large mountain rises where you released (about 2 s) and keeps firing
      blocks for 20 s or more, then disappears.
- [ ] **Propeller**: the disc tilts the opposite way from Anvil, every time. Repeat 5 times.
- [ ] **Jumping Bean**: hops, and each hop opens a hole in the territory.
- [ ] **Magnet**: enemy blocks within 8 m slide toward it.
- [ ] **Glue**: glued pieces do not drift apart on a tilting disc.
- [ ] **Black hole**: blocks within reach are pulled in hard, then the end-of-life effect
      happens (plan Q2).
- [ ] **Stackfall**: more blocks, falling from higher.

## Round 2 changes (docs/GIFT_PLAYTEST2_PLAN.md)
Tunables: **F4** panel (Debug page or in a match) for `SpecialTuning`, `RainTuning`; blast
strength and the particle numbers live in the gift's `.tres` under `config/specials/`
(`bomb.tres`, `rocket.tres` blast `radius_m` / `peak_speed_mps` / `max_delta_v_mps`;
`volcano.tres` particle tuning, see `config/specials/fx/VolcanoParticleTuning.gd`).
- [ ] **In-place Stackfall / Volcano / Earthquake**: click once. The effect starts at the
      cursor point at once; NO block falls or lies there, and the gift does not hang in the
      air. Look for: a stray cube or crate left after the effect (bug).
- [ ] **Paintball / Rocket flight**: released with a plain click, flies dead straight with no
      gravity arc, at the camera aim. Rocket: nose points where it flies, also when you aim
      steeply UP (it keeps climbing until fuel ends; it should not tumble or sag).
- [ ] **Aim, no LT**: Bomb / Magnet / Jumping Bean / Rocket / Paintball all release on
      the normal place button (click, `ghost_place`, pad A). The throw arc preview shows
      where it goes. Throw feel: 22 m/s, up ratio 0.35, spawns 8 m back along the camera line
      (F4 `SpecialTuning`: `gift_throw_speed_mps`, `gift_throw_up_ratio`, `gift_aim_back_m`).
      Adjust if it feels too weak/strong or lands short of the cursor.
- [ ] **Black hole**: a whole pile around and above it is pulled to its centre and dissolves
      (no block left hovering or orbiting). Nearby tall piles vanish top to bottom.
- [ ] **Jumping Bean**: after it lands it hops from the ground (first hop within about 0.4 s)
      and covers real ground, not one spot. Open feel check **Bontago-1pi.85.41**: is the
      hop distance right? Tunables: `JumpingBeanEffect` `hop_horizontal_speed` (7),
      `hop_impulse` (9), `hop_interval_s` (1.0); owner decides, leave the value if it looks right.
- [ ] **Bomb / Rocket blasts** are about 10x stronger: blocks near the blast fly clearly
      away, even 8 kg stacks. Too violent? lower `peak_speed_mps` / `max_delta_v_mps`; too
      wide? lower `radius_m` (Bomb 8 m, Rocket 7 m).
- [ ] **Released gift size**: Anvil and Propeller 5x, Bomb 3x, Rocket / Magnet / Bean 2x once
      released; the held preview stays 1x. Look for: model and physical box matching, a
      big Anvil not jumping the stack apart.
- [ ] **Held gifts** show their own colours/materials (not the player colour tint, no
      red/green overlay).
- [ ] **Random shapes**: Stackfall rain and Volcano eruptions produce a mix of piece shapes,
      not only cubes (`config/gifts/gift_shape_weights.tres` weights).
- [ ] **Volcano particles**: burst on each eruption and a continuous ember plume; none on
      the lowest graphics preset if budget-gated. Adjust the numbers in `VolcanoParticleTuning`.
- [ ] **Rain wet look** (weather rain on, with the gifts above): blocks and disc look wet,
      puddles on the disc, no gift model turning invisible. F4 `RainTuning`: `wet_sheen_add`
      (0.12), `wet_darken` (0.22), `wet_roughness_scale`, `puddle_*`.

## General
- [ ] A held gift does not rotate (rotate keys/buttons do nothing) and does not take your
      colour; an ordinary piece rotates again afterwards.
- [ ] Only the throwable gifts throw; a non-throwable gift refuses the throw button.
- [ ] Cat never appears.

## Online (second PC or Steam; not verified by the bench)
- [ ] Host a LAN or Steam game with one client. On the client, repeat Bomb, Volcano and
      Black hole: blink, mountain and black-hole visuals appear, blocks move, nothing is
      left behind after the gift ends. Watch the client console for red errors.
- [ ] Round 2 on the client: fire an upward Rocket (it freezes at the top of the play area
      on the client, a known wire limit: positions clamp at about 72 m up), and check Anvil
      size, Stackfall/Earthquake/Volcano with no leftover block, Black hole clearing a pile.
- [ ] With snow weather active, drop a Bomb or Volcano and watch the client console
      (see the SnowNet finding on Bontago-1pi.85.17).
