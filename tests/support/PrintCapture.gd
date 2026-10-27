class_name PrintCapture
extends Logger
## Collects what the game prints to stdout while installed, so a test can assert on log lines a
## harness parses (HEADLESS_MATCH, HEADLESS_BOTS) without reaching into the code that prints them.
## Engine errors are not collected here (GUT's own tracker handles those).

var _messages: PackedStringArray = PackedStringArray()


## Installs a new capture; call `stop()` (also from after_each) to remove it.
static func start() -> PrintCapture:
	var capture: PrintCapture = PrintCapture.new()
	OS.add_logger(capture)
	return capture


func stop() -> void:
	OS.remove_logger(self)


## Every captured line that begins with `prefix`, in print order, without trailing newlines.
func lines_starting_with(prefix: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for message: String in _messages:
		for line: String in message.split("\n", false):
			if line.begins_with(prefix):
				found.append(line)
	return found


func _log_message(message: String, error: bool) -> void:
	if not error:
		_messages.append(message)
