# badges_container.gd — attach to BadgesContainer
extends HBoxContainer

const GRAYSCALE_SHADER := preload("res://badge_grayscale.gdshader")

func _ready() -> void:
	PlayerData.profile_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	for badge in get_children():
		_setup_badge(badge)

func _setup_badge(badge: Node) -> void:
	if not badge is TextureRect:
		return

	# Give each badge its own ShaderMaterial instance
	var mat := ShaderMaterial.new()
	mat.shader = GRAYSCALE_SHADER
	badge.material = mat

	# Check against our global PlayerData singleton
	var is_earned := badge.name in PlayerData.earned_badges
	
	# Set directly to full color (0.0 gray) if earned globally, otherwise grayscale (1.0)
	mat.set_shader_parameter("gray_amount", 0.0 if is_earned else 1.0)
