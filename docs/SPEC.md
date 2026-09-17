# Bontãgo Remake — Design & Technical Spec (Godot 4)

> Hand-off document for Claude Code. Part 1 is research on the original game, taken from archived sources. Part 2 is the design for the remake. Part 3 is the technical architecture. Part 4 is the build plan with acceptance criteria.
>
> Each rule is tagged by where it comes from:
> - **[ORIGINAL]** is confirmed by one or more sources on the 2003 game.
> - **[RECONSTRUCTED]** is my best reading of vague or incomplete source descriptions.
> - **[NEW]** is a design decision for the remake.
>
> **Instructions for Claude Code:** Work milestone by milestone (Part 4). Every milestone must be runnable and playable before you start the next one. Put tunable numbers in config resources and never hard-code them. Ask before changing a rule tagged [ORIGINAL].

---

## PART 1 — Research: the original game

### 1.1 Facts
- **Title:** Bontãgo (also written "Bontago")
- **Release:** May 2003, free for Windows. Version 1.1 came later. There was a "Lite" build of about 4 MB with no backgrounds or music, and a full build of about 23 MB.
- **Developer:** Circular Logic, a team of four DigiPen Institute of Technology juniors. Eric Anderson did the graphics engine, Jason Bolton was programmer and tech director, Tristan Hall was producer and programmer, and Justin Kinchen was designer, artist, and programmer.
- **Awards:** At IGF 2004 it won "Innovation in Game Design" and was a finalist in the Open category. It was the first student game to win a professional-level IGF award.
- **Development:** About 7 months alongside school, plus about 2 months of cleanup. The budget was $79, spent on Terragen (skybox and landscape rendering). They wrote a design document and a technical design document. The technical design document went out of date quickly.
- **Physics:** They used the Tokamak physics library, which was optimized for stacking. They tried ODE first and found it too slow for large systems. Before that they tried to write their own physics engine and gave up. They had to work around several Tokamak bugs, and tuning the physics was the hardest part.
- **Networking:** Network play made the physics integration difficult. The first network game crashed. The programmer threw out all the networking code and rewrote it from scratch.
- **Scrapped feature:** The board was originally meant to balance continuously on its center based on where block weight sat. The physics couldn't handle more than 5 or 6 blocks doing this, and it wasn't fun. They replaced it with special blocks that tilt the board manually.
- **Plans for 2.0 that never shipped:** Odd-shaped tables, levels, new special blocks, a turn-based mode, better AI, and "flawless multiplayer". The designer said huge towers wouldn't be as easy to build in future versions.

### 1.2 Core rules [ORIGINAL]
From the official developer description and player accounts:

1. **Field:** A large disk, called "the field", floats in the sky and is balanced on a fulcrum at its center. It looks translucent or glassy and reflective, with 360° sky backgrounds. Water or landscape is visible far below.
2. **Start:** Each player has a colored flag. The flags are spaced evenly around the edge of the disk. Each flag has a circle around it that marks that player's controlled area.
3. **Block feed:** Every few seconds a block appears on each player's cursor. You can place it at any time before the timer runs out. If you're still holding it when time is up, it drops on its own wherever it is and the next block replaces it. The default timer is about 5 seconds and can be changed at game start. Players mention 6 seconds as a comfortable setting. The next block is shown in a Tetris-style preview.
4. **Placement restriction:** You can only drop blocks inside your own controlled area.
5. **Territory growth:** The radius of your controlled area depends on how tall your structures are, measured perpendicular to the disk. Taller means a bigger area, so you have to build both up and out.
6. **Height credit:** Players report "stealing credit" for someone else's tall tower by placing a single block on top of it. This means influence comes from the height of each player's own blocks, not from who built the tower underneath.
7. **Collisions between territories:** Where two opposing players' controlled areas overlap, a hole forms in the disk in the overlapping region. Blocks dropped into an overlapping area are thrown off the map.
8. **Win condition:** You win by being the first player whose single continuous controlled area contains the world flag or flags. In the default setup this is one white goal flag in the center. The number of goal flags can be changed.
9. **Blocks:** Blocks are handed out at random in semi-random shapes. The base unit is a cube, and the other shapes are combinations of cubes. The team added more shapes late in development.
10. **Losing blocks:** Towers fall over, and blocks slide off the edge of the disk and are gone.

### 1.3 Gifts / specials [ORIGINAL]
- **Gift boxes** (crates) drop onto the map at random during play.
- If your controlled area expands to enclose a gift box, the next block you receive is a **special block**.
- **Activation:** You activate a special by smashing it, meaning it hits something hard enough.
- **Gamepad parity** [NEW, equal priority with mouse and keyboard]:
- Every action and every menu must be fully usable with a gamepad. Test with both Xbox and PlayStation layouts.
- Define all bindings in the Input Map and never check keys directly in code. Key rebinding covers both devices.
- **Ghost movement:** The stick moves the ghost cursor across the field in world space, relative to the camera. Speed scales with camera zoom, with acceleration and a small dead zone.
- **Snapping aid:** Holding a modifier makes the ghost snap to the tops and edges of nearby blocks, so building precisely is as easy as with a mouse.
- **Throw aiming:** Aim with the right stick. The arc preview is shown, and holding the trigger sets strength.
- **Button prompts:** The UI shows the correct button icons and switches automatically based on the last device used.
- **Local play:** Multiple gamepads on one PC are out of scope for v1, but nothing should prevent adding split-screen later.

