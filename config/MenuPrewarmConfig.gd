class_name MenuPrewarmConfig
extends Resource
## Bontago-1pi.11.84 (MF0): what MenuPrewarmQueue loads behind the main menu and which CLI flags
## force a synchronous startup instead. Loaded once as config/menu_prewarm.tres.

## Serial load order. Every path is requested one at a time (a second overlapping threaded load
## can hang, plan F1) and each chunk should compile in about 1.1 s or less (plan F2): chunk
## boundaries are where Main may idle or quit. Paths not yet created by a later package are
## skipped by the queue.
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
