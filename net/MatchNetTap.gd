class_name MatchNetTap
extends RefCounted
## The one typed test seam on MatchNet and Match. Production holds null; a test installs a tap to
## force the deferred activation path and to capture what the host would have put on the wire
## (NetFanout.can_send() is false in a unit test, so the wire itself proves nothing). Game code
## never creates one.

## Forces the deferred late_activate() path in a headless run (MatchNet and Match both honour it).
var defer_activation: bool = false
## When true the host collects impacts and records every batch even without a live peer.
var capture_impacts: bool = false
## Batches recorded while capture_impacts is on, in send order.
var impact_batches: Array[PackedByteArray] = []


## Records one impact batch the host built.
func on_impacts(packet: PackedByteArray) -> void:
	impact_batches.append(packet)
