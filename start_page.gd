extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_button_pressed() -> void:
	var path := "res://intro_animation.tscn"
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to load scene: %s (error %d)" % [path, err])
