extends Node2D

const CircuitBackdrop := preload("res://ui/circuit_backdrop.gd")

@onready var text_label: RichTextLabel = $CanvasLayer/MainLayout/RichTextLabel
@onready var start_button: Button = $CanvasLayer/MainLayout/StartButton
@onready var replay_button: Button = $CanvasLayer/ReplayButton
@onready var skip_button: Button = $CanvasLayer/SkipButton

var story: Array [Dictionary] = [
	{"text": "[center][font_size=32][b]Assembly Adventures:\nThe Lost Instructions[/b][/font_size][/center]", "duration": 4.0, "type": "flicker"},
	{"text": "[center][i]The screen flickers to life.[/i][/center]", "duration": 2.5, "type": "flicker"},
	{"text": "[center][i]A warning pulses across the terminal.[/i][/center]", "duration": 2.5, "type": "fade"},
	{"text": "[center][color=red][b]SYSTEM ALERT:\nCRITICAL MEMORY CORRUPTION DETECTED[/b][/color][/center]", "duration": 4.0, "type": "pulse"},
	{"text": "[center]Deep inside the processor, something has gone wrong.[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center]The world of Assembly—the very instructions that power everything—are disappearing.[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center]Opcodes are vanishing. The stack is collapsing. Pipelines are breaking.[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center]And at the center of it all… is the [color=purple][b]Chip Chomper[/b][/color].[/center]", "duration": 4.0, "type": "fade"},
	{"text": "[center]A rogue program.[/center]", "duration": 2.0, "type": "fade"},
	{"text": "[center]A glitch turned monster.[/center]", "duration": 2.0, "type": "fade"},
	{"text": "[center]A devourer of logic.[/center]", "duration": 2.5, "type": "fade"},
	{"text": "[center]It feeds on mistakes, corrupts memory, and erases knowledge—one instruction at a time.[/center]", "duration": 5.0, "type": "fade"},
	{"text": "[center]Every student who has entered this system has tried to stop it.[/center]", "duration": 4.0, "type": "fade"},
	{"text": "[center]Every one of them has failed.[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center][b]Until now.[/b][/center]", "duration": 3.0, "type": "flicker"},
	{"text": "[center]You wake up inside the system—standing on a glowing path of instructions, stretching endlessly ahead.[/center]", "duration": 5.0, "type": "fade"},
	{"text": "[center]Lines of [color=green]RISC-V code[/color] flash beneath your feet like a living road.[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center]A voice echoes through the system:\n[color=cyan]“If you’re seeing this… it means the system chose you.”[/color][/center]", "duration": 5.0, "type": "fade"},
	{"text": "[center]The Chip Chomper is close. You can hear it—glitching, growling, consuming everything behind you.[/center]", "duration": 5.0, "type": "fade"},
	{"text": "[center]“You are the chosen one.”[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center]Your mission is simple—but not easy:\n[b]Run.[/b][/center]", "duration": 3.5, "type": "fade"},
	{"text": "[center]Jump across broken instructions.[/center]", "duration": 2.5, "type": "fade"},
	{"text": "[center]Answer challenges to stabilize the system.[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center]Restore lost knowledge before it disappears forever.[/center]", "duration": 4.0, "type": "fade"},
	{"text": "[center]Each level you survive brings you closer to restoring the system:[/center]", "duration": 3.5, "type": "fade"},
	{"text": "[center]• Rebuild basic instructions\n• Decode opcodes\n• Repair pipelining failures[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center]• Stabilize the stack\n• Trace corrupted code\n• Rewrite what was lost[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center]But be careful.[/center]", "duration": 2.0, "type": "fade"},
	{"text": "[center]The Chip Chomper learns from your mistakes.[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center]Every wrong answer… it gets closer.[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center]Every hesitation… it speeds up.[/center]", "duration": 3.0, "type": "fade"},
	{"text": "[center]Collect badges. Prove your mastery. Restore the system.[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center]Or get caught—and watch everything you’ve learned be erased.[/center]", "duration": 4.5, "type": "fade"},
	{"text": "[center][i]The system flickers again.[/i][/center]", "duration": 2.5, "type": "flicker"},
	{"text": "[center][color=green][b]The path loads.[/b][/color][/center]", "duration": 2.5, "type": "fade"},
	{"text": "[center][color=red][b]The chase begins.[/b][/color][/center]", "duration": 3.0, "type": "pulse"},
	{"text": "[center][font_size=24][b]Press Start… if you’re ready to run.[/b][/font_size][/center]", "duration": 9999.0, "type": "blink"}
]

