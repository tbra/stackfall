extends GutTest
## What the HUD shows from the MatchContext it is given: the null object reads as the lobby (no
## countdown, no stat rows), a context handed over before or after the HUD is in the tree primes the
## pre-game stat rows, and the countdown and sudden-death reads reach what the player sees.
## Assertions read visible Label text and visibility only, never node order or counts.

const HUD_SCENE: PackedScene = preload("res://ui/hud/HUD.tscn")
const NAMES: Array[String] = ["Ann", "Bo"]
const COUNTDOWN_LEFT_S: float = 2.4
const COUNTDOWN_SHOWN: String = "3"
const FRAMES: int = 2
const MATCH_MINUTES: int = 5
const TIME_LEFT_S: float = 65.0
const TIME_LEFT_TEXT: String = "1:05"


## A context for a match in `phase` with NAMES seated.
func _context(phase: int) -> FakeMatchContext:
	var context: FakeMatchContext = FakeMatchContext.new()
	var config: MatchConfig = MatchConfig.new()
	config.player_count = NAMES.size()
	config.match_timer_minutes = MATCH_MINUTES
	context.config_value = config
	context.slot_count_value = NAMES.size()
	context.state_value = phase
	for slot_id: int in range(NAMES.size()):
		context.slot_by_id[slot_id] = PlayerSlot.new(slot_id, slot_id, NAMES[slot_id], Color.WHITE)
	return context


func _hud(context: MatchContext = null) -> HUD:
	var hud: HUD = autofree(HUD_SCENE.instantiate()) as HUD
	if context != null:
		hud.match_context = context
	add_child_autofree(hud)
	return hud


func _visible_texts(root: Node) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for node: Node in root.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label.is_visible_in_tree():
			out.append(label.text)
	return out


func _countdown(hud: HUD) -> Label:
	return hud.find_child("CountdownLabel", true, false) as Label


func _clock(hud: HUD) -> UiRoundTimer:
	return hud.find_children("*", "UiRoundTimer", true, false)[0] as UiRoundTimer


func test_the_default_context_reads_as_the_lobby() -> void:
	var hud: HUD = _hud()
	await wait_process_frames(FRAMES)
	assert_false(_countdown(hud).visible, "no countdown without a match")
	var shown: PackedStringArray = _visible_texts(hud.get_node("%SharesBox"))
	for text: String in NAMES:
		assert_does_not_have(shown, text, "no stat card for %s in the lobby" % text)
	assert_eq(shown.size(), 0, "no stat cards at all")
	assert_false(_clock(hud).visible, "no match clock in the lobby")


func test_a_context_set_before_the_hud_enters_the_tree_primes_the_cards() -> void:
	var hud: HUD = _hud(_context(MatchPhase.State.COUNTDOWN))
	await wait_process_frames(FRAMES)
	var shown: PackedStringArray = _visible_texts(hud.get_node("%SharesBox"))
	for text: String in NAMES:
		assert_has(shown, text, "%s has a card from the first countdown frame" % text)


func test_a_context_set_after_ready_catches_up_to_a_match_already_in_pregame() -> void:
	var hud: HUD = _hud()
	hud.match_context = _context(MatchPhase.State.LOADING)
	var shown: PackedStringArray = _visible_texts(hud.get_node("%SharesBox"))
	for text: String in NAMES:
		assert_has(shown, text, "%s has a card as soon as the context arrives" % text)


func test_a_context_set_after_ready_in_the_lobby_shows_no_cards() -> void:
	var hud: HUD = _hud()
	hud.match_context = _context(MatchPhase.State.LOBBY)
	await wait_process_frames(FRAMES)
	assert_eq(_visible_texts(hud.get_node("%SharesBox")).size(), 0)


func test_the_countdown_label_follows_the_context_then_says_go() -> void:
	var context: FakeMatchContext = _context(MatchPhase.State.COUNTDOWN)
	context.countdown_remaining_value = COUNTDOWN_LEFT_S
	var hud: HUD = _hud(context)
	await wait_process_frames(FRAMES)
	assert_true(_countdown(hud).visible)
	assert_eq(_countdown(hud).text, COUNTDOWN_SHOWN, "the seconds left, rounded up")
	context.countdown_remaining_value = 0.0
	context.state_value = MatchPhase.State.PLAYING
	await wait_process_frames(FRAMES)
	assert_eq(_countdown(hud).text, hud.hud_visual_tuning.countdown_go_text)


func test_an_aborted_countdown_hides_the_label_without_go() -> void:
	var context: FakeMatchContext = _context(MatchPhase.State.COUNTDOWN)
	context.countdown_remaining_value = COUNTDOWN_LEFT_S
	var hud: HUD = _hud(context)
	await wait_process_frames(FRAMES)
	context.countdown_remaining_value = 0.0
	context.state_value = MatchPhase.State.LOBBY
	await wait_process_frames(FRAMES)
	assert_false(_countdown(hud).visible)


func test_the_match_clock_shows_the_time_left_then_overtime_in_sudden_death() -> void:
	var context: FakeMatchContext = _context(MatchPhase.State.PLAYING)
	context.match_timer_left_value = TIME_LEFT_S
	var hud: HUD = _hud(context)
	await wait_process_frames(FRAMES)
	assert_true(_clock(hud).visible)
	assert_eq(_clock(hud).label.text, TIME_LEFT_TEXT)
	context.state_value = MatchPhase.State.SUDDEN_DEATH
	context.sudden_death_value = true
	context.match_timer_left_value = 0.0
	await wait_process_frames(FRAMES)
	assert_true(_clock(hud).visible)
	assert_eq(_clock(hud).label.text, hud.hud_visual_tuning.round_timer_overtime_text)
