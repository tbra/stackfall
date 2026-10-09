# Stackfall Arcade — component guidelines
Frozen copy of the design system README and component READMEs (2026-10-10). The live design system is the source of truth if they differ.

---

Stackfall's interface is built from the same thing as the game: **blocks**. Every button, card and chip is a coloured face with a lit top edge, a dark lower lip and a solid ledge it sits on, and pressing it pushes it down onto that ledge. Surfaces are cut from the **arena disc**: warm violet-black faces, with the disc's glowing gold rim as the one accent that glows. The painted sky changes constantly (peach golden hour, navy night with aurora, green-grey storm), so the UI never takes its colour from the sky. It stays disc-dark everywhere, and the towers and player colours stay the brightest things on screen.

## Content fundamentals

- Buttons, headings, HUD labels, table headers and callouts are **UPPERCASE** and short: HOST, START MATCH, HELD, NEXT, CAN'T PLACE HERE.
- Setting values, descriptions, tips, player names and table cells are sentence case: "Borderless fullscreen", "Move your cursor over the disc and press LMB to place your held block."
- The voice is direct and second person, with game-show energy for outcomes: "Atlas wins!", "It's a draw!", "Flag captured".
- No emoji in UI copy. State uses ✓ ✕ ★ ♛ inside or beside ink tiles.
- Every input hint is a keycap plus a word, following the last-used device.

## Colour

- **Disc surfaces:**
  - `disc-900`: menu ground and HUD plates (at the `hud-plate` opacity)
  - `disc-800`: panels
  - `disc-700`: rows, fields, dropdowns and HUD cards inside a panel
  - `disc-600`: secondary buttons (`disc-500` on hover)
  - `disc-400`: control edges, 3.0:1
  - `disc-950`: only the ledge under blocks and the dialog and countdown scrims
- **Text on disc:**
  - `cream`: primary text and numbers
  - `sand`: secondary text and labels
  - `dust`: captions and table headers, 13px and up
- **Text on any bright face is `ink`.** Cream fails on `flare`, `rim`, `mint` and every player colour, while ink passes 4.5:1 or better on all of them.
- **`flare` is the single primary action per screen:** Host, Start match, Resume, Play again, Join IP.
- **`rim` is the disc's gold edge.** Use it for the active tab notch, the minimap ring, timer hurry, the winner row, rewards and GO. Never use it for a second primary button.
- **`mint`** is positive state (Ready, enabled chips). **`alert`** is negative and always carries ✕. **`locked`** is the release lock.
- **Players:** `player-1` … `player-8` are exactly `MatchConfig.player_colors`. A player is always shown by their **diamond marker** (*Player markers*), the same crystal as their home beacon in the arena. Red, blue and purple share a lightness, so the colour-assist setting swaps in the `-assist` diamonds, each with a slot mark.

## Type

- **Bungee** (`display`) is for the wordmark, numbers and big moments: `logo`, `timer`, `score`, `countdown`, the results banner, and HUD percentages. Never use it for sentences.
- **Rubik** (`ui`, variable 300–900) is for everything else:
  - `heading`: 24/800
  - `button`: 20/800
  - `button-sm`: 15/800
  - `body`: 16/500
  - `label`: 13/800, 1.2px tracking
  - `caption`: 13/500
- Decisions and prompts are 15px or larger at 1080p. Check every screen at 1280×720 and 3440×1440 (the menu atlas sizes).

## Shape, depth and space

- **The block recipe:** face colour, then a `top` (3px) lit edge (the face mixed 38% toward white), then a `lip` (6px) dark edge (30% toward black), then a `drop` (6px) ledge in `disc-950`. Compact blocks use `lip-sm` and `drop-sm`. The `shadow-block` tokens encode the same recipe.
- **Pressed:** down by `drop`, with `shadow-pressed`. **Disabled:** `opacity: disabled` and no ledge.
- **Wells** (fields, meters, lists, toggle tracks) are sunken: `disc-900` with `shadow-well` and no ledge.
- **Radii:** `radius-cell` 3, `radius-chip` 5, `radius-block` 8, `radius-panel` 12. Nothing is a pill. Only gamepad face-button caps, the timer ring and the minimap are round.
- **Focus** is always a 3px `cream` outline offset 3px, identical on every face.
- **Spacing** is on a 4px grid. Buttons stack `space-3` plus the drop apart. HUD groups are inset `space-5` from the screen edges, and menus `space-7`.

