class_name GiftExplosionFxTuning
extends Resource
## Presentation tunables for the Bomb/Rocket blast puff drawn by GiftFxPresenter on
## every peer. Loaded from config/specials/fx/gift_explosion_fx_tuning.tres. Visual-only:
## not in the F4 tuning panel, so no tuning_panel_hints entries (same as GiftBlinkTuning).

## Puff quad size as a multiple of the blast radius (the quad spans this many radii).
@export var size_per_blast_radius: float = 1.0

## Puff opacity scale (0 invisible, 1 solid).
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.95

## Puff tint multiplied into the flipbook.
@export var tint: Color = Color(1.0, 0.8, 0.5, 1.0)

## Flipbook playback speed (frames per second) and frame count of the impact atlas.
@export var fps: float = 30.0
@export var frame_count: int = 16

## Whether to use the hard (sharp) atlas rather than the soft one.
@export var hard: bool = true
