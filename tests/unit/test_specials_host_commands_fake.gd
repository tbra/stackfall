extends GutTest
## S1d: host-command specials reach the match only through MatchContext. Driven with a
## FakeMatchContext (no Match autoload state involved).

var _previous: MatchContext = null
var _fake: FakeMatchContext = null


func before_each() -> void:
	_previous = MatchContext.installed()
	_fake = FakeMatchContext.new()
	_fake.state_value = MatchPhase.State.PLAYING
	_fake.slot_count_value = 2
	MatchContext.install(_fake)


func after_each() -> void:
	MatchContext.install(_previous)


func _block(slot_id: int) -> Block:
	var block: Block = Block.new()
	block.owner_slot = slot_id
	add_child_autofree(block)
	return block


func test_glue_effect_records_one_grant() -> void:
	var effect: GlueEffect = GlueEffect.new()
	effect.drop_charges = 7
	effect.detonate(_block(1), null, 0)
	assert_eq(_fake.grant_glue_drops_calls.size(), 1)
	assert_eq(_fake.grant_glue_drops_calls[0]["slot_id"], 1)
	assert_eq(_fake.grant_glue_drops_calls[0]["count"], 7)


func test_cat_effect_starts_cat_with_itself_when_authoritative() -> void:
	var effect: CatEffect = CatEffect.new()
	effect.detonate(_block(0), null, 0)
	assert_eq(_fake.start_cat_calls.size(), 1)
	assert_eq(_fake.start_cat_calls[0]["effect"], effect)


func test_cat_effect_on_non_authority_does_nothing() -> void:
	_fake.has_authority_value = false
	CatEffect.new().detonate(_block(0), null, 0)
	assert_eq(_fake.start_cat_calls.size(), 0)


func test_cat_effect_ignores_out_of_range_slot_and_non_playing() -> void:
	CatEffect.new().detonate(_block(5), null, 0)
	_fake.state_value = MatchPhase.State.LOBBY
	CatEffect.new().detonate(_block(0), null, 0)
	assert_eq(_fake.start_cat_calls.size(), 0)


func test_seq_meta_alias_matches_special_ids() -> void:
	assert_eq(MatchGiftActivation.SEQ_META, SpecialIds.ACTIVATION_SEQ_META)
	assert_eq(MatchGiftActivation.IN_PLACE_META, SpecialIds.IN_PLACE_META)