## Screens

The current game screens map onto this system as follows (see the *Screens* previews):

- **Main menu:** the arena keeps playing behind a left `scrim`, replacing the pastel diorama. The left column holds the lockup, the Name field, Host (primary), Join, Play offline, then Options and Quit as small blocks. KeyPrompts sit bottom-right. Join (LAN/IP and Steam) and Local (Vs bots, Sandbox, Tutorial) swap the buttons in place.
- **Lobby:** a title row with a StatusBadge and Back, then Match settings (Dropdowns, SegmentMeters, Toggles, a Stepper, and an Advanced Section that opens ChipToggle grids for gifts, specials and experiments) and a Players panel (PlayerSlots). The footer has the ready count and Start match.
- **Options** (from the menu and from pause): side Tabs for Settings and Controls. Settings rows use group headers (Display, Audio, Rumble). Controls rows are BindingRows with a listening state. The footer has KeyPrompts, Reset to defaults and Back.
- **Loading:** a LoadingCard over the arena.
- **HUD:** Scoreboard top-left, FeedTimer top-centre, HeldNext bottom-left, Minimap bottom-right. The TipBanner and Special queued plate sit under the timer and scoreboard, and Callouts appear near the action. Every group is on a `hud-plate`.
- **Scoreboard (held)** and **Results:** a ResultsTable, plus the banner and Play again / Back to lobby on results.
- **Pause:** a Dialog.
- **Dev tools** (tuning panel, net debug, sandbox): use the same tokens at `caption` size on HUD plates. They aren't designed further; they're developer-only.

## Iconography

- **The mark** is three blocks with a fourth, gold block falling onto the stack. `stackfall-lockup` is for disc grounds and `stackfall-lockup-on-light` is for light grounds.
- **Player markers:** faceted diamonds echoing the home beacon crystal, in plain and colour-assist versions.
- **Icons** are solid, chunky voxel shapes with 2–3px strokes. They're `cream` on disc and `ink` on bright faces. The repo's existing menu, HUD and input glyph art hasn't been redrawn yet; use KeyPrompt caps for inputs until it is.

## Motion

- Blocks move like blocks. Press is 60ms down onto the ledge. Pop-ins drop 8px and land with a one-frame squash. Callouts last about 1.5s.
- The countdown scales from 1.3× to 1× in 120ms per step. Nothing fades slowly.

---

# BindingRow

One action in Options › Controls: the action name, then its bound inputs as KeyPrompt caps.

- **Rows:** alternate rows are lightly banded. The focused row is `disc-600` with the focus outline.
- **Listening:** pressing A or Enter on a row starts listening. The row gets a `rim` edge and reads PRESS A KEY… until an input arrives or Esc or B cancels.
- **Groups:** rows sit under `.sa-group` headers (Placement, Rotation, Camera).
- **The consumer provides:** the action name, its current bindings and the listening state.
- **Footer:** Reset to defaults lives in the footer, never per row.

---

# BlockButton

The game's button is a block: a coloured face, a lit top edge, a dark lower lip, and a solid ledge it sits on. Pressing it pushes it down onto that ledge.

**Variants**
- **Primary** (`flare`): the one forward action on the screen, such as Host on the home screen, Start match in the lobby, Resume in pause, Play again in results, or Join IP in the join flow. Use exactly one per screen.
- **Secondary** (`disc-600`): every other action, such as Join, Play offline, Options, Quit, Back, Refresh and Add bot.
- **Mint**: Ready. **Rim**: reward actions only.
- **Small** (`button-sm`): for rows, the roster, footers and dialogs. Reset to defaults and Back in the options footer are small secondary buttons.

**The consumer provides:** an uppercase label of one or two words, an optional leading icon or cube, and an optional trailing input hint.

**States**
- hover lightens the face
- pressed: `translateY(drop)` and `shadow-pressed`
- focus: 3px `cream` outline offset 3px, identical on every face
- disabled: `opacity: disabled` with no ledge

