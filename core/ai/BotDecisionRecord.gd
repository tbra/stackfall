class_name BotDecisionRecord
extends RefCounted
## Bontago-1t5.11 (BT1, docs/BOT_TRAINING_SOAK_PLAN.md section 1): pure builders for
## the JSONL schema v1 records and the one-line serialiser. No scene-tree or
## autoload access; every input is a value or a core/ai object.
##
## Record kinds: "header", "decision", "outcome", "match_end", "footer".

const KIND_HEADER: String = "header"
const KIND_DECISION: String = "decision"
const KIND_OUTCOME: String = "outcome"
const KIND_MATCH_END: String = "match_end"
const KIND_FOOTER: String = "footer"

## `policy` values on a decision record: trainers keep only "score".
const POLICY_SCORE: String = "score"
const POLICY_SPECIAL: String = "special"


## Rounds `value` to the nearest `step` (3 dp for 0.001); a non-positive step keeps it.
static func round_to(value: float, step: float) -> float:
	if step <= 0.0:
		return value
	return snappedf(value, step)


static func _vec(v: Vector2, step: float) -> Array:
	return [round_to(v.x, step), round_to(v.y, step)]


## Index of the highest-weighted candidate (first on ties, like pick_best's strict
## `>`); -1 when `terms` is empty. Used for the footer's passive policy self-check.
static func scored_best_index(terms: Array[BotScoreTerms], tuning: BotTuning) -> int:
	var best: int = -1
	var best_score: float = -INF
	for i: int in range(terms.size()):
		var value: float = terms[i].weighted(tuning)
		if best < 0 or value > best_score:
			best = i
			best_score = value
	return best


static func candidate_to_dict(candidate: BotCandidate, terms: BotScoreTerms, step: float) -> Dictionary:
	return {
		"o": _vec(candidate.origin, step),
		"r": candidate.orientation_index,
		"h": round_to(candidate.support_height, step),
		"sh": round_to(candidate.shape_height, step),
		"ct": candidate.corner_support_hits,
		"top": candidate.on_top_of_own_stack,
		"terms": [
			round_to(terms.height, step), round_to(terms.goal, step), round_to(terms.stability, step),
			round_to(terms.risk, step), round_to(terms.mode, step),
		],
	}


## One decision record. `meta` carries the scalar identity/state fields (`t`, `slot`, `team`,
## `shape_id`, `feed_seq`, `piece_index`, `state`: Dictionary, `id`: int); `chosen` indexes
## `candidates` (-1 when none); `scored_best` is the argmax recomputed from `terms`.
static func to_dict(
	meta: Dictionary,
	candidates: Array[BotCandidate],
	terms: Array[BotScoreTerms],
	chosen: int,
	scored_best: int,
	placed_origin: Vector2,
	reason: StringName,
	policy: String,
	step: float
) -> Dictionary:
	var cands: Array = []
	for i: int in range(mini(candidates.size(), terms.size())):
		cands.append(candidate_to_dict(candidates[i], terms[i], step))
	return {
		"kind": KIND_DECISION,
		"id": int(meta.get("id", 0)),
		"t": round_to(float(meta.get("t", 0.0)), step),
		"slot": int(meta.get("slot", -1)),
		"team": int(meta.get("team", -1)),
		"shape_id": String(meta.get("shape_id", "")),
		"feed_seq": int(meta.get("feed_seq", 0)),
		"piece_index": int(meta.get("piece_index", 0)),
		"policy": policy,
		"state": meta.get("state", {}),
		"cands": cands,
		"chosen": chosen,
		"placed_origin": _vec(placed_origin, step),
		"reason": String(reason),
		"scored_best": scored_best,
	}


## Outcome record joined to a decision by `id`. `deltas` maps horizon seconds -> d_share.
static func outcome_to_dict(
	decision_id: int, slot: int, horizons_s: PackedFloat32Array, deltas: PackedFloat32Array,
	own_blocks_alive: int, home_alive: bool, step: float
) -> Dictionary:
	var record: Dictionary = {"kind": KIND_OUTCOME, "id": decision_id, "slot": slot}
	for i: int in range(mini(horizons_s.size(), deltas.size())):
		record["d_share_%ds" % int(round(horizons_s[i]))] = round_to(deltas[i], step)
	record["own_blocks_alive_%ds" % int(round(horizons_s[horizons_s.size() - 1] if not horizons_s.is_empty() else 0.0))] = own_blocks_alive
	record["home_alive_%ds" % int(round(horizons_s[horizons_s.size() - 1] if not horizons_s.is_empty() else 0.0))] = home_alive
	return record


static func match_end_to_dict(
	slot: int, team: int, winner_team: int, final_share: float, eliminated_at: float, step: float
) -> Dictionary:
	return {
		"kind": KIND_MATCH_END,
		"slot": slot,
		"team": team,
		"winner_team": winner_team,
		"final_share": round_to(final_share, step),
		"won": winner_team >= 0 and winner_team == team,
		"eliminated_at": round_to(eliminated_at, step),
	}


## The BotTuning weights a trainer needs to rebuild `weighted()`.
static func weights_snapshot(tuning: BotTuning) -> Dictionary:
	return {
		"height": tuning.weight_height,
		"goal_progress": tuning.weight_goal_progress,
		"stability": tuning.weight_stability,
		"risk": tuning.weight_risk,
	}


static func to_json_line(record: Dictionary) -> String:
	return JSON.stringify(record, "", false)
