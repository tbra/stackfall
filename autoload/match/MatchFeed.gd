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

## Bontago-1pi.18.1 (QoL experiments 1 and 2; see config/QolExperiments.gd).
## _backlog[slot] holds blocks queued instead of force-dropped (host only);
## _backlog_mirror/_paused_mirror are what a client displays, kept by
## apply_replicated_qol(). _timer_pause is null unless the toggle is on.
var _backlog: Array[Array] = []
var _backlog_mirror: Array[int] = []
var _paused_mirror: Array[bool] = []
var _timer_pause: TimerPause = null
var _qol_scan_left: float = 0.0
## Reused by the topple scan / pause tick so the 0.25 s scan does not allocate.
var _qol_counts: PackedInt32Array = PackedInt32Array()
var _qol_no_counts: PackedInt32Array = PackedInt32Array()
var _qol_paused_before: Array[bool] = []
## Test seam: Callable() -> PackedInt32Array replaces the block-velocity scan.
var _qol_moving_counts_source: Callable = Callable()

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
## hot-seat and turn_based -- see _consume_and_refeed()'s DECISION for why
## neither ever sets this. Parallel to Match's slots, like every other
## per-slot feed array.
var _release_locked: Array[bool] = []
## A gift uses the ordinary bag's carrier shape, but is a distinct release.
## These dictionaries are cleared when a new bag is built or a match resets.
var _next_gift_shapes: Dictionary = {}
var _held_is_gift: Dictionary = {}
var _suppress_gift_roll: bool = false

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
	if slot_id >= 0 and slot_id < _backlog.size() and not _backlog[slot_id].is_empty():
		return _backlog[slot_id][0] as BlockShape
	if _next_gift_shapes.has(slot_id):
		return _next_gift_shapes[slot_id] as BlockShape
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


## Bontago-1pi.18.1: blocks the slot has queued (host: the real backlog; client:
## the replicated mirror). Always 0 with the backlog toggle off.
func backlog_count(slot_id: int) -> int:
	if _match._is_host():
		if slot_id < 0 or slot_id >= _backlog.size():
			return 0
		return _backlog[slot_id].size()
	if slot_id < 0 or slot_id >= _backlog_mirror.size():
		return 0
	return _backlog_mirror[slot_id]


## Bontago-1pi.18.1: whether the slot's block timer is frozen by the pause toggle.
func timer_paused(slot_id: int) -> bool:
	if _match._is_host():
		return _timer_pause != null and _timer_pause.is_paused(slot_id)
	if slot_id < 0 or slot_id >= _paused_mirror.size():
		return false
	return _paused_mirror[slot_id]


## Client: applies the host's QoL feed event (backlog count + paused flag).
func apply_replicated_qol(slot_id: int, backlog: int, paused: bool) -> void:
	if slot_id < 0 or slot_id >= _backlog_mirror.size():
		return
	_backlog_mirror[slot_id] = clampi(backlog, 0, QolExperiments.BACKLOG_MAX_CEILING)
	_paused_mirror[slot_id] = paused


