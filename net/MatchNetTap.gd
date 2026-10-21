class_name MatchNetTap
extends RefCounted
## The one typed test seam on MatchNet and Match. Production holds null; a test installs a tap to
## force the deferred activation path. Game code never creates one.

## Forces the deferred late_activate() path in a headless run (MatchNet and Match both honour it).
var defer_activation: bool = false
