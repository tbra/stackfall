class_name NetStatsLive
extends NetStatsSource
## Adapter that names the autoloads (Net, SnapshotSync, MatchNet) and assembles one NetStats.


func read() -> NetStats:
	return NetStats.new()
