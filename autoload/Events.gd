extends Node
## Global signal bus.
##
## Systems emit and connect here instead of reaching through the scene tree,
## so nothing needs deep node paths like get_node("../../..").
## Signals are added as each milestone needs them; M0 ships the bus empty.

## M1: a block became a live physics body, either placed by a player or
## auto-dropped when its feed timer ran out.
signal block_placed(block: RigidBody3D, shape_id: StringName)

## M1: a block left the simulation (kill plane for now; despawn/body-cap
## reasons arrive later). `reason` is a short machine-readable tag; use the
## REASON_* constants below rather than a string literal so it can't drift.
signal block_removed(block: RigidBody3D, reason: String)

## game/Field.gd: a block fell below tuning.kill_plane_y, or (Bontago-1pi.11.41)
## dissolved on a hole, which counts exactly like an edge fall.
const REASON_KILL_PLANE: StringName = &"kill_plane"

## Bontago-t8x.5: a gift body whose action completed was despawned. Not a
## kill: no edge-fall burst, no blocks_lost stat.
const REASON_GIFT_DESPAWN: StringName = &"gift_despawn"

## Bontago-1pi.11.41: `block` touched an applied hole cell at disc level and
## will be removed (block_removed, REASON_KILL_PLANE) after `duration_s`.
## Emitted by game/HoleDissolver.gd on the host and by net/MatchNet.gd on
## clients; presentation only (the A2 fade), never a rule input.
signal block_dissolve_started(block: RigidBody3D, net_id: int, duration_s: float)

# --- M2: match flow (spec 3.7) ----------------------------------------------

## The host's state machine moved. Both arguments are Match.State values.
signal match_state_changed(from_state: int, to_state: int)

## Bontago-1pi.46 (docs/MATCH_RESET_AUDIT.md section 4): a match world is about to
## be built, or was just torn down (host, client, sandbox and tutorial alike;
## game/Main.gd's _reset_match_scope() is the only emitter). Persistent owners
## that Main cannot name (sky, weather ceiling, audio, rumble) connect here and
## return to the state their own _ready() leaves on a fresh launch. Every
## listener must be idempotent: it fires once per world build and once per
## teardown, and a few teardown paths (e.g. a net leave that also aborts the
## match) fire it a second time with nothing left to reset.
signal match_scope_reset

## Bontago-t8x.4: the host pressed Start. Emitted on a client by
## net/MatchNet.gd's net_match_loading, one message ahead of net_match_start, so
## game/Main.gd can raise the loading overlay before the match world builds.
signal match_loading_announced

## Bontago-1pi.32: loading-screen ready gate (core/LoadingReadyGate.gd, owned per
## match by autoload/match/MatchLifecycle.gd). `ready_peer_ids` are the required
## peers that pressed ready, `required_peer_ids` every peer the host waits for
## (peers holding a human slot; bots never appear, they are auto-ready; offline
## and hot-seat the single local peer id Net.HOST_PEER_ID stands for every local
## human). Emitted on the host whenever either set changes and once at match
## start, and on a client when the host's mirror (Net._rpc_loading_ready_state)
## arrives. Presentation reads this; it never decides anything.
signal loading_ready_changed(ready_peer_ids: PackedInt32Array, required_peer_ids: PackedInt32Array)

## Bontago-1pi.32: the host's gate opened (min display elapsed AND everyone ready,
## or the safety cap) -- the countdown may now run. Host: emitted by the
## lifecycle; client: re-emitted when Net._rpc_loading_gate_open arrives. Always
## fires once per match, also when no gate was armed (headless/sandbox).
signal loading_gate_opened

## Bontago-1pi.32: Net validated that a seated peer pressed ready (host side
## only; offline/host-local presses come through Net.request_loading_ready()).
## MatchLifecycle owns the remaining checks (phase, required set, idempotence).
signal net_loading_ready_received(peer_id: int)

## One second of the 3 s pre-match countdown elapsed; 0 means "go".
signal countdown_tick(seconds_left: int)

## Hot-seat: it is now this slot's turn to hold and place a block.
signal turn_changed(slot_id: int)

