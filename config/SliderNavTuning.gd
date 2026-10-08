class_name SliderNavTuning
extends Resource
## Bontago-1pi.119: keyboard/gamepad step size for fine-grained menu sliders (Options + Lobby).
## Read by ui/SliderNav.gd. Not one of the F4 tuning panel's resource classes, so no
## config/tuning_panel_hints.tres entry is needed.

## A fine slider (more than this many native steps across its range) moves by
## range / steps_per_range per ui_left / ui_right press (1/20 of the range by default);
## coarser sliders (the minute timers, disc size) keep their own step.
@export var steps_per_range: int = 20
