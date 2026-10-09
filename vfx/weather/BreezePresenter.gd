class_name BreezePresenter
extends Node3D
## Bontago-470.2: draws each Breeze gust as a brief local swirl of cel streaks
## (GustPresentation) from Events.breeze_gust_started, identically on the host
## and on clients. Bounded: at most BreezeTuning.max_presented_gusts alive; a
## new gust beyond that is dropped. Presentation only.

const GUST_SCENE_DEFAULT_TUNING: BreezeTuning = preload("res://config/breeze.tres")

var tuning: BreezeTuning = GUST_SCENE_DEFAULT_TUNING
var _live: Array[GustPresentation] = []


func _ready() -> void:
	Events.breeze_gust_started.connect(_on_gust)
	Events.match_state_changed.connect(_on_match_state_changed)


func live_count() -> int:
	_prune()
	return _live.size()


func _prune() -> void:
	var keep: Array[GustPresentation] = []
	for gust: GustPresentation in _live:
		if is_instance_valid(gust):
			keep.append(gust)
	_live = keep


func _on_gust(gust: Dictionary) -> void:
	_prune()
	if _live.size() >= tuning.max_presented_gusts:
		return
	var node: GustPresentation = GustPresentation.new()
	node.configure(gust, tuning)
	add_child(node)
	_live.append(node)


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if MatchPhase.is_resetting(to_state):
		clear()


func clear() -> void:
	for gust: GustPresentation in _live:
		if is_instance_valid(gust):
			gust.queue_free()
	_live.clear()
