class_name BuildVersion
extends RefCounted
## Bontago-1pi.74: the one source of the build label shown in the main menu.
## "<application/config/version>+<short git revision>", or just the version
## when no revision is known, or FALLBACK when even the version is empty.
##
## Revision lookup, in order: res://build_info.cfg (written by
## tools/stamp_build_info.gd at export time; gitignored so it never churns
## commits), then `git rev-parse --short HEAD` in the project folder (dev and
## editor runs), else none.
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


static func read_revision() -> String:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(BUILD_INFO_PATH) == OK:
		var baked: String = str(cfg.get_value(INFO_SECTION, INFO_KEY_REVISION, "")).strip_edges()
		if not baked.is_empty():
			return baked
	return git_revision()


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
