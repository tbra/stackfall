class_name MatchFeed
extends RefCounted
## Match's block feed: bags, held/next shapes, feed_seq, interval timers,
## release locks, auto-drop expiry and the replicated feed mirror.
##
## Split out of autoload/Match.gd (pure refactor: no behaviour change). Every
## method here is the exact body that used to live on Match, with `_match`
## reads standing in for whatever another controller (or Match itself) now
## owns. See autoload/Match.gd's own header comment for the state machine
## this feed serves, and docs/AGENT_WORKFLOW.md's "Package size, reports and
## review scope" for why the split happened.

var _match: MatchAutoload = null

var _bags: Array[BlockBag] = []
var _held_shapes: Array[BlockShape] = []
var _feed_time_left: Array[float] = []
var _feed_expired: Array[bool] = []

## Spec 3.4 / docs/M3a_PLAN.md, "Never duplicated, never lost": one counter
## per slot, advanced every time the slot's held block is consumed. An intent
## carries the value its sender last saw; the host refuses one that is no
## longer current, so a replayed, doubled or raced intent is a no-op instead
## of silently spending the next block.
var _feed_seq: Array[int] = []

## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" placement cadence, restored
## after the M2 hot-seat prototype): whether the slot's currently held piece
## may be released right now. Every fixed `config.block_timer` interval
## permits exactly one release; placing early does not restart the interval
## -- it hands the slot its next piece to aim/prepare immediately, but that
## piece stays locked until the interval boundary. Only meaningful outside
## hot-seat -- see _consume_and_refeed()'s DECISION for why hot-seat never
## sets this. Parallel to Match's slots, like every other per-slot feed array.
var _release_locked: Array[bool] = []

## Lazily built id -> BlockShape index, used only by the client read model.
var _shapes_by_id: Dictionary = {}

## Whether _tick_feed() decrements anything this frame (Bontago-mv0.8).
## True for every real match; a sandbox match (config.sandbox) starts it
## false, so feed_time_left never counts down and no slot ever auto-drops —
## game/Sandbox.gd's sandbox_toggle_timer hotkey flips it back on to
## deliberately exercise auto-drop. A placement still refeeds immediately
## either way (_consume_and_refeed() runs from request_place() regardless of
## this flag), so "unlimited blocks" falls out of the existing per-placement
## refeed, not a separate code path.
##
## DECISION (autoload/Match.gd): a runtime flag read at the top of
## _tick_feed(), not a second MatchConfig field, because it has to change
## while a match is running (the toggle hotkey) — config is duplicated once
## at start_match() and normally never touched again, and reaching back into
## it from a hotkey would blur "match settings" with "what this instance is
## doing right now". Not implemented by setting block_timer to a huge number
## either: that would still tick, drift, and eventually expire, and would
## show a misleading countdown on ui/SandboxPanel.gd's timer readout instead
## of an honest "paused".
var _feed_timer_enabled: bool = true


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref


## The shape `slot_id` is holding right now, or null between blocks.
func held_shape(slot_id: int) -> BlockShape:
	if slot_id < 0 or slot_id >= _held_shapes.size():
		return null
	return _held_shapes[slot_id]


## What the HUD's next-block preview shows for `slot_id`.
func next_shape(slot_id: int) -> BlockShape:
	if slot_id < 0 or slot_id >= _bags.size():
		return null
	var preview: Array[BlockShape] = _bags[slot_id].peek(1)
	return preview[0] if preview.size() > 0 else null


## Seconds left on the slot's block timer (spec 2.8: 3-12 s, default 6).
func feed_time_left(slot_id: int) -> float:
	if slot_id < 0 or slot_id >= _feed_time_left.size():
		return 0.0
	return _feed_time_left[slot_id]


## feed_time_left / config.block_timer, 1 -> 0, for the HUD's timer ring.
func feed_progress(slot_id: int) -> float:
	if _match.config == null or _match.config.block_timer <= 0.0:
		return 0.0
	return clampf(feed_time_left(slot_id) / _match.config.block_timer, 0.0, 1.0)


## Whether _tick_feed() is currently decrementing timers (Bontago-mv0.8:
## true for every real match). ui/SandboxPanel.gd shows this as the timer's
## "running"/"paused" state.
func feed_timer_enabled() -> bool:
	return _feed_timer_enabled