var current_line: int = 0
var active_tween: Tween

func _ready() -> void:
	# The shared circuit board replaces the plain black background, dimmed so the story reads clearly.
	var backdrop := CircuitBackdrop.new()
	backdrop.modulate = Color(0.75, 0.75, 0.75)
	$CanvasLayer.add_child(backdrop)
	$CanvasLayer.move_child(backdrop, 0)
	$CanvasLayer/ColorRect.hide()
	# Connect UI button signals programmatically
	start_button.pressed.connect(_on_start_button_pressed)
	replay_button.pressed.connect(_on_replay_button_pressed)
	skip_button.pressed.connect(_on_skip_button_pressed)

	start_button.hide()
	replay_button.hide()
	skip_button.show()
	
	start_animation()
	
func start_animation() -> void:
	current_line = 0
	text_label.modulate.a = 0.0
	start_button.hide()
	replay_button.hide()
	skip_button.show()
	play_next_line()

func play_next_line() -> void:
	if current_line >= story.size():
		return

	if active_tween and active_tween.is_valid():
		active_tween.kill()

	var line_data = story[current_line]
	text_label.text = line_data["text"]
	
	active_tween = create_tween()
	
	match line_data["type"]:
		"fade":
			active_tween.tween_property(text_label, "modulate:a", 1.0, 0.5)
			active_tween.tween_interval(line_data["duration"] - 1.0)
			active_tween.tween_property(text_label, "modulate:a", 0.0, 0.5)
			active_tween.finished.connect(_on_line_finished)
			
		"flicker":
			active_tween.tween_property(text_label, "modulate:a", 1.0, 0.05)
			active_tween.tween_interval(0.1)
			active_tween.tween_property(text_label, "modulate:a", 0.2, 0.05)
			active_tween.tween_interval(0.08)
			active_tween.tween_property(text_label, "modulate:a", 1.0, 0.05)
			active_tween.tween_interval(line_data["duration"] - 0.7)
			active_tween.tween_property(text_label, "modulate:a", 0.0, 0.4)
			active_tween.finished.connect(_on_line_finished)
			
		"pulse":
			active_tween.tween_property(text_label, "modulate:a", 1.0, 0.3)
			for i in range(int(line_data["duration"] - 1.0)):
				active_tween.tween_property(text_label, "modulate:a", 0.4, 0.5)
				active_tween.tween_property(text_label, "modulate:a", 1.0, 0.5)
			active_tween.tween_property(text_label, "modulate:a", 0.0, 0.5)
			active_tween.finished.connect(_on_line_finished)
			
		"blink":
			# Explicitly show interactive elements at end of intro sequence
			text_label.modulate.a = 1.0
			start_button.show()
			replay_button.show()
			skip_button.hide()
			
			active_tween.set_loops()
			active_tween.tween_property(text_label, "modulate:a", 0.3, 0.6)
			active_tween.tween_property(text_label, "modulate:a", 1.0, 0.6)

func _on_line_finished() -> void:
	current_line += 1
	play_next_line()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and current_line < story.size() - 1:
		current_line += 1
		play_next_line()

func _on_start_button_pressed() -> void:
	print("Loading main game sequence...")
	get_tree().change_scene_to_file("res://control_center.tscn")

func _on_replay_button_pressed() -> void:
	if active_tween and active_tween.is_valid():
		active_tween.kill()
	start_animation()

func _on_skip_button_pressed() -> void:
	get_tree().change_scene_to_file("res://control_center.tscn")
