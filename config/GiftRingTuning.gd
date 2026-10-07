class_name GiftRingTuning
extends Resource
## Pulse ring under a landed gift crate (Bontago-1pi.85.57), drawn by the shared
## PulseRing (the same node the home beacons use). Presentation only.

@export var color: Color = Color(1.0, 0.89, 0.48, 1.0)
## Outer radius (m) and band thickness (m) of the ring.
@export var outer_radius_m: float = 1.1
@export var thickness_m: float = 0.12
@export var segments: int = 48
## Height (m) of the ring above the crate origin (the crate's centre).
@export var height_m: float = -0.27
## Seconds for one pulse cycle; 0 or less holds a steady glow.
@export var pulse_period_s: float = 1.6
## Fractional swing of the ring radius and of its emission energy.
@export var pulse_scale_amplitude: float = 0.12
@export var pulse_emission_amplitude: float = 0.4
## Base emission energy multiplier.
@export var emission: float = 1.6