## A team met the win condition (spec 2.3). The match state goes to End.
signal match_won(team_id: int)
## Bontago-22y.11: the active mode objective's replicated state ({"mode_id",
## "scores", "extra", "round_left"}). Host: emitted when it changes (MatchNet
## replicates it); client: emitted after the validated host state is applied.
signal mode_state_changed(state: Dictionary)

## Bontago-1pi.13: the full results-screen payload is ready -- fired once per
## match end, on the host directly from MatchLifecycle._finish_match() (right
## after match_won above) and on every client after net/MatchNet.gd's single
## EVENT_MATCH_RESULTS RPC has validated the wire payload
## (MatchStats.validate_results_payload()). `results` is always the typed
## Dictionary shape MatchStats.gd's own header comment documents (winner_kind/
## winner_id/winner_name/match_duration/rows); the results-screen UI worker
## (Bontago-1pi.6) is this signal's consumer.
signal match_results_ready(results: Dictionary)

# --- M2: block feed (spec 2.4, 3.7) -----------------------------------------

## A slot received a new block from the bag. `next_shape_id` is what the HUD
## shows in the next-block preview; it is &"" when the preview is off.
signal feed_block_issued(slot_id: int, shape_id: StringName, next_shape_id: StringName)

## A slot's block timer ran out. The slot's controller answers by calling
## Match.request_place(..., auto_drop = true) from wherever its ghost is;
## Match relocates it to the closest valid point if it has to (spec 2.5).
signal feed_timer_expired(slot_id: int)
## Bontago-1pi.18.1 (QoL experiments): a slot's queued-block count or its
## timer-paused flag changed. Host emits it; clients re-emit the replicated copy.
signal qol_feed_changed(slot_id: int, backlog: int, paused: bool)
## Bontago-1pi.18.2: a slot's gift-slot contents changed; activated/carrier are set when the slot was just spent.
signal gift_slot_changed(slot_id: int, contents: Array, activated: StringName, carrier_id: StringName)

## The host refused a placement intent. `reason` is one of the
## PlacementRules.REASON_* constants.
##
## Bontago-mv0.24 (owner test 2026-09-22): supersedes spec 2.2's older "the
## block is thrown off the map with a visible reject animation" line for a
## *manual* release — the owner's test of the original found a refused drop
## is simply not a drop: nothing is spawned or consumed, the player keeps
## holding the same piece, and the client shows a reject effect (spec 3.4)
## instead of a throw. An auto-drop that finds no valid point to relocate to
## (PlacementRules.closest_valid_point() returns NO_ORIGIN) still burns —
## see placement_relocated below for the relocated case.
signal placement_rejected(slot_id: int, reason: StringName)

## Bontago-mv0.24 (spec 2.5's auto-drop [ORIGINAL]): the host relocated an
## auto-drop that landed outside `slot_id`'s territory to the nearest valid
## point, `point` (disk-local x, z, Field's local space — the same frame the
## spawned block's origin sits in). Fired only for `slot_id`'s own client so
## its cursor and camera can jump to where the block actually landed; every
## other instance ignores an event for a slot that isn't its own.
signal placement_relocated(slot_id: int, point: Vector2)

# --- M2: territory (spec 2.2, 3.3) ------------------------------------------

## The host finished a territory solve, at TerritoryTuning.solve_hz. Carries
## the live raster; receivers read it, never mutate it.
signal territory_updated(raster: TerritoryRaster, groups: TerritoryGroups)

## Per-team share of the disk, 0..1, indexed by team id. HUD only.
signal territory_share_changed(shares: PackedFloat32Array)

## Cells whose hole state flipped in the last solve, as row-major CellGrid
## indices. Field batches the collision toggles and wakes the blocks above
## them (spec 3.3).
signal hole_cells_changed(opened: PackedInt32Array, closed: PackedInt32Array)

## A team is holding every goal flag in one connected territory. `progress`
## runs 0..1 over TerritoryTuning.capture_hold and drives the flag's radial
## ring (spec 2.3). team_id is -1 with progress 0 when a capture breaks.
signal goal_capture_progress(team_id: int, progress: float)

