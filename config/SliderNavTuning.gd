class_name SliderNavTuning
extends Resource
## Bontago-1pi.119: keyboard/gamepad step size for fine-grained menu sliders (Options + Lobby).
## Read by ui/SliderNav.gd. Not one of the F4 tuning panel's resource classes, so no
## config/tuning_panel_hints.tres entry is needed.

## A fine slider (more than this many native steps across its range) moves by
## range / steps_per_range per ui_left / ui_right press (1/20 of the range by default);
## coarser sliders (the minute timers, disc size) keep their own step.
@export var steps_per_range: int = 20

## Bontago-1pi.142: holding ui_left / ui_right (d-pad, stick or key) steps once at once, then
## repeats every repeat_interval_sec after repeat_delay_sec. Not the OS/engine echo.
@export var repeat_delay_sec: float = 0.45
@export var repeat_interval_sec: float = 0.15
## A stick that pressed a direction stays "held" until |axis| drops below this (hysteresis;
## the ui press threshold is the input action's deadzone), so drift near it never retriggers.
@export_range(0.0, 1.0, 0.01) var stick_release_threshold: float = 0.25

## Bontago-1pi.152 stick friction. # DECISION: values chosen by the implementer.
## A stick must pass this to press a step (above stick_release_threshold, and above the ui action
## deadzone so a slow push cannot re-press from the deadzone band).
@export_range(0.0, 1.0, 0.01) var stick_press_threshold: float = 0.5
## Only a stick pushed at least this far auto-repeats; a partial push gives exactly one step.
@export_range(0.0, 1.0, 0.01) var stick_repeat_threshold: float = 0.9
## Full-deflection hold: first repeat after this long, then every stick_repeat_interval_sec
## (slower than the d-pad / key repeat).
@export var stick_repeat_delay_sec: float = 0.6
@export var stick_repeat_interval_sec: float = 0.2
