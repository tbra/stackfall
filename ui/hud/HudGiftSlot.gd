class_name HudGiftSlot
extends RefCounted
## The held-gift column beside the held/next piece row. Stub: builds nothing until the HUD
## extraction fills it in.

var _row: HBoxContainer
var _reference_card: Control
var _arcade: ArcadeVisualTuning


func _init(row: HBoxContainer, reference_card: Control, arcade: ArcadeVisualTuning) -> void:
	_row = row
	_reference_card = reference_card
	_arcade = arcade


func refresh(_head_id: StringName, _count: int, _force: bool = false) -> void:
	pass
