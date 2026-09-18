class_name NetSim
extends RefCounted
## Application-level lag and packet-loss simulator (spec Part 4 M3: "a client
## with 100 ms of simulated lag and 2% packet loss sees smooth towers").
##
## `ENetConnection` has no netem, and wrapping the peer in a
## MultiplayerPeerExtension would let us drop packets *below* ENet's
## reliability layer — which would silently destroy reliable RPCs rather than
## simulate a lossy link. So the simulation lives one level up, in the two
## places that own their own traffic:
##   - net/SnapshotSync.gd runs every inbound snapshot packet through a NetSim
##     (these are unreliable, so dropping them is exactly right);
##   - autoload/Net.gd runs outbound intents and cursor updates through one,
##     delaying reliable traffic and dropping only the unreliable kind.
##
## Pure and clock-injected: `now` is passed in rather than read, so a unit test
## can push 1000 packets through a simulated 100 ms / 2% link and assert the
## delivery order and drop rate without waiting a second (CLAUDE.md: core/ has
## no scene-tree dependence).
##
## `lag_ms` is **one-way** added delay. Enabling 100 ms on a client alone makes
## that client see the world 100 ms later and its intents arrive 100 ms late,
## which is what the acceptance criterion describes.

@warning_ignore_start("unused_parameter")


## `lag_ms` one-way delay, `jitter_ms` random +- spread on top of it, `loss`
## the fraction of droppable packets discarded (0..1). `rng_seed` >= 0 makes a
## run reproducible; -1 randomizes.
func _init(lag_ms: float = 0.0, jitter_ms: float = 0.0, loss: float = 0.0, rng_seed: int = -1) -> void:
	pass


## Re-tunes a live simulator without dropping what is already queued.
func configure(lag_ms: float, jitter_ms: float, loss: float) -> void:
	pass


## True when nothing is being delayed or dropped, so callers can skip the
## queue entirely on the common path.
func is_idle() -> bool:
	return true


## Offers a payload to the link at time `now` (seconds, monotonic). Returns
## false when the simulator dropped it — only ever possible when
## `droppable` is true, which callers set for unreliable traffic and clear for
## reliable traffic. A kept packet becomes deliverable at now + lag + jitter.
func submit(payload: Variant, now: float, droppable: bool) -> bool:
	return true


## Everything whose delivery time has arrived, oldest first, removed from the
## queue. Order is preserved even when jitter would reorder it: a packet never
## overtakes one submitted earlier, because reordering is a separate failure
## mode from jitter and simulating it would make "never duplicated or lost"
## untestable.
func drain(now: float) -> Array:
	return []


## Payloads still waiting.
func pending_count() -> int:
	return 0


## Packets submitted since the last reset, for the debug overlay.
func submitted_count() -> int:
	return 0


## Packets dropped since the last reset, for the debug overlay.
func dropped_count() -> int:
	return 0


## Empties the queue and the counters.
func reset() -> void:
	pass


@warning_ignore_restore("unused_parameter")