func _issue_next_block(slot_id: int, from_backlog: bool = true) -> void:
	var bag: BlockBag = _bags[slot_id]
	var shape: BlockShape = null
	var is_gift: bool = false
	var popped: bool = false
	if from_backlog and slot_id < _backlog.size() and not _backlog[slot_id].is_empty():
		# DECISION (Bontago-1pi.18.1): a queued block is handed out before the
		# bag is touched, so placing "takes from the backlog first"; a pending
		# gift carrier stays pending for the first bag draw after the backlog.
		shape = _backlog[slot_id].pop_front() as BlockShape
		popped = true
	else:
		shape = bag.next()
		is_gift = _next_gift_shapes.has(slot_id)
		_next_gift_shapes.erase(slot_id)
	_held_is_gift[slot_id] = is_gift
	if is_gift:
		_match._gifts.activate_next_special(slot_id)
	else:
		_match._gifts.clear_held_special(slot_id)
	_held_shapes[slot_id] = shape
	var preview: Array[BlockShape] = bag.peek(1)
	var next_id: StringName = preview[0].id if preview.size() > 0 else &""
	if slot_id < _backlog.size() and not _backlog[slot_id].is_empty():
		next_id = (_backlog[slot_id][0] as BlockShape).id
	var was_suppressed: bool = _suppress_gift_roll
	_suppress_gift_roll = was_suppressed or is_gift
	Events.feed_block_issued.emit(slot_id, shape.id if shape != null else &"", next_id)
	_suppress_gift_roll = was_suppressed
	if popped:
		_emit_qol_state(slot_id)


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
	_tick_qol_pause(delta)
	if _match.config.is_sequential_play():
		# stackfall-reviewer finding (Bontago-keo.10, M6 B4 turn-based review):
		# turn_based used to fall into the concurrent `else` branch below,
		# which ticked down EVERY slot's timer regardless of whose turn it
		# was -- a non-active slot could expire and auto-drop, and
		# net/MatchNet.gd's host-side check refuses that placement as
		# NOT_YOUR_TURN (docs/M6_PLAN.md B4: only the active slot may act).
		# turn_based shares hot-seat's one-actor-at-a-time shape (spec 2.7 vs.
		# spec 2.4's concurrent "[ORIGINAL target]"), so it takes the same
		# single-slot branch, including the recovery just below.
		var active_slot: int = _match.active_slot()
		if active_slot == -1:
			return
		if not _match.slot(active_slot).home_flag_alive:
			# stackfall-reviewer finding: without this, a turn_based active
			# slot eliminated before it ever places (e.g. a hole from another
			# player's territory capture) left _turn_settle_wait_left at its
			# initial -1.0 -- no settle-wait is running to advance the turn --
			# and the match deadlocked on a slot that can never place again.
			# Mirrors hot-seat's own pre-existing recovery exactly.
			#
			# DECISION (autoload/match/MatchFeed.gd, not settled by docs/
			# M6_PLAN.md's B4 section): this call is a no-op whenever a
			# settle-wait IS currently running (the active slot placed, then
			# died before its blocks finished settling) -- advance_turn()
			# itself doesn't touch MatchLifecycle._turn_settle_wait_left, so a
			# stale wait would still fire its own advance_turn() once settled
			# or capped, double-advancing the turn. That case is narrow (a
			# slot needs to lose its home flag strictly between placing and
			# settling, e.g. a special detonating mid-fall) and
			# MatchLifecycle.gd is out of this package's owned files; flagged
			# for the MatchLifecycle owner rather than fixed here. The
			# reported deadlock this package fixes is the more common case --
			# eliminated BEFORE ever placing, when no wait is running yet, so
			# this call is exactly the hot-seat recovery it mirrors.
			_match.advance_turn()
			return
		if timer_paused(active_slot):
			return
		_feed_time_left[active_slot] = maxf(_feed_time_left[active_slot] - delta, 0.0)
		if _feed_time_left[active_slot] <= 0.0 and not _feed_expired[active_slot]:
			_feed_expired[active_slot] = true
			Events.feed_timer_expired.emit(active_slot)
	else:
		# Spec 2.4 "[ORIGINAL target]": "players act concurrently, each
		# handling their own supplied piece". Every slot's fixed-interval
		# timer runs at once and several blocks may land in the same second;
		# nothing here serialises them. Neither hot_seat nor turn_based ever
		# reaches this branch (both take the single-active-slot branch above).
		for i: int in range(_match._lifecycle._slots.size()):
			if not _match._lifecycle._slots[i].home_flag_alive:
				continue
			if _match._lifecycle._disconnect_grace_left[i] >= 0.0:
				# The peer vanished: its feed stops the moment it does
				# (docs/M3a_PLAN.md, "Disconnects and the in-flight held
				# block") so a player who reconnects inside the grace period
				# has not been auto-dropped a tower's worth of blocks.
				continue
			if timer_paused(i):
				# Bontago-1pi.18.1 (QoL 1): frozen by an event or a topple.
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
			elif _try_backlog_push(i):
				# Bontago-1pi.18.1 (QoL 2): queued instead of forced.
				pass
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
	if not MatchAutoload.is_live(_match.state()) or _match.config == null:
		return
	for i: int in range(_feed_time_left.size()):
		if not _match.slot(i).home_flag_alive:
			continue
		if _paused_mirror.size() > i and _paused_mirror[i]:
			continue
		_feed_time_left[i] = maxf(_feed_time_left[i] - delta, 0.0)


## Bontago-1pi.18.1 (QoL 2): at expiry, if the backlog toggle is on and has room,
## queue the held block and hand the slot a fresh one with a new interval
## instead of force-dropping. Returns false (caller force-drops) when the toggle
## is off, the backlog is full, or the held block is a gift.
func _try_backlog_push(slot_id: int) -> bool:
	var qol: QolExperiments = _match.config.qol
	if qol == null or qol.effective_backlog_max() <= 0 or slot_id >= _backlog.size():
		return false
	if is_held_gift(slot_id) or _backlog[slot_id].size() >= qol.effective_backlog_max():
		return false
	var held: BlockShape = _held_shapes[slot_id]
	if held == null:
		return false
	# The fresh block comes from the bag, so the queued one is not handed
	# straight back; _issue_next_block() pops the backlog only AFTER this draw.
	var fresh: Array[BlockShape] = _bags[slot_id].peek(1)
	if fresh.is_empty():
		return false
	_feed_seq[slot_id] += 1
	_feed_time_left[slot_id] = _match.config.block_timer
	_feed_expired[slot_id] = false
	_backlog[slot_id].append(held)
	_issue_from_bag(slot_id)
	_emit_qol_state(slot_id)
	return true


