extends Node
## Sound effects and background music for every screen (autoloaded as Audio). The music
## keeps playing across scene changes; the sound switch mutes both. Credits: assets/CREDITS.md.

const SOUNDS := {
	"press": preload("res://assets/audio/sfx/key_press.ogg"),
	"undo": preload("res://assets/audio/sfx/undo.ogg"),
	"hint": preload("res://assets/audio/sfx/hint.ogg"),
	"open": preload("res://assets/audio/sfx/gate_open.ogg"),
	"overflow": preload("res://assets/audio/sfx/overflow.ogg"),
	"strike": preload("res://assets/audio/sfx/strike.ogg"),
	"chomp": preload("res://assets/audio/sfx/chomp.ogg"),
	"dragged": preload("res://assets/audio/sfx/dragged_back.ogg"),
	"complete": preload("res://assets/audio/sfx/level_complete.ogg"),
}
const MUSIC := preload("res://assets/audio/music/circuit_loop.ogg")  # Looping is set in its import settings.

var enabled := true
var music_volume := 1.0
var effects_volume := 1.0
var players: Array = []
var music: AudioStreamPlayer
const PREFERENCES := "user://audio.cfg"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var preferences := ConfigFile.new()
	if preferences.load(PREFERENCES) == OK:
		enabled = bool(preferences.get_value("audio", "enabled", true))
		music_volume = clampf(float(preferences.get_value("audio", "music", 1.0)), 0.0, 1.0)
		effects_volume = clampf(float(preferences.get_value("audio", "effects", 1.0)), 0.0, 1.0)
	# A small pool, so overlapping sounds (a press during a gate opening) don't cut each other off.
	for i in range(6):
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	music = AudioStreamPlayer.new()
	music.stream = MUSIC
	music.volume_db = -20.0 + linear_to_db(maxf(music_volume, 0.0001))
	add_child(music)
	music.play()
	music.stream_paused = not enabled or music_volume == 0.0

## `vary` nudges the pitch at random so repeated presses don't sound mechanical.
func play(sound: String, volume_db: float = 0.0, vary: float = 0.0) -> void:
	if not enabled or effects_volume == 0.0 or not SOUNDS.has(sound):
		return
	var player: AudioStreamPlayer = players[0]
	for candidate in players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = SOUNDS[sound]
	player.volume_db = volume_db - 6.0 + linear_to_db(maxf(effects_volume, 0.0001))
	player.pitch_scale = 1.0 + randf_range(-vary, vary)
	player.play()

func set_enabled(on: bool) -> void:
	enabled = on
	music.stream_paused = not on or music_volume == 0.0
	if not on:
		for player in players:
			player.stop()
	_save_preferences()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	music.volume_db = -20.0 + linear_to_db(maxf(music_volume, 0.0001))
	music.stream_paused = not enabled or music_volume == 0.0
	_save_preferences()

func set_effects_volume(value: float) -> void:
	effects_volume = clampf(value, 0.0, 1.0)
	_save_preferences()

func _save_preferences() -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("audio", "enabled", enabled)
	preferences.set_value("audio", "music", music_volume)
	preferences.set_value("audio", "effects", effects_volume)
	preferences.save(PREFERENCES)
