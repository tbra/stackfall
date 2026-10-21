class_name SoakFuzzPlan
extends RefCounted
## Seeded generator of place intents the host must refuse (SOAK_PLAN section 6.3). It never
## produces a legitimate intent, so a seated fuzz client's accepted count must stay exactly zero.

enum Kind { NEGATIVE_SEQ, STALE_SEQ, NON_FINITE_POSE, FOREIGN_SLOT, OUT_OF_DISC, FLOOD }

const _AXES: int = 3

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _config: SoakConfig
var _net_config: NetConfig


## One place intent, with the arguments of `MatchNet.submit_place`.
class Intent:
	extends RefCounted
	var kind: Kind = Kind.NEGATIVE_SEQ
	var slot_id: int = -1
	var origin: Vector3 = Vector3.ZERO
	var orientation_index: int = 0
	var free_quat: Quaternion = Quaternion.IDENTITY
	var feed_seq: int = 0


func _init(rng_seed: int, config: SoakConfig, net_config: NetConfig) -> void:
	_rng.seed = rng_seed
	_config = config
	_net_config = net_config


## The intents to send this tick: one single-intent batch of a seeded random kind, or a FLOOD
## burst. `feed_seq` is the sender's current sequence, `disc_radius_m` the field radius.
func next_batch(own_slot: int, feed_seq: int, disc_radius_m: float) -> Array[Intent]:
	var kind: Kind = Kind.values()[_rng.randi_range(0, Kind.size() - 1)]
	var batch: Array[Intent] = []
	if kind == Kind.FLOOD:
		var count: int = ceili(_config.fuzz_flood_factor * float(_net_config.flood_place_burst))
		for _i: int in count:
			batch.append(_intent(kind, own_slot, feed_seq, disc_radius_m))
	else:
		batch.append(_intent(kind, own_slot, feed_seq, disc_radius_m))
	return batch


## One intent of `kind`: a plausible in-disc pose and the sender's own slot and sequence, with
## exactly the one fault the kind names (a FLOOD intent carries a non-finite pose, so every one
## is refused even when the flood gate lets it through).
func _intent(kind: Kind, own_slot: int, feed_seq: int, disc_radius_m: float) -> Intent:
	var intent: Intent = Intent.new()
	intent.kind = kind
	intent.slot_id = own_slot
	intent.feed_seq = feed_seq
	intent.origin = Vector3(
		_rng.randf_range(-disc_radius_m, disc_radius_m), 0.0,
		_rng.randf_range(-disc_radius_m, disc_radius_m)
	)
	match kind:
		Kind.NEGATIVE_SEQ:
			intent.feed_seq = -1 - _rng.randi_range(0, maxi(feed_seq, 0))
		Kind.STALE_SEQ:
			intent.feed_seq = feed_seq - 1
		Kind.FOREIGN_SLOT:
			intent.slot_id = own_slot + 1
		Kind.OUT_OF_DISC:
			# A corner of the bounding square is sqrt(2) radii from the centre.
			var sign_x: float = 1.0 if _rng.randi_range(0, 1) == 0 else -1.0
			var sign_z: float = 1.0 if _rng.randi_range(0, 1) == 0 else -1.0
			intent.origin = Vector3(sign_x * disc_radius_m, 0.0, sign_z * disc_radius_m)
		Kind.NON_FINITE_POSE, Kind.FLOOD:
			intent.origin[_rng.randi_range(0, _AXES - 1)] = NAN
	return intent
