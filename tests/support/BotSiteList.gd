class_name BotSiteList
extends RefCounted
## Shared bot-test helper: the sites `BotCandidateGen.begin` builds once its
## fill has run to the end.


static func build(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> Array[BotCandidate]:
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(view, intent, profile, rng, tuning)
	while not job.fill_step(job.attempts_left()):
		pass
	return job.out
