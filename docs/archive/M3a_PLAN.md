# M3a — Multiplayer over ENet: parallel build plan

Spec: §2.5, §2.8, §3.2, §3.4 (this milestone), §3.7, Part 4 M3a. Four packages build in
parallel off the stub commit; **file ownership is disjoint** and every package writes its
tests first. Only the integrator touches `game/Main.gd` / `.tscn` and `project.godot`'s
`[autoload]`. **Acceptance:** 4 local instances play a full match; a client with 100 ms
simulated lag and 2% packet loss sees smooth towers; placements are never duplicated or
lost. M3b (Steam) is its own milestone — design so swapping the peer is all it takes, but
plan no Steam work.

## Questions for the owner — answer before P3 lands

1. **Per-player or shared block timer (spec "Still open" 1).** Hot-seat serialised turns, so
   this never bit; in real-time play `per_player_timer = true` means all 2–8 timers run at
   once and eight blocks can land in the same second. **(a) per player, concurrent** is the
   spec's default and §3.7's "Each player has a feed timer"; **(b) one shared global timer**
   drops everyone's block on the same beat — calmer and more readable. The plan builds (a):
   `Match._tick_feed`'s non-hot-seat branch already implements it, and (b) is ~15 lines in
   that one function plus a `MatchConfig` flag that exists. Answer either way; nothing moves.
2. **What happens to a disconnected player's towers?** Spec is silent. **(a)** blocks stay
   and the slot keeps its influence forever (a dead player can still wall off the goal);
   **(b)** grace period, then the slot is eliminated exactly as a lost home flag does it
   (`Events.player_eliminated`) and its towers unanchor; **(c)** an AI takes over — needs M5.
   The plan builds **(b)** with `NetConfig.disconnect_grace = 10 s`: it reuses a rule that
   exists and cannot deadlock a match behind an absent player's wall. One function,
   `Match.on_peer_left(slot_id)`.
3. **Does hot-seat survive as a menu mode?** M2's hot-seat is a debug scaffold with strict
   alternation (`MatchConfig.hot_seat`); networked play needs one local player per instance.
   The plan keeps it reachable but **unlisted** — `--hot-seat` plus the existing
   `HotSeat.tscn`, behaviour byte-identical so `test_hot_seat.gd` still passes — and the menu
   offers only Host / Join. Say the word and P4 adds a local-2-player button; split-screen or
   two mice on one PC is **not** planned and would be its own milestone.

No M3a work changes a rule tagged **[ORIGINAL]**; §2.5's auto-drop is one and is preserved
exactly — see "Auto-drop never crosses the wire".

### P1 — Transport & session — **sonnet** (7 owned files; broad MultiplayerAPI wiring, but every step is a documented Godot API)
**Owns:** `autoload/Net.gd`, `net/LanDiscovery.gd`, `core/net/NetSim.gd`, `config/NetConfig.gd` + `net_config.tres`, `tests/unit/test_net_session.gd`, `tests/unit/test_net_sim.gd`, `tests/unit/test_lan_discovery.gd`.
**Reads only:** `config/MatchConfig.gd`, `config/MapDef.gd`, `autoload/Events.gd`.
**Tests first:** two `ENetMultiplayerPeer`s in one process (host on an ephemeral port,
client on 127.0.0.1) connect, handshake and appear in each other's roster within
`connect_timeout`; a client whose `build_version` differs is refused with
`JoinError.VERSION_MISMATCH` **and disconnected**, never receiving a slot; a 9th peer gets
`SERVER_FULL`; `peer_disconnected` fires `Events.net_peer_left` with the right slot;
`leave()` from either side returns both to `Mode.OFFLINE` and is idempotent.
`encode_advert`/`decode_advert` round-trip and reject a foreign or truncated payload
without erroring. `NetSim`: 1000 packets at 100 ms / 2% deliver in submission order, none
early, drop rate within ±1% of 2%, `droppable = false` never drops, `is_idle()` true at 0/0.
**Acceptance:** a headless test hosts and joins in-process, exchanges a ping and reports
`ping_ms` under 50 ms; `apply_command_line()` parses `--host`, `--join=127.0.0.1:47778`,
`--port=`, `--headless-host`, `--sim-lag=`, `--sim-loss=`.
**Must NOT:** name a gameplay concept — no `Block`, `Match`, `TerritoryRaster`,
`BlockShape`, placement or snapshot anywhere in P1. `ENetMultiplayerPeer`, `PacketPeerUDP`
and IP literals appear **only** in `Net._make_*_peer()` and `LanDiscovery`, nowhere else in
the project, now or in M3b. Do not add `class_name` to `Net.gd`.

