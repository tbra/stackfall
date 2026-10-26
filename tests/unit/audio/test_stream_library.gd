extends GutTest
## core/audio/StreamLibrary.gd: cached audio stream loading from one directory (P7 plan 2.2).
## Contract tests over a temp folder of tiny wavs: availability follows the folder, a stream is
## decoded once and then cached, a miss is null and is not cached, the root is per library.

const TINY_WAV_SAMPLES: int = 2205
const TINY_WAV_RATE: int = 22050
const TINY_WAV_LENGTH_S: float = 0.1
const LENGTH_TOLERANCE_S: float = 0.01

var _dir: String
var _other_dir: String


func before_each() -> void:
	_dir = _fresh_dir("test_stream_library_tmp")
	_other_dir = _fresh_dir("test_stream_library_other_tmp")


func after_each() -> void:
	for dir: String in [_dir, _other_dir]:
		_clear_dir(dir)
		DirAccess.remove_absolute(dir)


func _fresh_dir(name: String) -> String:
	var dir: String = OS.get_user_data_dir().path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	_clear_dir(dir)
	return dir


func _clear_dir(dir: String) -> void:
	for existing: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(existing))


func _write_wav(dir: String, filename: String, samples: int = TINY_WAV_SAMPLES) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = TINY_WAV_RATE
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples * 2)
	wav.data = data
	assert_eq(wav.save_to_wav(dir.path_join(filename)), OK, "fixture wav should save: %s" % filename)


# --- available ---------------------------------------------------------------------

func test_a_library_over_an_existing_folder_is_available() -> void:
	assert_true(StreamLibrary.new(_dir).available())


func test_a_library_over_a_missing_folder_is_not_available() -> void:
	assert_false(StreamLibrary.new(_dir.path_join("does_not_exist")).available())


# --- has_file ----------------------------------------------------------------------

func test_has_file_is_true_only_for_files_in_the_root() -> void:
	_write_wav(_dir, "click.wav")
	var library: StreamLibrary = StreamLibrary.new(_dir)
	assert_true(library.has_file("click.wav"))
	assert_false(library.has_file("other.wav"))


func test_has_file_is_false_in_a_missing_folder() -> void:
	assert_false(StreamLibrary.new(_dir.path_join("does_not_exist")).has_file("click.wav"))


# --- stream: load, cache, miss -----------------------------------------------------

func test_stream_decodes_a_wav_from_the_root() -> void:
	_write_wav(_dir, "click.wav")
	var stream: AudioStream = StreamLibrary.new(_dir).stream("click.wav")
	assert_not_null(stream, "the file is in the root")
	if stream == null:
		return
	assert_true(stream is AudioStreamWAV)
	assert_almost_eq(stream.get_length(), TINY_WAV_LENGTH_S, LENGTH_TOLERANCE_S)


func test_stream_returns_the_decoded_content_of_each_file() -> void:
	_write_wav(_dir, "short.wav", TINY_WAV_SAMPLES)
	_write_wav(_dir, "long.wav", TINY_WAV_SAMPLES * 4)
	var library: StreamLibrary = StreamLibrary.new(_dir)
	var short: AudioStream = library.stream("short.wav")
	var long: AudioStream = library.stream("long.wav")
	assert_not_null(short)
	assert_not_null(long)
	if short == null or long == null:
		return
	assert_gt(long.get_length(), short.get_length() * 2.0, "each name resolves to its own file")


func test_a_second_request_returns_the_cached_stream() -> void:
	_write_wav(_dir, "click.wav")
	var library: StreamLibrary = StreamLibrary.new(_dir)
	var first: AudioStream = library.stream("click.wav")
	assert_not_null(first)
	assert_same(library.stream("click.wav"), first, "decoded once, shared after")