**Rules**
- Labels on bright faces are `ink`.
- Stacked buttons are separated by `space-3` plus the drop.
- Nothing is a pill.

---

# Callout

A momentary HUD message (about 1.5s) above the cursor or near the top centre.

- **Faces:** `alert` with ✕, `mint` with ✓, `rim` with ★.
- **Text:** uppercase, four words at most.
- **One at a time**, never over HeldNext.

---

# ChipToggle

A grid of on/off chips for the gift and special pool (Anvil, Black hole, Bomb…) and the lobby's experiment flags.

- **On:** a `mint` block with an ink ✓ box.
- **Off:** a `disc-700` block with an empty box.
- **The check box carries the state**, so it never relies on colour.
- **Layout:** two columns in the lobby and three at ultrawide.
- **The consumer provides:** a label, an optional icon from the gift pictograms, and the state.
- **Gamepad:** A toggles the focused chip.

---

# Countdown

The pre-match 3-2-1-GO in Bungee at 128px with an 8px disc drop, on a `disc-950` scrim at the `scrim` opacity.

- **Numbers:** `cream`. GO is `rim`.
- **Motion:** each step scales 1.3× down to 1× in 120ms.

---

# Dialog

A centred modal on a full-screen `disc-900` scrim, used for Pause and confirmations (Leave match? Kick player?).

- **Size:** 340px wide, with `radius-panel`.
- **Heading:** centred `heading`.
- **Actions:** stacked full-width BlockButtons. The forward action (Resume) is primary and gets initial focus.
- **Destructive actions** (Leave match, Kick) are secondary blocks with a `flare` label and always lead to a second confirm.
- **The consumer provides:** a title and an ordered list of actions.
- **Gamepad:** Start or B closes it.

---

# Dropdown

A raised `disc-700` block with a 2px `disc-400` edge and a `sand` chevron. It replaces every OptionButton: game mode, time of day, weather, tilt, holes, graphics preset, window mode and bot difficulty.

- **Value:** `cream` in sentence case.
- **Open list:** a `disc-800` panel of rows. The current row is `disc-600` with a ✓.
- **The consumer provides:** a value and its options.
- **Gamepad:** A opens it, up and down move, A picks, B cancels.

---

# FeedTimer

The top-centre ring showing the seconds left before your held block is forced to drop.

- **Ring:** your `player-N` colour around Bungee seconds in `cream`, on a round HUD plate.
- **Last 2 seconds:** the ring and number turn `rim`, and the countdown tick plays.
- **Locked:** while the fixed-interval release lock holds, the ring is a full `locked` circle and reads LOCKED.
- **Tutorial:** the TipBanner sits directly below the ring, never over it.
- **The consumer provides:** seconds, fraction and lock state.

---

# Field

A sunken text input for the player name, direct IP and lobby code.

- **Style:** a `disc-900` face with a 2px `disc-400` edge (3.0:1), `shadow-well` and `radius-block`.
- **Text:** `cream` at 16px/600, with `dust` placeholders.
- **Focus:** the edge turns `cream` and the outline appears.
- **The consumer provides:** a value or placeholder, plus a label above it in the `label` style.

---

# HeldNext

The bottom-left HUD pair showing the block you hold and the next one.

- **Cards:** two `disc-700` cards on a HUD plate, labelled HELD and NEXT.
- **Shape:** drawn as voxel cells in your colour. The live 3D thumbnails can replace the cells, but keep the card and label.
- **Gift:** when the next item is a gift or special, the label reads NEXT · GIFT in `rim`.
- **Locked:** the cards drop to 60% opacity.
- **The consumer provides:** the held and next shapes (or renders), plus the gift and lock state.

---

# KeyPrompt

The footer input hint used on every menu ("Enter Select · Esc Back", "A Select · B Back · LB RB Tabs"), shown as a keycap block plus an action word.

- **Keyboard caps:** `cream` with an `ink` legend.
- **Pad face buttons:** round caps with ink letters: A `mint`, B `flare`, X `player-2`, Y `rim`.
- **Action words:** `sand`, in the `label` style.
- **Placement:** bottom-right of menu screens, and bottom-left inside options and pause footers.
- **The consumer provides:** the bound input from the Input Map and the action word.
- **Device:** follow the last-used device, and never show both sets at once.

