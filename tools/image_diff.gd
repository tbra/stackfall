extends SceneTree
## Parity diff of two captures (SKY rebuild parity harness, tools/shot.gd output).
##
##   godot --headless --path <checkout> -s tools/image_diff.gd -- <a.png> <b.png> \
##     [--max-mean=<0..255 units>] [--max-over8=<fraction 0..1>] [--max-over1=<fraction>] [--diff-out=<png>]
##
## Prints one line: IMAGE_DIFF mean_abs=<0..255 units> over1=<fraction> over8=<fraction> pixels=<n>.
## mean_abs is the mean absolute per-channel difference (RGB) in 8-bit units; over1/over8 are the shares
## of pixels whose largest channel difference exceeds 1/255 and 8/255. Exit 0 when every given
## threshold holds (or none given), 1 when one fails, 2 on bad arguments or unreadable/mismatched images.

const BAD_ARGS_EXIT: int = 2
const FAIL_EXIT: int = 1
const BYTE_MAX: int = 255
const OVER_LOW: int = 1
const OVER_HIGH: int = 8
const CHANNELS: int = 3
const DIFF_GAIN: int = 16
const RGBA_BYTES: int = 4
const MEAN_ARG: String = "--max-mean="
const OVER8_ARG: String = "--max-over8="
const OVER1_ARG: String = "--max-over1="
const OUT_ARG: String = "--diff-out="


func _init() -> void:
	quit(run(OS.get_cmdline_user_args()))


## Runs the diff for `args`; returns the exit code.
static func run(args: PackedStringArray) -> int:
	var paths: PackedStringArray = PackedStringArray()
	var limits: Dictionary = {}
	var diff_out: String = ""
	for arg: String in args:
		if arg.begins_with(MEAN_ARG):
			limits["mean_abs"] = float(arg.trim_prefix(MEAN_ARG))
		elif arg.begins_with(OVER8_ARG):
			limits["over8"] = float(arg.trim_prefix(OVER8_ARG))
		elif arg.begins_with(OVER1_ARG):
			limits["over1"] = float(arg.trim_prefix(OVER1_ARG))
		elif arg.begins_with(OUT_ARG):
			diff_out = arg.trim_prefix(OUT_ARG)
		elif not arg.begins_with("--"):
			paths.append(arg)
	if paths.size() != 2:
		printerr("IMAGE_DIFF_ERROR want exactly two image paths")
		return BAD_ARGS_EXIT
	var a: Image = Image.load_from_file(paths[0])
	var b: Image = Image.load_from_file(paths[1])
	if a == null or b == null or a.is_empty() or b.is_empty():
		printerr("IMAGE_DIFF_ERROR cannot read %s or %s" % [paths[0], paths[1]])
		return BAD_ARGS_EXIT
	if a.get_size() != b.get_size():
		printerr("IMAGE_DIFF_ERROR size mismatch %s vs %s" % [a.get_size(), b.get_size()])
		return BAD_ARGS_EXIT
	var stats: Dictionary = compare(a, b, diff_out)
	print("IMAGE_DIFF mean_abs=%.6f over1=%.6f over8=%.6f pixels=%d" % [
		stats["mean_abs"], stats["over1"], stats["over8"], stats["pixels"]])
	for key: String in limits:
		if float(stats[key]) > float(limits[key]):
			printerr("IMAGE_DIFF_FAIL %s %.6f > %.6f" % [key, stats[key], limits[key]])
			return FAIL_EXIT
	return 0


## {mean_abs, over1, over8, pixels} for two same-size images; writes an amplified diff PNG to
## `diff_out` when it is not empty.
static func compare(a: Image, b: Image, diff_out: String = "") -> Dictionary:
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var pixels: int = a.get_width() * a.get_height()
	var sum: int = 0
	var over1: int = 0
	var over8: int = 0
	var out: PackedByteArray = PackedByteArray()
	if not diff_out.is_empty():
		out.resize(da.size())
	for p: int in range(pixels):
		var worst: int = 0
		var base: int = p * RGBA_BYTES
		for c: int in range(CHANNELS):
			var d: int = absi(int(da[base + c]) - int(db[base + c]))
			sum += d
			worst = maxi(worst, d)
			if not out.is_empty():
				out[base + c] = mini(d * DIFF_GAIN, BYTE_MAX)
		if not out.is_empty():
			out[base + CHANNELS] = BYTE_MAX
		if worst > OVER_LOW:
			over1 += 1
		if worst > OVER_HIGH:
			over8 += 1
	if not out.is_empty():
		Image.create_from_data(a.get_width(), a.get_height(), false, Image.FORMAT_RGBA8, out).save_png(diff_out)
	var count: float = maxf(float(pixels), 1.0)
	return {
		"mean_abs": float(sum) / (count * float(CHANNELS)), "over1": float(over1) / count,
		"over8": float(over8) / count, "pixels": pixels,
	}
