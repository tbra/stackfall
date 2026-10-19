class_name TokenBucket
extends RefCounted
## Token bucket: starts full at `burst`, refills `refill_per_s` per second, caps at
## `burst`. Pure rule logic driven by a caller-supplied clock, so tests use synthetic
## time. Same maths as the chat limiter it replaces (ChatRules.Bucket).

## Cost of one accepted call, in tokens.
const TOKEN_COST: float = 1.0
## `_tokens` before the first take(): the bucket then starts full.
const UNSET_TOKENS: float = -1.0
## A bucket always holds at least one token so a zero burst cannot lock a peer out forever.
const MIN_BURST: int = 1

var _tokens: float = UNSET_TOKENS
var _last_s: float = 0.0


## True (and one token spent) when a call may pass at time `now_s` seconds.
## A clock that steps backwards refills nothing and becomes the new reference.
func take(now_s: float, burst: int, refill_per_s: float) -> bool:
	var cap: float = float(maxi(burst, MIN_BURST))
	if _tokens < 0.0:
		_tokens = cap
	else:
		_tokens = minf(cap, _tokens + maxf(now_s - _last_s, 0.0) * maxf(refill_per_s, 0.0))
	_last_s = now_s
	if _tokens >= TOKEN_COST:
		_tokens -= TOKEN_COST
		return true
	return false


## Tokens left after the last take(); UNSET_TOKENS before the first one. For tests.
func tokens() -> float:
	return _tokens
