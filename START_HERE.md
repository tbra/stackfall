# Start here

## 1. Setup checklist (about 20 min, before opening Claude Code)
- [ ] Install **Godot 4.6+ (standard build, not .NET)** from godotengine.org. Put the `godot` command on your PATH, or note the full path to it.
- [ ] Install **Steam** and log in. You'll need it for M3b.
- [ ] Have **a gamepad** connected, Xbox or PlayStation.
- [ ] Create the repo:
  ```bash
  mkdir stackfall && cd stackfall && git init
  mkdir docs
  # copy BONTAGO_REMAKE_SPEC.md -> docs/SPEC.md
  # copy CLAUDE.md -> ./CLAUDE.md
  git add . && git commit -m "Spec and project instructions"
  ```
- [ ] Start Claude Code in the repo folder: `claude`
- [ ] Optional: a private GitHub repo as a remote for backups.
- [ ] Optional: for testing online play later, a second PC or a friend with Steam.

## 2. Assets to collect later (for M7, no rush)
- **Skies:** Poly Haven HDRIs (CC0), for example sunset, overcast, and clear sky.
- **Sound effects:** Kenney.nl (CC0) impact and UI packs, and freesound.org (check each file's license).
- **Fonts:** Google Fonts, for example Inter for the UI and a rounded display font for the title.
- **Button prompt icons:** Kenney "Input Prompts" (CC0).
- **Music:** Something calm and atmospheric, like the original. Use royalty-free tracks or commission them.

## 3. Prompts to paste (one at a time)
Wait until each milestone passes its acceptance criteria before sending the next prompt. If something is off, give feedback in the same session first.

### M0
> Read CLAUDE.md and docs/SPEC.md in full. Then do milestone M0: create the Godot 4.6+ project using the §3.1 settings and the §3.2 folder layout. Set up the autoloads (empty stubs are fine) and the Input Map with every action from §2.5, including gamepad bindings. Set up a unit test framework with one passing sample test, plus .gitignore and .gitattributes. Stop and give me a summary when you're done.

### M1
> Do milestone M1 from docs/SPEC.md. Start with the BlockShape resources and the block factory, then the static disk and camera rig, then the ghost preview with 24-orientation rotation, free rotation, and reset, then placing blocks and the kill plane, then the benchmark scenes. Both input devices must work. Show me how to run each benchmark.

### M2
> Do milestone M2. Write TerritorySolver in res://core with unit tests **first** (overlap, connected to home, cut-off towers, teams, contested areas), then connect it to the game: territory raster and shader, holes including the hole_mode setting, placement validation, block feed and timer with auto-drop, next-block preview, goal flag capture, win check, and a basic HUD. Local hot-seat with 2 players.

### M3a
> Do milestone M3a: build the Net.gd transport abstraction with ENet first. Lobby, LAN discovery, direct IP, host-authoritative physics, snapshot sync following §3.4 (quantized, only bodies that are awake, keyframes), client interpolation, intent RPCs checked on the host, ghost cursors for other players, disconnects. Add a debug overlay showing ping, snapshot size, and interpolation delay, and a way to simulate lag and packet loss.

### M3b
> Do milestone M3b: add GodotSteam and SteamMultiplayerPeer using app ID 480. Steam lobbies with match settings stored as lobby data, invites and joining through the overlay, a build version check, and falling back to LAN and direct IP when Steam isn't running. Tell me exactly which GodotSteam build to install and how to test with two PCs.

### M4
> Do milestone M4: gift crates, claiming them, the special feed, throwing with an arc preview (mouse and gamepad), arming and triggering, the chain cap, and the tilt controller. Implement the specials in this order, one commit each: bomb, rocket, anvil, fan, earthquake, volcano. Run the volcano-chain benchmark.

### M5
> Do milestone M5: BotController following §2.9 with 3 difficulty levels, bots available in the lobby, and the headless 8-bot command-line mode. Run a headless soak match and report the results.

### M6
> Do milestone M6: teams, sandbox with its tools, tutorial, turn-based mode, match timer and sudden death, map variants, PHYSICAL_BALANCE tilt mode, every lobby setting from §2.8, and the user settings screen (graphics presets, rebinding for both devices, audio, custom music folder).

### M7
> Do milestone M7, presentation polish, following §2.10. Before you write any code, propose an art direction in a short list (palette, block and disk material look, sky themes, how the UI looks) and wait for my approval.

### M8
> Do milestone M8: the extra specials (magnet, freeze, glue, gravity well), freezing of stable blocks, the body cap and cleanup, reconnect and late join, a 2-hour bot soak test, and export presets for Windows, Linux, and macOS.

## 4. Useful mid-session prompts
- "Something's wrong: [describe it]. Find the root cause before changing any code, and explain it in 3 lines."
- "Run the tests and the benchmark, and report the numbers."
- "Summarize every DECISION comment made so far."
- "Physics feels floaty or jittery: [describe it]. Suggest 3 changes to PhysicsTuning values, and only apply them after I pick one."
