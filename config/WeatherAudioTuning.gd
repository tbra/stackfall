class_name WeatherAudioTuning
extends Resource
## Weather ambience tunables (Bontago-mp0.118). Which loop belongs to which
## weather lives on WeatherTuning (ambience_loop); this resource carries the
## shared mixing numbers for autoload/match/weather/WeatherAmbience.gd.
## config/weather_audio.tres is the shipped instance.

## Seconds for a loop to fade fully in or out. Used on weather changes, at
## match start and at match end/return to menu.
@export_range(0.05, 10.0, 0.05) var crossfade_s: float = 2.0
## Extra attenuation (dB) on the ambience while the pause menu is open.
@export_range(-40.0, 0.0, 0.5) var pause_duck_db: float = -12.0
## Bed gain below this linear value counts as silent and stops the player.
@export_range(0.0, 0.1, 0.001) var silent_gain: float = 0.001
## Volume (dB) of a gust whoosh before the Master/SFX sliders are added.
@export_range(-40.0, 6.0, 0.5) var gust_volume_db: float = -6.0
## One-shot whoosh streams, short to long. A gust picks the one whose length
## is closest to the gust's own duration.
@export_file("*.wav") var gust_streams: PackedStringArray = PackedStringArray()
## Whooshes that may overlap before the oldest is cut.
@export_range(1, 8, 1) var gust_voices: int = 3