### P2 — Snapshot sync & interpolation — **opus** (8 owned files; bit packing and a render clock are the subtlest work in M3a)
**Owns:** `net/SnapshotSync.gd`, `net/Interpolator.gd`, `core/net/Quantize.gd`, `tests/unit/test_quantize.gd`, `tests/unit/test_snapshot_wire.gd`, `tests/unit/test_interpolator.gd`, `tests/bench/bench_snapshot.gd` + `.tscn`.
**Reads only:** `config/NetConfig.gd`, `config/MapDef.gd`, `config/PhysicsTuning.gd`, `game/BlockRegistry.gd`, `game/Block.gd`, `autoload/Net.gd`.
**Tests first:** `quantize_axis`/`dequantize_axis` round-trip inside one step, and clamp
past both ends; a position anywhere in the map-M AABB round-trips within **2.1 mm** and a
random quaternion within **0.005°**, with `q` and `-q` packing identically; the sleeping
flag survives; `pack_body` writes exactly `BODY_RECORD_BYTES = 15` (14 until the review fix
Bontago-mv0.1.7 widened the id — see "The wire, byte for byte").
`encode_fragment`/`decode_fragment` round-trip header, disk state and bodies; a truncated,
wrong-version or random payload decodes to `{}` and logs nothing; a fragment never exceeds
`NetConfig.max_packet_bytes`; 300 bodies split into exactly the count
`bodies_per_fragment()` predicts, all sharing one sequence. `Interpolator` (clock injected,
no tree): a clean 30 Hz stream renders exactly `base_interp_delay_ms` behind; ±40 ms
injected jitter raises `delay_ms()` and it decays back; a 200 ms stall extrapolates for at
most `max_extrapolation_ms` and then **holds** (never snaps or drifts); a reordered sample
is rejected; an unknown net_id increments `dropped_unknown_count()` and changes nothing.
**Acceptance:** `bench_snapshot.gd` packs 300 awake bodies and reports bytes and pack time
— **budget ≤ 2 ms per snapshot at 30 Hz** and ≤ 4.5 KB total. Miss it and raise
`max_packet_bytes` or lower `snapshot_hz` **in the resource**, never in code.
**Must NOT:** create, free or reparent a body; decide a rule; read `TerritoryRaster`; call
`rpc()` on anything but its own `net_snapshot`; write a transform outside `_physics_process`
(see "Frozen bodies"); use `BlockRegistry`'s settled flag as "awake" (see "Two kinds of
asleep"). Remove every stub `@warning_ignore_start`.

### P3 — Authority, intents & replication — **opus** (9 owned files; ordering and idempotence are where this milestone is won or lost)
**Owns:** `autoload/Match.gd`, `net/MatchNet.gd`, `game/BlockRegistry.gd`, `game/PlayerController.gd`, `game/HotSeat.gd`, `game/RemoteCursors.gd` + `.tscn`, `core/territory/TerritoryRaster.gd`, `tests/unit/test_match_net.gd`, `tests/unit/test_raster_replication.gd`, plus edits to the M2 tests it owns the subjects of (`test_match_flow.gd`, `test_block_registry.gd`, `test_hot_seat.gd`, `test_playercontroller_*.gd`).
**Reads only:** everything P1 and P2 own, `core/rules/*`, `config/*`, `game/Field.gd`, `game/GhostPreview.gd`, `ui/HUD.gd`.
**Tests first:** `MatchNet.submit_place` on a host calls `Match.request_place` **inline,
same frame**, and on a client sends and returns without touching `Match`; an intent whose
`slot_id` does not match `Net.slot_of_peer(sender)` is refused and `intents_accepted` does
not move; the same intent delivered twice (same `feed_seq`) spawns **one** block and the
second returns `REASON_NO_BLOCK`; an intent for a stale `feed_seq` is refused; `feed_seq`
advances on every `_consume_and_refeed`. `Match` with `Net` faked to CLIENT runs no solve,
no feed tick and no win check, and `BlockRegistry.influence_circles()` returns empty.
`TerritoryRaster.apply_replicated_state` reproduces `team_at`, `is_contested`,
`is_hole_index`, `team_share` and therefore `PlacementRules.validate` bit-for-bit against
a host raster; a diff applied to a stale mirror then a full keyframe converge.
`test_hot_seat.gd` and every M2 match-flow test still pass untouched with
`MatchConfig.hot_seat = true` and `Net` offline.
**Work:** `Match` gains `if not Net.is_host(): return` gates on `_tick_feed`,
`_tick_territory` and `_check_home_flags`, a `feed_seq(slot_id) -> int` counter, an
`on_peer_left(slot_id)` hook (question 2), and a trailing **defaulted** `feed_seq: int = -1`
on `request_place` so every M2 call site compiles unchanged; `_spawn_block` calls
`MatchNet.replicate_spawn`, the kill-plane removal `replicate_despawn`. `BlockRegistry`
gains `set_host_authority(bool)` (clients skip net_id allocation and the settle tick) and
`bind_net_id(block, net_id)`. `PlayerController` routes through `MatchNet.submit_place` /
`submit_cursor`, acts for `Net.local_slot()` online and `Events.turn_changed`'s slot
offline, and locks its ghost after an intent until `feed_block_issued` or
`intent_ack_timeout`. `RemoteCursors` instances one `GhostPreview` per non-local slot from
`Events.remote_cursor_updated`.
**Must NOT:** call `rpc()` outside `MatchNet`; move a rule out of `Match`/`core/` or add
one to `MatchNet`; change `Events.feed_block_issued`'s signature (add `Match.feed_seq()`
instead); edit `ui/HUD.gd`, `game/GhostPreview.gd` or `game/Field.gd` — report it instead.

