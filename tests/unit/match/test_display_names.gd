extends GutTest
## concept M: labels never empty, tables line up with the enums.


func test_special_names() -> void:
	assert_eq(DisplayNames.special(&"jumping_bean"), "Jumping Bean")
	assert_eq(DisplayNames.special(MatchGifts.PENDING_SPECIAL_ID), "Special")
	assert_eq(DisplayNames.special(&"not_a_gift"), "Not A Gift")
	assert_eq(DisplayNames.special(&""), DisplayNames.special(MatchGifts.PENDING_SPECIAL_ID))

