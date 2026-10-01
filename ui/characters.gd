extends RefCounted
## The robot (the player's avatar) and the Chip Chomper as sprites. The art is SVG in
## assets/sprites/, drawn larger than it appears on screen so it stays sharp when the game
## scales up; edit or replace those files to restyle the characters. Owners move the nodes and set
## the mood fields (hop, tilt, hurt, cheer, walking, mouth); the nodes pick frames themselves.

const ROBOT := "res://assets/sprites/robot/%s.svg"
const CHOMPER := "res://assets/sprites/chomper/%s.svg"


class Robot extends Node2D:
	## The node sits at the robot's feet. The texture's centre is 28 px above them, close to
	## the middle of the body, so tilting pivots naturally.
	const BODY := Vector2(0, -28)
	var sprite := AnimatedSprite2D.new()
	var hop := 0.0
	var tilt := 0.0
	var hurt := 0.0
	var cheer := 0.0
	var walking := false
	var t := 0.0

	func _init() -> void:
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		for animation in [["idle", 4.0, ["idle_0", "idle_0", "idle_0", "blink", "idle_0", "idle_1"]],
				["walk", 10.0, ["walk_0", "walk_1"]], ["hurt", 1.0, ["hurt"]], ["cheer", 6.0, ["cheer_0", "cheer_1"]]]:
			frames.add_animation(animation[0])
			frames.set_animation_speed(animation[0], animation[1])
			for frame in animation[2]:
				frames.add_frame(animation[0], load(ROBOT % frame))
		sprite.sprite_frames = frames
		sprite.scale = Vector2(0.5, 0.5)
		add_child(sprite)
		sprite.play("idle")

	func _process(delta: float) -> void:
		t += delta
		cheer = maxf(cheer - delta, 0.0)
		var mood := "hurt" if hurt > 0.4 else "cheer" if cheer > 0.0 else "walk" if walking else "idle"
		if sprite.animation != mood:
			sprite.play(mood)
		sprite.position = BODY + Vector2(sin(t * 60.0) * 3.0 * hurt, -hop + sin(t * 6.0) * 1.5)
		sprite.rotation = tilt
		sprite.modulate = Color.WHITE.lerp(Color(1.0, 0.55, 0.55), hurt)


class Chomper extends Node2D:
	## A corrupted FATAL_ERR pop-up window that hovers on a glitch glow; its top half lifts and its
	## lower half, OK and Cancel buttons included, drops to open a wide mouth. The node sits FEET px above
	## the floor it hovers over. `mouth` runs from 0 (shut) to 1 (wide open); when `chew` is on it
	## also gnaws on its own.
	const SCALE := 0.45
	const FEET := 27.0
	var sprite := Sprite2D.new()
	var mouths: Array = []
	var mouth := 0.3
	var chew := true
	var t := 0.0

	func _init() -> void:
		for frame in ["closed", "half", "open"]:
			mouths.append(load(CHOMPER % frame))
		sprite.texture = mouths[0]
		sprite.scale = Vector2(SCALE, SCALE)
		add_child(sprite)

	func _process(delta: float) -> void:
		t += delta
		var opening := mouth + (0.22 * sin(t * 5.0) if chew else 0.0)
		sprite.texture = mouths[0 if opening < 0.2 else 1 if opening < 0.6 else 2]
		# The art's floor shadow is 96 px below the texture centre; keep it FEET below the node.
		sprite.position = Vector2(0, FEET - 96.0 * SCALE + sin(t * 3.0) * 2.0)