### P4 — Lobby, debug overlay & test harness — **sonnet** (12 owned files; broad, each piece small)
**Owns:** `ui/MainMenu.gd` + `.tscn`, `ui/Lobby.gd` + `.tscn`, `ui/NetDebugOverlay.gd` + `.tscn`, `tools/bootstrap_project.gd`, `tools/run_m3a_local.ps1`, `tools/run_m3a_local.sh`, `tests/bench/m3a_acceptance.gd` + `.tscn`, `tests/unit/test_lobby.gd`, `tests/unit/test_net_debug_overlay.gd`.
**Reads only:** everything P1–P3 own.
**Tests first:** every §2.8 setting in `Lobby` round-trips through `MatchConfig.to_dict()`
→ `Net.set_lobby_data` → `Events.net_lobby_data_changed` → `from_dict` → `sanitize()`, and
a client's controls are disabled while the host's are not; a value outside its §2.8 range
arriving over the wire is clamped, not trusted; the LAN list adds, refreshes and expires an
entry; direct-IP entry accepts `1.2.3.4` and `1.2.3.4:47999` and rejects junk; Start is
disabled until `Net.all_peers_ready()`; the overlay's labels read back exactly
`Net.stats()`, and its preset button applies `sim_preset_lag_ms` / `sim_preset_loss`.
**Input Map:** one new action, `net_debug_toggle` (F3 + gamepad Back+Y), added in
`tools/bootstrap_project.gd` and regenerated — never by hand-editing `project.godot`
(CLAUDE.md). Commit the regenerated `[input]` section as its own step.
**Acceptance:** `tools/run_m3a_local.ps1 -Peers 4` launches 1 headless host + 3 headless
clients, they play the scripted match, every instance prints `M3A_ACCEPT` lines and the
script exits non-zero if any did; `-SimLag 100 -SimLoss 0.02` applies the acceptance
condition to client 1.
**Must NOT:** own a rule, an RPC or a peer. The lobby never calls `Match.start_match` on a
client — it asks the host. The overlay reads and never writes game state.

## Integration order
1. **P1 first** — everything gates on `Net.is_host()` and `NetConfig`.
2. **P2 second**, independent of P3: it needs only `NetConfig`, `Net`, and
   `BlockRegistry`'s existing `block_for_net_id`.
3. **P3 third** (needs `Net` and `SnapshotSync.begin_match`), **P4 last** (needs all
   three). Each merge must pass `godot --headless --editor --path . --quit` (no errors, no
   new warnings) and the full GUT suite before the next lands. `autoload/Events.gd` is the
   one expected conflict: every side only **appends**, so keep both blocks.
