class_name TuningPanelHints
extends Resource
## Per-property slider/spinbox ranges for ui/TuningPanel.gd's reflection-built
## tabs (Bontago-mv0.18, owner request: "add a settings menu with sliders").
##
## Every numeric @export field TuningPanel finds gets a control regardless of
## whether it has an entry here: an unlisted field falls back to
## TuningPanel._fallback_range() (roughly "[0, 4x current value]", the shape
## the design brief specified), which is a fine slider range for most
## tunables but a poor one for anything whose sane default sits at or below
## zero (kill_plane_y, the negative camera pitch angles...) or whose useful
## range isn't proportional to its default at all (a friction/bounce
## coefficient conventionally reads 0..1-ish regardless of where it currently
## sits). This resource only needs entries for those -- the fields the owner
## is actually likely to reach for (camera feel, gravity/damping/bounce/
## friction) get a deliberately chosen range; everything else is left to the
## fallback rather than hand-tuning every field across every tuning resource.
##
## Loaded once as config/tuning_panel_hints.tres.

## "<script class name>.<property name>" -> Vector2(min, max). Keyed on the
## class name too (not just the bare property name) so two tuning resources
## that ever share a field name -- none do today -- can't collide.
@export var ranges: Dictionary = {}

## "<script class name>.<property name>" -> one-sentence, plain-language
## description of what the field controls (Bontago-mv0.21, owner request:
## every row show "what it controls... visible without hovering"). Same
## keying scheme as `ranges` above. Populated for every numeric/bool/Color
## field ui/TuningPanel.gd currently builds a row for, across all six tuning
## resources -- see tests/unit/test_tuning_panel.gd's "every shown field has
## a non-empty description" test, which walks the same reflection list this
## panel builds rows from and fails loudly if a field is ever added here
## without a matching entry.
@export var descriptions: Dictionary = {}


## Vector2(NAN, NAN) (an invalid sentinel TuningPanel._range_for() checks for)
## when `class_name_ + "." + property_name` has no entry here.
func range_for(class_name_: String, property_name: String) -> Vector2:
	var key: String = "%s.%s" % [class_name_, property_name]
	if ranges.has(key):
		return ranges[key] as Vector2
	return Vector2(NAN, NAN)


## "" when `class_name_ + "." + property_name` has no entry here.
func description_for(class_name_: String, property_name: String) -> String:
	var key: String = "%s.%s" % [class_name_, property_name]
	if descriptions.has(key):
		return String(descriptions[key])
	return ""

## Bontago-1pi.113 (F4 panel redo). "<script class name>.<property name>" ->
## section title: the panel shows a field under a foldable section header with
## this title (the `## -- Title --` comment above the field in its config
## script). Sections are ordered by first appearance in declaration order unless
## `section_order` names them.
@export var sections: Dictionary = {}

## "<script class name>" -> Array[String] of section titles to list first, in
## this order (unlisted sections follow in declaration order).
@export var section_order: Dictionary = {}

## "<script class name>.<section title>" -> tab name, for a section that belongs
## on a different tab than the resource's first one (e.g. GhostTuning's visual
## sections on "Ghost & Blocks").
@export var section_tabs: Dictionary = {}

## "<script class name>.<property name>" -> unit text ("m/s", "rad/px"...) for
## a field whose name carries no unit suffix. A recognised suffix (_s, _m, _deg,
## _px, _hz, _mps...) is picked up by unit_for() without an entry here.
@export var units: Dictionary = {}

## Name suffix -> unit shown after the value, and dropped from the label.
const SUFFIX_UNITS: Dictionary = {
	"seconds": "s", "second": "s", "s": "s", "duration": "s", "delay": "s", "hold": "s",
	"time": "s", "m": "m", "distance": "m", "px": "px", "deg": "°", "degrees": "°",
	"hz": "Hz", "mps": "m/s", "fps": "fps",
}
## Words shown upper-case in a humanized label.
const ACRONYMS: PackedStringArray = ["hud", "ssr", "hdr", "fov", "fps", "ui", "ctf", "uv"]
const GENERAL_SECTION: String = "General"


## "" when the field has no section entry.
func section_for(class_name_: String, property_name: String) -> String:
	return String(sections.get("%s.%s" % [class_name_, property_name], ""))


## The tab a section shows on: its `section_tabs` entry, else `default_tab`.
func tab_for(class_name_: String, section: String, default_tab: String) -> String:
	return String(section_tabs.get("%s.%s" % [class_name_, section], default_tab))


## Section titles of `class_name_` in display order given the field names in
## declaration order (`fields`).
func ordered_sections(class_name_: String, fields: Array[String]) -> Array[String]:
	var seen: Array[String] = []
	for field_name: String in fields:
		var title: String = section_for(class_name_, field_name)
		if title.is_empty():
			title = GENERAL_SECTION
		if not seen.has(title):
			seen.append(title)
	var result: Array[String] = []
	for listed: Variant in (section_order.get(class_name_, []) as Array):
		if seen.has(String(listed)):
			result.append(String(listed))
	for title: String in seen:
		if not result.has(title):
			result.append(title)
	return result


## Unit text for a field ("" for none): an explicit `units` entry, else the name suffix.
func unit_for(class_name_: String, property_name: String) -> String:
	var key: String = "%s.%s" % [class_name_, property_name]
	if units.has(key):
		return String(units[key])
	var suffix: String = property_name.get_slice("_", property_name.get_slice_count("_") - 1)
	if property_name.contains("_") and SUFFIX_UNITS.has(suffix):
		return String(SUFFIX_UNITS[suffix])
	return ""


## Player-facing field name: underscores to spaces, first word capitalised,
## acronyms upper-cased, and a unit suffix token dropped (the unit shows beside
## the value instead). "dust_lifetime_s" -> "Dust lifetime", "fov_deg" -> "FOV".
func label_for(class_name_: String, property_name: String) -> String:
	var words: PackedStringArray = property_name.split("_", false)
	if words.size() > 1 and SUFFIX_UNITS.has(words[words.size() - 1]) and not units.has("%s.%s" % [class_name_, property_name]):
		words.remove_at(words.size() - 1)
	var out: PackedStringArray = PackedStringArray()
	for index: int in words.size():
		var word: String = words[index]
		if ACRONYMS.has(word):
			word = word.to_upper()
		elif index == 0:
			word = word.capitalize()
		out.append(word)
	return " ".join(out)
