extends GutTest
## Bontago-1pi.149: the Join page's "Searching for games..." well shows three pulsing cells
## (components.md ServerRow), only while the empty-state line is visible.


func test_cells_pulse_staggered_between_min_alpha_and_one() -> void:
	var times: Array[float] = [0.0, 0.3, 0.6, 0.9]
	for time_sec: float in times:
		for index: int in range(SearchingCells.CELL_COUNT):
			var alpha: float = SearchingCells.cell_alpha(index, time_sec)
			assert_between(alpha, SearchingCells.MIN_ALPHA - 0.001, 1.001)
	assert_ne(SearchingCells.cell_alpha(0, 0.0), SearchingCells.cell_alpha(1, 0.0), "cells are staggered")


func test_join_page_cells_follow_the_searching_line() -> void:
	var menu: MainMenu = autofree((load("res://ui/MainMenu.tscn") as PackedScene).instantiate() as MainMenu)
	add_child_autofree(menu)
	var label: Label = menu.get_node("%EmptyStateLabel") as Label
	var cells: SearchingCells = label.get_node("SearchingCells") as SearchingCells
	assert_not_null(cells)
	menu._games = []
	menu._rebuild_game_list()
	assert_true(label.visible)
	assert_true(cells.visible)
	menu._games = [{"name": "G", "players": 1, "max": 2, "address": "1.2.3.4", "port": 1}]
	menu._rebuild_game_list()
	assert_false(label.visible)
	assert_false(cells.is_visible_in_tree(), "hidden with the line")