4. **Integrator wires `game/Main.gd` / `Main.tscn`** — the only files nobody owns. `Main`
   becomes a router, not a match: `_ready` calls `Net.apply_command_line()`; with no flag
   it shows `ui/MainMenu.tscn` → `ui/Lobby.tscn` → the match world; with `--hot-seat` it
   does exactly what M2 did. Building the world keeps M2's order (`register_world` →
   `start_match` → `place_flags` → `set_overlay_source`) **plus**
   `SnapshotSync.begin_match(registry, map_def)` and a `RemoteCursors` instance; on a
   client `start_match` is driven by `net_match_start`, not the menu. `HotSeat.tscn` is
   instanced once and bound to `Net.local_slot()` when online.
5. **Integrator registers two autoloads** in `project.godot` after `Match` — order matters,
   both read `Net` and `Match` in `_ready`: `SnapshotSync="*res://net/SnapshotSync.gd"`,
   `MatchNet="*res://net/MatchNet.gd"`. That is `[autoload]`, not `[input]`, so editing it
   directly is correct. Then update `README.md` and run the 4-way harness plus a windowed
   2-instance pass for feel.

## Where every tunable lives — no magic numbers (CLAUDE.md); nothing below may be a literal in code
| Resource | Owner | Holds |
|---|---|---|
| `net_config.tres` | P1 | `discovery_port` 47777, `game_port` 47778, `max_peers` 8, `discovery_broadcast_hz` 1, `discovery_entry_ttl` 3, `connect_timeout` 8, `handshake_timeout` 5, `peer_timeout_ms` 5000 (+min/max), `ping_hz` 1, `ping_history` 8, `disconnect_grace` 10, `snapshot_hz` 30, `raster_diff_hz` 5, `cursor_hz` 15, `max_packet_bytes` 1200, `pos_xz_margin` 1.5, `pos_min_y` −48, `pos_max_y` 72, `keyframe_interval` 2, `resend_position_epsilon` 0.005, `resend_angle_epsilon` 0.5, `base/min/max_interp_delay_ms` 100/50/300, `jitter_multiplier` 2, `interp_delay_smoothing` 0.1, `max_extrapolation_ms` 100, `interp_buffer_samples` 16, `clock_correction_rate` 0.15, `intent_ack_timeout` 1, `raster_full_threshold_fraction` 0.35, `raster_compress`, `sim_lag_ms` / `sim_jitter_ms` / `sim_loss` (0 = off), `sim_preset_lag_ms` 100 / `sim_preset_loss` 0.02, `stats_hz` 2, `stats_window` 2 |
| `match_defaults.tres` | read-only | every §2.8 setting, already `to_dict`/`from_dict`/`sanitize`-ready — the lobby needs **no new field** |
| `physics_tuning.tres` | read-only | `kill_plane_y` −40, which `pos_min_y` must sit below |
| `maps/*.tres` | read-only | `field_radius`, which sizes the quantization AABB on both ends |
| script `const` | P2/P3 | `SnapshotSync.SNAPSHOT_CHANNEL` 1, `MatchNet.CURSOR_CHANNEL` 2, `Net.HOST_PEER_ID` 1, `Quantize.*_BYTES`. `@rpc` needs a compile-time constant, and a channel index is architecture, not a tunable — the same reason `Match.COUNTDOWN_SECONDS` is a const. |

## Design notes — the parts that are easy to get wrong

**The wire, byte for byte.** Both layouts live in the stubs' doc comments and are the
contract: `net/SnapshotSync.gd` has the 12-byte fragment header (version, u16 sequence,
fragment index/count, u32 `host_time_ms`, flags, u16 body count, optional 12-byte disk
state); `core/net/Quantize.gd` has the 15-byte body record (**u24** `net_id`, 3×u16 position
over the AABB, 48-bit smallest-three quaternion with the sleeping flag in the spare bit).
Little-endian throughout. `SnapshotSync.PACKET_VERSION` is 2 for this layout. **The id is
u24, not §3.4's u16 — a deliberate deviation (Bontago-mv0.1.7, `# DECISION` at
`Quantize.pack_net_id`).** `net_id` is never reused within a match (next paragraph), so a
u16 field would alias the 65537th block onto the first and drop the 65536th as "no body";
eight players on a 3 s timer with the match timer off get there in under seven hours. u24
gives 16.7 M ids (72 days at that rate) and costs one byte per body — 300 bodies are 4560 B
in four 78-body fragments, inside the 1200 B and 4.5 KB budgets — where u32 would need five
fragments and 4860 B. `Quantize.NET_ID_MAX` is the single statement of the ceiling; the
host's allocator refuses (logs an error, leaves `net_id = -1`, body stays host-only) rather
than wrapping if it is ever reached. **Both ends must derive the AABB from the same `MapDef`**, which
arrives in `net_match_start` before any snapshot; get it wrong and every body lands somewhere
plausible but wrong — far harder to spot than a crash.

