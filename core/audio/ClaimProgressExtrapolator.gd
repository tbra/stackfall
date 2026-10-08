class_name ClaimProgressExtrapolator
extends RefCounted
## Client-side smoothing of the beacon-claim hold progress (Bontago-1pi.117,
## shared by Sfx's claim-tension bed and the HUD capture ring so they never
## disagree). A client only receives Events.goal_capture_progress when the
## territory raster changes, so on a static board the value freezes. Between
## updates this advances the hold at 1 / hold_seconds per second while the
## holding team is unchanged; every real update snaps it. Pure rules, no scene
## tree, nothing replicated; the host never calls advance().

const NO_TEAM: int = -1

var _team: int = NO_TEAM
var _progress: float = 0.0


## Snap to a received value. A zero/no-team value clears the hold.
func snap(team_id: int, progress: float) -> void:
	var holding: bool = team_id != NO_TEAM and progress > 0.0
	_team = team_id if holding else NO_TEAM
	_progress = progress if holding else 0.0


## Break, win or scope reset: stop extrapolating.
func clear() -> void:
	_team = NO_TEAM
	_progress = 0.0


func is_holding() -> bool:
	return _team != NO_TEAM


func team() -> int:
	return _team


func progress() -> float:
	return _progress


## Advances the extrapolated value. Returns true when it changed.
func advance(delta: float, hold_seconds: float) -> bool:
	if _team == NO_TEAM or hold_seconds <= 0.0 or _progress >= 1.0 or delta <= 0.0:
		return false
	_progress = minf(_progress + delta / hold_seconds, 1.0)
	return true
