extends GutTest
## Bontago-mp0.125: every gift and weather option resolves to UI art through
## config/gift_icon_table.tres, and the lobby/HUD widgets show it.


func _make_lobby() -> Lobby:
	var lobby: Lobby = autofree((load("res://ui/Lobby.tscn") as PackedScene).instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	lobby.net_provider = fake
	return lobby


func test_every_weather_mode_has_pictogram() -> void:
	var table: GiftIconTable = GiftIconTable.shared()
	for mode: int in MatchConfig.WeatherMode.values():
		assert_not_null(table.weather_pictogram(mode), "weather %d" % mode)
	assert_null(table.weather_pictogram(99))
	assert_null(table.gift_pictogram(&"nope"))


func test_lobby_widgets_use_pictograms() -> void:
	var lobby: Lobby = _make_lobby()
	var table: GiftIconTable = GiftIconTable.shared()
	var checklist: GridContainer = lobby.get_node("%SpecialsChecklist") as GridContainer
	assert_gt(checklist.get_child_count(), 0)
	for box: Node in checklist.get_children():
		var check: UiChipToggle = box as UiChipToggle
		var id: StringName = StringName(check.label.to_lower().replace(" ", "_"))
		assert_eq(check.chip_icon, table.gift_pictogram(id), "checkbox %s" % id)
	var weather: UiDropdown = lobby.get_node("%WeatherOption") as UiDropdown
	for i: int in weather.item_count:
		assert_eq(weather.get_item_icon(i), table.weather_pictogram(i), "weather item %d" % i)