---

# LoadingCard

The centred card while a match loads: the mode name in Bungee, then each player with their diamond and four progress cells that fill in `mint`.

- **Background:** the arena flyover with a light scrim.
- **No spinners.** Progress is always cells.
- **The consumer provides:** the mode and per-player load progress.

---

# Minimap

The bottom-right top-down disc showing every territory and home beacon.

- **Frame:** `disc-900` with a 3px `rim` ring and a soft rim glow. That echoes the arena's own glowing gold edge and is the one place the HUD glows.
- **Contents:** territories in `player-N` colours, your beacon as your diamond marker, and other beacons as small diamonds.
- **Contested goal:** a `rim` arc fills around it as it's claimed.
- **Size:** 168px at 1080p, never under 120px.
- **The consumer provides:** the territory raster, beacon positions and your slot.

---

# Panel

The `disc-800` slab every menu sits in: the home card, the lobby's two columns, options, pause and results.

- **Style:** `radius-panel`, `space-5` padding, a `disc-600` top light, and `shadow-panel` (a solid ledge plus a soft lift off the 3D scene).
- **Header:** an uppercase `heading` led by the flare voxel bullet.
- **The consumer provides:** a heading and rows.
- **Text:** `cream` for names and values, `sand` for labels and secondary values, `dust` for captions.
- **No nesting.** Groups inside a panel use a `.sa-group` rule header ("DISPLAY", "AUDIO", "PLACEMENT") or a Section.

---

# PlayerSlot

One seat in the lobby's Players column: the player's diamond marker, their name and role, and on the right their state or controls.

- **Marker:** the `player-N` diamond from *Player markers*, the same crystal as their home beacon in the arena. With colour assist on, use the `-assist` diamond.
- **Name:** `cream` 16px/700. The host gets ♛. The sub line (Host · you, LAN · 5 ms, AI) is `dust`.
- **Status:** a `mint` ✓ Ready badge or a `disc-500` Not ready badge.
- **Bot rows:** the host sees a difficulty Dropdown and a ✕ remove block.
- **Open seat:** a dashed outline with + Add bot.
- **The consumer provides:** a slot, name, sub line, ready state and whether the viewer is the host.

---

# ResultsTable

The end-of-match card: the mode as a `rim` kicker, the outcome in Bungee ("Atlas wins!", "It's a draw!"), the stats table, and Play again (primary) beside Back to lobby.

- **Table:** each row is a `disc-700` strip with a marker and name on the left and tabular numbers on the right. Headers are `dust` labels.
- **Winner:** the row is tinted toward `rim` with a 4px rim edge. A draw tints no row.
- **Sorting:** sort by territory, then height.
- **The same table** opens mid-match as the held Scoreboard overlay, without the banner or buttons.
- **The consumer provides:** the mode, outcome, and per-player stats.

---

# Scoreboard

The always-on territory list in the top-left of the HUD: one row per player with a diamond marker, name, share bar and percentage.

- **Plate:** `disc-900` at `hud-plate` opacity, so it reads over a peach day sky and a navy night.
- **Bar:** the player's colour on a `disc-700` track with a cut every 10%. That's enough to compare 5% and 12% at a glance without the bar looking empty.
- **Percentage:** Bungee in `cream`. Your own row adds "· YOU" in `rim`.
- **Order:** keep slot order during a match so rows don't jump. Sort only on the results screen.
- **Size:** at 8 players it's about 250px tall at 1080p. Hold Tab or Back for the full Scoreboard table.
- **The consumer provides:** slot, name and share per player, plus which slot is you.

---

# Lobby (screen)

A reference composition of the host's lobby: title, status badge and Back across the top, with Match settings on the left and Players on the right as two Panels over the scrimmed arena.

- **Footer:** the ready count bottom-left, and Start match as the screen's single primary action bottom-right.
- **Advanced:** opens in place as a Section with ChipToggle grids for gifts, specials and experiments.

---

# Main menu (screen)