**Throwing:** Specials can be thrown outward, even beyond your own territory, to hit other players. You throw by flicking the mouse in a direction and letting go before the cursor leaves your territory. In normal games only specials can be thrown. In sandbox mode ordinary blocks can be thrown too.
- **Chain reactions:** A special's effect can knock blocks into other crates or specials and set them off, producing chaotic cascades.
- **Gifts can be turned off.** They're on by default. A "special frequency" setting exists, apparently on a 0–100 scale, and players warn that volcano chain reactions get out of hand above about 60.

The following specials are named in sources. The list is incomplete, since the developer description ends with "and other blocks".

| Special | What sources say |
|---|---|
| Volcano | Shoots fiery orbs that can hit other specials and set them off |
| Earthquake | Shakes the whole field |
| Rocket / Missile | Attacks opponents' stacks directly |
| Bomb | Works like a mine and explodes when triggered |
| Anvil | Very heavy; tilts the whole arena, knocking down everyone's towers including your own |
| Fan | Tilts the board ("tilted by 2 fans") |

### 1.4 Modes & options [ORIGINAL]
- **Modes:** Solo against AI, multiplayer, sandbox (free building with no rules), and tutorials (including a "misc" section).
- **Players:** Up to 8 total, so you plus 7 opponents. Free-for-all or teams. Any mix of humans and AI.
- **Multiplayer:** LAN, or internet by typing in an IP address. There was no lobby or server browser. People found games through IRC.
- **Game setup options:** Number of opponents, gravity strength, number of goal flags, special frequency, gifts on or off, block timer, and map size (a "largest map" is mentioned).
- **Music:** You could point the game at your own MP3 folder. Ctrl+R toggled shuffle and L looped the current track.
- **HUD:** Shows tower height as a number. Players quote heights like 87 and 102.93.

### 1.5 Original controls [ORIGINAL]
- The mouse moves the held block over the field.
- A and S rotate the block. Tapping the middle mouse button rotates it by 90°. There was also a free-rotate mode.
- Q levels the block, and holding the middle mouse button and pressing Home resets the block to its original orientation.
- Mouse flick throws a special.
- The camera used all three mouse buttons.

### 1.6 What players loved
- Stacking felt satisfying and physical, with a real sense of weight and balance.
- The core tension was whether to build one tall tower (fast, fragile) or a network of shorter, sturdier towers (slow, safe). The best strategy was a mix.
- Chaos: tilting boards, volcano chains, and towers collapsing. It was a huge amount of fun in multiplayer and with teams.
- Sandbox building: dominoes, silly structures, and height records.
- Visuals: reflective floor, smooth slightly glowing blocks, shadows, and large skyboxes.

### 1.7 What was broken (fix these in the remake)
| Problem | Remake fix |
|---|---|
| Rotation drifted until blocks sat lopsided, and was hard to recover | Snap to 90° by default, free rotation behind a modifier key, one-key reset (§2.5) |
| Frame rate collapsed with many specials or a crowded board | Jolt physics, sleeping bodies, cap on active bodies, pooled effects (§3.5) |
| Game slowed down after a few minutes as blocks piled up | Remove fallen blocks, freeze old stable blocks as static (§3.5) |
| Crashes: on startup, when a song ended, and in network play | Rely on Godot's audio and networking instead of custom code |
| Games lasted 4 hours with no winner | Optional match timer and escalating sudden death (§2.8) |
| Gifts felt too random, and the anvil hurt everyone | Tunable weights per special, more targeted specials, better throw aiming (§2.6) |
| Throwing was hard to discover and hard to judge | Arc preview while aiming, clear territory edge at the cursor (§2.5) |
| No lobby; online play needed a typed IP | LAN auto-discovery plus direct IP (§3.4) |
| Only one real strategy once learned | Map variety (odd-shaped tables were planned for 2.0), team modes, special variety |

### 1.8 Sources
- DigiPen showcase: https://www.digipen.edu/showcase/student-games/bontago
- GameDev.net interview, 2004: https://gamedev.net/tutorials/industry/interviews/circular-logic-r2060
- Official description (FilePlanet archive): https://fileplanet.download.it/p-18772/Bontago
- MobyGames: https://www.mobygames.com/game/13746/bontago/
- JayIsGames review and comments, 2007: https://jayisgames.com/review/bontago.php
- GameFAQs review, 2009: https://gamefaqs.gamespot.com/pc/919886-bontago/reviews/137421
- Unknown Worlds forum thread, 2004 (includes a developer post): https://forums.unknownworlds.com/discussion/69613/bontago

---

## PART 2 — Remake game design

