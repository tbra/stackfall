> Historical research on the original Bontago (2003), moved verbatim from docs/SPEC.md Part 1 (Bontago-gmu.2, 2026-10-14).
> It is no longer a design gate: Stackfall is its own game and docs/SPEC.md is the design reference.

## PART 1 — Research: the original game

### 1.1 Facts
- **Title:** Bontãgo (also written "Bontago")
- **Release:** DigiPen's [game gallery](https://games.digipen.edu/games/bontago) records May 1, 2003. Later releases must not be assumed mechanically identical.
- **Developer:** Circular Logic: Eric Anderson, Jason Bolton, Tristan Hall and Justin Kinchen. The [2004 interview](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/) identifies Jason as technical director and Eric as graphics programmer; DigiPen's current page labels Eric technical director. Preserve the attribution difference rather than silently choosing one.
- **Awards:** DigiPen confirms the 2004 IGF Innovation in Game Design win and Open Category finalist status. [DigiPen showcase](https://www.digipen.edu/showcase/student-games/bontago).
- **Development:** The team reported seven months plus cleanup, Tokamak physics after trying ODE, and a networking rewrite. [Developer interview](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/).
- **Tilt:** Ordinary block weight was originally intended to balance the board continuously, but that feature was abandoned; specials tilted the shipped board instead. This supports specials-driven tilt, **not** a particular spring equation, tilt angle or return time. The interview discusses possible future maps, specials and a turn-based mode; these are not evidence that those features shipped. [Developer interview](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/).

### 1.2 Core rules — evidence and limits

**[ORIGINAL, preserved description]** Home flags supply initial circles around a disk. Players place randomly supplied cube-based shapes within their controlled area. Structure height perpendicular to the disk expands influence; victory requires one continuous area containing all world flags. The preserved text explicitly describes holes at opposing territory overlaps. It does not specify their collision geometry, lifetime or exact ownership formula. [Description mirror](https://fileplanet.download.it/p-18772/Bontago).

**[ORIGINAL, developer explanation]** On March 15, 2004, developer Vulcan/Eric described fixed placement intervals: an early drop gives the next piece for preparation, but it cannot be released until the next interval. Expiry forces release. This is simultaneous real-time play, not players taking alternate turns. The post does not establish network clock synchronization. [Release thread](https://gamedev.net/forums/topic/177069-bontago/).

**Fidelity decision:** the owner's later instruction to prioritize concrete original evidence adopts the documented timer in §2.4 and restores overlap holes as the default target in §2.2. Earlier immediate-timer/no-overlap proposals remain documented alternatives, not the original rules. The capture hold (5 s since owner playtest 2026-10-03; previously 3 s) is an explicitly retained remake exception.

**[ORIGINAL, installed tutorial]** The owner-installed executable advertises version 1.1. Its embedded tutorial confirms timer locking, overlap sinking, height-based influence, allied placement and the all-white-flags objective. Its menu documents a configurable requirement to connect influence to the home flag for dropping. See [installed-file evidence, offsets and hash](../ORIGINAL_INSTALL_EVIDENCE.md). This is direct textual inspection, not a gameplay test.

**[REPORTED]** Tower-top ownership tricks, exact default timers and invalid-drop rejection behavior in the earlier draft still lack sufficiently specific evidence. Do not derive an exact height-credit algorithm or auto-drop relocation rule from them.

### 1.3 Gifts / specials — evidence and limits

**[ORIGINAL, preserved description]** Enclosing a randomly dropped gift box awards a special as the next piece; impact activates it. Volcano, earthquake and rocket are named. Exact thresholds, queues, targeting and fuse behavior are not supplied. [Description mirror](https://fileplanet.download.it/p-18772/Bontago).

**[REPORTED]** Contemporary players describe throwing specials beyond territory, normal-block throwing in sandbox, and chain reactions. The review names rockets, volcanoes, earthquakes and a tilting anvil. These accounts do not establish the precise behaviors or numbers in §2.6. [JayIsGames review/comments](https://jayisgames.com/review/bontago.php).

**[ORIGINAL, installed tutorial/menu]** Seven documented types are **DaBomb/Bomb, Volcano, Earthquake, Propeller, Anvil, Rocket and Jumping Bean**. Rocket launches upward and explodes after its fuel is spent; Earthquake helps level the field; Propeller rises and tilts it; Jumping Bean creates a hole between random hops. The earlier homing Rocket, proximity-mine Bomb and horizontal-blowing Fan were unsupported reconstructions. §2.6 now follows the installed descriptions. [Artifact evidence](../ORIGINAL_INSTALL_EVIDENCE.md).

The options describe **gift spawning probability per turn**, plus separate probabilities for the seven types. A seconds-based spawn interval and a specific 0–100 mapping were not recovered from this binary's text.

### 1.4 Modes & options [REPORTED unless stated otherwise]
The following inventory is retained from the earlier research; it is not a verified list of original defaults/ranges. Sandbox is also named in the preserved description. [JayIsGames review/comments](https://jayisgames.com/review/bontago.php); [MobyGames](https://www.mobygames.com/game/13746/bontago/).
- **Modes:** Solo against AI, multiplayer, sandbox (free building with no rules), and tutorials (including a "misc" section).
- **Players:** Up to 8 total, so you plus 7 opponents. Free-for-all or teams. Any mix of humans and AI.
- **Multiplayer:** LAN and direct-IP join are confirmed by installed menu text. Ready/team controls and pre-game chat also exist, so the earlier blanket "no lobby" claim was wrong. A public matchmaking service is not established. [Artifact evidence](../ORIGINAL_INSTALL_EVIDENCE.md).
- **Game setup options:** Number of opponents, gravity strength, number of goal flags, special frequency, gifts on or off, block timer, and map size (a "largest map" is mentioned).
- **Music:** Installed tutorial confirms custom music paths and Control-modified shortcuts: Ctrl+R for shuffle and Ctrl+L for looping. [Artifact evidence](../ORIGINAL_INSTALL_EVIDENCE.md).
- **HUD:** Shows tower height as a number. Players quote heights like 87 and 102.93.

### 1.5 Original controls [REPORTED; verify against the relevant build's tutorial]
Do not treat this historical key list as the remake's binding contract; §2.5 owns that. Player comments corroborate the middle-button/Home reset and throwing, not every mapping below. [JayIsGames](https://jayisgames.com/review/bontago.php).
- The mouse moves the held block over the field.
- A and S rotate the block. Tapping the middle mouse button rotates it by 90°. There was also a free-rotate mode.
- Q levels the block, and holding the middle mouse button and pressing Home resets the block to its original orientation.
- Mouse flick throws a special.
- The camera used all three mouse buttons.

### 1.6 Reported appeal (qualitative notes, not rule evidence)
- Stacking felt satisfying and physical, with a real sense of weight and balance.
- The core tension was whether to build one tall tower (fast, fragile) or a network of shorter, sturdier towers (slow, safe). The best strategy was a mix.
- Chaos: tilting boards, volcano chains, and towers collapsing. It was a huge amount of fun in multiplayer and with teams.
- Sandbox building: dominoes, silly structures, and height records.
- Visuals: reflective floor, smooth slightly glowing blocks, shadows, and large skyboxes.

### 1.7 Reported problems and proposed remake responses
Retained qualitative notes from the earlier draft, not a verified defect list for every original version. Proposed responses are design ideas, not guarantees of fixes.

| Problem | Remake fix |
|---|---|
| Rotation drifted until blocks sat lopsided, and was hard to recover | Snap to 90° by default, free rotation behind a modifier key, one-key reset (§2.5) |
| Frame rate collapsed with many specials or a crowded board | Jolt physics, sleeping bodies, cap on active bodies, pooled effects (§3.5) |
| Game slowed down after a few minutes as blocks piled up | Remove fallen blocks, freeze old stable blocks as static (§3.5) |
| Crashes: on startup, when a song ended, and in network play | Rely on Godot's audio and networking instead of custom code |
| Games lasted 4 hours with no winner | Optional match timer and escalating sudden death (§2.8) |
| Gifts felt too random, and the anvil hurt everyone | Tunable weights per special, more targeted specials, better throw aiming (§2.6) |
| Throwing was hard to discover and hard to judge | Arc preview while aiming, clear territory edge at the cursor (§2.5) |
| No verified public matchmaking service; original has pre-game setup/chat | Modern Steam lobbies plus LAN discovery and direct IP (§3.4) |
| Only one real strategy once learned | Map variety (odd-shaped tables were planned for 2.0), team modes, special variety |

### 1.8 Sources
- [Installed Bontago 1.1 textual evidence](../ORIGINAL_INSTALL_EVIDENCE.md): executable SHA-256, byte offsets and paraphrased tutorial/menu findings, inspected read-only on 2026-09-20. Stronger evidence than secondary accounts where they conflict, but not a runtime behavioral test.
- [DigiPen showcase](https://www.digipen.edu/showcase/student-games/bontago) and [game gallery](https://games.digipen.edu/games/bontago): primary institutional sources for credits, date, awards and broad premise; not detailed rulebooks.
- [GameDev.net developer interview, March 9, 2004](https://www.gamedev.net/tutorials/industry/interviews/circular-logic-r2060/): primary developer testimony, especially shipped versus abandoned tilt behavior.
- [GameDev.net release thread, 2003–2004](https://gamedev.net/forums/topic/177069-bontago/): developer Vulcan/Eric's March 15 timing explanation; August 28 player bug report and developer response concerning overlaps/falling blocks. Bug reports are not idealized rules.
- [Preserved developer-description mirror](https://fileplanet.download.it/p-18772/Bontago): useful historical wording, but third-party hosting and an unspecified build, not an inspected original manual.
- MobyGames: https://www.mobygames.com/game/13746/bontago/
- JayIsGames review and comments, 2007: https://jayisgames.com/review/bontago.php
- GameFAQs review, 2009: https://gamefaqs.gamespot.com/pc/919886-bontago/reviews/137421
- Unknown Worlds forum thread, 2004 (includes a developer post): https://forums.unknownworlds.com/discussion/69613/bontago

Audit date: 2026-09-20. DigiPen, the interview, release thread, description mirror and JayIsGames were inspected. MobyGames returned an access error; GameFAQs and remaining legacy citations are retained leads, not newly verified evidence. Secondary reviews and comments establish reported observations only. The older draft's exact numerical defaults, controls and special-effect details remain provisional where no specific evidence is attached. Owner requirements are separately sourced to [the owner's feedback](../bloody_mess.md) and the decision record at the end of this document.
