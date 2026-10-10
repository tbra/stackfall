class_name BotIntent
extends RefCounted
## Bot V2 strategy intent (docs/BOT_AI_REDESIGN.md 2.3): what the bot is trying
## to achieve with the current piece. Data only. P1 creates the shape; BotStrategy
## (P4) fills it. Kind values double as bit positions in
## BotDifficultyProfile.intent_mask.

enum Kind { RACE, ANCHOR, FINISH, HOLD, DEFEND, STRIKE, SIEGE, AREA }
## Evaluation terms an intent weights (BotEvaluator, P3).
enum Term { REACH, AREA, KILL, EXPOSURE, TIP, WASTE }

var kind: Kind = Kind.RACE
var target: Vector2 = Vector2.ZERO
var focus_circle: int = -1
## Indexed by Term.
var weights: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	weights.resize(Term.size())


## True when `kind_value` is enabled in a BotDifficultyProfile.intent_mask bit set.
static func is_enabled(mask: int, kind_value: Kind) -> bool:
	return (mask & (1 << int(kind_value))) != 0
