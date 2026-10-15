class_name ToastStack
extends UiStack
## H1: the ONE place every transient HUD message (placement reject, relocated,
## gift claimed, ...) appears: bottom centre. Messages stack (oldest on top, newest at the bottom),
## each holds then fades, and they expire in the order they arrived. At most `max_visible` show at
## once; the rest wait in a FIFO queue and start their hold when a slot frees up. Pushing the text of a
## toast that is already showing restarts that toast instead of adding a duplicate.
## Styling is injected (`styler`) so the HUD keeps its Callout look in one place.

## Called once per new toast Label: styler.call(label: Label, face: Color, glyph: HudCallout.Glyph).
var styler: Callable = Callable()
var max_visible: int = 1

var _queue: Array[Dictionary] = []
var _active: Array[Dictionary] = []


## Shows (or queues) a toast. `hold_s` fully visible, then `fade_s` fading out.
func push(text: String, face: Color, glyph: HudCallout.Glyph, hold_s: float, fade_s: float) -> void:
	for entry: Dictionary in _active:
		if (entry["label"] as Label).text == text:
			_restart(entry, face, glyph, hold_s, fade_s)
			return
	for entry: Dictionary in _queue:
		if entry["text"] == text:
			entry["face"] = face
			entry["glyph"] = glyph
			entry["hold"] = hold_s
			entry["fade"] = fade_s
			return
	_queue.append({"text": text, "face": face, "glyph": glyph, "hold": hold_s, "fade": fade_s})
	_promote()


## Texts of the toasts currently on screen, oldest first.
func active_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in _active:
		out.append((entry["label"] as Label).text)
	return out


func queued_count() -> int:
	return _queue.size()


## The Label of the on-screen toast showing `text`, or null.
func label_for(text: String) -> Label:
	for entry: Dictionary in _active:
		if (entry["label"] as Label).text == text:
			return entry["label"] as Label
	return null


func clear() -> void:
	for entry: Dictionary in _active:
		_kill(entry)
		(entry["label"] as Label).queue_free()
	_active.clear()
	_queue.clear()


func _promote() -> void:
	while _active.size() < max_visible and not _queue.is_empty():
		var next: Dictionary = _queue.pop_front() as Dictionary
		var label: Label = Label.new()
		label.text = next["text"] as String
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		add_child(label)
		if styler.is_valid():
			styler.call(label, next["face"], next["glyph"])
		var entry: Dictionary = {"label": label, "tween": null}
		_active.append(entry)
		_start_tween(entry, next["hold"] as float, next["fade"] as float)


func _restart(entry: Dictionary, face: Color, glyph: HudCallout.Glyph, hold_s: float, fade_s: float) -> void:
	var label: Label = entry["label"] as Label
	label.modulate = Color.WHITE
	if styler.is_valid():
		styler.call(label, face, glyph)
	_start_tween(entry, hold_s, fade_s)


func _start_tween(entry: Dictionary, hold_s: float, fade_s: float) -> void:
	_kill(entry)
	var label: Label = entry["label"] as Label
	var tween: Tween = create_tween()
	tween.tween_interval(hold_s)
	tween.tween_property(label, ^"modulate:a", 0.0, fade_s)
	tween.tween_callback(_expire.bind(entry))
	entry["tween"] = tween


func _kill(entry: Dictionary) -> void:
	var tween: Tween = entry["tween"] as Tween
	if tween != null and tween.is_valid():
		tween.kill()


func _expire(entry: Dictionary) -> void:
	_active.erase(entry)
	var label: Label = entry["label"] as Label
	if is_instance_valid(label):
		label.queue_free()
	_promote()
