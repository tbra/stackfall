class_name BlockBag
extends RefCounted
## The weighted "bag" randomizer (spec 2.4), replacing M1's SimpleBlockFeed.
##
## Spec 2.4: "Weights are set per shape in BlockFeedConfig. Use a 'bag'
## randomizer so no player goes long without getting a stabilizing shape."
##
## **Algorithm.** A bag holds round(weight * bag_multiplier) copies of each
## shape, at least one each, shuffled with a seeded RandomNumberGenerator.
## next() draws from the front; when the bag empties, a fresh one is built and
## shuffled. Before shuffling, the bag is checked against
## min_stabilizers_per_bag: if it holds fewer copies of the shapes named in
## stabilizer_ids than that, extra stabilizer copies are added until it does.
## That is the "no player goes long without a stabilizing shape" guarantee,
## and it is a property a unit test can assert over many bags.
##
## The seed is per player slot and comes from MatchConfig.rng_seed, so a
## replayed match with the same seed deals the same blocks. Pure logic: no
## scene tree (CLAUDE.md).

var _config: BlockFeedConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(config: BlockFeedConfig, rng_seed: int = -1) -> void:
	_config = config
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


func config() -> BlockFeedConfig:
	return _config


@warning_ignore_start("unused_parameter")
## The shapes this bag deals from: BlockFeedConfig.shapes, or every shape
## under res://config/blocks/ via BlockShape.load_all_shapes() when that is
## empty.
func shapes() -> Array[BlockShape]:
	return []


## Effective weight of a shape: the BlockFeedConfig override if there is one,
## otherwise BlockShape.weight. Never returns a non-positive number.
func weight_of(shape: BlockShape) -> float:
	return 1.0


## Draws the next shape, refilling the bag when it runs dry. Never null once
## the feed has at least one shape.
func next() -> BlockShape:
	return null


## The next `count` shapes without consuming them, for the HUD's next-block
## preview (spec 2.4: the next block, optionally the next 3). Peeking across a
## bag boundary refills first, so the preview never goes short.
func peek(count: int = 1) -> Array[BlockShape]:
	return []


## How many draws are left before the bag refills. Tests use it to line
## themselves up on a bag boundary.
func remaining() -> int:
	return 0


## Total draws made so far, across all bags.
func draw_count() -> int:
	return 0
@warning_ignore_restore("unused_parameter")
