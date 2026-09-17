# CLAUDE.md

## Project
A remake of Bontãgo (2003): a physics-based, competitive block-stacking territory game built in Godot 4.6+ with Jolt physics. It supports 2–8 players, online over Steam and on LAN.
**The full spec is `docs/SPEC.md`. Read the relevant sections before starting any milestone.** Where this file and the spec disagree, the spec wins.

## How to work
- Build **one milestone at a time** (spec Part 4). Don't start the next milestone until the current one's acceptance criteria pass and I've confirmed.
- Within a milestone, work in small steps that each leave the game runnable. Commit after each working step with a clear message.
- For any rule tagged [ORIGINAL] in the spec, ask me before changing it.
- If something in the spec is ambiguous, pick the simplest reasonable option, write a `// DECISION:` comment at that spot in the code, and list it in your summary.
- End every task with a short summary covering what changed, how to test it, and any decisions or open issues.

## Tech rules
- Godot **4.6+**, Forward+ renderer, `physics/3d/physics_engine = Jolt Physics`, 60 physics ticks per second, physics interpolation on.
- GDScript with **static typing everywhere** (typed variables, parameters, and return values). Treat warnings for untyped declarations as errors.
- **No magic numbers.** Every tunable value belongs in a `Resource` under `res://config/`: `MatchConfig`, `PhysicsTuning`, `BlockShape`, `SpecialDef`, `MapDef`.
- Keep pure rule logic (territory, connectivity, win check, block bag) in `res://core/` with no dependence on the scene tree, and cover it with unit tests.
- Use a global signal bus (`Events` autoload) to decouple systems. Don't have deep node paths like `get_node("../../..")`.
- **All input goes through the Input Map.** Every action needs both a keyboard/mouse binding and a gamepad binding. Never check raw keycodes in code.
- **Multiplayer:**
  - The host is authoritative, and only the host runs physics.
  - Clients send intents. The host checks every intent before acting on it.
  - Gameplay code uses only `MultiplayerAPI` and must never assume a transport. Use ENet for LAN, direct IP, and tests, and Steam (GodotSteam, app ID 480 during development) for online play.
- Don't add third-party addons without asking. GodotSteam is already approved.

## Commands
- Run the editor: `godot --editor --path .`
- Run the game: `godot --path .`
- Headless unit tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`, adjusting if a different test framework is chosen in M0.
- Headless bot match (from M5 onward): `godot --headless --path . -- --headless-host --bots=8`
- Multiplayer testing: in the editor, Debug → Customize Run Instances → 2–4 instances.

## Folder layout
Follow spec §3.2. New scenes go next to their scripts, and shaders go in `res://shaders/`.

## Definition of done (every task)
- [ ] The project opens without errors, and there are no new warnings.
- [ ] Unit tests pass.
- [ ] The feature works with mouse and keyboard **and** with a gamepad, where relevant.
- [ ] From M3 onward, it works for a client over ENet with simulated lag.
- [ ] The summary includes steps to test it by hand.