**net_id allocation and the spawn/snapshot race.** The host's `BlockRegistry` allocates
`net_id` from a monotonic counter starting at 1, **never reused within a match** — reuse
would let a snapshot in flight move the wrong body. Clients never allocate:
`set_host_authority(false)` makes `_on_block_placed` skip allocation and the spawner calls
`bind_net_id`. The reliable `net_block_spawned` and the unreliable snapshot ride different
channels, so a snapshot **can** name a body whose spawn has not arrived. Rule: **the client
drops samples for unknown net_ids** and counts them
(`Interpolator.dropped_unknown_count`). Buffering needs an unbounded side table keyed on
ids that may never arrive — a despawned body's id can appear in a snapshot in flight too —
and buys at most one 33 ms interval, by which time the reliable spawn has landed. A client
draws a new block at the transform its spawn RPC carried and does not move it until the
interpolator holds two samples, so nothing pops.

**Frozen bodies, and two kinds of asleep.** Clients set every synced body
`freeze_mode = FREEZE_MODE_KINEMATIC` then `freeze = true`, and move it by writing
`global_transform` **in `_physics_process` only**: `physics_interpolation = true` is on, so
writing in `_process` fights Godot's own interpolator and produces exactly the jitter the
acceptance criterion tests for. Writing at 60 Hz from a 30 Hz buffer and letting the engine
smooth to the display is the whole trick. Separately, `RigidBody3D.sleeping` (the snapshot's
"awake") is **not** M2's settled rule (`sleep_linear_threshold` 0.15 /
`sleep_angular_threshold` 0.3 held 0.5 s, tracked by `BlockRegistry`), which is looser and
feeds territory influence. On a client every body is frozen, so velocities are zero and the
settled rule would call everything settled instantly — hence `influence_circles()` returns
empty there and `Match`'s 10 Hz solve must not run. **Clients never solve territory.**

**The client's raster is a mirror, not a solve.** `TerritoryRaster.apply_replicated_state`
(P3, additive) writes `_team_ids` from the owner byte (0 = unowned, else `team_id + 1`),
`_group_ids = TerritoryGroups.CONTESTED` where the state byte's `STATE_CONTESTED` bit is
set, `_hole` from `STATE_HOLE`, and rebuilds `_team_counts` for `team_share` — exactly the
set `PlacementRules.validate` reads (`is_in_disk`, `is_hole_index`, `is_contested`,
`team_at`). A client's ghost tint is therefore byte-identical to the host's answer as of the
last diff, and `request_place` still re-validates on the host from scratch (§3.4). Real
group indices cannot be reconstructed and are not needed: the win check is host-only.
Applying a diff also re-emits `Events.hole_cells_changed` for the cells whose hole bit
flipped, so `Field` opens the same holes with no extra RPC.

**Auto-drop never crosses the wire.** §2.5's auto-drop is [ORIGINAL] and must keep dropping
"from its current ghost position". A round trip on timer expiry could lose or duplicate the
drop, so **the host auto-drops from the last `update_cursor` it received for that slot** —
at 15 Hz at worst 67 ms stale, and `closest_valid_origin` relocates from there anyway.
`update_cursor` therefore carries `orientation_index` and `free_quat` too (`# DECISION` in
`MatchNet.submit_cursor`: §3.4 writes `update_cursor(pos)`, but other players' ghosts need
the rotation and auto-drop needs it right). The timer path stays inside `Match`, in order.

**Never duplicated, never lost.** Reliable ENet cannot duplicate a packet, so the real risk
is the player: a client clicks twice inside one RTT and spends two blocks. Two defences.
(1) `Match` keeps a per-slot `feed_seq` advancing on every `_consume_and_refeed`; an intent
carries the `feed_seq` its sender last saw, and a stale one is refused with `REASON_NO_BLOCK`
— so a replayed, doubled or raced intent is a no-op, not the next block. (2)
`PlayerController` locks its ghost after sending until `feed_block_issued` for its slot
arrives or `intent_ack_timeout` elapses. The host pays neither: `submit_place` calls
`Match.request_place` inline.

