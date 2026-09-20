# Installed Bontago — primary textual evidence

Inspected 2026-09-20, at the owner's request. This is a source record, not a task backlog.

## Artifact and method

- Source: `C:\Program Files (x86)\Bontago\Bontago.exe`, 2,895,872 bytes.
- SHA-256: `9320CF4FA4FA5627A5A8B76FE83924629D0C73ED0F6587ED35156C58EB2E09BC`.
- Embedded version label: `Version 1.1` at file offset `0x0018EC38`. Windows version-resource fields were empty; this label identifies the file's advertised version, not independently verified release provenance.
- Read printable text directly from the binary without executing or modifying it. Offsets below are hexadecimal **file byte offsets**, not virtual addresses. They let another reviewer locate the evidence in this exact file.
- Tutorial/menu text is primary evidence of documented intended behavior. It does not prove the executable follows every statement without bugs. No gameplay session, disassembly or numeric-default decoding was performed.
- `User.ini` is binary despite its extension. Do not parse it as an INI or infer settings from adjacent numeric bytes. Sound filenames corroborate names only; they do not establish mechanics.

## Rules established by tutorial and option text

| Offset | Paraphrased evidence | Spec consequence / limit |
|---|---|---|
| `0x00190928`, `0x0019096B` | Expiry releases the held block; after an early release the next block cannot be placed until the timer finishes | Confirms fixed-window placement lock, not immediate-reset rapid placement. Does not establish cross-player clock phase |
| `0x001908EC`, `0x001908A8` | Placement requires own influence; unavailable held pieces appear black/translucent | Preserve both spatial legality and timer lock as distinct reasons |
| `0x00190AA0` | Pieces placed at overlaps of connected influence from opposing teams sink through the board | Direct confirmation of overlap sinking. Visible mesh removal, whole-body selection, exact collider layout, delays and closure are still unverified |
| `0x00190B00`, `0x00190B60`, `0x00190BB6` | Higher placed blocks generate greater influence; connected areas have a bright border and allow expansion | Does not recover radius law, cap, settled thresholds or a whole-stack ownership algorithm |
| `0x00190C00` | Objective is influence surrounding all white flags | Does not specify capture hold or flag-base sampling geometry |
| `0x0018F9C4`, `0x0018F9E0` | A require-flag-connection option gates whether influence must connect to the player's flag for dropping | Home connection is a configurable original placement rule. Default value and whether disabling it changes win connectivity are not established |
| `0x00190DBE` | Players in teams may build within their teammates' influence as well as their own | Allied placement is directly documented, not merely a remake assumption |
| `0x00190820`, `0x00190856`, `0x001907B8`, `0x00190760` | Specials arrive on the field, can be collected through connected influence, can be mouse-thrown, and activate under substantial impact | Pickup/activation distinction established; storage order, replacement timing and numeric impulse threshold remain unknown |
| `0x0018FC3C` | Gift appearance uses a probability per turn | Replace the supposed original seconds-based spawning interval with a per-window probability target. Trial count per player versus per match remains unknown |
| `0x0018FA29`–`0x0018FB76` | Separate probability controls identify seven gift types | Seven documented types; units, normalization and exact default weights remain unverified |
| `0x00190A1F`, `0x00190A61` | Preview contains next piece/timer; minimap shows controlled areas from above | Confirms those HUD elements |
| `0x00190E28`–`0x00190EE0` | Music shortcuts are under Control, including shuffle and loop toggles | Earlier bare `L` loop claim was incomplete: tutorial places it under Control |

## Documented special roster

These paraphrases replace the earlier speculative homing/mine/fan descriptions. Quantities, trajectories, radii and durations remain tunable reconstructions unless independently observed.

| Name in this file | Description offset | Documented effect |
|---|---|---|
| DaBomb (menu probability text calls it Bomb) | `0x00190599` | Large explosion; no proximity-mine or adhesive behavior described |
| Volcano | `0x001905B6` | Erupts with explosive lava projectiles |
| Earthquake | `0x001905E9` | Shakes the field and helps bring a tilted field level |
| Propeller | `0x00190620` | Rises gradually, tilting the field; not a documented horizontal wind emitter |
| Anvil | `0x00190650` | Adds weight that tilts the field |
| Rocket | `0x00190691` | Launches upward and explodes upon fuel exhaustion; no enemy seeking described |
| Jumping Bean | `0x001906EF` | Moves in random hops and creates a local field hole between hops |

The generic impact activation text precedes these effects conceptually: do not confuse triggering a Rocket with its later fuel-exhaustion explosion. The earlier universal eight-second fallback fuse is not supported by this text.

## Still requires observation or deeper inspection

Goal exclusion zones, home elimination, hole collision/visual details, gift queue behavior, exact influence mathematics and numerical defaults are not established by the strings inspected. Absence from tutorial text does not prove absence from gameplay. Controls tutorial strings interpolate binding names; extracting sentence fragments is not enough to identify their default keys. Keep the 3-second hold as the owner's explicit remake exception.

No original executable, textures, models or audio have been copied into the remake. This record contains identification and paraphrased mechanics only.