## A slot's home flag was lost to a hole opening under it (spec 2.2 is silent
## on this; docs/M2_PLAN.md's owner decision: this eliminates the slot —
## PlayerSlot.home_flag_alive goes false, its circles unanchor, and it gets no
## more feed). Match ends the match itself via match_won if only one
## player/team is left.
signal player_eliminated(slot_id: int, team_id: int)

# --- M4 P1: gift crates (spec 2.6) ------------------------------------------

## A gift crate appeared at `position` (disk-local x, z). Host-authored; a
## client only ever builds the visual from this and the two events below.
signal gift_spawned(gift_id: int, position: Vector2)

## Host flight contract; the old gift_spawned signal remains for existing consumers.
signal gift_flight_spawned(gift_id: int, origin: Vector3, landing: Vector3)
signal gift_landed(gift_id: int, landing: Vector3)

## A crate in a team's territory popped: `slot_id` is the RESOLVED RECIPIENT --
## the one teammate whose home circle (PlayerSlot.home_position) is nearest
## the crate, picked by autoload/match/MatchGifts.gd's _resolve_recipient_slot()
## (Bontago-keo.17, owner decision "b" on docs/M6_PLAN.md's Owner Q1). Only
## that slot's own pending queue (Match.held_special()/pop_pending_special())
## grows; a claim never queues onto a teammate's queue who isn't the resolved
## recipient. `special_id` is the id drawn for this claim -- Orchestrator
## amendment 1 (M4 P2b, 2026-09-23): the special TYPE is decided at claim
## time on the host, not at spawn time, so a player already knows what they
## hold while aiming/placing it. See autoload/match/MatchGifts.gd's
## PENDING_SPECIAL_ID for the placeholder id used until P2c installs the real
## weighted draw.
##
## Bontago-keo.17: a team-WIDE consumer (a toast/sfx every teammate should
## still see/hear even though only `slot_id` holds the item) derives "is my
## team" from `MatchConfig.team_of_slot(slot_id)`, never by comparing
## `slot_id` to a raw local slot id -- harmless while team_of_slot() is the
## identity (TeamMode.OFF), wrong once real teams exist.
signal gift_claimed(gift_id: int, slot_id: int, special_id: StringName)

## A crate lived past GiftConfig.life_s without being claimed.
signal gift_expired(gift_id: int)

## M4 P2c (docs/M4_P2_PACKAGES.md, orchestrator amendment 2): a spawned
## special (placed or thrown) triggered -- game/specials/SpecialBehavior.gd
## emits its own `triggered(def_id, position, chain_depth)` signal per
## instance; autoload/match/MatchPlacement.gd connects every behaviour it
## attaches to a forwarder that re-emits it here with the block's net_id
## added, so a listener can tell which block without holding a live reference
## to it. Host-only: only the host ever attaches a SpecialBehavior (a client
## never calls _spawn_block() -- decision 4 in docs/M4_P2_PACKAGES.md).
## net/MatchNet.gd (Bontago-1en.17, not this package) replicates it to
## clients from here.
signal special_triggered(net_id: int, def_id: StringName, position: Vector3, chain_depth: int)

## Bontago-1en.21: the head of `slot_id`'s pending-special queue was actually
## spent -- a place-spawn or a throw (autoload/match/MatchGifts.gd's
## pop_pending_special() is the one host-side emit site; a burned auto-drop
## deliberately never reaches it, see MatchPlacement._attach_pending_special()'s
## own doc comment). `special_id` is the id that was popped. Host-authored;
## net/MatchNet.gd replicates it (EVENT_SPECIAL_CONSUMED) and a client's mirror
## (MatchGifts.apply_replicated_special_consumed()) re-emits this same signal
## after popping its own queue, so a client's pending_special_count()/
## held_special() shrink in step with the host's, the spend-side counterpart of
## gift_claimed's own grow-side replication.
signal special_consumed(slot_id: int, special_id: StringName)

