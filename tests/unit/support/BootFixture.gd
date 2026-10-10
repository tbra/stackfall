extends Node
## Bontago-1pi.11.80 fixture for test_boot: a scene whose script graph preloads resources, so
## a threaded load of it has real work to do.

const TUNING: Resource = preload("res://config/physics_tuning.tres")
