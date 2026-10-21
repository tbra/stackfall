class_name MatchLaunch
extends RefCounted
## Pure builders for the configs and CLI values of the non-lobby modes: no scene
## tree, no autoload.


# STUB: filled by MD-L1
static func sandbox_config(base: MatchConfig, _player_count: int, _preset: SandboxConfig) -> MatchConfig:
	return base.duplicate(true) as MatchConfig


# STUB: filled by MD-L1
static func tutorial_config(base: MatchConfig, _lesson: TutorialConfig) -> MatchConfig:
	return base.duplicate(true) as MatchConfig


## `--players=N` for the sandbox.
# STUB: filled by MD-L1
static func sandbox_player_count(_args: PackedStringArray, _preset: SandboxConfig, defaults: SandboxConfig) -> int:
	return defaults.default_player_count


## `--force-special=<id>`, or &"" when absent.
# STUB: filled by MD-L1
static func forced_special_arg(_args: PackedStringArray) -> StringName:
	return &""
