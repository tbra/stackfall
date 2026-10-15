class_name DiscShakeConfig
extends Resource
## Bontago-1pi.110: which gift specials shake the camera. Only events that
## shake the disc itself or risk toppling towers do; cosmetic ones (volcano
## spew, landings, UI) never do. Not shown in the F4 panel on purpose.

## Specials whose trigger gives one decaying shake impulse, when it happens
## within `max_distance_field_factor` x the field radius of the disc centre.
@export var impulse_special_ids: Array[StringName] = [&"anvil", &"bomb", &"rocket"]

## Bontago-1pi.110 (review fix): the earthquake's special_triggered fires at
## the END of the quake, so it cannot drive the shake. Instead the camera
## shakes while the disc itself is visibly tilting faster than this (rad/s),
## measured from Field.tilt_vector() on every peer (clients get the tilt from
## the replicated disk state), so it tracks the quake's real active window
## with no duplicated duration.
@export var disc_tilt_rate_threshold: float = 0.05

## Disc-motion shake amplitude as a fraction of CameraShakeConfig.max_offset_m.
@export var disc_tilt_amplitude_fraction: float = 0.5

## Impulse specials farther than this many field radii from the disc centre
## do not shake the camera.
@export var max_distance_field_factor: float = 1.5
