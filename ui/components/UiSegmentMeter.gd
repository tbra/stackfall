class_name UiSegmentMeter
extends Control
## STUB (Bontago-1pi.159.4 C1a): the typed public API of the design system's SegmentMeter (cells,
## Bungee readout). It will replace ui/SegmentMeter.gd (an overlay on an HSlider). Built in C2.
## TODO(C2): cells, value readout, ui_left/right, row item METER.

@warning_ignore("unused_signal")
signal value_changed(value: int)

@export var step_count: int = 5
@export var value: int = 0
## Display only: turns the value into the readout text.
var formatter: Callable = Callable()
