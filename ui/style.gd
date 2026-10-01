extends RefCounted
## The game's shared look: the neon circuit-board palette, fonts, and drawing helpers.
## Screens take colours and fonts from here or from GameTheme.tres (the project theme),
## so the art direction lives in one place.

const BG := Color("171b25")
const PANEL := Color(0.07, 0.09, 0.13, 0.88)
const CYAN := Color("4de1ff")
const PURPLE := Color("b36bff")
const GOLD := Color("f5c542")
const GREEN := Color("5fd38d")
const RED := Color("ff6b6b")
const ORANGE := Color("ff9f43")
const DIM := Color("59606e")
const SOCKET := Color("2a303d")
const TEXT := Color("e6e9ef")
## Numbers and assembly read best in a monospace face.
const MONO := preload("res://assets/fonts/ibm-plex-mono/IBMPlexMono-SemiBold.ttf")


static func rounded(canvas: CanvasItem, rect: Rect2, fill: Color, radius: int = 10,
		border: Color = Color.TRANSPARENT, border_width: int = 0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(border_width)
	style.anti_aliasing = true
	canvas.draw_style_box(style, rect)


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(14)
	style.border_color = Color(CYAN, 0.25)
	style.set_border_width_all(1)
	style.set_content_margin_all(18)
	return style


## A one-shot spray of square "bits" at `at` in `parent`, in colours picked from `colors`.
## CPU particles are used because they are the most reliable choice for the web build.
static func burst(parent: Node, at: Vector2, colors: Array, amount: int = 16, speed: float = 170.0,
		spread: float = 180.0, gravity: float = 420.0, size: float = 5.0, lifetime: float = 0.7) -> void:
	var particles := CPUParticles2D.new()
	particles.position = at
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.direction = Vector2.UP
	particles.spread = spread
	particles.initial_velocity_min = speed * 0.45
	particles.initial_velocity_max = speed
	particles.gravity = Vector2(0, gravity)
	particles.angular_velocity_min = -360.0
	particles.angular_velocity_max = 360.0
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	var palette := Gradient.new()
	palette.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	palette.offsets = PackedFloat32Array(range(colors.size()).map(func(i): return float(i) / colors.size()))
	palette.colors = PackedColorArray(colors)
	particles.color_initial_ramp = palette
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	particles.color_ramp = fade
	parent.add_child(particles)
	particles.emitting = true
	parent.get_tree().create_timer(lifetime + 0.3).timeout.connect(particles.queue_free)


## A chunky arcade key, tinted by what kind of operation it runs.
static func key_style(color: Color, state: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = {"hover": color.darkened(0.55), "pressed": color.darkened(0.4),
		"disabled": Color(SOCKET, 0.8)}.get(state, color.darkened(0.72))
	style.border_color = DIM if state == "disabled" else color
	style.set_border_width_all(2)
	style.border_width_bottom = 2 if state == "pressed" else 6
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	return style
