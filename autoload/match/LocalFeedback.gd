extends RefCounted
## Bontago-1pi.52 (owner playtest 2026-10-03: "the host could hear my block
## rejected sound"): the one answer to "may this machine give its player
## refusal feedback (sound, rumble) for `slot_id`?".
##
## Events.placement_rejected is a fact about a slot, emitted on the host for
## every slot it refuses -- a remote client's, a bot's, its own -- so a reaction
## that plays a sound or buzzes a pad must not fire for just any slot.
## It does only when a human at *this* machine drives the slot: Net.is_local_slot()
## (the host's own seat, a client's own seat, or every seat in offline
## hot-seat) and not a bot. Match-layer state (slot.is_bot) is read through the
## Match autoload; the session through Net, so this stays transport-neutral.
## ui/HUD.gd and game/PlayerController.gd already apply the same per-viewer
## slot filter to their own reactions.
##
## No class_name on purpose: Sfx and Rumble preload() it, so a checkout whose
## global class cache predates this file still compiles.


## True when `slot_id` is a human seat driven by this instance's own input.
## An unknown slot (no match running yet) is not a bot, so only Net decides.
static func is_own_human_slot(slot_id: int) -> bool:
	if not Net.is_local_slot(slot_id):
		return false
	var seat: PlayerSlot = Match.slot(slot_id)
	return seat == null or not seat.is_bot
