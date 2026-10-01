extends Control

const CircuitBackdrop := preload("res://ui/circuit_backdrop.gd")
const Style := preload("res://ui/style.gd")
const Characters := preload("res://ui/characters.gd")

var robot
var chomper


func _ready() -> void:
	var backdrop := CircuitBackdrop.new()
	add_child(backdrop)
	move_child(backdrop, 0)
	var title: RichTextLabel = $VBoxContainer/RichTextLabel_AA
	title.add_theme_font_override("normal_font", get_theme_font("bold_font", "RichTextLabel"))
	title.add_theme_color_override("font_outline_color", Color(Style.CYAN, 0.4))
	title.add_theme_constant_override("outline_size", 12)
	$VBoxContainer/RichTextLabel.add_theme_color_override("default_color", Style.CYAN)
	# The Chomper lurks on the left while the robot waits on the right, cheering now and then.
	chomper = Characters.Chomper.new()
	chomper.scale = Vector2(1.6, 1.6)
	add_child(chomper)
	robot = Characters.Robot.new()
	robot.scale = Vector2(1.6, 1.6)
	add_child(robot)
	resized.connect(_place_characters)
	_place_characters()
	var cheering := Timer.new()
	cheering.wait_time = 3.5
	cheering.autostart = true
	cheering.timeout.connect(func(): robot.cheer = 1.2)
	add_child(cheering)


func _place_characters() -> void:
	chomper.position = Vector2(size.x * 0.5 - 330, size.y * 0.5 + 170)
	robot.position = Vector2(size.x * 0.5 + 330, size.y * 0.5 + 215)


func _on_button_pressed() -> void:
	var path := "res://intro_animation.tscn"
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load scene: %s (error %d)" % [path, err])
