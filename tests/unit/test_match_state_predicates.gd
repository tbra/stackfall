extends GutTest
## Match.is_live / is_replicating / is_resetting over every State (Bontago-fca.36.3).

const EXPECT_LIVE: Array[MatchAutoload.State] = [MatchAutoload.State.PLAYING, MatchAutoload.State.SUDDEN_DEATH]
const EXPECT_REPLICATING: Array[MatchAutoload.State] = [
	MatchAutoload.State.COUNTDOWN, MatchAutoload.State.PLAYING, MatchAutoload.State.SUDDEN_DEATH,
]
const EXPECT_RESETTING: Array[MatchAutoload.State] = [
	MatchAutoload.State.LOADING, MatchAutoload.State.LOBBY, MatchAutoload.State.END,
]


func test_predicates_over_every_state() -> void:
	for key: String in MatchAutoload.State.keys():
		var s: int = MatchAutoload.State[key]
		assert_eq(MatchAutoload.is_live(s), EXPECT_LIVE.has(s), "is_live %s" % key)
		assert_eq(MatchAutoload.is_replicating(s), EXPECT_REPLICATING.has(s), "is_replicating %s" % key)
		assert_eq(MatchAutoload.is_resetting(s), EXPECT_RESETTING.has(s), "is_resetting %s" % key)
		assert_ne(MatchAutoload.is_replicating(s), MatchAutoload.is_resetting(s), "complements %s" % key)
		if MatchAutoload.is_live(s):
			assert_true(MatchAutoload.is_replicating(s), "live implies replicating %s" % key)
