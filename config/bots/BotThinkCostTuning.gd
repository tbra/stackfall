class_name BotThinkCostTuning
extends Resource
## Bontago-1t5.62: tunables of the opt-in Hard-bot think-cost report (core/ai/BotThinkCostReport.gd,
## core/ai/BotThinkCostCollector.gd; headless run: tools/run_bot_think_cost.ps1). Loaded as
## config/bots/bot_think_cost.tres.

## Match seconds one headless scenario runs before it reports and quits.
@export var default_duration_s: float = 180.0
## Median fraction.
@export var median_fraction: float = 0.5
## "p95" fraction.
@export var high_fraction: float = 0.95
## "p99" fraction (per-frame bot time).
@export var tail_fraction: float = 0.99
## Rolling window of the live (overlay) collector: the last N thinks and N * frames_per_think bot frames.
@export var window_thinks: int = 64
## Bot frames kept per window think.
@export var frames_per_think: int = 8
