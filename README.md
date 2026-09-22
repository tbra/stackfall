# Stackfall

A physics-based, competitive block-stacking territory game for 2–8 players, online over
Steam and on LAN. It is a remake of **Bontãgo** (Circular Logic, 2003); "Stackfall" is a
placeholder name, because the original name and assets belong to DigiPen and Circular Logic.

Built in Godot 4.7 (Forward+, Jolt physics). The full design and technical spec is
[docs/SPEC.md](docs/SPEC.md); working rules for the project are in [CLAUDE.md](CLAUDE.md).

## Status

**M3a — multiplayer over ENet.** `godot --path .` opens a main menu: **Host** a game (LAN
advertising plus direct IP), **Join** one from the LAN list or a typed address, or **Quit**.
The lobby that follows exposes every §2.8 match setting, a ready-up roster and a host-only
Start button; once the match starts, every peer plays in real time — no more turn order,
each player has their own feed timer. Each screen's own HUD shows only that player's status:
their colour and name, their held- and next-block previews, their timer ring (greyed out and
labelled LOCKED while the fixed-interval release lock holds), and their territory share — the
old hot-seat "Player N's turn" banner is hot-seat-only now. A block you place goes through
the host before it spawns anywhere, so a placement is never duplicated or lost, even doubled
clicks or a lossy link. `F3` (or gamepad Back+Y) opens a debug overlay with ping, snapshot size, interpolation
delay and measured loss, plus sliders to simulate lag and packet loss yourself. M2's hot-seat
build is still there, unlisted: `godot --path . -- --hot-seat` starts the old two-player,
one-PC, turn-by-turn match unchanged. Steam is M3b.

## Playing the networked build by hand

Start it with `godot --path .`. The steps below are for one machine hosting and one or more
others (or other instances on the same machine — see "Local multiplayer without a second
PC" below) joining it; hot-seat's controls are unchanged from M2 and are described further
down.

1. On the host's machine, click **Host**. The lobby opens with every §2.8 setting
   (map, player/AI count, block timer, gravity, goals, gifts, specials, tilt, holes, match
   timer, sudden death) live-editable; a client sees the same settings greyed out and
   updating as the host changes them.
2. On each other machine (or instance), click **Join**: pick the host from the LAN list
   (same subnet, UDP broadcast) or type its address as `1.2.3.4` or `1.2.3.4:47999` under
   direct IP.
3. Every joined player ticks **Ready**. The host's **Start** button lights up once everyone
   has; press it to begin the 3-second countdown.
4. Placement, rotation, hover and camera controls are exactly the hot-seat build's (see the
   gamepad/mouse list further down) — the only difference online is that every player's
   timer runs at once, not in turn.
5. `F3` (gamepad: hold **Back** and press **Y**) toggles the debug overlay: ping, snapshot
   bytes/sec, interpolation delay and measured packet loss, with sliders to dial in your own
   simulated lag/loss (or the one-button preset for the spec's acceptance condition, 100 ms /
   2%) to see how your own connection would feel.
6. A fast double-click sends only one intent — the second is refused as a duplicate, not
   spent as your next block (test this: only one block should ever land per double-click,
   on every screen). If a client's connection drops mid-match, that slot's timer stops
   immediately; after a 10-second grace period it is eliminated and its towers unanchor,
   exactly as a lost home flag would (verify: the remaining players keep playing without the
   host or match hanging). If the *host* leaves or crashes, every client drops back to the
   main menu rather than sitting in a dead match.

### Local multiplayer without a second PC

`tools/run_m3a_local.ps1` (PowerShell) and `tools/run_m3a_local.sh` (bash) launch one
headless host and N−1 headless clients from a single command, all on `127.0.0.1`, run a
scripted match end to end, and exit non-zero if anything failed:

```powershell
tools/run_m3a_local.ps1 -Peers 4                       # 1 host + 3 clients
tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02   # client 1 gets the acceptance condition
```

```bash
tools/run_m3a_local.sh --peers 4
```

For a windowed feel-test instead of a scripted one, use the editor's **Debug → Customize
Run Instances** with 2–4 instances (`--hot-seat` is a per-instance argument there too, if
you want one of them running the old build). Only one process per machine can listen on the
LAN discovery port, so local multi-instance testing always joins by direct IP
(`127.0.0.1:<port>`), never the LAN list.

## Playing the hot-seat build by hand

Start it with `godot --path . -- --hot-seat`. After a 3-second countdown, player 1 is up;
the turn passes on every release, valid or not.

