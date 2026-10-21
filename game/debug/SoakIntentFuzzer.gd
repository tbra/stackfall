class_name SoakIntentFuzzer
extends Node
## Client-side authority probe (SOAK_PLAN section 3): sends the SoakFuzzPlan intents, which the
## host must refuse, through MatchNet.submit_place and logs a SOAK_FUZZ line for each. Main
## creates it when `--soak-fuzz` is on the command line in debug mode and sets `config` before
## add_child.

const _ROLE: StringName = &"client"

const _NET_CONFIG_PATH: String = "res://config/net/net_config.tres"


## The game calls the fuzzer needs, bound by Main so the fuzzer holds no global state.
class Seams:
	extends RefCounted
	## () -> bool: the match is PLAYING.
	var playing: Callable
	## () -> int: this client's slot, -1 when seatless.
	var local_slot: Callable
	## (slot: int) -> int: the slot's current feed sequence.
	var feed_seq: Callable
	## () -> float: the field radius in metres.
	var field_radius: Callable
	## (slot_id, origin, orientation_index, free_quat, auto_drop, feed_seq) -> Variant, as
	## MatchNet.submit_place.
	var submit_place: Callable
	## (text: String) -> void: writes one SOAK_FUZZ line.
	var line: Callable


## Fuzz seed, cadence and flood factor.
var config: SoakConfig = null
## Set before add_child.
var seams: Seams = null

var _plan: SoakFuzzPlan = null
# Seconds the match has been PLAYING, and seconds since the last batch.
var _playing_s: float = 0.0
var _since_batch_s: float = 0.0
var _sent: int = 0


func _ready() -> void:
	_plan = SoakFuzzPlan.new(
		config.fuzz_seed, config, load(_NET_CONFIG_PATH) as NetConfig
	)


func _physics_process(delta: float) -> void:
	if not bool(seams.playing.call()):
		return
	_playing_s += delta
	if _playing_s < config.fuzz_start_after_s:
		return
	_since_batch_s += delta
	if _since_batch_s < config.fuzz_interval_s:
		return
	_since_batch_s = 0.0
	var slot: int = int(seams.local_slot.call())
	if slot < 0:
		return
	var batch: Array[SoakFuzzPlan.Intent] = _plan.next_batch(
		slot, int(seams.feed_seq.call(slot)), float(seams.field_radius.call())
	)
	for intent: SoakFuzzPlan.Intent in batch:
		seams.submit_place.call(
			intent.slot_id, intent.origin, intent.orientation_index, intent.free_quat, false,
			intent.feed_seq
		)
		_sent += 1
		seams.line.call(
			SoakLine.fuzz(_ROLE, _sent, SoakFuzzPlan.Kind.keys()[intent.kind], intent.slot_id)
		)