## Like _issue_next_block() but always draws the bag (skips the backlog head).
func _issue_from_bag(slot_id: int) -> void:
	_issue_next_block(slot_id, false)


func _emit_qol_state(slot_id: int) -> void:
	Events.qol_feed_changed.emit(slot_id, backlog_count(slot_id), timer_paused(slot_id))


## Bontago-1pi.18.1 (QoL 1): feeds the pause rule (topple scan on an interval)
## and announces per-slot pause changes.
func _tick_qol_pause(delta: float) -> void:
	if _timer_pause == null:
		return
	var counts: PackedInt32Array = _qol_no_counts
	_qol_scan_left -= delta
	if _qol_scan_left <= 0.0:
		_qol_scan_left = _match.config.qol.topple_scan_interval_s
		counts = _qol_moving_counts()
	_qol_paused_before.resize(_feed_time_left.size())
	for i: int in range(_qol_paused_before.size()):
		_qol_paused_before[i] = _timer_pause.is_paused(i)
	_timer_pause.update(delta, counts)
	for i: int in range(_qol_paused_before.size()):
		if _qol_paused_before[i] != _timer_pause.is_paused(i):
			_emit_qol_state(i)


## Per-slot count of own placed blocks above the topple speed threshold.
func _qol_moving_counts() -> PackedInt32Array:
	if _qol_moving_counts_source.is_valid():
		return _qol_moving_counts_source.call() as PackedInt32Array
	var counts: PackedInt32Array = _qol_counts
	counts.resize(_feed_time_left.size())
	counts.fill(0)
	var registry: BlockRegistry = _match.registry()
	if registry == null:
		return counts
	var limit_sq: float = _match.config.qol.topple_speed_threshold_mps
	limit_sq *= limit_sq
	registry.count_fast_blocks_by_owner(limit_sq, counts)
	return counts


## A special triggered: pauses timers per QolExperiments.pause_event_s.
func note_special_triggered() -> void:
	if _timer_pause == null:
		return
	var before: Array[bool] = []
	for i: int in range(_feed_time_left.size()):
		before.append(_timer_pause.is_paused(i))
	_timer_pause.note_special()
	for i: int in range(before.size()):
		if before[i] != _timer_pause.is_paused(i):
			_emit_qol_state(i)


func _build_bags() -> void:
	_bags.clear()
	_backlog.clear()
	_backlog_mirror.clear()
	_paused_mirror.clear()
	_timer_pause = null
	_qol_scan_left = 0.0
	if _match.config.qol != null and _match.config.qol.timer_pause_enabled:
		_timer_pause = TimerPause.new(_match.config.qol, _match.slot_count())
	_next_gift_shapes.clear()
	_held_is_gift.clear()
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
		_backlog.append([])
		_backlog_mirror.append(0)
		_paused_mirror.append(false)


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
##
## stackfall-reviewer finding (Bontago-keo.10, M6 B4 turn-based review):
## turn_based shares the same exemption -- its turn also passes to a
## different slot's controls once the settle-wait ends (docs/M6_PLAN.md B4),
## just not the instant a block lands, so the same slot likewise never places
## twice in the same turn and never needs a release lock either.
func _consume_and_refeed(slot_id: int, auto_drop: bool) -> void:
	var released_gift: bool = is_held_gift(slot_id)
	# The sequence advances before the new block is issued, so the
	# feed_block_issued that tells the owner "you have a block" already
	# carries the sequence its next intent must quote.
	_feed_seq[slot_id] += 1
	if _match.config.is_sequential_play():
		_feed_time_left[slot_id] = _match.config.block_timer
		_feed_expired[slot_id] = false
		_issue_next_block(slot_id)
		return
	if released_gift and not _feed_expired[slot_id]:
		# DECISION: a gift consumes its own exception, not an ordinary window.
		# Keep the original clock and ordinary release eligibility intact.
		_suppress_gift_roll = true
		_issue_next_block(slot_id)
		_suppress_gift_roll = false
		return

	if auto_drop or _feed_expired[slot_id]:
		# The interval's own piece was just forced out at the boundary: the
		# new one starts fresh, unlocked, for a brand new interval.
		#
		# Bontago-2lr: `_feed_expired[slot_id]` can be true here with
		# `auto_drop == false` -- the interval's piece was still unspent when
		# `_tick_feed()` latched `_feed_expired` true and fired
		# `feed_timer_expired` (see that function's own comment), but nobody
		# answered it with the host's own forced auto_drop placement before
		# the slot's owner placed voluntarily instead (a fixture/test with no
		# controller listening; in the real game PlayerController/MatchNet
		# always auto-drop unconditionally on that signal, so this race does
		# not arise there -- see their own `_on_feed_timer_expired()`).
		# Spec 2.4 "[ORIGINAL target]": "At expiry, force release only if
		# that interval's piece is still unspent" -- this placement is
		# exactly the piece becoming spent, so it resolves the expiry the
		# same way the host's own forced release would have. Without this,
		# `_feed_expired[slot_id]` stayed latched true forever (nothing but
		# this branch or `_tick_feed()`'s own boundary-crossing ever clears
		# it, and that function skips a slot for as long as
		# `_feed_expired[i]` is true), so `_tick_feed()` never counted this
		# slot's timer down again and its next voluntary release found itself
		# `is_release_locked()` with no boundary left to unlock it --
		# REASON_NO_BLOCK forever.
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
	return _release_locked[slot_id] and not is_held_gift(slot_id)


