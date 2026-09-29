# Gift delivery rework (owner playtest 2026-09-29)

## Contract

`feedback/playtest.md` is the current owner direction. A gift descends under a
parachute, is visible on the minimap, and can be claimed in flight when a
player's held block touches it. A landed gift claims immediately if its landing
cell is owned; otherwise it claims when that cell becomes owned and expires
after ten unclaimed seconds. The claim replaces the piece immediately behind
the held piece. That gift can be released as soon as the current held piece is
released, while the ordinary interval clock stays synchronized across players.
This replaces SPEC 2.6's stationary/60-second prototype and pending-special
FIFO behavior. Per-window spawn probability and host authority stay as shipped.

The host owns phase, position, collision, claim order, feed sequence, and timer.
Clients render replicated state and never send an authoritative claim intent.
The held ghost is not a physics body, so its touch is measured against the
host-validated cursor pose and held BlockShape, including remote cursor poses
from MatchNet. Tuning values belong in GiftConfig, not in scripts.

## Package order and file ownership

1. **Rules and interface stubs** (`Bontago-3ow.4`): `docs/SPEC.md`,
   `config/GiftConfig.gd`, `config/gift_config.tres`, `autoload/Events.gd`,
   `autoload/Match.gd`. Define the `FALLING`/`LANDED` phase read model and
   host-authored landed event. Retain the existing gift-spawn roll and cap.
   Fix the replacement and displaced-piece semantics in the decision bead
   before freezing the feed interface. Gate: Godot import and typed parse.
2. **Host gift lifecycle** (`Bontago-3ow.1`): `autoload/match/MatchGifts.gd`,
   `core/gifts/GiftSpawner.gd`, `game/GiftCrate.gd/.tscn`, and focused gift tests.
   Store deterministic spawn origin, landing point and elapsed descent time;
   progress flight on host physics ticks. Resolve midair touch from validated
   held-piece poses, then landing territory and ten-second landed expiry.
   A single gift is claimed or expired at most once. An expired gift's existing
   replacement rule spawns a *new descending gift* elsewhere. Tests cover two
   contenders, ownership at landing, later ownership, exact expiry boundary,
   reset and seeded repeatability.
3. **Next-piece and timer exception** (`Bontago-3ow.3`):
   `autoload/match/MatchFeed.gd`, `autoload/match/MatchPlacement.gd`,
   `game/PlayerController.gd`, and focused feed/placement tests. Keep the current
   held piece unchanged on claim. The gift becomes the next actual piece and
   may be validly placed or thrown while the ordinary release lock is active.
   Invalid actions consume nothing. After gift use, the normal next piece
   resumes under the original window boundary; feed sequence remains monotonic
   and rejects duplicate intents. Tests cover early ordinary release, instant
   gift release, ordinary lock recovery, auto-drop and rejected inputs.
4. **Network state** (`Bontago-3ow.1` integration): `net/MatchNet.gd`,
   `tests/unit/test_match_net.gd`, and the ENet harness. Replicate flight origin,
   destination and landing as reliable events with finite-coordinate and
   phase-order validation. Reuse authoritative claim and feed events. One
   bounded four-peer ENet check covers contention and a gift released during
   the normal lock.
5. **Presentation** (`Bontago-3ow.2`): `ui/Minimap.gd`, `ui/HUD.gd`, HUD tuning
   resources, and focused UI tests. Render falling and landed markers in disk
   coordinates, remove them on claim or expiry, and show the claimed gift in
   next-piece and held-piece previews. Manual check at multiple camera bearings
   with mouse and gamepad.

Only the orchestrator integrates packages. Run targeted tests during each
package, one ENet check after networking changes, and the full GUT suite once
after the combined game-code batch if the environment permits `user://` writes.
Run any physics benchmarks without competing Godot processes.

## Decisions and dependencies

`Bontago-3ow.3` depends on the queue decision and the interface package;
presentation depends on the replicated phase model. `Bontago-22y.1` through
`.3` (new gifts) depend on this rework. The 2026-09-29 owner instructions
already resolve stationary versus descending gifts, 60 versus 10 seconds, and
ordinary FIFO versus next-piece replacement; no second approval is needed for
those changes. The queue decision must settle whether another claim replaces an
already queued gift and whether the displaced ordinary bag draw is discarded
or deferred. Fall speed and touch margin are tunable implementation values.
