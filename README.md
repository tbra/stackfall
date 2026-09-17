# Stackfall

A physics-based, competitive block-stacking territory game for 2–8 players, online over
Steam and on LAN. It is a remake of **Bontãgo** (Circular Logic, 2003); "Stackfall" is a
placeholder name, because the original name and assets belong to DigiPen and Circular Logic.

Built in Godot 4.7 (Forward+, Jolt physics). The full design and technical spec is
[docs/SPEC.md](docs/SPEC.md); working rules for the project are in [CLAUDE.md](CLAUDE.md).

## Status

**M2 — rules & territory (hot-seat, 2 players).** `godot --path .` starts a two-player
hot-seat match on one PC: block feed with a timer and auto-drop, placement validation
against your own territory, the territory raster and shader, contested zones, holes you
can fall through, home and goal flags, the win check, and a basic HUD. Multiplayer is
M3.

## Playing the hot-seat build by hand

Start it with `godot --path .`. After a 3-second countdown, player 1 is up; the turn
passes on every release, valid or not.

**Mouse and keyboard**

1. Move the mouse to aim the ghost block. It is tinted your colour where you may drop it,
   red outside your territory, over a contested cell or off the disk, and hatched over a
   hole.
2. `A` / `S` or the mouse wheel yaw the block; `Shift`+wheel or a middle-click **tap**
   pitch it; `[` / `]` roll it; hold `R` to free-rotate with the mouse; `Home` or `F`
   resets the rotation. `Ctrl`+wheel, `PageUp` / `PageDown` raise and lower the hover.
3. **Left click** to release. Inside your territory the block lands and the turn passes.
   Outside it, the block is thrown off the map and you lose it anyway — the HUD names the
   reason.
4. Hold the **middle mouse button** and drag to orbit; arrow keys (or `Space`-drag) pan;
   `Z` / `X` zoom while no block is held; `1` snaps to your home flag, `2` to the goal.
5. Let the timer ring in the top-left run out to watch the auto-drop relocate the block to
   the nearest valid spot, or burn it if there isn't one.
6. Build toward the other player. Where your territories overlap, the cells shimmer, then
   open into holes after about a second; drop a block on one and it falls through the disk.
7. Cut a tower off from your home flag — knock out the blocks between — and watch its
   patch of territory disappear from the overlay and from the share bars.
8. Surround the goal flag in the middle with one connected territory. Its ring fills over
   three seconds and you win.

**Gamepad** (same order, Xbox layout)

1. Left stick moves the ghost; **A** releases it.
2. **LB** / **RB** yaw, the **D-pad** pitches and rolls, **Y** resets the rotation, hold
   **RT** to free-rotate with the right stick, **RS click** / **X** raise and lower the
   hover.
3. Right stick orbits the camera; hold **LS click** and use the left stick to pan; the
   triggers zoom while no block is held; **Back** snaps to your home flag, **B** to the
   goal.

There is no pause menu or lobby yet — `pause_menu` is bound but does nothing until M6.
Close the window to quit.

Everything above is bound through the Input Map (`tools/bootstrap_project.gd`), so
rebinding is a change there rather than in gameplay code.

## Requirements

- Godot **4.6+**, standard build (not .NET). Developed against 4.7.2.
- Steam, for the online transport from M3b onward.
- A gamepad. Gamepad support has equal priority with mouse and keyboard.

## Commands

Run the editor:

```bash
godot --editor --path .
```

Run the game:

```bash
godot --path .
```

Run the unit tests (GUT, headless):

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

Rewrite project settings and the Input Map from source, after editing
`tools/bootstrap_project.gd`:

```bash
godot --headless --path . -s tools/bootstrap_project.gd
```

Run the M2 end-to-end acceptance scenario (a scripted hot-seat match; ~100 s, exits
non-zero on failure):

```bash
godot --headless --path . res://tests/bench/m2_acceptance.tscn
```

Run the physics and territory benchmarks:

```bash
godot --headless --path . res://tests/bench/bench_tower.tscn
godot --headless --path . res://tests/bench/bench_rain.tscn
godot --headless --path . res://tests/bench/bench_territory.tscn
```

Save a screenshot of the M2 build to `user://m2_main.png`, with a few blocks placed by
script:

```bash
godot --path . res://tools/screenshot_main.tscn
```

Multiplayer testing (from M3a): in the editor, **Debug → Customize Run Instances**, 2–4
instances.

## Layout

Follows spec §3.2.

| Path | What lives there |
|---|---|
| `autoload/` | `Events` signal bus, `Settings`, `Net`, `Match` singletons |
| `config/` | Tunable values as `Resource` files — no magic numbers in code |
| `core/` | Pure rule logic (territory, feed, win check), no scene tree, unit-tested |
| `game/` | Scenes and scripts for the field, blocks, specials, controllers |
| `net/` | Snapshot sync, interpolation, LAN discovery |
| `ui/`, `vfx/`, `sfx/`, `shaders/` | Presentation |
| `tests/unit/`, `tests/bench/` | Unit tests and physics benchmark scenes |
| `tools/` | Build-time scripts that are not part of the running game |