## Absolute host-owned Glue charge state. revision increases per slot within
## one match; client mirrors re-emit only when accepting a newer update.
signal glue_charges_changed(slot_id: int, charges: int, revision: int)

## Paintball's host-owned block conversion. Clients emit this only after a
## valid, new owner change by net ID; terrain ownership uses the registry.
signal block_owner_changed(net_id: int, owner_slot: int)

## Freeze special (Bontago-8or.2): a block started/stopped being held frozen by
## the special. Host emits it (net_id is the host's); clients re-emit on the
## replicated event after applying the icy visual.
signal block_frozen_changed(net_id: int, frozen: bool)

## Cat is a separate transient body, never a registered Block. Host events
## carry activation and expiry; snapshots carry its moving pose.
signal cat_started(id: int, slot_id: int, position: Vector3, duration: float)
signal cat_ended(id: int)

# --- M3a: session and transport (spec 3.4) ----------------------------------

## Net changed between OFFLINE, HOST and CLIENT. `mode` is a Net.Mode value.
signal net_mode_changed(mode: int)

## A peer finished the build-version handshake and holds a slot. `slot_id` is
## -1 while it is only sitting in the lobby without a seat.
signal net_peer_joined(peer_id: int, slot_id: int, player_name: String)

## A peer disconnected. `reason` is a Net.LeaveReason value. The host decides
## what happens to its slot (docs/M3a_PLAN.md); this is the notification, not
## the decision.
signal net_peer_left(peer_id: int, slot_id: int, reason: int)

## A join attempt failed. `error` is a Net.JoinError value; `detail` is a
## human-readable line for the lobby, never parsed.
signal net_join_failed(error: int, detail: String)

## The host published new lobby settings (spec 3.4: Steam lobbies store match
## settings as lobby data; over ENet the host broadcasts the same Dictionary).
## The payload is MatchConfig.to_dict() plus the roster.
signal net_lobby_data_changed(data: Dictionary)

## The LAN browser's list changed (spec 3.4 "LAN discovery"). Each entry is
## {name, address, port, version, players, max, map}.
signal net_games_discovered(games: Array[Dictionary])

## Ping, snapshot size, interpolation delay and measured loss, refreshed at
## NetConfig.stats_hz. ui/NetDebugOverlay.gd is the only consumer; the shape
## is Net.stats().
signal net_stats_updated(stats: Dictionary)

## Bontago-mv0.6: the lobby roster changed (a peer's ready flag flipped, or
## one joined/left). Emitted on the host from autoload/Net.gd's
## _broadcast_roster() with the roster it just sent, and on a client from the
## end of its _rpc_roster_update() with the roster it just applied, so both
## sides update without a wait for net_lobby_data_changed to be republished.
## Each entry is {peer_id, slot_id, name, ready}; ui/Lobby.gd is the only
## consumer today.
signal net_roster_changed(roster: Array[Dictionary])

# --- M3a: replication (spec 3.4) --------------------------------------------

## A client built its frozen copy of a block the host spawned. The local
## equivalent of block_placed for bodies this instance does not simulate:
## emitted only on clients, and always before the first snapshot moves it.
signal block_replicated(block: RigidBody3D, net_id: int)

## A client applied a territory update from the host. Clients never solve
## territory themselves (spec 3.4: only the host runs physics and the rules),
## so this replaces territory_updated on a client. The raster is the client's
## mirror; read it, never mutate it.
signal territory_replicated(raster: TerritoryRaster)

## Another player's ghost moved (spec 3.4: "update_cursor(pos) ... only used to
## show other players' ghosts"). Emitted on every instance for every non-local
## slot, at NetConfig.cursor_hz.
signal remote_cursor_updated(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
)

# --- M3b: Steam transport (spec 3.4, docs/M3b_PLAN.md P1) -------------------

## Net.init_steam() finished (or the extension isn't installed). `available`
## mirrors Net.steam_available(); `detail` is a human-readable line for the
## menu's notice label, never parsed.
signal net_steam_status_changed(available: bool, detail: String)

