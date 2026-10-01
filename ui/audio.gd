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
var players: Array = []
var music: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A small pool, so overlapping sounds (a press during a gate opening) don't cut each other off.
	for i in range(6):
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	music = AudioStreamPlayer.new()
	music.stream = MUSIC
	music.volume_db = -20.0
	add_child(music)
	music.play()

## `vary` nudges the pitch at random so repeated presses don't sound mechanical.
func play(sound: String, volume_db: float = 0.0, vary: float = 0.0) -> void:
	if not enabled or not SOUNDS.has(sound):
		return
	var player: AudioStreamPlayer = players[0]
	for candidate in players:
		if not candidate.playing:
			player = candidate
			break
	player.stream = SOUNDS[sound]
	player.volume_db = volume_db - 6.0
	player.pitch_scale = 1.0 + randf_range(-vary, vary)
	player.play()

func set_enabled(on: bool) -> void:
	enabled = on
	music.stream_paused = not on