**Bontago-mv0.14: original-style block-locked controls.** The camera is attached to the
held block and follows it, the way the original's tutorial describes ("the mouse positions
the block" and the camera moves with it) — the mouse no longer projects a screen cursor
onto the field. The game captures the OS mouse cursor while playing (there is no pause menu
yet to release it into; see below). At match start the cursor and camera both start at your
own home flag, with the camera already looking from there toward the disk's centre.

**Mouse and keyboard**

1. Move the mouse to move the ghost block in the field plane, relative to the camera, which
   follows a step behind it. It is tinted your colour where you may drop it, red outside
   your territory, over a contested cell or off the disk, and hatched over a hole. A
   footprint — one tinted quad per cell of the block's own footprint, rotation included —
   projects straight down onto whatever is directly beneath it (the disk, or the top of a
   tower), so you can see exactly what it will land on before you release.
2. The **mouse wheel** raises and lowers the block's height. This is the only thing that
   changes it — moving the cursor over a tower does not lift the block to clear it; raise it
   yourself with the wheel first.
3. Hold **`R`** (Rotation Mode) and move the mouse to snap the block's yaw/pitch by 90°
   per drag threshold, the same table `A`/`S`/`W`/`D`/`[`/`]` step one tap at a time.
   Middle-click (**rotate_snap**) yaws 90° in one tap; `Home` or `F` resets the rotation.
4. Hold **`Ctrl`** (`lock_vertical`) to ignore the mouse's left/right and forward/back
   motion — only the wheel changes height while it's held.
5. **Left click** to release. Inside your territory the block lands and the turn passes.
   Outside it, the block is thrown off the map and you lose it anyway — the HUD names the
   reason.
6. Hold **`C`** (Camera Mode) and move the mouse to orbit the camera around the held block
   instead of moving it; `Z` / `X` zoom while no block is held.
7. Let the timer ring in the top-left run out to watch the auto-drop relocate the block to
   the nearest valid spot, or burn it if there isn't one.
8. Build toward the other player. Where your territories overlap, the cells shimmer, then
   open into holes after about a second; drop a block on one and it falls through the disk.
9. Cut a tower off from your home flag — knock out the blocks between — and watch its
   patch of territory disappear from the overlay and from the share bars.
10. Surround the goal flag in the middle with one connected territory. Its ring fills over
    three seconds and you win.

**Gamepad** (same order, Xbox layout)

1. Left stick moves the ghost; **A** releases it.
2. **RS click** / **X** raise and lower the hover.
3. Hold **RT** (Rotation Mode) and use the left stick to snap yaw/pitch the same way the
   mouse does; **LB** / **RB** yaw, the **D-pad** pitches and rolls one tap at a time, **Y**
   resets the rotation.
4. Right stick always orbits the camera around the held block (no hold needed — the stick
   has no other job).
5. The triggers zoom while no block is held (they double as rotation_mode/throw while one
   is); **Back** snaps to your home flag, **B** to the goal (both only apply to the legacy
   free-orbit camera, off by default — see `CameraTuning.follow_block`).

There is no dedicated `lock_vertical` gamepad binding: the stick (movement) and the hover
buttons (height) are already on separate physical inputs, so there's nothing to lock.

There is no pause menu yet — `pause_menu` is bound and toggles the mouse capture on/off
(Esc, or gamepad Start) but opens no menu until M6. Close the window to quit.

Everything above is bound through the Input Map (`tools/bootstrap_project.gd`), so
rebinding is a change there rather than in gameplay code.

## Sandbox mode

`godot --path . -- --sandbox [--players=N]` is a second unlisted debug build, like
`--hot-seat`: an offline match with every slot locally controllable, no feed timer (so
nothing auto-drops), and a fresh block issued the instant the last one lands. `N` defaults
to 2 (`config/sandbox.tres`); sandbox is the one place a 1-player match is allowed, for
solo rules testing. Placement, rotation, hover and camera controls are the hot-seat build's
(above); one extra set of hotkeys switches who you're playing and pokes at the match
directly:

| Action | Keyboard | Gamepad |
|---|---|---|
| Switch active slot | `Tab` | Back |
| Reset the field (same config) | `F5` | Paddle 1 |
| Toggle the feed timer (off by default) | `F6` | Paddle 3 |
| Spawn a tower of blocks at the cursor | `F7` | Paddle 2 |
| Toggle the territory overlay | `F8` | Paddle 4 |

