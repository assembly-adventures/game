extends CanvasLayer
## Shared settings overlay. The scene stays in place, paused, while the controls remain usable.

signal changed

const Style := preload("res://ui/style.gd")
const IconButton := preload("res://ui/icon_button.gd")
const PREFERENCES := "user://settings.cfg"

var is_open := false
var hide_leaderboard := false
var was_paused := false
var previous_focus: WeakRef
var overlay: Control
var panel: PanelContainer
var close_button: Button
var fullscreen: CheckButton
var mute: CheckButton
var music_slider: HSlider
var effects_slider: HSlider
var visibility_toggle: CheckButton
var hide_toggle: CheckButton
var status: Label
var saving := false

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var preferences := ConfigFile.new()
	if preferences.load(PREFERENCES) == OK:
		hide_leaderboard = bool(preferences.get_value("competition", "hide_board", false))
	_build()
	overlay.hide()
	PlayerData.profile_changed.connect(_sync_profile)
	get_viewport().size_changed.connect(_layout)

func make_button() -> Button:
	var button := IconButton.new("settings")
	button.pressed.connect(open)
	return button

func open() -> void:
	if is_open:
		return
	var focus := get_viewport().gui_get_focus_owner()
	previous_focus = weakref(focus) if focus != null else null
	was_paused = get_tree().paused
	get_tree().paused = true
	is_open = true
	fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	mute.set_pressed_no_signal(not Audio.enabled)
	music_slider.set_value_no_signal(Audio.music_volume * 100.0)
	effects_slider.set_value_no_signal(Audio.effects_volume * 100.0)
	_update_volume_label(music_slider)
	_update_volume_label(effects_slider)
	hide_toggle.set_pressed_no_signal(hide_leaderboard)
	_sync_profile()
	overlay.show()
	_layout()
	close_button.grab_focus()
	if not PlayerData.guest:
		var result := await PlayerData.api_request("/me")
		if result.ok:
			PlayerData.apply_profile(result.data)
		else:
			status.text = result.error

func close() -> void:
	if not is_open:
		return
	is_open = false
	overlay.hide()
	get_tree().paused = was_paused
	if previous_focus != null and is_instance_valid(previous_focus.get_ref()):
		previous_focus.get_ref().grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			if is_open:
				close()
			else:
				open()
			get_viewport().set_input_as_handled()
		elif is_open and event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
		elif is_open and event.keycode == KEY_F11:
			# PlayerData handles F11 globally; reflect the resulting browser/window state.
			_sync_fullscreen.call_deferred()

