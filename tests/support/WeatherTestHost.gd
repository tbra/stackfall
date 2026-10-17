class_name WeatherTestHost
extends RefCounted
## Test helpers for the weather tests: a MatchWeather's host answer comes from a
## throwaway Match instance whose net provider is a FakeNet, and a wind effect's block list and
## surface height come from a FakeMatchContext (registry + field).


## Binds `weather` to a fresh Match node (owned by `test`, freed after the test) that answers
## Net.is_host() with `is_host`.
static func bind_host(test: GutTest, weather: MatchWeather, is_host: bool) -> void:
	var node: MatchAutoload = test.autofree(MatchAutoload.new()) as MatchAutoload
	node._net_provider = FakeNet.host() if is_host else FakeNet.client(0)
	weather.setup(node)


## A FakeMatchContext whose registry lists `blocks()` and whose field sits at `surface_y()`;
## the nodes it builds are owned by `test`.
static func wind_context(test: GutTest, blocks: Callable, surface_y: Callable) -> FakeMatchContext:
	var context: FakeMatchContext = FakeMatchContext.new()
	var registry: _ListRegistry = test.autofree(_ListRegistry.new()) as _ListRegistry
	registry.source = blocks
	var field: _FlatField = test.autofree(_FlatField.new()) as _FlatField
	field.source = surface_y
	context.registry_value = registry
	context.field_value = field
	return context


class _ListRegistry:
	extends BlockRegistry
	var source: Callable = Callable()

	func all_blocks() -> Array[Block]:
		var listed: Array[Block] = []
		listed.assign(source.call() as Array)
		return listed


class _FlatField:
	extends Field
	var source: Callable = Callable()

	func surface_y() -> float:
		return float(source.call())
