extends Control

@onready var levels_grid: GridContainer = $MainLayout/LevelsGrid
@onready var challenge_button: Button = $MainLayout/level_7
@onready var progress_bar: ProgressBar = $MainLayout/ProgressBar
var status_label: Label
var retry_button: Button

func _ready() -> void:
	get_tree().paused = false
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$MainLayout.add_child(status_label)
	retry_button = Button.new()
	retry_button.text = "Retry loading saved progress"
	retry_button.pressed.connect(_load_profile)
	$MainLayout.add_child(retry_button)
	for button in levels_grid.get_children():
		button.disabled = true
	challenge_button.disabled = true
	$MainLayout/LevelsGrid/level_1.pressed.connect(func(): get_tree().change_scene_to_file("res://levels/level_1/risc_v_level.tscn"))
	PlayerData.profile_changed.connect(_update_progress)
	_load_profile()

func _load_profile() -> void:
	retry_button.hide()
	status_label.text = "Loading saved progress…"
	if not await PlayerData.refresh_profile():
		status_label.text = PlayerData.last_error
		retry_button.show()
		return
	for level in PlayerData.levels:
		var button: Button = levels_grid.get_node_or_null("level_%d" % int(level.id))
		if button:
			button.disabled = not bool(level.is_active)
			button.tooltip_text = "Available soon" if button.disabled else "Start or resume your saved run"
	status_label.text = "Progress is saved to your UNC account."
	_update_progress()

func _update_progress() -> void:
	progress_bar.value = PlayerData.get_progress_ratio() * 100.0
