# Stackfall

A physics-based, competitive block-stacking territory game for 2–8 players, online over
Steam and on LAN. It is a remake of **Bontãgo** (Circular Logic, 2003); "Stackfall" is a
placeholder name, because the original name and assets belong to DigiPen and Circular Logic.

Built in Godot 4.7 (Forward+, Jolt physics). The full design and technical spec is
[docs/SPEC.md](docs/SPEC.md); working rules for the project are in [CLAUDE.md](CLAUDE.md).

## Status

**M0 — project setup.** The project boots into an empty scene. No gameplay yet.

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