## game/Sandbox.gd's sandbox_toggle_timer hotkey. A no-op call outside
## sandbox is harmless (every real match starts true and nothing else in the
## shipped game ever calls this), but nothing stops a caller from flipping it
## — this file does not gate it on config.sandbox, the same way
## set_process(false) in the test harness is trusted rather than re-checked.
func set_feed_timer_enabled(enabled: bool) -> void:
	_feed_timer_enabled = enabled


func _issue_next_block(slot_id: int) -> void:
	var bag: BlockBag = _bags[slot_id]
	var shape: BlockShape = bag.next()
	_held_shapes[slot_id] = shape
	var preview: Array[BlockShape] = bag.peek(1)
	var next_id: StringName = preview[0].id if preview.size() > 0 else &""
	Events.feed_block_issued.emit(slot_id, shape.id if shape != null else &"", next_id)


func _tick_feed(delta: float) -> void:
	if not _match._is_host():
		return
	if not _feed_timer_enabled:
		# Bontago-mv0.8: sandbox's default state (and sandbox_toggle_timer's
		# "off" position) — feed_time_left is left exactly where it is, so
		# ui/SandboxPanel.gd reads a paused timer, not a frozen countdown
		# drifting toward zero. Bontago-mv0.10: this also means the
		# placement-interval lock below never engages while the timer is
		# paused -- sandbox's own "unlimited blocks" with the timer disabled
		# gets no lock either, by the same reasoning _consume_and_refeed()'s
		# matching DECISION explains.
		return
	if _match.config.hot_seat:
		var active_slot: int = _match.active_slot()
		if active_slot == -1:
			return
		if not _match.slot(active_slot).home_flag_alive:
			_match.advance_turn()
			return
		_feed_time_left[active_slot] = maxf(_feed_time_left[active_slot] - delta, 0.0)
		if _feed_time_left[active_slot] <= 0.0 and not _feed_expired[active_slot]:
			_feed_expired[active_slot] = true
			Events.feed_timer_expired.emit(active_slot)
	else:
		# Spec 2.4 "[ORIGINAL target]": "players act concurrently, each
		# handling their own supplied piece". Every slot's fixed-interval
		# timer runs at once and several blocks may land in the same second;
		# nothing here serialises them.
		for i: int in range(_match._lifecycle._slots.size()):
			if not _match._lifecycle._slots[i].home_flag_alive:
				continue
			if _match._lifecycle._disconnect_grace_left[i] >= 0.0:
				# The peer vanished: its feed stops the moment it does
				# (docs/M3a_PLAN.md, "Disconnects and the in-flight held
				# block") so a player who reconnects inside the grace period
				# has not been auto-dropped a tower's worth of blocks.
				continue
			_feed_time_left[i] = maxf(_feed_time_left[i] - delta, 0.0)
			if _feed_time_left[i] > 0.0 or _feed_expired[i]:
				continue
			if _release_locked[i]:
				# Bontago-mv0.10 (spec 2.4): this interval's one release
				# already happened early -- the slot has been aiming its next
				# piece, locked, since then. The boundary just unlocks it and
				# starts a fresh interval for it; nothing needs forcing, so no
				# feed_timer_expired fires and _feed_expired never needs to
				# latch true for this crossing.
				_release_locked[i] = false
				_feed_time_left[i] = _match.config.block_timer
			else:
				# This interval's piece is still unspent: force it, exactly
				# as spec 2.5's [ORIGINAL] auto-drop always has. _feed_expired
				# latches until _consume_and_refeed(auto_drop = true) resolves
				# the forced placement and starts the next interval.
				_feed_expired[i] = true
				Events.feed_timer_expired.emit(i)


## DECISION (autoload/Match.gd): docs/M3a_PLAN.md says a client runs "no feed
## tick", meaning it decides nothing — but with no local decrement at all the
## HUD's timer ring would sit frozen between the host's 1-per-block feed
## events, which reads as a bug. So a client counts the same timers down for
## display only: it never emits feed_timer_expired, never issues a block and
## never touches the bag, and every replicated feed event resets the timer to
## the host's value, so it cannot drift. Nothing here can duplicate or lose a
## placement, which is what the gate above exists to guarantee.
func _tick_client_display(delta: float) -> void:
	if _match.state() != MatchAutoload.State.PLAYING or _match.config == null:
		return
	for i: int in range(_feed_time_left.size()):
		if not _match.slot(i).home_flag_alive:
			continue
		_feed_time_left[i] = maxf(_feed_time_left[i] - delta, 0.0)