## The Steam lobby list changed after Net.refresh_lobby_list(). Each entry is
## {lobby_id, name, players, max, map}, the Steam-side equivalent of
## net_games_discovered.
signal net_steam_lobbies_discovered(lobbies: Array[Dictionary])

# --- Audio (assets-audio package) --------------------------------------------

## game/Block.gd detected a sudden drop in its own speed frame to frame (a
## landing or collision -- no contact_monitor, which cost too much physics
## step time; see Block._physics_process()). `speed` is that deceleration
## magnitude in m/s; autoload/Sfx.gd is the only listener and scales its
## thud's volume from it (config/AudioConfig.gd's impact_speed_min/_loud).
## Throttled per block (Block.IMPACT_EMIT_INTERVAL_MS) so a long slide or
## tumble doesn't spam one impact into a machine-gun of thuds.
signal block_impacted(speed: float)

# --- M7 P4: block effects (spec 2.10) ---------------------------------------

## Additive alongside block_impacted above (Bontago-xtq.29, M7 P4 fix):
## game/Block.gd emits both from the same detection, in the same call, right
## next to each other -- this one also carries the block's own global
## position at emit time, for effects that need to know *where* the impact
## happened (game/BlockEffectsManager.gd's landing-dust/impact burst).
## autoload/Sfx.gd deliberately keeps listening to block_impacted only and is
## untouched by this signal.
signal block_impacted_at(speed: float, position: Vector3)

# --- M7 P42: pause menu (owner playtest: "no pause menu, can't abandon a
# game and go back to the main menu or quit the game") -----------------------

## ui/PauseMenu.gd opened (pause_menu action -- Esc/gamepad Start -- while no
## other menu already owns that input). game/PlayerController.gd is the one
## listener today: it sets its own input_enabled false and releases mouse
## capture, the same "gate input, don't touch the scene tree" contract
## ui/TuningPanel.gd's own toggle already established. Physics/simulation is
## never paused (CLAUDE.md's host-authority model) -- this only suppresses
## local input while the overlay is up.
signal pause_menu_opened

## ui/PauseMenu.gd closed (Resume, or ui_cancel/pause_menu again while no
## nested menu is capturing it). game/PlayerController.gd restores
## input_enabled and, if it had mouse capture enabled, re-captures the mouse.
signal pause_menu_closed

# --- Options menu: input device tracking (Bontago-1pi.10) --------------------

## autoload/Settings.gd detected the player's last-used input device changed
## (a real keyboard/mouse press/motion vs. a gamepad button/stick beyond its
## own deadzone -- see Settings._classify_device()). ui/OptionsMenu.gd's
## Controls page and ui/KeyRebindRow.gd's own glyph row are today's only
## listeners: each swaps which device's binding glyphs it shows, live,
## without the player needing to reopen the menu.
signal input_device_changed(device: StringName)

# --- Weather events (Bontago-22y.10) ------------------------------------------
# Emitted on the host and, from replicated state, on every client, so
# presentation code (vfx/weather/WeatherPresenter.gd, a later HUD cue) needs
# no networking of its own.

## A weather event began (one at a time). `weather_id` is a WeatherTuning.id.
signal weather_started(weather_id: StringName)

## The event finished its ramp-out (or the match ended) and physics is back
## at baseline.
signal weather_stopped(weather_id: StringName)

## The ramped intensity 0..1 of the active weather changed.
signal weather_intensity_changed(weather_id: StringName, intensity: float)

## The schedule phase changed (calm began, an event began, hold, ramp-out).
## `state` is MatchWeather.state_dict(): "sched" (MatchWeather.Sched), "left"
## (seconds until the next event while calm, or until the event ends), "id",
## "phase" and "t". A HUD can show a "weather incoming" cue from it.
signal weather_state_changed(state: Dictionary)

## Bontago-470.2: a Breeze gust started (host, and on clients from
## net/BreezeNet.gd). `gust` is the compact wire dictionary: "id", "x", "y",
## "z" (world centre), "a" (heading, radians), "r" radius, "d" duration s, "s"
## strength 0..1. Presentation only.
signal breeze_gust_started(gust: Dictionary)
