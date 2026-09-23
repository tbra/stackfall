class_name MatchTestReset
extends RefCounted
## Shared after_each() cleanup for tests that call Match.register_world()
## with an autofree()d Field/BlockRegistry/blocks-parent (Bontago-bmh).
##
## autoload/Match.gd's `_field`/`_registry`/`_blocks_parent` are plain
## autoload vars: MatchLifecycle._reset_match_state() (run by
## Match.abort_match()) deliberately leaves them alone, because in the real
## game the Field is a persistent scene node under game/Main.tscn that
## outlives any one match (Match.register_world() is only called once, at
## boot). In a test run, though, every script that registers its own throw-
## away world via Match.register_world() leaves those vars pointing at nodes
## this script's own autofree()/add_child_autofree() calls just freed at
## end-of-script -- and Match is a singleton that outlives the script, so the
## next script in the same GUT process that reads Match.field()/registry()/
## blocks_parent() without registering its own world first (e.g.
## test_throw_arc_preview.gd's PlayerController fixtures, via
## PlayerController._drive_throw_visuals() -> ThrowArcPreview.update_arc())
## gets a freed object and Godot's own argument type-check throws
## "previously freed" before the callee even runs -- reproduced by running
## any world-registering script immediately before test_throw_arc_preview.gd
## (see Bontago-bmh).
##
## Call this from after_each(), after Match.abort_match(), in every test
## script that calls Match.register_world().
static func clear_world() -> void:
	Match._field = null
	Match._registry = null
	Match._blocks_parent = null