func is_held_gift(slot_id: int) -> bool:
	return bool(_held_is_gift.get(slot_id, false))


## A claim replaces the bag's next draw. The next draw after the discarded
## one supplies the gift carrier shape; a later claim discards that carrier.
func replace_next_with_gift(slot_id: int) -> StringName:
	if slot_id < 0 or slot_id >= _bags.size():
		return &""
	_bags[slot_id].next()
	var preview: Array[BlockShape] = _bags[slot_id].peek(1)
	if preview.is_empty():
		return &""
	_next_gift_shapes[slot_id] = preview[0]
	return preview[0].id


## Bontago-1pi.18.2: hands `slot_id` its pending gift carrier right now (the
## gift slot's use), in place of the piece in hand. The block timer keeps
## running its current window, but never below `min_window_s` so a gift
## activated just before the boundary is not auto-dropped at once; the sequence
## bump retires any in-flight intent for the piece that was swapped out.
func issue_gift_now(slot_id: int, min_window_s: float = 0.0) -> void:
	_feed_seq[slot_id] += 1
	_issue_next_block(slot_id, false)
	if not _feed_expired[slot_id]:
		_feed_time_left[slot_id] = maxf(_feed_time_left[slot_id], min_window_s)


func apply_replicated_next_gift(slot_id: int, shape_id: StringName) -> void:
	var shape: BlockShape = _shape_by_id(shape_id)
	if shape != null:
		_next_gift_shapes[slot_id] = shape


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
	if host_feed_seq >= 0 and host_feed_seq < _feed_seq[slot_id]:
		return
	var is_gift: bool = _next_gift_shapes.has(slot_id)
	_next_gift_shapes.erase(slot_id)
	_held_is_gift[slot_id] = is_gift
	if is_gift:
		_match._gifts.activate_next_special(slot_id)
	else:
		_match._gifts.clear_held_special(slot_id)
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


## M6 B2, game/Sandbox.gd's block-picker OptionButton: forces `slot_id`'s
## currently held shape to `shape_id` without touching the bag, so a tester
## can drop an exact shape on demand instead of waiting on the bag's draw
## order. Gated exactly like MatchGifts.debug_queue_special() (that
## function's own comment) -- host-only and config.sandbox-only, so a real
## match can never have its held shape overwritten by a debug seam even if
## something mistakenly called this host-side. Re-emits Events.
## feed_block_issued exactly like _issue_next_block() does, so every listener
## that reacts to a newly-held shape (ghost, HUD, bot controllers) picks the
## forced shape up the normal way, with no second code path to keep in sync.
## Does not touch _feed_seq -- this is not a real consume, so no in-flight
## intent for the previous held shape is invalidated by it.
##
## DECISION (autoload/match/MatchFeed.gd): game/Sandbox.gd calls this
## directly as `Match._feed.debug_force_next_shape(...)` rather than through a
## new one-line Match wrapper (the shape debug_queue_special/set_special_
## drawer/etc. all have on autoload/Match.gd) -- docs/M6_PLAN.md's package B2
## explicitly counts this file as the *only* autoload/match/ append this
## package owns; autoload/Match.gd itself is out of this package's file list.
func debug_force_next_shape(slot_id: int, shape_id: StringName) -> void:
	if not _match._is_host():
		return
	if _match.config == null or not _match.config.sandbox:
		return
	if slot_id < 0 or slot_id >= _held_shapes.size():
		return
	var shape: BlockShape = _shape_by_id(shape_id)
	if shape == null:
		push_warning("MatchFeed: debug_force_next_shape(%s) is not a known shape id; ignoring" % [shape_id])
		return
	_held_shapes[slot_id] = shape
	var preview: Array[BlockShape] = _bags[slot_id].peek(1) if slot_id < _bags.size() else []
	var next_id: StringName = preview[0].id if preview.size() > 0 else &""
	Events.feed_block_issued.emit(slot_id, shape.id, next_id)


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