func _build_bags() -> void:
	_bags.clear()
	for i: int in range(_match.slot_count()):
		# DECISION (autoload/Match.gd): MatchConfig has one rng_seed for the
		# whole match; each slot's bag needs its own seed so slots don't deal
		# identical sequences. Spread deterministically from the match seed
		# with a large odd stride so per-slot seeds don't collide for any
		# player_count in spec 2.8's 2-8 range.
		var seed: int = -1
		if _match.config.rng_seed >= 0:
			seed = _match.config.rng_seed + i * 1000003
		_bags.append(BlockBag.new(_match._block_feed_config, seed))


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" placement cadence): "Each
## fixed interval permits one release. Releasing early does not restart the
## interval: the next piece can be positioned but remains release-locked
## until the interval boundary. At expiry, force release only if that
## interval's piece is still unspent." `auto_drop` tells the two cases apart:
## it is true only for the host's own forced release at the interval boundary
## (request_place()'s own doc comment; never taken from the wire), so every
## other call here is the "released early" case.
##
## DECISION (autoload/Match.gd): hot-seat is exempt -- its turn already passes
## to a *different* player's controls the instant a block lands
## (docs/M2_PLAN.md owner decision 1: strict alternation), so the same slot
## can never place twice in a row and there is nothing for a release lock to
## prevent. Spec Part 4 M2 itself calls the hot-seat build a historical test
## harness, not the target cadence ("A separate hot-seat/turn-based test mode
## must not become normal play"), so this keeps hot-seat exactly as M2 shipped
## it rather than growing it a lock it was never meant to need.
func _consume_and_refeed(slot_id: int, auto_drop: bool) -> void:
	# The sequence advances before the new block is issued, so the
	# feed_block_issued that tells the owner "you have a block" already
	# carries the sequence its next intent must quote.
	_feed_seq[slot_id] += 1
	if _match.config.hot_seat:
		_feed_time_left[slot_id] = _match.config.block_timer
		_feed_expired[slot_id] = false
		_issue_next_block(slot_id)
		return

	if auto_drop:
		# The interval's own piece was just forced out at the boundary: the
		# new one starts fresh, unlocked, for a brand new interval.
		_release_locked[slot_id] = false
		_feed_time_left[slot_id] = _match.config.block_timer
		_feed_expired[slot_id] = false
	elif _feed_timer_enabled:
		# Released early, with the real cadence running: the new piece may be
		# aimed but not released until this same interval's boundary -- do
		# NOT touch _feed_time_left, which keeps counting down from when the
		# interval actually started (spec 2.4: "does not restart the
		# interval").
		_release_locked[slot_id] = true
	# else: _feed_timer_enabled is false (sandbox's default, "unlimited
	# blocks", or between _feed_timer_enabled being switched off and any
	# match with it disabled) -- _tick_feed() never runs the interval-
	# boundary logic in that state, so a lock here could never be lifted by
	# anything but this same function. Leaving _release_locked false is what
	# "sandbox with the timer disabled has no lock" means: every placement
	# reissues immediately, exactly like M2's original feed did.
	#
	# Bontago-mv0.10 follow-up: every branch above updates _release_locked/
	# _feed_time_left *before* this call, not after -- _issue_next_block()
	# emits Events.feed_block_issued synchronously, and net/MatchNet.gd's
	# handler reads is_release_locked()/feed_time_left() at that exact
	# instant to replicate them, so a client's mirror must see this slot's
	# post-placement state, not its pre-placement one.
	_issue_next_block(slot_id)


## The value an intent for `slot_id` must quote to be accepted right now. It
## advances on every consumed block, so exactly one intent can spend any one
## held block (docs/M3a_PLAN.md, "Never duplicated, never lost").
func feed_seq(slot_id: int) -> int:
	if slot_id < 0 or slot_id >= _feed_seq.size():
		return -1
	return _feed_seq[slot_id]


## Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): whether `slot_id`'s
## currently held piece may be released right now. game/PlayerController.gd
## reads this every frame to tint the ghost distinctly from the normal
## valid/invalid/hole states -- "a location-valid ghost does not imply that
## the current interval permits release" (spec 2.5). Always false in
## hot-seat and whenever the feed timer is disabled (sandbox's default), for
## the same reasons _consume_and_refeed() never sets it in those cases. On a
## client this is a mirror, kept accurate by apply_replicated_feed()'s
## `host_is_locked`, not decided locally -- a client never runs
## _consume_and_refeed() itself (request_place() is host-only).
func is_release_locked(slot_id: int) -> bool:
	if slot_id < 0 or slot_id >= _release_locked.size():
		return false
	return _release_locked[slot_id]


## Test-only seam (tests/unit/test_match_net.gd, test_remote_intent_
## validation.gd): unlocks `slot_id`'s post-placement interval immediately
## and starts a fresh one for it, exactly what _tick_feed()'s own boundary-
## crossing branch does once `config.block_timer` really elapses. Lets a
## unit test place a slot's held shape more than once in the same frame --
## Bontago-mv0.10's fixed-interval cadence otherwise refuses every deliberate
## release after the first with REASON_NO_BLOCK until that many real
## _process() ticks run. Game code never calls this; it exists so tests don't
## have to reach into _release_locked/_feed_time_left/_feed_expired directly.
func debug_unlock_slot(slot_id: int) -> void:
	if slot_id < 0 or slot_id >= _release_locked.size():
		return
	_release_locked[slot_id] = false
	if _match.config != null:
		_feed_time_left[slot_id] = _match.config.block_timer
	_feed_expired[slot_id] = false


# --- The client's read model (spec 3.4) -------------------------------------

## The host issued `slot_id` a block. Sets the held shape the ghost and the
## HUD read, resets the slot's display timer — which is what keeps the
## client's timer ring honest without a feed tick of its own — and takes the
## host's feed sequence verbatim.
##
## `host_feed_seq` is copied rather than counted up to, because the two ends
## do not start level: the host's first block comes from _begin_playing(),
## which issues without consuming, while a client never runs that at all. A
## client that counted its own would quote a sequence one ahead for the rest
## of the match and have every intent refused.
## Bontago-mv0.10 follow-up: `host_feed_time_left` and `host_is_locked` mirror
## Match.feed_time_left()/is_release_locked() for this slot at the instant
## the host issued this event (net/MatchNet.gd's _on_feed_block_issued reads
## them synchronously off the same emit that carries shape_id/feed_seq -- see
## _consume_and_refeed()'s and _begin_playing()'s own comments on why every
## state update there happens before _issue_next_block()). Without this a
## client's mirror always reset the ring to a full config.block_timer on
## every feed event, which is wrong exactly on an early release: the host's
## real interval did not restart, only the held shape did (spec 2.4 "does not
## restart the interval").
##
## `host_feed_time_left < 0.0` is the sentinel for "not sent" -- kept so an
## older or manufactured event (this file's own tests included) still falls
## back to the pre-existing "assume a fresh interval" behavior instead of
## silently mis-reading a negative duration.
func apply_replicated_feed(
	slot_id: int,
	shape_id: StringName,
	_next_shape_id: StringName,
	host_feed_seq: int,
	host_feed_time_left: float = -1.0,
	host_is_locked: bool = false
) -> void:
	if slot_id < 0 or slot_id >= _held_shapes.size():
		return
	_held_shapes[slot_id] = _shape_by_id(shape_id)
	if host_feed_seq >= 0:
		_feed_seq[slot_id] = host_feed_seq
	if host_feed_time_left >= 0.0:
		_feed_time_left[slot_id] = host_feed_time_left
	elif _match.config != null:
		_feed_time_left[slot_id] = _match.config.block_timer
	if slot_id < _release_locked.size():
		_release_locked[slot_id] = host_is_locked
	_feed_expired[slot_id] = false


## BlockShape.load_all_shapes() scans a directory, so the index is built once
## and only on the instance that needs it: a client, resolving the shape ids
## the host's feed events name.
func _shape_by_id(shape_id: StringName) -> BlockShape:
	if shape_id == &"":
		return null
	if _shapes_by_id.is_empty():
		for shape: BlockShape in BlockShape.load_all_shapes():
			_shapes_by_id[shape.id] = shape
	return _shapes_by_id.get(shape_id) as BlockShape
