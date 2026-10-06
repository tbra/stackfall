# Gift effects: owner demo checklist

Source: `docs/GIFT_EFFECTS_PLAN.md` section 6 (Bontago-1pi.85.17). Automated coverage:
`tests/bench/run_gift_fx_enet.ps1` (four-peer ENet: Bomb blink and explosion, Black hole and
Volcano visuals on clients, despawn). Everything below needs a human, a window and, for the
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

## General
- [ ] A held gift does not rotate (rotate keys/buttons do nothing) and does not take your
      colour; an ordinary piece rotates again afterwards.
- [ ] Only the throwable gifts throw; a non-throwable gift refuses the throw button.
- [ ] Cat never appears.

## Online (second PC or Steam; not verified by the bench)
- [ ] Host a LAN or Steam game with one client. On the client, repeat Bomb, Volcano and
      Black hole: blink, mountain and black-hole visuals appear, blocks move, nothing is
      left behind after the gift ends. Watch the client console for red errors.
- [ ] With snow weather active, drop a Bomb or Volcano and watch the client console
      (see the SnowNet finding on Bontago-1pi.85.17).