func _sync_fullscreen() -> void:
	fullscreen.set_pressed_no_signal(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
	if is_open:
		_sync_fullscreen()

func _build() -> void:
	overlay = Control.new()
	overlay.name = "SettingsOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = preload("res://GameTheme.tres")
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close())
	overlay.add_child(shade)
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := Style.panel_style()
	panel_style.bg_color = Color("111b28")
	panel_style.border_color = Color(Style.CYAN, 0.65)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := _label("Settings", 28, Style.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	close_button = Button.new()
	close_button.text = "Done"
	close_button.tooltip_text = "Close settings (Escape)"
	close_button.pressed.connect(close)
	heading.add_child(close_button)
	content.add_child(_label("Make yourself at home. Your puzzle will be here when you return.", 14, Color(Style.TEXT, 0.65)))
	_section(content, "DISPLAY")
	fullscreen = _toggle(content, "Full screen", "Fullscreen")
	fullscreen.toggled.connect(func(_value: bool):
		PlayerData.toggle_fullscreen()
		_sync_fullscreen.call_deferred())
	fullscreen.tooltip_text = "You can also press F11."
	_section(content, "AUDIO")
	mute = _toggle(content, "Mute all sound", "Mute")
	mute.toggled.connect(func(value: bool): Audio.set_enabled(not value))
	music_slider = _volume(content, "Music", Audio.set_music_volume)
	effects_slider = _volume(content, "Sound effects", Audio.set_effects_volume)
	_section(content, "WEEKLY LEADERBOARD")
	visibility_toggle = _toggle(content, "Show my Onyen on the leaderboard", "LeaderboardVisibility")
	visibility_toggle.toggled.connect(_save_visibility)
	hide_toggle = _toggle(content, "Hide the leaderboard on this device", "HideLeaderboard")
	hide_toggle.toggled.connect(func(value: bool):
		hide_leaderboard = value
		var preferences := ConfigFile.new()
		preferences.set_value("competition", "hide_board", value)
		preferences.save(PREFERENCES)
		changed.emit())
	status = _label("", 14, Color(Style.TEXT, 0.65))
	content.add_child(status)
	content.add_child(_label("Audio preferences stay on this device. Leaderboard visibility follows your UNC account.", 12, Color(Style.TEXT, 0.5)))
	# Keep keyboard focus inside the modal even on the welcome screen and while a level is paused.
	var controls: Array[Control] = [close_button, fullscreen, mute, music_slider, effects_slider, visibility_toggle, hide_toggle]
	for i in range(controls.size()):
		controls[i].focus_next = controls[i].get_path_to(controls[(i + 1) % controls.size()])
		controls[i].focus_previous = controls[i].get_path_to(controls[(i - 1 + controls.size()) % controls.size()])

func _layout() -> void:
	if panel == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	panel.size = Vector2(minf(600.0, viewport.x - 32.0), minf(650.0, viewport.y - 32.0))
	panel.position = ((viewport - panel.size) / 2.0).round()

func _section(parent: Control, title: String) -> void:
	var label := _label(title, 12, Style.CYAN)
	label.add_theme_font_override("font", Style.MONO)
	parent.add_child(label)

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _toggle(parent: Control, title: String, node_name: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = node_name
	toggle.text = title
	toggle.add_theme_font_size_override("font_size", 17)
	toggle.custom_minimum_size.y = 38
	parent.add_child(toggle)
	return toggle

func _volume(parent: Control, title: String, setter: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var label := _label(title, 17, Style.TEXT)
	label.custom_minimum_size.x = 126
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = title.replace(" ", "") + "Volume"
	slider.accessibility_name = title + " volume"
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.custom_minimum_size = Vector2(80, 32)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value := _label("100%", 15, Style.CYAN)
	value.custom_minimum_size.x = 48
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.set_meta("value_label", value)
	slider.value_changed.connect(func(percent: float):
		setter.call(percent / 100.0)
		_update_volume_label(slider))
	return slider

func _update_volume_label(slider: HSlider) -> void:
	(slider.get_meta("value_label") as Label).text = "%d%%" % int(slider.value)

func _sync_profile() -> void:
	if visibility_toggle == null:
		return
	visibility_toggle.set_pressed_no_signal(PlayerData.leaderboard_visible and not PlayerData.guest)
	visibility_toggle.disabled = saving or PlayerData.guest or not PlayerData.profile_loaded
	if saving:
		status.text = "Saving your leaderboard preference…"
	elif PlayerData.guest:
		status.text = "Guest progress is not ranked. Sign in with UNC to join the weekly leaderboard."
	elif not PlayerData.profile_loaded:
		status.text = "Sign in to manage your leaderboard entry."
	elif PlayerData.leaderboard_visible:
		status.text = "Your best completed runs appear under your Onyen. You can hide your entry anytime."
	else:
		status.text = "Your entry is hidden. Your progress is still saved and visible to course staff."

func _save_visibility(value: bool) -> void:
	if saving or PlayerData.guest or not PlayerData.profile_loaded:
		return
	saving = true
	_sync_profile()
	var result := await PlayerData.api_request("/preferences", HTTPClient.METHOD_POST, {"leaderboard_visible": value})
	saving = false
	if result.ok:
		PlayerData.leaderboard_visible = bool(result.data.get("leaderboard_visible", value))
		PlayerData.profile_changed.emit()
		changed.emit()
		_sync_profile()
	else:
		_sync_profile()
		status.text = result.error + " Reopen Settings to check your saved visibility."
