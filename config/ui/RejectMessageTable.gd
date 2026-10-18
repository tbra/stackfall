class_name RejectMessageTable
extends Resource
## Plain sentences for the placement/throw refusal reasons the host sends to the HUD
## (PlacementRules.REASON_*, ThrowRules.REASON_NOT_A_SPECIAL). Loaded as
## config/ui/reject_message_table.tres so the HUD carries no strings. Presentation only.
## Not an F4 tuning panel resource (no hints entry needed).

## Reason id (String) -> one short sentence that tells the player what to do.
@export var messages: Dictionary = {}

## Shown for a reason id with no entry in `messages`.
@export var fallback_message: String = "You can't place that block there."


## True when `reason` has its own sentence.
func has_message(reason: StringName) -> bool:
	return messages.has(String(reason))


## The sentence for `reason`, or fallback_message (with a debug warning) when unknown.
func message_for(reason: StringName) -> String:
	if has_message(reason):
		return String(messages[String(reason)])
	if OS.is_debug_build():
		push_warning("RejectMessageTable: no message for reason '%s'" % reason)
	return fallback_message
