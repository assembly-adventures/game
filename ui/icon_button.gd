extends Button
## Small keyboard-accessible toolbar buttons drawn as vectors so they stay crisp at any scale.

const Style := preload("res://ui/style.gd")

var symbol := "settings"

func _init(kind: String = "settings") -> void:
	symbol = kind
	name = "LeaderboardButton" if kind == "leaderboard" else "SettingsButton"
	tooltip_text = "Weekly leaderboard" if kind == "leaderboard" else "Settings (F10)"
	accessibility_name = "Leaderboard" if kind == "leaderboard" else "Settings"
	custom_minimum_size = Vector2(52, 48)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

func _draw() -> void:
	var center := size / 2.0
	var color := Style.GOLD if symbol == "leaderboard" else Style.CYAN
	if disabled:
		color = Style.DIM
	if symbol == "leaderboard":
		var cup := PackedVector2Array([center + Vector2(-8, -11), center + Vector2(8, -11),
			center + Vector2(6, 0), center + Vector2(0, 5), center + Vector2(-6, 0), center + Vector2(-8, -11)])
		draw_polyline(cup, color, 2.0, true)
		draw_polyline(PackedVector2Array([center + Vector2(-8, -8), center + Vector2(-14, -8),
			center + Vector2(-12, -1), center + Vector2(-5, 2)]), color, 2.0, true)
		draw_polyline(PackedVector2Array([center + Vector2(8, -8), center + Vector2(14, -8),
			center + Vector2(12, -1), center + Vector2(5, 2)]), color, 2.0, true)
		draw_line(center + Vector2(0, 5), center + Vector2(0, 10), color, 2.0, true)
		draw_line(center + Vector2(-7, 11), center + Vector2(7, 11), color, 2.0, true)
	else:
		var gear := PackedVector2Array()
		for tooth in range(8):
			for part in range(4):
				var angle := (float(tooth) + float(part) / 4.0) * TAU / 8.0
				var radius := 13.0 if part in [1, 2] else 10.0
				gear.append(center + Vector2.from_angle(angle) * radius)
		gear.append(gear[0])
		draw_polyline(gear, color, 2.0, true)
		draw_arc(center, 4.5, 0.0, TAU, 28, color, 2.0, true)