func test_a_cached_stream_outlives_its_file() -> void:
	_write_wav(_dir, "click.wav")
	var library: StreamLibrary = StreamLibrary.new(_dir)
	var first: AudioStream = library.stream("click.wav")
	assert_not_null(first)
	DirAccess.remove_absolute(_dir.path_join("click.wav"))
	assert_same(library.stream("click.wav"), first, "the cache answers without touching the disk")


func test_names_differing_only_in_case_share_one_stream() -> void:
	# Effect filenames in AudioConfig are matched case-insensitively against lower-case files.
	_write_wav(_dir, "click.wav")
	var library: StreamLibrary = StreamLibrary.new(_dir)
	var lower: AudioStream = library.stream("click.wav")
	assert_not_null(lower)
	assert_same(library.stream("Click.WAV"), lower)


func test_a_missing_file_is_null() -> void:
	_write_wav(_dir, "click.wav")
	assert_null(StreamLibrary.new(_dir).stream("nope.wav"))


func test_a_miss_does_not_poison_the_name() -> void:
	var library: StreamLibrary = StreamLibrary.new(_dir)
	assert_null(library.stream("late.wav"), "not there yet")
	_write_wav(_dir, "late.wav")
	assert_not_null(library.stream("late.wav"), "a file that appears later still loads")


func test_a_miss_in_a_missing_folder_is_null() -> void:
	assert_null(StreamLibrary.new(_dir.path_join("does_not_exist")).stream("click.wav"))


func test_a_file_of_an_unsupported_type_is_null() -> void:
	var file: FileAccess = FileAccess.open(_dir.path_join("notes.txt"), FileAccess.WRITE)
	file.store_string("not audio")
	file.close()
	assert_null(StreamLibrary.new(_dir).stream("notes.txt"))


# --- root ----------------------------------------------------------------------------

func test_each_library_reads_only_its_own_root() -> void:
	_write_wav(_dir, "click.wav")
	_write_wav(_other_dir, "other.wav")
	var first: StreamLibrary = StreamLibrary.new(_dir)
	var second: StreamLibrary = StreamLibrary.new(_other_dir)
	assert_not_null(first.stream("click.wav"))
	assert_null(first.stream("other.wav"))
	assert_not_null(second.stream("other.wav"))
	assert_null(second.stream("click.wav"))
	assert_true(first.has_file("click.wav") and not first.has_file("other.wav"))


func test_two_libraries_over_one_root_cache_separately() -> void:
	_write_wav(_dir, "click.wav")
	var first: AudioStream = StreamLibrary.new(_dir).stream("click.wav")
	var second: AudioStream = StreamLibrary.new(_dir).stream("click.wav")
	assert_not_null(first)
	assert_not_null(second)
	assert_not_same(first, second, "the cache belongs to the library instance")


func test_the_shipped_effects_folder_is_available_and_loads_a_known_cue() -> void:
	var config: AudioConfig = load("res://config/audio/audio_config.tres") as AudioConfig
	var library: StreamLibrary = StreamLibrary.new(ProjectSettings.globalize_path("res://assets/audio/sfx"))
	assert_true(library.available())
	assert_true(library.has_file(config.drop_file))
	var stream: AudioStream = library.stream(config.drop_file)
	assert_not_null(stream)
	if stream != null:
		assert_gt(stream.get_length(), 0.0)


# --- release -------------------------------------------------------------------------

func test_release_drops_the_cache_so_the_next_request_decodes_afresh() -> void:
	_write_wav(_dir, "click.wav")
	var library: StreamLibrary = StreamLibrary.new(_dir)
	var before: AudioStream = library.stream("click.wav")
	assert_not_null(before)
	library.release()
	var after: AudioStream = library.stream("click.wav")
	assert_not_null(after, "a released library still serves its folder")
	assert_not_same(after, before, "release let go of the cached stream")


func test_release_on_an_unused_library_is_harmless() -> void:
	var library: StreamLibrary = StreamLibrary.new(_dir)
	library.release()
	library.release()
	assert_true(library.available())
