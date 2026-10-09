class_name MatchPhase
extends RefCounted
## Pure match-phase rules (spec 3.7), moved from autoload/Match.gd (Bontago-1pi.11.77.1, D4).
## MatchAutoload keeps `const State = MatchPhase.State` and one-line forwarding statics.

## Spec 3.7's states.
enum State { LOBBY, LOADING, COUNTDOWN, PLAYING, SUDDEN_DEATH, END }


## Single source for the match-state sets (Bontago-fca.36.3; tools/lint_single_source.py
## STATE_SET bans hand-written sets elsewhere).
## LIVE = PLAYING, SUDDEN_DEATH: the host simulates play (placement, throws, gifts,
## special spawns, bots, win checks, the match clock). COUNTDOWN is not live: nothing
## may be placed or won before the horn.
static func is_live(state: int) -> bool:
	return state == State.PLAYING or state == State.SUDDEN_DEATH


## REPLICATING = COUNTDOWN, PLAYING, SUDDEN_DEATH: a match that has started and not
## ended. Clients accept replicated weather/world state and a mid-match joiner is
## admitted and replayed into exactly these states (spec 3.7). Superset of is_live.
static func is_replicating(state: int) -> bool:
	return state == State.COUNTDOWN or state == State.PLAYING or state == State.SUDDEN_DEATH


## RESETTING = LOADING, LOBBY, END: the world is being built, is torn down, or is over,
## so per-match effect state (weather, wind ids, snow patches) must be cleared.
## Complement of is_replicating. Sites that clear on a narrower set (LOBBY|END cursors
## and rain, LOBBY|LOADING impacts) are intentionally not this predicate.
static func is_resetting(state: int) -> bool:
	return state == State.LOADING or state == State.LOBBY or state == State.END


# DECISION (Bontago-fca.36.10): presentation sites whose sets match none of the three
# above get narrowly named predicates here, so every site keeps its exact behaviour.
## IN_PROGRESS = LOADING, COUNTDOWN, PLAYING, SUDDEN_DEATH: everything but LOBBY and END
## (the pause menu's "match in progress"; spans the loading window).
static func is_in_progress(state: int) -> bool:
	return state != State.LOBBY and state != State.END


## PREGAME = LOADING, COUNTDOWN: the window before play (HUD primes its widgets).
static func is_pregame(state: int) -> bool:
	return state == State.LOADING or state == State.COUNTDOWN


## LOBBY or END: no match on screen. Unlike is_resetting this excludes LOADING (cursors,
## rain and the HUD survive the build of the next match's world).
static func is_lobby_or_end(state: int) -> bool:
	return state == State.LOBBY or state == State.END


## The LOBBY -> LOADING transition: a match (or sandbox reset) starts building its world.
static func is_start_transition(from_state: int, to_state: int) -> bool:
	return from_state == State.LOBBY and to_state == State.LOADING
