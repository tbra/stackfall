class_name MenuPrewarmConfig
extends Resource
## What MenuPrewarmQueue loads behind the main menu and which CLI flags
## force a synchronous startup instead. Loaded once as config/match/menu_prewarm.tres.

## Serial load order. Every path is requested one at a time (a second overlapping threaded load
## can hang) and each chunk should compile in about 1.1 s or less: chunk
## boundaries are where Main may idle or quit. Paths that do not exist are skipped by the
## queue.
@export var chunks: Array[PackedStringArray] = []
## CLI user flags (without leading dashes) that make Main load everything synchronously first.
@export var eager_flags: PackedStringArray = PackedStringArray()


## Every configured path in serial order, without duplicates.
func all_paths() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for chunk: PackedStringArray in chunks:
		for path: String in chunk:
			if not result.has(path):
				result.append(path)
	return result


## True when one of `user_args` (leading dashes ignored) is an eager flag.
func wants_eager(user_args: PackedStringArray) -> bool:
	for raw: String in user_args:
		if eager_flags.has(raw.lstrip("-")):
			return true
	return false
