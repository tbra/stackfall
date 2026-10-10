class_name BotRecordingConfig
extends Resource
## Bontago-1t5.11 (BT1, docs/BOT_TRAINING_SOAK_PLAN.md section 1): tunables for the
## passive bot decision recorder (game/BotDecisionRecorder.gd). Loaded once as
## config/bot_recording.tres. Recording stays OFF unless `--bot-record=<dir>` is
## given, whatever `enabled_default` says.

## Schema version written into every header line (bump on any field change).
@export var schema_version: int = 1
## Seconds after a decision at which its outcome (change in own territory share) is
## sampled; one `d_share_<n>s` field per entry, in ascending order.
@export var horizons_s: PackedFloat32Array = PackedFloat32Array([10.0, 30.0, 60.0])
## Buffered JSONL lines per file before an explicit flush (also flushed on match end).
@export var flush_every: int = 32
## Whether recording starts without the command-line flag (kept false: opt-in only).
@export var enabled_default: bool = false
## Decimal places kept for every recorded float (0.001 = 3 dp).
@export var round_step: float = 0.001
## Hard cap on bytes written per process; the recorder disables itself past it.
@export var max_bytes: int = 2000000000
