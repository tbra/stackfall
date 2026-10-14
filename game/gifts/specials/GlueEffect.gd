class_name GlueEffect
extends SpecialEffect
## Impact/fuse activation grants the owner a fixed number of future glue
## drops. The shared SpecialDef resource holds tuning only; MatchGifts owns
## each slot's mutable charge count.

@export_range(1, 100, 1) var drop_charges: int = 5


func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null:
		return
	MatchContext.current().grant_glue_drops(block.owner_slot, drop_charges)
