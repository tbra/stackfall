class_name BeaconTimerText
extends RefCounted
## Bontago-1pi.188 / 1pi.189: the text shown above each goal beacon and the CTF
## score-multiplier chip. Pure: no scene tree, so the host and every client
## format the same replicated claim/hold state identically and tests need no scene.
##
## Classic: the capture is a shared hold (WinChecker.capture_progress over
## capture_hold), so every beacon counts the seconds left until the current
## claimant captures; hidden while nobody is claiming.
## CTF: each held beacon counts up how long its current holder has held it, and a
## team holding several beacons scores that many times faster (multiplier).

## A multiplier is only worth showing from this many held beacons.
const MIN_MULTIPLIER: int = 2
const SECONDS_PER_MINUTE: int = 60


## "m:ss" for a whole number of seconds (negative clamps to 0).
static func clock(seconds: int) -> String:
	var whole: int = maxi(seconds, 0)
	return "%d:%02d" % [whole / SECONDS_PER_MINUTE, whole % SECONDS_PER_MINUTE]


static func remaining_seconds(progress: float, hold_seconds: float) -> float:
	return maxf((1.0 - clampf(progress, 0.0, 1.0)) * hold_seconds, 0.0)


## CTF count-up: how long `holder` (a team id, < 0 = nobody) has held the beacon.
static func ctf_text(holder: int, held_seconds: float) -> String:
	if holder < 0:
		return ""
	return clock(int(floor(maxf(held_seconds, 0.0))))


## "x2" for two or more held beacons, else "".
static func multiplier_text(held_count: int) -> String:
	if held_count < MIN_MULTIPLIER:
		return ""
	return "x%d" % held_count


## Beacons `team` holds in a replicated CTF mode state ({"mode_id", "extra": {"held_N"}}).
static func held_count_in_state(state: Dictionary, team: int) -> int:
	if int(state.get("mode_id", -1)) != MatchConfig.GameMode.CAPTURE_THE_FLAG or team < 0:
		return 0
	var extra: Dictionary = state.get("extra", {}) as Dictionary
	return int(extra.get("held_%d" % team, 0))


static func multiplier_text_in_state(state: Dictionary, team: int) -> String:
	return multiplier_text(held_count_in_state(state, team))