A reference composition of the home screen over a live arena capture.

- **Background:** the arena keeps playing behind a left `scrim`, replacing the static pastel diorama.
- **Left column:** the lockup, the tagline, the Name field, then Host (primary), Join and Play offline as full blocks, with Options and Quit as small blocks.
- **Footer:** input prompts on a HUD plate, bottom-right.
- **Sub-screens:** Join (LAN/IP and Steam) and Local (Vs bots, Sandbox, Tutorial) replace the column's buttons in place, with Back last.

---

# Match HUD (screen)

The live HUD layout over a day capture, keeping the game's current placement.

- **Top-left:** Scoreboard. **Top-centre:** FeedTimer. **Bottom-left:** HeldNext. **Bottom-right:** Minimap.
- **Callouts** appear near the action.
- **Plates:** every group sits on a `hud-plate`, so the same HUD works on the night and storm skies.
- **Safe area:** groups are inset `space-5` from the edges at 1080p and scale with the UI scale setting.

---

# Section

A collapsible group header inside a panel, used for the lobby's Advanced and Experiments groups.

- **Header:** a `rim` caret (pointing right when closed, down when open), an uppercase label, and on the right a `dust` summary of the current values so the player can read the settings without opening it.
- **The consumer provides:** a label, a summary string and the open state.
- **Gamepad:** A toggles it.

---

# SegmentMeter

A slider drawn as voxel cells, used for volumes, mouse and stick speed, rumble intensity, disc size, block timer and gravity.

- **Cells:** filled cells are `flare` blocks. The current cell has a `cream` outline. Everything sits in a well.
- **Value:** always shown to the right in Bungee (`100%`, `5.0 s`, `1.00×`, `Medium`).
- **Step count:** 10 cells by default. Use more for fine values, but never fewer than 5.
- **The consumer provides:** a label, a value, a step count and a formatted value.
- **Gamepad:** left and right step it.

---

# ServerRow

A row in the LAN or Steam game list (Join › LAN/IP) inside a well, with a Refresh button above.

- **Row:** the game name in `cream`, players/max and ping in `sand` at 13px.
- **Selected:** the face lifts to `disc-600` with the focus outline.
- **Empty list:** one `dust` line reading "Searching for games…" with three pulsing cells. Never leave the well blank.
- **The consumer provides:** a name, players/max and ping.

---

# StatusBadge

A small flat label next to the lobby title (Hosting · LAN, Vs bots, Steam) with a live `mint` dot.

- **Lobby footer:** the "all players ready" state uses the `rim` badge.
- **Badges never take focus.**
- **The consumer provides:** the text and whether the session is live.

---

# Stepper

A small-integer setting with − and + blocks around a Bungee value: goal flags, bots and match minutes.

- **At a limit:** dim the button with `opacity: disabled`.
- **The consumer provides:** a label, min, max and step.
- **Gamepad:** left and right step it.

---

# Tabs

Navigation between sections of one screen. There are two forms.

- **Side tabs:** used for Options (Settings and Controls), left of the content. The active tab is `disc-600` with a 4px `rim` notch on its left edge.
- **Top tabs:** used for the lobby's advanced rules and the dev tuning panel. The active tab merges into the panel below and carries a `rim` notch on top.
- **Labels:** uppercase.
- **Gamepad:** LB and RB cycle tabs. Show those keycaps in the footer.

---

# TipBanner

A tutorial and contextual hint centred under the timer ring, with the SpecialQueued chip beside it.

- **Style:** a HUD plate with a `rim` step block (1/5), then a sentence in `cream` 16px with inline KeyPrompt caps for the inputs.
- **Length:** one sentence and 640px at most. It must never cover the timer.
- **Special queued:** a small plate under the scoreboard with a `rim` label and the special's name.
- **The consumer provides:** the step index and total, the text with input tokens, and the queued special.

---

# Toggle

An on/off switch for camera shake, adaptive quality, rumble, sudden death, teams, turn-based and allow joining mid-match.

- **Knob:** a block sliding in a well. It turns `mint` when on.
- **The ON/OFF word is required.**
- **Placement:** in a settings row, the toggle sits in the control column.
- **The consumer provides:** the setting name.
