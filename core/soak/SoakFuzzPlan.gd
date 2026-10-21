class_name SoakFuzzPlan
extends RefCounted
## Seeded generator of place intents the host must refuse (SOAK_PLAN section 6.3). It never
## produces a legitimate intent, so a seated fuzz client's accepted count must stay exactly zero.

enum Kind { NEGATIVE_SEQ, STALE_SEQ, NON_FINITE_POSE, FOREIGN_SLOT, OUT_OF_DISC, FLOOD }


## One place intent, with the arguments of `MatchNet.submit_place`.
class Intent:
	extends RefCounted
	var kind: Kind = Kind.NEGATIVE_SEQ
	var slot_id: int = -1
	var origin: Vector3 = Vector3.ZERO
	var orientation_index: int = 0
	var free_quat: Quaternion = Quaternion.IDENTITY
	var feed_seq: int = 0


func _init(_rng_seed: int, _config: SoakConfig, _net_config: NetConfig) -> void:
	pass


## The intents to send this tick: one single-intent batch of a seeded random kind, or a FLOOD
## burst. `feed_seq` is the sender's current sequence, `disc_radius_m` the field radius.
func next_batch(_own_slot: int, _feed_seq: int, _disc_radius_m: float) -> Array[Intent]:
	return []
