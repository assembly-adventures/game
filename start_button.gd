extends Button


# The project theme styles the button; it fades in once the title has typed out.
func _ready() -> void:
	text = "Begin Challenge"
	custom_minimum_size = Vector2(240, 52)
	add_theme_font_size_override("font_size", 22)
	modulate.a = 0.0
	disabled = true
	await get_tree().create_timer(4.5).timeout
	disabled = false
	create_tween().tween_property(self, "modulate:a", 1.0, 0.5)