A debug panel in the top-right shows the active slot and its colour, the block held and up
next, whether the timer is running or paused, why the ghost is (in)valid right where it's
aimed (the same `PlacementRules` reason the HUD's reject message uses), territory share per
slot, blocks spawned so far and the physics step time. `F3`'s net debug overlay works here
too (it just reports Offline/0 peers).

Every hotkey still goes through `Match.request_place()`/`Match.start_match()` like a real
click would — sandbox decides no rules of its own, so a territory rewrite only ever changes
what the panel's validity label prints, never this file.

## Tuning panel (F4)

Press **F4** (gamepad: hold **Start** and press **X**) at any time — sandbox, hot-seat, or a
real networked match — to open an in-game panel of sliders/spinboxes/checkboxes/color
pickers for every tunable in `config/CameraTuning.gd`, `GhostTuning.gd`, `PhysicsTuning.gd`,
`TerritoryTuning.gd`/`TerritoryVisuals.gd` and `BlockFeedConfig.gd`, one control per exported
field, built automatically by reflection: add a new `@export` to any of those resources and
it gets a control here for free, no panel code change required. The mouse is released and
gameplay input (moving/rotating/dropping the ghost) is suppressed while it's open; closing it
re-hides the mouse and hands control back.

Five tabs: **Camera**, **Controls** (ghost/placement feel), **Physics** (gravity, damping,
friction, bounce, the kill plane...), **Territory** (rule numbers plus the overlay's look),
**Feed** (the block bag). A client in a networked match only sees **Camera**/**Controls** —
editing physics or territory locally on a client would be inert anyway, since only the host
runs physics (`net/SnapshotSync.gd` freezes and moves a client's bodies for it).

Every control writes straight onto the same live resource instance the rest of the game
already reads, so most fields take effect on their very next read (next frame, for almost
everything). A few are pushed explicitly the moment you change them: a **Physics** edit
(damping, friction, bounce, gravity) re-applies to every block already standing, not just the
next one spawned; a **Territory** visuals edit (colors, outline, shimmer, rim) refreshes the
disk's shader uniforms immediately. Two fields are **not** live: `CameraTuning.follow_distance`
/ `follow_pitch_deg` are only read once, when the camera rig is built, so a change shows up
next match/scene reload; `TerritoryVisuals.disk_mesh_segments` is baked into the disk mesh the
same way.

Buttons at the bottom:

- **Reset** — reloads every resource's fields from its `.tres` on disk (discards unsaved
  edits, does not touch a saved override file).
- **Save override** — writes every field to `user://tuning_overrides.cfg`. `game/Main.gd`
  applies this file to the shared tuning resources first thing at boot, before anything else
  in the game reads them, so a saved tweak survives a restart without editing a `.tres`.
- **Copy** — copies every field's current value to the clipboard as `name = value` lines
  (`Color(r, g, b, a)` for colours), grouped under a `# ClassName` header per resource, ready
  to paste straight into the matching `config/*.tres` file to make a tweak permanent in the
  repo.

## Requirements

- Godot **4.6+**, standard build (not .NET). Developed against 4.7.2.
- Steam, for the online transport from M3b onward. M3a plays over ENet — LAN, direct IP,
  or 127.0.0.1 for local multi-instance testing — with no Steam dependency.
- A gamepad. Gamepad support has equal priority with mouse and keyboard.

## Steam setup (development)

M3b's Steam transport (`SteamMultiplayerPeer`, via the GodotSteam GDExtension) is not part
of a fresh clone. `res://addons/godotsteam/` is **entirely untracked, by design** — see the
spike results in `docs/M3b_RESEARCH.md` (Bontago-mv0.2.1). Godot only tries to load a
`.gdextension` file if one actually exists on disk, so skipping this step gives a perfectly
clean `godot --headless --editor --path . --quit` and full LAN/ENet/`--hot-seat` play; a
**half**-installed addon (the `.gdextension` present without its platform library or Valve's
`steam_api64.dll`) is the one state that prints `ERROR` lines from Godot's
`GDExtensionManager` on every project open, so always install everything below in one pass,
never partially.

None of this is required to build, run, or test Stackfall over LAN, direct IP, or hot-seat.

To develop or test the Steam transport locally (Windows):

1. Download the current GodotSteam **GDExtension** release (not the precompiled editor
   build, which replaces the Godot binary and conflicts with this project's pinned 4.7.2
   shim) from https://codeberg.org/godotsteam/godotsteam/releases — the `*-gde` tag, asset
   named `godotsteam-<version>-gdextension-plugin-4.4.zip`. As of this writing that's
   v4.22.1-gde (Steamworks SDK 1.65).
2. Unzip it and copy into `res://addons/godotsteam/` in this repo:
   - `godotsteam.gdextension` and `license.md`
   - `win64/libgodotsteam.windows.template_debug.x86_64.dll`
   - `win64/libgodotsteam.windows.template_release.x86_64.dll`
   - `win64/steam_api64.dll` — this **is** Valve's redistributable; GodotSteam's zip ships
     it alongside its own binaries, so no separate partner.steamgames.com download is
     needed for Windows development.
3. Run `tools/check_steam_setup.ps1` to confirm the install is complete, or
   `godot --headless --path . -s res://tools/steam_probe.gd` to confirm
   `Steam.steamInitEx()` actually initializes — status `0` if the Steam client is running
   and logged in, `2` if it isn't; both are fine for local testing.
4. `godot --headless --editor --path . --quit` should still print nothing.

## Original assets (optional)

`autoload/Sfx.gd` plays placeholder sound effects and music lifted from the original 2003
Bontago install. Those files are **third-party copyrighted assets and never enter this
public repo** — `res://assets/original/` is entirely untracked, the same pattern
`res://addons/godotsteam/` uses above. Without it, the game runs and plays silently; one
info line prints at startup and every `Sfx.play()` call is a no-op.

To install them locally, if you have an original Bontago install (Windows):

```powershell
tools/install_original_assets.ps1 [-Source "C:\Program Files (x86)\Bontago"]
```

This copies `Audio\SoundFX\*.wav` and `Audio\Music\bontago1.mp3` (lowercasing every
filename) into `assets/original/audio/`. Re-run it any time; it's idempotent.
`tools/export_windows.ps1` mirrors `assets/original/` beside an exported `.exe` the same
way it mirrors the GodotSteam DLLs, so an exported build keeps its sound.

## Commands

Run the editor:

```bash
godot --editor --path .
```

Run the game (main menu; see "Command-line flags" below for the other entry points):

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

Run the M2 end-to-end acceptance scenario (~120 s, exits non-zero on failure). Most
criteria run a scripted hot-seat match -- a single-process scripting convenience, not a
turn-taking rule claim -- except the placement-cadence criterion, which needs
`hot_seat = false` to exercise the real fixed-interval release lock:

```bash
godot --headless --path . res://tests/bench/m2_acceptance.tscn
```

Run the M3a end-to-end acceptance scenario (1 headless host + N-1 headless clients play a
scripted match over ENet; see "Local multiplayer without a second PC" above):

```bash
tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02
```

Run the physics, territory and networking benchmarks:

```bash
godot --headless --path . res://tests/bench/bench_tower.tscn
godot --headless --path . res://tests/bench/bench_rain.tscn
godot --headless --path . res://tests/bench/bench_territory.tscn
godot --headless --path . res://tests/bench/bench_snapshot.tscn
```

### Command-line flags

`game/Main.gd` reads these after `--` (`godot --path . -- --host`, etc.), the same
convention `OS.get_cmdline_user_args()` uses:

| Flag | Effect |
|---|---|
| `--hot-seat` | Skips the menu and lobby entirely; starts M2's two-player, one-PC build. |
| `--host` | Hosts on `net_config.tres`'s `game_port` (or `--port=`) and opens the lobby. |
| `--headless-host` | Same as `--host`, for a dedicated/scripted host with no window. |
| `--join=<ip[:port]>` | Joins that address and opens the lobby. |
| `--port=<n>` | Overrides the port for `--host`/`--headless-host`/`--join`. |
| `--sim-lag=<ms>` / `--sim-loss=<0..1>` | Simulated one-way lag / packet loss from launch, the same sliders the F3 overlay controls. |

With no flag, `Main` shows the main menu and these are chosen through Host/Join instead.

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
| `autoload/` | `Events` signal bus, `Settings`, `Net`, `Match`, `SnapshotSync`, `MatchNet` singletons |
| `config/` | Tunable values as `Resource` files — no magic numbers in code |
| `core/` | Pure rule logic (territory, feed, win check, net wire packing), no scene tree, unit-tested |
| `game/` | Scenes and scripts for the field, blocks, specials, controllers, `Main` (the router) |
| `net/` | `SnapshotSync`, `Interpolator`, `MatchNet` (RPCs), `LanDiscovery` |
| `ui/`, `vfx/`, `sfx/`, `shaders/` | Presentation — `MainMenu`, `Lobby`, `NetDebugOverlay` live in `ui/` |
| `tests/unit/`, `tests/bench/` | Unit tests and physics benchmark scenes |
| `tools/` | Build-time scripts that are not part of the running game |
