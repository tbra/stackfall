# Stackfall

A physics-based, competitive block-stacking territory game for 1–8 players, built in Godot
with Jolt physics. Inspired by Bontãgo (Circular Logic).

Everyone drops blocks at the same time. Each block claims territory around it, towers
reach further the taller they get, and where two players' territory overlaps the floor
opens into holes. Build toward the goal in the middle, knock out your rivals' towers, and
watch the whole thing wobble.

## Status

Playable and under active development. Online play over Steam is a development setup (see
[Multiplayer](#multiplayer)); there is no packaged release yet.

## Features

- Physics-driven block stacking: a wide range of block shapes, fed from a bag so nobody goes long
  without a stabilizing piece.
- Territory from every settled block, connected back to your home flag. Overlapping claims
  open temporary or permanent holes in the disc.
- Five game modes: Classic (capture every goal flag), Capture the Flag, Elimination,
  Reach the Sky and Domination.
- Free-for-all or teams of 2–4, with humans and bots (Easy, Normal, Hard) mixed freely.
- Gifts that parachute onto the field: Rocket, Bomb, Volcano, Earthquake, Anvil,
  Propeller, Jumping Bean, Magnet, Freeze, Glue, Stackfall, Paintball and Black Hole.
- Online play over LAN, direct IP or Steam, with a host-authoritative simulation.
- Keyboard and mouse or gamepad, with equal priority; all bindings are rebindable.
- Offline Tutorial, Vs Bots and Sandbox modes.

## How to play

Choose a mode from the main menu: **Host** or **Join** for multiplayer, **Play Offline**
and **Vs Bots** for a local match, **Sandbox** for free experimenting, or **Tutorial** for
a short guided introduction. The host sets map, game mode, block timer, gravity, goal
flags, gifts, hole mode and more in the lobby; every player readies up and the host
starts the match.

**The goal.** In Classic, hold every goal flag with one connected stretch of your team's
territory, linked to a living home flag, for the full capture hold. Losing your home flag
eliminates you. The other modes score by flag holding, last team standing, height, or
territory share when the round timer ends. Design details are in [docs/SPEC.md](docs/SPEC.md).

**Turn structure.** There are no turns. Each player has their own timer and may release
one block per interval; a block you do not drop in time is dropped for you.

### Controls

All input goes through the Input Map, which is defined in `tools/bootstrap_project.gd`.
You can rebind in Options > Controls.

| Action | Keyboard and mouse | Gamepad |
| --- | --- | --- |
| Move the held block | Mouse | Left stick |
| Place the block | Left click | A |
| Raise or lower the block | Mouse wheel, Page Up / Page Down | RB / LB |
| Lock to vertical movement | Ctrl (held) | none |
| Yaw 90° | A (counter-clockwise), S (clockwise) | B |
| Pitch | W, D | D-pad up, D-pad down |
| Roll | `[`, `]` | D-pad left, D-pad right |
| Free-rotate | R (held) and move the mouse, or middle mouse drag | RT (held) and left stick |
| Reset rotation | Home, F or Q | Y |
| Throw a throwable special | Left click and drag, then release | A |
| Orbit the camera | Right mouse drag, or C (held) and move the mouse | Right stick |
| Zoom the camera | Z / X | LT (held) and left stick up or down |
| Reset the camera | V | Back |
| Scoreboard | Tab (held) | Right stick click |
| Use a slotted gift (experimental option) | G | X |
| Chat | Enter or T | none |
| Pause menu | Esc | Start |
| Net debug overlay | F3 | Y |
| Tuning panel | F4 | X |
| Performance overlay | F1 | Right stick click |
| Screenshot | F12 | Misc1 |

Some gamepad actions share a physical button and are told apart by context or by a held
chord; the Options screen lists every binding.

Sandbox adds hotkeys: Tab (next slot), F5 (reset field), F6 (toggle timer), F7 (spawn
tower), F9 (force a special), F10 (slow motion) and F11 (pause physics).

## Requirements

- Godot **4.7**, standard build (not .NET). The project is developed and tested on 4.7.2;
  its `project.godot` declares the `4.7` and `Forward Plus` features.
- Renderer: Forward+. Physics: **Jolt Physics** (`physics/3d/physics_engine`), 60 ticks per
  second with physics interpolation. These are set in `project.godot` and regenerated from
  `tools/bootstrap_project.gd`.
- A desktop GPU that supports Forward+; a Low graphics preset is available.
- Optional: a gamepad, and the Steam client plus the GodotSteam addon for online play.

## Running and building

```bash
godot --editor --path .      # open the editor
godot --path .               # run the game (main menu)
```

Open the project in the editor once (or run `godot --headless --editor --path . --quit`)
before running scripts headlessly, so Godot builds its class cache. That command should
print no errors or warnings.

If you edit `tools/bootstrap_project.gd`, regenerate the project settings and the Input
Map. Do not edit the `[input]` section of `project.godot` by hand.

```bash
godot --headless --path . -s tools/bootstrap_project.gd
```

### Exporting (Windows)

`export_presets.cfg` defines a Windows Desktop preset that writes `build/windows/Stackfall.exe`.
With the Godot export templates for your engine version installed:

```powershell
tools/export_windows.ps1              # release export
tools/export_windows.ps1 -Debug       # debug export with visible script errors
tools/export_windows.ps1 -SkipSmoke   # skip the exported-build bot-match smoke test
```

The export also writes a development `steam_appid.txt` next to the executable.

### Command-line flags

Pass these after `--`, for example `godot --path . -- --host`.

| Flag | Effect |
| --- | --- |
| `--host` | Host on the default port and open the lobby. |
| `--join=<ip[:port]>` | Join that address and open the lobby. |
| `--port=<n>` | Override the port for `--host`, `--headless-host` and `--join`. |
| `--headless-host` | Host with no window, for a dedicated or scripted host. Add `--advertise` to show it in LAN browsers, and `--bots=<n>` to start a bot match. |
| `--sandbox [--players=N]` | Offline sandbox: every slot locally controllable, no feed timer. |
| `--sim-lag=<ms>`, `--sim-loss=<0..1>` | Simulate one-way lag and packet loss from launch. |
| `--steam-online`, `--host-online` | Initialize Steam (see below); `--host-online` also hosts a Steam lobby. |

## Multiplayer

The host is authoritative and the only peer that runs physics. Clients send intents that
the host validates. Gameplay code uses Godot's `MultiplayerAPI` only, so the transport is
swappable: ENet for LAN, direct IP and tests, and Steam for online play.

**LAN and direct IP.** No extra setup is needed.

1. One player chooses **Host**. The lobby opens with every match setting.
2. Everyone else chooses **Join** and picks the host from the LAN list (same subnet), or
   types the host's address as `1.2.3.4` or `1.2.3.4:47778` under **Join IP**. Forward
   the game port (default UDP 47778) if you are playing across the internet.
3. Each player readies up; the host starts the match.

To test several instances on one machine, use the editor's **Debug > Customize Run
Instances** (2–4 instances). Only one process per machine can listen for LAN discovery,
so join the other instances by direct IP (`127.0.0.1:<port>`). `tools/run_m3a_local.ps1
-Peers 4` runs a scripted headless match with one host and three clients on the local
machine, and exits non-zero on failure.

**Steam (development setup).** The GodotSteam addon is not part of a fresh clone
(`addons/godotsteam/` is untracked on purpose), and nothing else needs it. A fresh clone
runs LAN, direct IP and offline modes with no setup. To work on the Steam transport on
Windows:

1. Download the GodotSteam **GDExtension** release (not the precompiled editor build, which
   replaces the Godot binary) from the GodotSteam project's releases page.
2. Copy into `addons/godotsteam/`: `godotsteam.gdextension`, `license.md`, the two
   `libgodotsteam.windows.*.x86_64.dll` files, and `steam_api64.dll` from the same archive.
   Install all of them in one pass. A half-installed addon prints errors on every project
   open.
3. Run `tools/check_steam_setup.ps1` to confirm the install is complete, and
   `godot --headless --path . -s res://tools/steam_probe.gd` to confirm Steam initializes.
4. Start the game with `godot --path . -- --steam-online`. Development uses Steam's test
   app ID 480. The ordinary run skips Steam initialization because that test app's Steam
   Input intercepts controller events.

## Development

The spec is [docs/SPEC.md](docs/SPEC.md): game design (Part 1) and technical architecture
(Part 2), including the project layout. Working rules for contributors are in
[CLAUDE.md](CLAUDE.md). Highlights: statically typed GDScript with untyped declarations as
compile errors, tunables in `Resource` files under `config/`, pure rule logic in `core/`
with no scene-tree dependency, and a global `Events` signal bus.

Tests use [GUT](https://github.com/bitwes/Gut) and are headless.

```powershell
tools/run_gut.ps1 test_net_session,test_steam_client   # targeted: named scripts, seconds
tools/run_gut.ps1 test_match_net -Unit test_a_client   # one test by name substring
```

```bash
python tools/full_gate.py          # whole suite, sharded; prints FULL GATE GREEN or RED
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit   # plain serial run
python tools/lint_all.py           # every gate lint; prints LINT ALL GREEN or RED
```

Benchmarks live in `tests/bench/`, for example
`godot --headless --path . res://tests/bench/bench_tower.tscn`.

Off-screen screenshots of any screen are produced by `tools/shot.tscn`; see
`tools/shot.gd` for targets and options.

Only GodotSteam and GUT are used as third-party addons; ask before adding another.