**Working title:** Use a placeholder such as "Stackfall" rather than "Bontãgo" if the game will ever be shared publicly. The name and assets belong to DigiPen and Circular Logic.

**Scale:** 1 unit = 1 cube edge = 1 m. All numbers below are starting values and should be tuned.

### 2.1 Field
- **Shape:** A disk with radius `field_radius`: 30 on small maps, 45 on medium, 60 on large. [ORIGINAL sizes existed; values are NEW]
- **Structure:** The disk is one rigid body pivoting on a central fulcrum. It has two tilt modes, chosen in game setup:
  - `tilt_mode = SPECIALS_ONLY` (default): **[ORIGINAL]** behavior. The disk is animated rather than simulated. Specials apply tilt impulses to a spring-damper model, and the disk eases back to level. Maximum tilt is 12°, and the return time constant is about 4 s.
  - `tilt_mode = PHYSICAL_BALANCE`: **[NEW]**, the scrapped original idea, now practical on modern hardware. The disk is a RigidBody3D attached to the fulcrum with a joint that allows rotation on two axes. Torque from block weight tilts it, and a restoring spring plus angular damping keeps it controllable. It's a fun, chaotic option and not the default.
- **Holes:** The disk surface is divided into cells so that holes can appear (§3.3).
- **Out of bounds:** Any body that drops below `kill_plane_y = -40` is removed.
- **Map variants** [NEW, based on the planned 2.0 feature]: Round (default), Oval, Ring (with a hole in the middle and the goal flag on a bridge), Twin disks joined by a bridge, and Cross.

### 2.2 Players, flags, territory
- **Start positions:** 2–8 players. Each player's home flag sits at `0.85 * field_radius`, spaced evenly around the edge. [ORIGINAL]
- **Goal flags:** 1 goal flag in the center by default. Setup allows 1–5. Extra flags are placed symmetrically at `0.4 * field_radius`. [ORIGINAL setting; placement NEW]
- **Home circle:** Radius `home_radius = 6`. It always exists while the flag is on the disk. [ORIGINAL]
- **Influence per block** [RECONSTRUCTED]:
  - Each of your blocks that is settled (see below) produces an influence circle.
  - The circle is centered on the block's center of mass, projected onto the disk plane.
  - Its radius is `r = influence_base + influence_k * h`, where `h` is the height of the block's highest point above the disk surface, measured along the disk's normal. That way tilting the disk changes influence, as in the original.
  - Starting values: `influence_base = 1.5`, `influence_k = 0.9`, and `r` is capped at `influence_max = 0.6 * field_radius`.
  - A block counts as **settled** when its linear speed is below 0.15 m/s and its angular speed below 0.3 rad/s for 0.5 s. This prevents falling blocks from briefly flashing influence.
- **Connected territory** [RECONSTRUCTED]:
  - Build a graph where each influence circle is a node, and two circles are connected if they overlap.
  - Your **territory** is the union of all circles connected, directly or through other circles, to your home circle.
  - Circles that aren't connected to your home give no territory. If a tower is cut off, its influence is gone.
