class_name BuildVersion
extends RefCounted
## Bontago-1pi.74: the one source of the build label shown in the main menu.
## "<application/config/version>+<short git revision>", or just the version
## when no revision is known, or FALLBACK when even the version is empty.
##
## Revision lookup: editor-binary runs use `git rev-parse --short HEAD` in the
## project folder, falling back to res://build_info.cfg; exported builds use
## res://build_info.cfg (written by tools/stamp_build_info.gd at export time;
## gitignored so it never churns commits), else none.
##
## DECISION: no generated file is committed; a per-commit baked revision would
## churn every commit. Exports run tools/stamp_build_info.gd first.

const FALLBACK: String = "dev"
const BUILD_INFO_PATH: String = "res://build_info.cfg"
const INFO_SECTION: String = "build"
const INFO_KEY_REVISION: String = "revision"
const VERSION_SETTING: String = "application/config/version"
const REVISION_SEPARATOR: String = "+"
const GIT_SHORT_LENGTH: int = 8

static var _cached: String = ""


## Cached label for the running build; never empty.
static func label() -> String:
	if _cached.is_empty():
		_cached = compose(str(ProjectSettings.get_setting(VERSION_SETTING, "")), read_revision())
	return _cached


## Pure join rule (unit-tested): version[+revision], FALLBACK if both missing.
static func compose(version: String, revision: String) -> String:
	var v: String = version.strip_edges()
	var r: String = revision.strip_edges()
	if v.is_empty() and r.is_empty():
		return FALLBACK
	if r.is_empty():
		return v
	if v.is_empty():
		return r
	return v + REVISION_SEPARATOR + r


## Bontago-1pi.136: editor-binary runs (dev, `godot --path .`) prefer the live
## git revision, so a build_info.cfg left behind by an earlier export cannot
## show a stale label; exported builds have no git and use the baked file.
static func read_revision() -> String:
	var is_editor_build: bool = OS.has_feature("editor")
	var live: String = git_revision() if is_editor_build else ""
	return pick_revision(is_editor_build, live, baked_revision())


## Pure choice rule (unit-tested): editor builds take the live revision when
## known, everything else (and an editor without git) takes the baked one.
static func pick_revision(is_editor_build: bool, live: String, baked: String) -> String:
	var l: String = live.strip_edges()
	if is_editor_build and not l.is_empty():
		return l
	return baked.strip_edges()


## Revision baked by tools/stamp_build_info.gd, "" when absent.
static func baked_revision() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(BUILD_INFO_PATH) != OK:
		return ""
	return str(cfg.get_value(INFO_SECTION, INFO_KEY_REVISION, "")).strip_edges()


## Short HEAD revision of the project checkout, "" when git is unavailable.
static func git_revision() -> String:
	if not OS.has_feature("editor"):
		return ""
	var out: Array = []
	var args: PackedStringArray = ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short=%d" % GIT_SHORT_LENGTH, "HEAD"]
	var code: int = OS.execute("git", args, out, false)
	if code != 0 or out.is_empty():
		return ""
	return str(out[0]).strip_edges()
