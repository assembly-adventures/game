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


## A rectangle's outline in dashes: the look of an empty place something can go.
static func dashed_box(canvas: CanvasItem, rect: Rect2, color: Color, width: float = 2.0, dash: float = 6.0) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in range(4):
		canvas.draw_dashed_line(corners[i], corners[(i + 1) % 4], color, width, dash)


## A numbered step of a gate: what to do, with an optional note on how underneath (or, `inline`,
## on the same line after it). Every level numbers its steps beside the controls they use. With
## `wrap`, the text fills the row and wraps; without it, the row is as wide as its text, so it can
## be centred. The note's label is the row's "note" meta, so a room can change it.
static func step(number: int, text: String, note: String = "", wrap: bool = true, inline: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var badge := Label.new()
	badge.text = str(number)
	badge.custom_minimum_size = Vector2(19, 19)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", BG)
	var disc := StyleBoxFlat.new()
	disc.bg_color = GOLD
	disc.set_corner_radius_all(10)
	badge.add_theme_stylebox_override("normal", disc)
	row.add_child(badge)
	var words: BoxContainer = HBoxContainer.new() if inline else VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL if wrap else Control.SIZE_SHRINK_BEGIN
	words.add_theme_constant_override("separation", 10 if inline else 0)
	row.add_child(words)
	for part in [[text, 14, Color(TEXT, 0.92)], [note, 12, Color(TEXT, 0.55)]]:
		var label := Label.new()
		label.text = part[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap and not inline else TextServer.AUTOWRAP_OFF
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", part[1])
		label.add_theme_color_override("font_color", part[2])
		words.add_child(label)
	words.get_child(1).visible = not note.is_empty()
	row.set_meta("note", words.get_child(1))
	return row


## The hint, once a room shows it: a gold-edged box over the bottom of `view`, so showing it never
## moves the controls; or, not as an `overlay`, the last item of `view` (a column whose other items
## make room). Returns its label; the box (hidden until shown) is the label's parent.
static func hint_box(view: Control, overlay: bool = true) -> Label:
	var box := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(BG, 0.94)
	look.border_color = Color(GOLD, 0.7)
	look.set_border_width_all(1)
	look.set_corner_radius_all(8)
	look.set_content_margin_all(8)
	box.add_theme_stylebox_override("panel", look)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if overlay:
		box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		box.offset_left = 4
		box.offset_right = -4
		box.offset_top = -4
		box.offset_bottom = -4
		box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.hide()
	view.add_child(box)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	return label


## The same numbered badge, for headings a view draws itself; `center` is the badge's middle.
static func draw_step_badge(canvas: Control, center: Vector2, number: int) -> void:
	canvas.draw_circle(center, 9.5, GOLD)
	canvas.draw_string(canvas.get_theme_default_font(), center + Vector2(-9.5, 4.5), str(number),
		HORIZONTAL_ALIGNMENT_CENTER, 19, 12, BG)


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


## A 32-bit word as the signed number C would print.
static func word_text(value: int) -> String:
	value &= 0xFFFFFFFF
	return str(value - (1 << 32) if value >> 31 != 0 else value)


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
