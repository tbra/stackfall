extends GutTest
## every gift resolves to UI art; weather options carry no icons (mp0.166) through
## config/gifts/gift_icon_table.tres, and the lobby/HUD widgets show it.


func _make_lobby() -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/lobby/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	lobby.net_provider = fake
	return lobby


func test_unknown_gift_has_no_pictogram() -> void:
	assert_null(GiftIconTable.shared().gift_pictogram(&"nope"))


func test_lobby_widgets_use_pictograms() -> void:
	var lobby: Lobby = _make_lobby()
	var table: GiftIconTable = GiftIconTable.shared()
	var checklist: GridContainer = lobby.get_node("%SpecialsChecklist") as GridContainer
	assert_gt(checklist.get_child_count(), 0)
	for box: Node in checklist.get_children():
		var check: UiChipToggle = box as UiChipToggle
		var id: StringName = StringName(check.label.to_lower().replace(" ", "_"))
		assert_eq(check.chip_icon, table.gift_pictogram(id), "checkbox %s" % id)
	var weather: UiCycler = lobby.get_node("%WeatherOption") as UiCycler
	for i: int in weather.get_item_count():
		assert_null(weather.get_item_icon(i), "weather item %d has no icon" % i)