- **Height credit:** Blocks belong to whoever placed them, permanently. Putting your block on top of an enemy tower gives you influence at that height. [ORIGINAL]
- **Contested zones:** Areas where two or more territories from different teams overlap are contested. [ORIGINAL]
  - Contested cells become **holes** after `hole_delay = 0.75 s`. [NEW]
  - Blocks resting on holes fall through.
  - `hole_mode` lobby setting [NEW] (the original's rule is unknown):
    - `TEMPORARY` (default): a cell stays a hole while contested and closes 2 s after the overlap ends.
    - `PERMANENT`: holes never close, so the board erodes over the match.
  - Players can't place blocks in contested areas. If a block is released there anyway, it is thrown off the map with a visible "reject" animation. [ORIGINAL]
- **Teams:** Territories of teammates never create holes between them. They merge for the win check.

### 2.3 Win condition
- A player or team wins when one connected territory contains **every goal flag** continuously for `capture_hold = 3 s`. [ORIGINAL win; hold time NEW]
- **Capture display:** A radial progress ring appears on each goal flag while someone is capturing it.

### 2.4 Blocks
- **Rigid bodies:** Every block is one RigidBody3D with a compound shape made of cube BoxShape3Ds. The cube size is 1 m, minus a 0.02 m margin so neighboring blocks don't jam against each other.
- **Mass:** Each cube has a mass of 1.
- **Physics material:** Friction 0.8, bounce 0.05.
- **Shape set:** Every shape is defined as a `BlockShape` resource. [ORIGINAL: base cube plus combinations; the exact original set is unknown]

| id | cubes | notes |
|---|---|---|
| cube | 1 | |
| domino | 2 in a line | |
| bar3 | 3 in a line | |
| bar4 | 4 in a line | tall-tower maker, rare |
| L3 | 3, L shape | |
| L4 | 4, L shape | |
| T4 | 4, T shape | |
| S4 | 4, S shape | |
| square4 | 2×2 flat | stable base |
| slab6 | 2×3 flat | rare, strong base |
| pillar | 1×1×3 upright variant of bar3 | |
| wedge | cube with a 45° slope, drawn as a cube with a sloped collision shape | [NEW] ramps |

- **Weighted random feed:** Weights are set per shape in `BlockFeedConfig`. Use a "bag" randomizer so no player goes long without getting a stabilizing shape. [NEW]
- **Next-block preview:** The HUD shows the next block. [ORIGINAL] You can optionally show the next 3. [NEW]

### 2.5 Controls & placement feel [ORIGINAL base with NEW fixes]

**Held block (ghost):**
- The held block isn't simulated.
- It follows the cursor raycast on the surface under it (disk or existing blocks), hovering `hover_height = 0.3 m` above the first thing it would touch.
- A projected drop shadow and a vertical guide line show exactly where it will land.
- The ghost is tinted in the player's color when the spot is valid, red when it's outside territory or contested, and has a hatched pattern when over a hole.

| Action | Mouse/Keyboard | Gamepad [NEW] |
|---|---|---|
| Move ghost | Mouse | Left stick |
| Place (drop) | Left click | A / Cross |
| Rotate yaw ±90° | Mouse wheel, or A/S | LB/RB |
| Rotate pitch/roll 90° | Middle click / Shift+wheel | D-pad |
| Free rotate | Hold R + move mouse | Right stick while holding RT |
| Reset rotation | Home or F | Y |
| Raise/lower hover | Ctrl + wheel | |
| Throw (specials only in normal play) | Hold right mouse button, drag back to aim, release | Hold LT, aim, release |
| Camera orbit | Hold middle mouse button + move mouse | Right stick |
| Camera zoom | Wheel while not holding a block, or Z/X | Triggers |
| Camera pan | WASD / hold Space and drag | |
| Snap camera to home / goal | 1 / 2 | |

**Rotation:**
- Store rotation as an integer orientation index. There are 24 axis-aligned orientations of a cube.
- Free rotation adds a separate quaternion on top of that. Reset clears the free rotation and sets the index back to 0. This prevents the drift the original had.

**Throwing:**
- While aiming, show an arc preview.
- Throw strength scales with drag distance, capped at `throw_max_speed = 25 m/s`.
- The release point has to be inside your own territory, so show the territory edge clearly near the cursor.

**Auto-drop:** When the timer runs out, the held block drops from its current ghost position. If that spot isn't valid, it drops at the closest valid point. [ORIGINAL]

### 2.6 Gifts & specials
- **Gift crates:** A crate spawns at a random uncontested point every `gift_interval` seconds, with ±40% randomness. The interval is based on the `special_frequency` setting (0–100), for example 20 → 45 s and 100 → 6 s.
- **Crate life:** Crates are physics bodies. They disappear after 60 s if nobody claims them.
- **Claiming:** When a crate is inside your territory, it pops. It shows which player it belongs to, and your next fed block becomes a special. [ORIGINAL]
- **Arming and triggering:** A special triggers on an impact above `arm_impulse`, or when an explosion hits it.
  - Specials become armed 0.4 s after they're released, so dropping one gently doesn't set it off.
  - Specials with no hit within 8 s trigger automatically. [NEW]
- **Chain reactions:** Allowed. [ORIGINAL] Cap them at `max_chain_depth = 4` to keep frame rate stable. [NEW]

| Special | Behavior | Tunables | Source |
|---|---|---|---|
| **Rocket** | After it's released, it locks onto the nearest enemy block within 25 m, flies with continuous collision detection, and explodes on impact | speed 18, radius 3, impulse 14 | ORIGINAL (name) |
| **Bomb** | Lands, sticks, and becomes a mine that explodes when an enemy block comes within 1.5 m or something hits it | radius 3.5, impulse 18 | ORIGINAL |
| **Volcano** | Erupts for 3 s, firing 8–14 burning orbs upward in a cone. Each orb explodes on impact and can set off other specials | orb impulse 6, cone 35° | ORIGINAL |
| **Earthquake** | Shakes the disk for 4 s with random small oscillations in tilt and vertical position. Blocks near the impact point get extra shaking | amplitude 0.25 m / 2.5° | ORIGINAL |
| **Anvil** | Very heavy block (mass 60) that tilts the disk toward where it lands | tilt impulse ∝ distance from center | ORIGINAL |
| **Fan** | Stands where it lands and blows for 5 s. It pushes nearby blocks sideways and tilts the disk away from itself | force 10, range 12 | ORIGINAL (name); behavior RECONSTRUCTED |
| **Magnet** | Pulls enemy blocks within 8 m toward itself for 3 s | | NEW |
| **Freeze** | Makes your own blocks within 6 m static for 20 s | | NEW (defensive, cuts down on luck) |
| **Glue** | Joins touching blocks of yours within 4 m with breakable joints | break force 40 | NEW |
| **Gravity well** | Flips gravity to 30% within 10 m for 5 s | | NEW |

Every special is its own `SpecialDef` resource plus a script, so it's easy to add, remove, or reweight specials. Players can turn individual specials on or off in game setup. [NEW]

### 2.7 Modes
- **Free-for-all:** 2–8 players, humans and AI.
- **Teams:** 2–4 teams.
- **Sandbox:** No timer and no territory limits. Throwing ordinary blocks is allowed, and there's a block picker. Specials can be spawned from a menu. It also has slow-motion, pause-physics, and height-record tools. [ORIGINAL + NEW tools]
- **Tutorial:** 5 short interactive steps: placing, rotating, territory, specials and throwing, and camera.
- **Turn-based** [NEW, a planned 2.0 feature]: Players take turns. Physics settles completely (all bodies asleep, or after 6 s) before the next player's turn starts.

### 2.8 Match settings (lobby)
| Setting | Range | Default |
|---|---|---|
| Map | Round / Oval / Ring / Twin / Cross | Round |
| Map size | S/M/L | M |
| Players / AI count & difficulty | 2–8, Easy/Normal/Hard | 4 |
| Teams | Off / 2 / 3 / 4 | Off |
| Block timer | 3–12 s | 6 s |
| Gravity | 0.5×–2× | 1× |
| Goal flags | 1–5 | 1 |
| Gifts | On/Off | On |
| Special frequency | 0–100 | 35 |
| Enabled specials | checklist | all ORIGINAL ones |
| Tilt mode | Specials only / Physical balance | Specials only |
| Hole mode | Temporary / Permanent | Temporary |
| Match timer | Off / 10–40 min | Off |
| Sudden death | Off/On | On if match timer is set |

**Sudden death** [NEW]: Starts when the match timer runs out.
- Special frequency climbs to 100.
- The disk's edge crumbles inward by 1 m every 10 s.
- The first player or team to reach the win condition wins. If nobody has won when the disk has shrunk to a radius of 8, the player or team with the most territory wins.

### 2.9 AI bots [ORIGINAL feature, NEW implementation]
The AI runs only on the host, and for multiple bots it spreads its thinking across several frames.

**Placement:** Each time a bot receives a block, it samples 40–120 candidate spots. Each spot combines a position in its territory, the orientation (out of the 24) that gives the flattest base, and whether to stack on a block or place on the disk. Each candidate gets a score:
- **Height gained** at that spot, found by raycasting down onto whatever is below it.
- **Progress toward the goal**, i.e. how much closer its territory edge gets to the goal flag.
- **Stability:** The area of contact under the block, and whether its center of mass sits over that contact area. Estimate this with raycasts from the block's footprint cells.
- **Risk:** Distance from enemy territory and from active specials.

**Specials:** A bot throws rockets and bombs at the enemy tower that contributes the most influence. It throws anvils or fans so the tilt pushes blocks toward enemies. If throwing would hurt it more than it gains, it throws the special off the map.

**Difficulty:** Affects how many spots are sampled, a random aiming error, reaction delay, and whether the bot uses defensive specials.

### 2.10 Presentation [NEW, modernizing the original look]
- **Disk:** Frosted glass or polished stone look, with screen-space reflections and a reflection probe for nearby blocks.
  - Territory is drawn by a shader. Each player's area is a soft tint in their color with an animated outline.
  - Contested areas shimmer. Hole edges glow and crackle.
- **Blocks:** Bevelled cubes with a subtle PBR material and an emissive seam in the owner's color. They glow brighter when they're contributing influence.
- **Sky:** Starts with a procedural sky, with support for HDRI panoramas for different themes (dawn, sunset, stormy, night). A cloud layer below the disk made with volumetric fog, and a distant ocean or landscape.
- **Effects:** GPUParticles3D for explosions, lava orbs, dust when blocks land, and debris falling off the edge.
  - Camera shake scales with the size of the impulse, and can be turned off in settings.
  - Blocks that fall off leave a trail and fade out.
- **HUD:** Timer ring around the next-block preview, current max height in meters, territory percentage per player, special indicator, goal capture ring, and a minimap (top-down territory texture).
- **Audio:**
  - Impact sounds vary in volume and pitch with impulse and material.
  - Stacking a block gives a rising "tick" that climbs in pitch with height.
  - Specials have distinct warning sounds.
  - Music is adaptive, getting more intense as someone gets close to capturing.
  - A custom music folder is supported. [ORIGINAL]

---

## PART 3 — Technical architecture

### 3.1 Stack
- **Engine:** Godot **4.6 or newer**, stable release. 4.6 makes Jolt the default 3D physics engine for new projects. Confirm `physics/3d/physics_engine = Jolt Physics` in project settings.
- **Renderer:** Forward+. Include a "Low" graphics preset that turns off SSR, SSIL, and volumetrics.
- **Language:** GDScript with static typing (`@warning_ignore` sparingly, enable `untyped_declaration` warnings).
- **Tests:** GUT or gdUnit4 for pure-logic unit tests: territory math, connectivity, win check, block feed.
- **Platforms:** Windows, Linux, and macOS desktop, distributed through Steam.
- **Plugins:** GodotSteam (from M3b). Keep third-party addons in `res://addons/` and pin their versions.

### 3.2 Project layout
```
res://
  project.godot
  autoload/
    Events.gd            # global signal bus
    Settings.gd          # user settings (graphics, audio, controls), saved to user://
    Net.gd               # NetworkManager: host/join, discovery, peer registry
    Match.gd             # match config + state machine (Lobby, Countdown, Playing, SuddenDeath, End)
  config/
    match_defaults.tres  # MatchConfig resource
    physics_tuning.tres  # PhysicsTuning resource
    blocks/*.tres        # BlockShape resources
    specials/*.tres      # SpecialDef resources
    maps/*.tres          # MapDef resources
  core/                  # pure logic, no nodes where possible -> unit testable
    territory/TerritorySolver.gd
    territory/InfluenceCircle.gd
    feed/BlockBag.gd
    rules/WinChecker.gd
  game/
    Field.tscn / Field.gd          # disk, cells, fulcrum, tilt controller
    Block.tscn / Block.gd          # RigidBody3D, built from BlockShape
    GiftCrate.tscn
    specials/*.tscn + *.gd
    PlayerController.gd            # local input -> intents
    GhostPreview.tscn              # non-physics held block
    BotController.gd
    CameraRig.tscn
  net/
    SnapshotSync.gd                # host->client body state
    Interpolator.gd
    LanDiscovery.gd
  ui/
    MainMenu.tscn, Lobby.tscn, HUD.tscn, Settings.tscn, Tutorial.tscn
  vfx/, sfx/, shaders/
    territory.gdshader, block.gdshader, hole_edge.gdshader
  tests/
```

### 3.3 Territory & holes implementation
- **Data:** `TerritorySolver` takes a list of `(owner_team, center2D, radius)` circles plus the home circles. It returns connected groups for each team.
  - Connectivity is found with union-find over pairs of overlapping circles.
  - Use a spatial hash grid (cell size = `influence_max`) so it doesn't check every pair against every other pair.
- **Rate:** Recompute territory at 10 Hz on the host, not every physics tick.
- **Raster map:** A `territory_res × territory_res` grid (256 for S, 384 for M, 512 for L) in disk-local polar-free Cartesian space.
  - Each pixel stores which team owns it, or a contested flag, or a hole flag.
  - Fill each connected group's circles onto the grid. Pixels with more than one team are contested.
  - Keep a separate float array so each pixel's contested time can build up toward `hole_delay`.
- **Rendering:** Upload the grid as an `ImageTexture` (R = owner id, G = contested/hole alpha) to `territory.gdshader` on the disk. The shader draws soft edges with an SDF-like blur or bilinear sampling plus smoothstep, and discards pixels where holes are.
- **Physics holes:**
  - The disk's collision is built from `cells` (a square grid of `cell_size = 1.0` BoxShape3Ds clipped to the disk shape) inside one body.
  - When a cell's hole state changes, toggle `shape_owner_set_disabled` on that cell's shape.
  - Batch the toggles so there are at most 64 per frame.
  - Wake up any sleeping blocks above cells that change state.
- **Placement validation:** On the host, the cell under the ghost's footprint must be owned by the placing player's team and not contested or a hole.
- **Win check:** For each team, check whether one of its connected groups contains every goal flag position. Use the raster grid for this.

### 3.4 Networking
**Online from the start.** Gameplay code only talks to Godot's high-level `MultiplayerAPI` and never to a specific transport. `Net.gd` picks the transport:

| Transport | Used for | Implementation |
|---|---|---|
| **Steam** (default online) | Internet play with friends, invites, lobbies, NAT traversal through Valve's relay network | GodotSteam (GDExtension or the precompiled editor) plus its `SteamMultiplayerPeer`. Steam lobbies store match settings as lobby data. Friends join through the Steam overlay invite or "Join Game". |
| **ENet** | LAN (auto-discovery), direct IP, local multi-instance testing, headless bot tests | `ENetMultiplayerPeer` |

- **Development app ID:** Use Steam's public test app ID **480** ("Spacewar") in `steam_appid.txt` during development. Your own app ID (paid Steam Direct fee) is only needed before release.
- **Steam startup:** If Steam isn't running, the game still works with LAN and direct IP. Hide the online menu entries and show a notice.
- **Channels:** Use a separate channel for snapshots only if the chosen Steam peer supports channels. Otherwise send snapshots as unreliable packets and tag each with a sequence number.
- **Version check:** Refuse connections when the game build version doesn't match. Compare the version when joining a lobby and during the ENet handshake.
- **Anti-cheat:** Out of scope beyond the host checking every intent (friends-only game).

**Model:** Host-authoritative listen server. The host is also a player. It uses the high-level multiplayer API on top of whichever transport is selected. **Only the host simulates physics.** Clients set every synced RigidBody3D to `freeze = true` (kinematic) and move them by interpolating snapshots. [NEW]

Deterministic lockstep isn't an option, because Godot's Jolt integration doesn't guarantee determinism.

**Channels:**
- **Reliable** (RPCs): lobby, match config, block spawn/despawn, special trigger events, territory raster diffs (sent compressed at 5 Hz), win and end, chat.
- **Unreliable sequenced** (custom packets on their own channel): body snapshots.

**Client → host intents** (RPCs with `@rpc("any_peer", "call_remote", "reliable")`, checked on the host):
- `request_place(slot_id, pos: Vector3, orient_index: int, free_quat: Quaternion)`
- `request_throw(slot_id, pos, orient, velocity: Vector3)`: the host clamps velocity to `throw_max_speed`.
- `update_cursor(pos)`: unreliable, 15 Hz. Only used to show other players' ghosts.

The host checks territory, the timer, and that the slot matches, then spawns the block. The client shows the ghost immediately and plays a small placement effect. If the host rejects the request, the client shows a "reject" effect.

**Snapshots:**
- **Rate:** 30 Hz.
- **Contents per body:** `net_id: u16`, position quantized to int16 per axis over map bounds (≈1–2 mm precision), rotation as a 48-bit "smallest three" quaternion, and a sleeping flag.
- **What to send:** Only bodies that are awake or changed since the last acknowledgement. Every 2 s, send a full "keyframe" for sleeping bodies at a low rate.
- **Disk state:** Tilt quaternion and position offset, sent every snapshot.
- **Size:** 300 awake bodies × ~13 bytes ≈ 4 KB per packet. Split into several packets if needed to stay under ~1200 bytes each.

**Client interpolation:** Render 100 ms behind the host (the delay adjusts to measured jitter), interpolating between the two surrounding snapshots. If snapshots are late, extrapolate for at most 100 ms.

**Late join / reconnect:** Send the full world state in chunks: all bodies, the territory raster, and match state. Match time pauses while a player is joining in lobby-only mode. Mid-match joins can be enabled in settings.

**LAN discovery (`LanDiscovery.gd`):**
- The host broadcasts `{game, version, name, players, max, map, port}` once per second over `PacketPeerUDP` to 255.255.255.255 on port 47777.
- Clients listen and show a list of games.
- Direct IP entry is available as a fallback.
- The default game port is 47778.

**Testing:** Use the editor's "Customize Run Instances" to run 2–4 instances locally. Add a `--headless-host` command-line flag for automated bot-versus-bot soak tests.

### 3.5 Physics tuning (Jolt)
- **Tick rate:** `physics/common/physics_ticks_per_second = 60`. Turn on physics interpolation (`physics/common/physics_interpolation = true`) so rendering stays smooth at high refresh rates.
- **Solver:** Raise Jolt's solver velocity and position iterations from the defaults. Start at 10 and 4, and tune using a benchmark scene with a 40-block tower.
- **Sleep:** Bodies sleep after 0.5 s below the speed thresholds. Wake them when the disk tilts, when something nearby explodes, or when the hole cell under them changes.
- **Stable-block optimization** [NEW]: If a block has been asleep for more than 20 s and isn't touching any awake body, the host switches it to `freeze_mode = STATIC`. It goes back to normal the moment any impulse, tilt, or change in the cells under it happens. When the disk tilts, all frozen blocks within the tilted region wake up, because the disk moving must affect them.
- **Continuous collision:** Rockets, lava orbs, thrown specials, and any body moving faster than 15 m/s use `continuous_cd`.
- **Body limits:**
  - `max_active_blocks = 600`. Beyond that, the lowest-influence blocks that are off the disk or fully buried are removed first, with a visible dissolve.
  - Explosion chains are capped (§2.6).
- **Explosions:**
  - Query bodies in range with `PhysicsDirectSpaceState3D.intersect_shape` (sphere).
  - Apply `apply_impulse` with falloff `(1 - d/r)^2`.
  - Clamp the impulse per body to `max_explosion_impulse`.
  - Wake the bodies it hits.
- **Tilt:**
  - In `SPECIALS_ONLY` mode, the disk is an `AnimatableBody3D` with `sync_to_physics = true`, driven by a critically damped spring on its tilt vector. Blocks resting on it are carried along correctly.
  - In `PHYSICAL_BALANCE` mode, the disk is a RigidBody3D pinned at the fulcrum with a `Generic6DOFJoint3D` or `ConeTwistJoint3D`. It has a restoring angular spring.
- **Gravity:** Multiply the default gravity by the match setting.
- **Materials:** Disk friction 0.9. Blocks as in §2.4. Specials' friction varies with type, for example the anvil is 1.0.
- **Benchmark scenes** (in `tests/bench/`):
  - A tower of 40 blocks that must stay standing for 60 s with no jitter.
  - 300 blocks falling at once, which must hold ≥120 fps on a mid-range PC.
  - A chain of 5 volcanoes, which must never drop below 60 fps.

### 3.6 Key data resources
```gdscript
class_name BlockShape extends Resource
@export var id: StringName
@export var cells: Array[Vector3i]        # cube offsets
@export var weight: float = 1.0           # feed weight
@export var mesh: Mesh                    # optional custom mesh (else generated)

class_name SpecialDef extends Resource
@export var id: StringName
@export var scene: PackedScene
@export var weight: float = 1.0
@export var enabled_by_default: bool = true
@export var arm_delay: float = 0.4
@export var arm_impulse: float = 6.0
@export var params: Dictionary

class_name MatchConfig extends Resource
# all §2.8 settings, serializable to Dictionary for RPC

class_name PhysicsTuning extends Resource
# all §3.5 numbers + influence_base/k/max, hole_delay, etc.
```

### 3.7 Match state machine (host)
`Lobby → Loading → Countdown(3s) → Playing → (SuddenDeath) → End → Lobby`

**Playing loop on the host:**
- **Block feed:** Each player has a feed timer. When it runs out, the held block auto-drops and the next block from the bag is issued. Players with a claimed gift get a special instead.
- **Territory:** Recomputed at 10 Hz. Territory diffs are sent to clients at 5 Hz.
- **Gifts:** A gift spawner runs on its own timer.
- **Win check:** Runs every territory update.

---

## PART 4 — Build plan (milestones)

Each milestone ends with a playable build and passes its acceptance criteria.

### M0 — Project setup (short)
- Create the Godot 4.6+ project and set Jolt, 60 Hz, and physics interpolation.
- Set up the folder layout, autoloads, typed-GDScript warnings, the test framework, and `.gitignore`.
- **Accept:** The project opens and runs an empty scene. A sample unit test passes.

### M1 — Physics sandbox (offline)
- Disk (static for now), camera rig, and block spawning from `BlockShape` resources.
- Ghost preview with drop shadow, 24-orientation rotation plus free rotation and reset, placing blocks, kill plane.
- Benchmark scenes from §3.5.
- **Accept:**
  - You can build a stable 30-block tower, with mouse and keyboard and with a gamepad.
  - Rotation never drifts.
  - The benchmarks hit their targets.

### M2 — Rules & territory (hot-seat, 2 players)
- `TerritorySolver` with unit tests covering overlap, connectivity, being cut off, and teams.
- Territory raster and shader, contested zones, holes (visuals and collision), placement validation, block feed and timer with auto-drop, next-block preview, goal flag, win check, basic HUD.
- **Accept:**
  - Two players take turns on one PC and can win.
  - Holes appear where territories overlap, and blocks fall through them.
  - A tower that gets cut off loses its influence.

### M3 — Multiplayer (ENet, then Steam)
- **M3a:** Transport abstraction in `Net.gd`, ENet host and join, LAN discovery, direct IP, lobby with MatchConfig, host-authoritative physics, snapshot sync with interpolation, intent RPCs, other players' ghost cursors, disconnect handling.
- **M3b:** GodotSteam integration with app ID 480. Create Steam lobbies, invite friends, join through the overlay, use `SteamMultiplayerPeer` for gameplay traffic, and fall back to ENet when Steam isn't running.
- **Accept:**
  - 4 local instances play a full match.
  - A client with 100 ms of simulated lag and 2% packet loss sees smooth towers.
  - Placements are never duplicated or lost.
  - Two PCs on different home networks play a full match over Steam.

### M4 — Gifts & specials
- Gift crates, claiming them, special feed, throwing with arc preview, arming and triggering, chain cap.
- Rocket, bomb, volcano, earthquake, anvil, fan. Tilt controller (SPECIALS_ONLY).
- **Accept:**
  - Every special works in both single-player and LAN.
  - A 5-volcano chain stays ≥60 fps on the host.

### M5 — AI bots
- `BotController` with placement scoring, using specials, and 3 difficulty levels. Mix bots and humans in the lobby.
- **Accept:**
  - A Hard bot beats a passive player in under 10 minutes.
  - An 8-bot headless match finishes without errors.

### M6 — Modes & settings
- Teams, sandbox (with its tools), tutorial, turn-based mode, match timer and sudden death, map variants, PHYSICAL_BALANCE tilt mode, all lobby settings, user settings (graphics presets, key rebinding, audio, custom music folder).
- **Accept:** Every setting in §2.8 changes gameplay as described.

### M7 — Presentation polish
- Block and disk materials, sky themes, clouds, particles, camera shake, sound design, adaptive music, full HUD with minimap, main menu styling.
- **Accept:** Looks and feels good. Holds 144 fps at 1440p with 300 blocks on the High preset on a mid-range GPU (tune as needed).

### M8 — Extra specials & hardening
- Magnet, freeze, glue, gravity well.
- Stable-block freezing, body cap and removal, reconnect and late join, 2-hour soak test with bots, crash-free exports for Windows, Linux, and macOS.

---

## Decisions made
- **Holes:** Unknown in the original, so hole behavior is a lobby setting. Temporary is the default.
- **Online:** Online from the start, over Steam through GodotSteam. ENet is kept for LAN, direct IP, and testing.
- **Controls:** Gamepad has equal priority with mouse and keyboard.

## Still open
1. **Timer:** Was the block timer a shared global timer or separate for each player? Default for now: separate for each player.
2. **Other specials:** Do you remember any beyond volcano, earthquake, rocket, bomb, anvil, and fan?
3. **Territory shape:** Did the original draw influence as circles around each block, or as one circle whose radius came from your tallest point? Default for now: a circle around each block.
