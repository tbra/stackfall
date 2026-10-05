class_name GiftBlink
## Visual-only blinking effect for gift warning (Bomb).
##
## `apply` modulates the gift visual's emissive channel with a blinking pattern.
## Blink phase is derived client-side from `Block.gift_id` and local spawn age
## (no RPC needed). Period and duration are configurable.
##
## Depends on: Block


## Applies a blinking emissive flash to the gift visual on block.
## Blink period_s controls flash frequency; duration_s is total effect duration.
## Client-only: blink phase is computed locally from block gift_id and elapsed time.
static func apply(block: Block, period_s: float, duration_s: float) -> void:
	pass
