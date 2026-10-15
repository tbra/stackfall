extends GutTest
## Bontago-1pi.11.77.3 (S2b): LateScripts path table and the activation hook.

class ActivationProbe:
	extends Node
	var calls: int = 0

	func late_activate() -> void:
		calls += 1


func test_every_path_loads() -> void:
	for path: String in LateScripts.paths():
		assert_not_null(load(path), "loads %s" % path)


func test_activate_autoloads_calls_late_activate_on_root_children() -> void:
	var probe: ActivationProbe = ActivationProbe.new()
	get_tree().root.add_child(probe)
	LateScripts.activate_autoloads(get_tree())
	assert_eq(probe.calls, 1)
	probe.queue_free()
