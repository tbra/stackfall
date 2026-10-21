class_name MatchEventMirror
extends RefCounted
## Host-side Events subscribers that mirror match-flow events to net_match_event, one
## on_<event> per MatchWireEvents name. Stub: bodies arrive with the M4 move out of MatchNet.


func bind(events_source: Node) -> void:
	push_error("MatchEventMirror.bind is a stub until M4")
	if events_source == null:
		return


func on_state_changed(_from_state: int, _to_state: int) -> void:
	push_error("MatchEventMirror.on_state_changed is a stub until M4")


func on_countdown(_seconds_left: int) -> void:
	push_error("MatchEventMirror.on_countdown is a stub until M4")


func on_turn_changed(_slot_id: int) -> void:
	push_error("MatchEventMirror.on_turn_changed is a stub until M4")


func on_feed_issued(_slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	push_error("MatchEventMirror.on_feed_issued is a stub until M4")


func on_feed_expired(_slot_id: int) -> void:
	push_error("MatchEventMirror.on_feed_expired is a stub until M4")


func on_qol_feed(_slot_id: int, _backlog: int, _paused: bool) -> void:
	push_error("MatchEventMirror.on_qol_feed is a stub until M4")


func on_gift_slot(_slot_id: int, _contents: Array, _activated: StringName, _carrier_id: StringName) -> void:
	push_error("MatchEventMirror.on_gift_slot is a stub until M4")


func on_placement_rejected(_slot_id: int, _reason: StringName) -> void:
	push_error("MatchEventMirror.on_placement_rejected is a stub until M4")


func on_placement_relocated(_slot_id: int, _point: Vector2) -> void:
	push_error("MatchEventMirror.on_placement_relocated is a stub until M4")


func on_player_eliminated(_slot_id: int, _team_id: int) -> void:
	push_error("MatchEventMirror.on_player_eliminated is a stub until M4")


func on_match_won(_team_id: int) -> void:
	push_error("MatchEventMirror.on_match_won is a stub until M4")


func on_mode_state(_state: Dictionary) -> void:
	push_error("MatchEventMirror.on_mode_state is a stub until M4")


func on_match_results(_results: Dictionary) -> void:
	push_error("MatchEventMirror.on_match_results is a stub until M4")


func on_gift_flight(_gift_id: int, _origin: Vector3, _landing: Vector3) -> void:
	push_error("MatchEventMirror.on_gift_flight is a stub until M4")


func on_gift_landed(_gift_id: int, _landing: Vector3) -> void:
	push_error("MatchEventMirror.on_gift_landed is a stub until M4")


func on_gift_spawned(_gift_id: int, _position: Vector2) -> void:
	push_error("MatchEventMirror.on_gift_spawned is a stub until M4")


func on_gift_claimed(_gift_id: int, _slot_id: int, _special_id: StringName) -> void:
	push_error("MatchEventMirror.on_gift_claimed is a stub until M4")


func on_gift_expired(_gift_id: int) -> void:
	push_error("MatchEventMirror.on_gift_expired is a stub until M4")


func on_special_triggered(_net_id: int, _def_id: StringName, _position: Vector3, _chain_depth: int) -> void:
	push_error("MatchEventMirror.on_special_triggered is a stub until M4")


func on_special_consumed(_slot_id: int, _special_id: StringName) -> void:
	push_error("MatchEventMirror.on_special_consumed is a stub until M4")


func on_glue_charges(_slot_id: int, _charges: int, _revision: int) -> void:
	push_error("MatchEventMirror.on_glue_charges is a stub until M4")


func on_block_glued(_net_id: int, _glued: bool) -> void:
	push_error("MatchEventMirror.on_block_glued is a stub until M4")


func on_block_owner_changed(_net_id: int, _owner_slot: int) -> void:
	push_error("MatchEventMirror.on_block_owner_changed is a stub until M4")


func on_block_frozen(_net_id: int, _frozen: bool) -> void:
	push_error("MatchEventMirror.on_block_frozen is a stub until M4")


func on_cat_started(_id: int, _slot_id: int, _position: Vector3, _duration: float) -> void:
	push_error("MatchEventMirror.on_cat_started is a stub until M4")


func on_cat_ended(_id: int) -> void:
	push_error("MatchEventMirror.on_cat_ended is a stub until M4")


func on_block_dissolve_started(_block: RigidBody3D, _net_id: int, _duration_s: float) -> void:
	push_error("MatchEventMirror.on_block_dissolve_started is a stub until M4")


func on_slot_replay(_slot_id: int) -> void:
	push_error("MatchEventMirror.on_slot_replay is a stub until M4")


func on_match_clock(_seconds_left: float) -> void:
	push_error("MatchEventMirror.on_match_clock is a stub until M4")


func on_loading_gate(_gate: Array) -> void:
	push_error("MatchEventMirror.on_loading_gate is a stub until M4")


func on_live_scores(_scores: Dictionary) -> void:
	push_error("MatchEventMirror.on_live_scores is a stub until M4")