**Disconnects and the in-flight held block.** A held block is a ghost — it exists only on
the owner's screen and in `Match._held_shapes`, so a vanished peer leaves nothing to clean up
in the physics world. `Match.on_peer_left` stops that slot's feed at once and starts
`disconnect_grace`, after which question 2's answer applies; an intent already in flight is
refused by the peer-id check, its sender being gone from the registry. The host leaving is
different: clients get `server_disconnected`, `Net` returns them to `OFFLINE` and `Main`
routes back to the menu — never a half-dead match.

**Version refusal has to happen after connect.** The high-level API completes the ENet
connection before any RPC can run, so: on `connected_to_server` the client sends `Net`'s
handshake RPC with `build_version` (read from `ProjectSettings`' `application/config/version`)
and its name; the host validates, assigns a slot and broadcasts the roster, or replies with a
`JoinError` and calls `disconnect_peer`. A peer holds no slot and receives no gameplay RPC
until accepted, and `set_refuse_new_connections(true)` goes on when the lobby fills or the
match starts.

## Testing without a second PC

**Four instances from one command.** `tools/run_m3a_local.ps1` (and the `.sh` twin)
launches `godot --headless --path . res://tests/bench/m3a_acceptance.tscn -- --headless-host
--port=47778` plus N−1 clients with `--join=127.0.0.1:47778`, waits, and returns non-zero if
any exit code is. The scene reads its role from the command line, so one file drives both
ends. For feel rather than assertions, the editor's **Debug → Customize Run Instances**
with 2–4 instances and per-instance arguments does the same windowed. It must be a `.tscn`,
as `m2_acceptance` is: autoload identifiers (`Net`, `Match`) do not resolve in a `-s`
SceneTree script, so a harness written that way will not even compile.

**100 ms lag and 2% loss.** `ENetConnection` has no netem, and a `MultiplayerPeerExtension`
wrapper would drop packets *below* ENet's reliability layer — destroying reliable RPCs
rather than simulating a lossy link. So `core/net/NetSim.gd` is an application-level
delay/drop queue with an injected clock, used where traffic is owned: `SnapshotSync` runs
inbound snapshots through it (unreliable, so dropping is right), `Net` runs outbound intents
and cursors through it (delayed; dropped only when unreliable). `lag_ms` is **one-way**, so
`--sim-lag=100 --sim-loss=0.02` on one client is exactly the acceptance condition. NetSim
never reorders — a different failure mode, and simulating it would make the duplication
assertions untestable.

**Proving placements are never duplicated or lost.** Each client sends exactly K scripted
intents and prints `MatchNet.intents_sent`; the host prints `intents_accepted`,
`intents_refused` and its block count. The harness asserts on the host that
`blocks_spawned == sum(intents_accepted) + auto_drops` and per slot that
`intents_accepted + intents_refused == intents_sent`; and on every client that its
replicated block count equals the host's, that no `net_id` was spawned twice, and that
`Interpolator.dropped_unknown_count()` stayed under one snapshot's worth. Because `feed_seq`
makes intents idempotent, a deliberately doubled intent in `test_match_net.gd` proves the
rule deterministically, without the timing the end-to-end run depends on.

## Known limitations (planned, M3a)

- **Late join and reconnect are M8.** M3a joins in the lobby only; the host refuses new
  connections once the match starts. §3.4's chunked world-state transfer is designed for —
  the raster's full-keyframe path serves a fresh client at match start — but not built.
- **One LAN browser per machine.** `PacketPeerUDP.bind()` sets no `SO_REUSEADDR`, so only
  one process per PC can listen on 47777. Multi-instance local testing joins by direct IP,
  §3.4's supported fallback.
- **No disk tilt yet.** The snapshot sends the disk's transform every snapshot (§3.4 "Disk
  state"), but the disk is static until M4. Sending it now means M4 changes no wire format.
- **Specials and gifts are not replicated** — there are none until M4. §3.4's reliable
  channel lists "special trigger events"; `MatchNet.replicate_match_event` is the seam.
- **A 15-byte body record, not 13.** §3.4 estimates "~13 bytes"; a u24 id (not §3.4's u16 —
  see "The wire, byte for byte") plus 6+6 is 15 once the sleeping flag folds into the
  quaternion's spare bit. 300 awake bodies cost 4.56 KB — still §3.4's "≈4 KB", still four
  fragments, and inside P2's 4.5 KB (4608 B) benchmark budget.
