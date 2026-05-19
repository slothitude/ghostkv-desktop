extends Control

const MOBILE_BREAKPOINT := 720

var _sidebar: Control
var _sidebar_sep: VSeparator
var _h_box: HBoxContainer
var _chat_view: Control
var _input_bar: Control
var _status_bar: Control
var _clear_btn: Button
var _menu_btn: Button
var _voice_btn: Button
var _voice_overlay: Button
var _sidebar_overlay: ColorRect
var _state: Node
var _session_mgr: Node
var _react_loop: Node
var _voice_mgr: Node
var _current_messages: Array = []
var _audio: AudioStreamPlayer
var _snd_send: AudioStream
var _snd_receive: AudioStream
var _snd_error: AudioStream
var _is_mobile: bool = false
var _sidebar_open: bool = true
var _is_android: bool = false
var _voice_overlay_tween: Tween = null

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_session_mgr = Engine.get_singleton("SessionManager")
	_react_loop = Engine.get_singleton("ReactLoop")

	# Detect mobile layout
	_is_mobile = DisplayServer.screen_get_size().x < MOBILE_BREAKPOINT

	# Root layout
	_h_box = HBoxContainer.new()
	_h_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_h_box)

	# Hamburger menu button (mobile only)
	_menu_btn = Button.new()
	_menu_btn.text = "≡"
	_menu_btn.add_theme_font_size_override("font_size", 22)
	_menu_btn.custom_minimum_size = Vector2(48, 48)
	_menu_btn.add_theme_color_override("font_color", Color("#6c63ff"))
	_menu_btn.add_theme_color_override("font_hover_color", Color("#8888ff"))
	_menu_btn.position = Vector2(4, 4)
	_menu_btn.z_index = 10
	_menu_btn.visible = _is_mobile
	_menu_btn.pressed.connect(_toggle_sidebar)
	add_child(_menu_btn)

	# Sidebar overlay (mobile only — dark backdrop when sidebar is open)
	_sidebar_overlay = ColorRect.new()
	_sidebar_overlay.color = Color(0, 0, 0, 0.5)
	_sidebar_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sidebar_overlay.z_index = 5
	_sidebar_overlay.visible = false
	_sidebar_overlay.gui_input.connect(_on_overlay_input)
	add_child(_sidebar_overlay)

	# Sidebar
	_sidebar = load("res://ui/sidebar.tscn").instantiate()
	_sidebar.custom_minimum_size.x = 280
	_sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_h_box.add_child(_sidebar)

	# Separator
	_sidebar_sep = VSeparator.new()
	_sidebar_sep.custom_minimum_size.x = 1
	_h_box.add_child(_sidebar_sep)

	# Main area
	var main_vbox := VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_h_box.add_child(main_vbox)

	# Chat view
	_chat_view = load("res://ui/chat_view.tscn").instantiate()
	_chat_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_chat_view)

	# Status bar row (status + voice toggle + clear button)
	var status_row := HBoxContainer.new()
	main_vbox.add_child(status_row)

	_status_bar = load("res://ui/status_bar.tscn").instantiate()
	_status_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_bar.custom_minimum_size.y = 36
	status_row.add_child(_status_bar)

	_is_android = OS.has_feature("android")

	# Voice mode toggle button (Android only)
	_voice_btn = Button.new()
	_voice_btn.text = "Voice"
	_voice_btn.add_theme_font_size_override("font_size", 11)
	_voice_btn.tooltip_text = "Toggle voice chat mode"
	_voice_btn.custom_minimum_size = Vector2(56, 36)
	_voice_btn.add_theme_color_override("font_color", Color("#666680"))
	_voice_btn.add_theme_color_override("font_hover_color", Color("#6c63ff"))
	var voice_bg := StyleBoxFlat.new()
	voice_bg.bg_color = Color("#141428")
	voice_bg.corner_radius_top_left = 4
	voice_bg.corner_radius_top_right = 4
	voice_bg.corner_radius_bottom_left = 4
	voice_bg.corner_radius_bottom_right = 4
	_voice_btn.add_theme_stylebox_override("normal", voice_bg)
	_voice_btn.visible = _is_android
	_voice_btn.pressed.connect(_on_voice_toggle)
	status_row.add_child(_voice_btn)

	_clear_btn = Button.new()
	_clear_btn.text = "Clear"
	_clear_btn.add_theme_font_size_override("font_size", 11)
	_clear_btn.tooltip_text = "Clear chat history"
	_clear_btn.custom_minimum_size = Vector2(56, 36)
	_clear_btn.add_theme_color_override("font_color", Color("#666680"))
	_clear_btn.add_theme_color_override("font_hover_color", Color("#ff7788"))
	var clear_bg := StyleBoxFlat.new()
	clear_bg.bg_color = Color("#141428")
	clear_bg.corner_radius_top_left = 4
	clear_bg.corner_radius_top_right = 4
	clear_bg.corner_radius_bottom_left = 4
	clear_bg.corner_radius_bottom_right = 4
	_clear_btn.add_theme_stylebox_override("normal", clear_bg)
	_clear_btn.pressed.connect(_on_clear_chat)
	status_row.add_child(_clear_btn)

	# Input bar
	_input_bar = load("res://ui/input_bar.tscn").instantiate()
	_input_bar.custom_minimum_size.y = 56
	main_vbox.add_child(_input_bar)

	# Floating voice overlay (Android only — circular mic button, bottom-right)
	_voice_overlay = Button.new()
	var mic_icon := load("res://assets/icons/mic.svg")
	if mic_icon:
		_voice_overlay.icon = mic_icon
	else:
		_voice_overlay.text = "🎤"
	_voice_overlay.custom_minimum_size = Vector2(64, 64)
	_voice_overlay.visible = false
	_voice_overlay.z_index = 50
	var overlay_bg := StyleBoxFlat.new()
	overlay_bg.bg_color = Color("#6c63ff")
	overlay_bg.corner_radius_top_left = 32
	overlay_bg.corner_radius_top_right = 32
	overlay_bg.corner_radius_bottom_left = 32
	overlay_bg.corner_radius_bottom_right = 32
	overlay_bg.shadow_color = Color(0, 0, 0, 0.4)
	overlay_bg.shadow_size = 8
	_voice_overlay.add_theme_stylebox_override("normal", overlay_bg)
	var overlay_pressed := overlay_bg.duplicate()
	overlay_pressed.bg_color = Color("#ff4466")
	_voice_overlay.add_theme_stylebox_override("pressed", overlay_pressed)
	_voice_overlay.pressed.connect(_on_voice_overlay_tap)
	add_child(_voice_overlay)

	# Voice manager setup
	_voice_mgr = Engine.get_singleton("VoiceManager") as Node
	if _voice_mgr:
		if _voice_mgr.has_method("set_input_bar"):
			_voice_mgr.set_input_bar(_input_bar)
		_voice_mgr.voice_mode_changed.connect(_on_voice_mode_changed)
		_voice_mgr.listening_changed.connect(_on_listening_state)
		_voice_mgr.speaking_changed.connect(_on_speaking_state)

	# Connect signals
	_input_bar.message_sent.connect(_on_message_sent)
	_state.agent_busy.connect(_on_agent_busy)
	_state.session_changed.connect(_on_session_changed)
	_react_loop.answer_ready.connect(_on_answer_ready)
	_react_loop.loop_error.connect(_on_loop_error)

	# Confirmation dialog for SMS/calls (overlay on top of everything)
	var confirm_dialog := PanelContainer.new()
	confirm_dialog.set_script(load("res://ui/confirm_dialog.gd"))
	confirm_dialog.z_index = 100
	add_child(confirm_dialog)
	var builtin_tools := Engine.get_singleton("BuiltinTools") as Node
	if builtin_tools and builtin_tools.has_method("set_confirm_dialog"):
		builtin_tools.set_confirm_dialog(confirm_dialog)

	# Load current session
	_load_session(_state.current_session)

	# Sound effects
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_snd_send = load("res://assets/sounds/tap.ogg")
	_snd_receive = load("res://assets/sounds/click.ogg")
	_snd_error = load("res://assets/sounds/switch.ogg")

	# Apply mobile layout
	_apply_layout()

func _apply_layout() -> void:
	if _is_mobile:
		_sidebar_open = false
		_sidebar.visible = false
		_sidebar_sep.visible = false
		_menu_btn.visible = true
	else:
		_sidebar_open = true
		_sidebar.visible = true
		_sidebar_sep.visible = true
		_menu_btn.visible = false
		_sidebar_overlay.visible = false

func _toggle_sidebar() -> void:
	_sidebar_open = not _sidebar_open
	_sidebar.visible = _sidebar_open
	_sidebar_sep.visible = _sidebar_open
	_sidebar_overlay.visible = _sidebar_open

	# On mobile, show sidebar as floating overlay on top of chat
	if _is_mobile and _sidebar_open:
		_sidebar.z_index = 8
		_sidebar.position = Vector2.ZERO
		_sidebar.size = Vector2(280, size.y)
		_sidebar_sep.visible = false

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.pressed):
		_toggle_sidebar()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var new_mobile := size.x < MOBILE_BREAKPOINT
		if new_mobile != _is_mobile:
			_is_mobile = new_mobile
			_apply_layout()
		if _voice_overlay.visible:
			_position_voice_overlay()

func _on_message_sent(text: String) -> void:
	_chat_view.add_message("user", text)
	_chat_view.set_last_user_text(text)
	_current_messages.append({"role": "user", "content": text})

	_state.set_busy(true)
	_state.reset_tokens()

	# Close sidebar on mobile after sending
	if _is_mobile and _sidebar_open:
		_toggle_sidebar()

	_play_sound(_snd_send)
	_react_loop.run(text, _current_messages)

func _on_agent_busy(busy: bool) -> void:
	if not busy:
		_save_session()

func _on_answer_ready(_text: String) -> void:
	_current_messages = _react_loop.get_messages()
	_state.set_busy(false)
	_play_sound(_snd_receive)

func _on_session_changed(session_name: String) -> void:
	_save_session()
	_load_session(session_name)

func _load_session(name: String) -> void:
	var data: Dictionary = _session_mgr.load_session(name)
	_current_messages = data.get("messages", [])
	_chat_view.call("clear")

	for msg in _current_messages:
		var role: String = msg.get("role", "")
		var content: String = msg.get("content", "")
		if role == "user":
			_chat_view.add_message("user", content)
		elif role == "assistant":
			_chat_view.add_message("assistant", content)

func _save_session() -> void:
	var data := {
		"name": _state.current_session,
		"messages": _current_messages,
		"steps": _state.get_step(),
		"total_tokens": 0,
		"tool_history": []
	}
	_session_mgr.save_session(_state.current_session, data)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed:
			if key_event.keycode == KEY_ESCAPE:
				if _react_loop and _react_loop.is_running():
					_react_loop.stop()
					_state.set_busy(false)
				elif _is_mobile and _sidebar_open:
					_toggle_sidebar()
			elif key_event.keycode == KEY_N and key_event.ctrl_pressed and key_event.shift_pressed:
				_state.current_session = "session-%d" % Time.get_ticks_msec()
				_state.session_changed.emit(_state.current_session)
			elif key_event.keycode == KEY_N and key_event.ctrl_pressed:
				_state.current_session = "session-%d" % Time.get_ticks_msec()
				_state.session_changed.emit(_state.current_session)
			elif key_event.keycode == KEY_S and key_event.ctrl_pressed:
				_save_session()
			elif key_event.keycode == KEY_L and key_event.ctrl_pressed:
				if _input_bar and _input_bar.has_method("focus_input"):
					_input_bar.focus_input()

func _on_clear_chat() -> void:
	if _state.is_busy():
		return
	_current_messages.clear()
	_chat_view.call("clear_chat")
	_save_session()

func _on_loop_error(_msg: String) -> void:
	_play_sound(_snd_error)

func _play_sound(stream: AudioStream) -> void:
	if stream and _audio:
		_audio.stream = stream
		_audio.play()

# ── Voice mode handlers ──────────────────────────────────────────

func _on_voice_toggle() -> void:
	if _voice_mgr:
		_voice_mgr.toggle_voice_mode()

func _on_voice_mode_changed(active: bool) -> void:
	# Update voice button appearance
	if _voice_btn:
		if active:
			_voice_btn.add_theme_color_override("font_color", Color("#6c63ff"))
		else:
			_voice_btn.add_theme_color_override("font_color", Color("#666680"))

	# Show/hide floating overlay
	_voice_overlay.visible = active
	if active:
		_position_voice_overlay()
		# Reset to mic icon + purple
		_set_overlay_listening_style()

func _on_voice_overlay_tap() -> void:
	if _voice_mgr and _voice_mgr.is_voice_mode():
		_voice_mgr.barge_in()

func _on_listening_state(active: bool) -> void:
	if not _voice_overlay.visible:
		return
	if active:
		_set_overlay_listening_style()
		_voice_overlay_pulse()
	else:
		if _voice_overlay_tween:
			_voice_overlay_tween.kill()
			_voice_overlay_tween = null
		_voice_overlay.modulate.a = 1.0

func _on_speaking_state(speaking: bool) -> void:
	if not _voice_overlay.visible:
		return
	if speaking:
		_set_overlay_speaking_style()
		_voice_overlay_pulse()
	else:
		_set_overlay_listening_style()
		if _voice_overlay_tween:
			_voice_overlay_tween.kill()
			_voice_overlay_tween = null
		_voice_overlay.modulate.a = 1.0

func _voice_overlay_pulse() -> void:
	if _voice_overlay_tween:
		_voice_overlay_tween.kill()
	_voice_overlay_tween = create_tween()
	_voice_overlay_tween.set_loops()
	_voice_overlay_tween.tween_property(_voice_overlay, "modulate:a", 0.4, 0.6).set_trans(Tween.TRANS_SINE)
	_voice_overlay_tween.tween_property(_voice_overlay, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

func _set_overlay_listening_style() -> void:
	var mic_icon := load("res://assets/icons/mic.svg")
	if mic_icon:
		_voice_overlay.icon = mic_icon
	_voice_overlay.tooltip_text = "Listening..."
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#6c63ff")
	bg.corner_radius_top_left = 32
	bg.corner_radius_top_right = 32
	bg.corner_radius_bottom_left = 32
	bg.corner_radius_bottom_right = 32
	bg.shadow_color = Color(0, 0, 0, 0.4)
	bg.shadow_size = 8
	_voice_overlay.add_theme_stylebox_override("normal", bg)

func _set_overlay_speaking_style() -> void:
	var stop_icon := load("res://assets/icons/stop.svg")
	if stop_icon:
		_voice_overlay.icon = stop_icon
	_voice_overlay.tooltip_text = "Tap to interrupt"
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#ff4466")
	bg.corner_radius_top_left = 32
	bg.corner_radius_top_right = 32
	bg.corner_radius_bottom_left = 32
	bg.corner_radius_bottom_right = 32
	bg.shadow_color = Color(0, 0, 0, 0.4)
	bg.shadow_size = 8
	_voice_overlay.add_theme_stylebox_override("normal", bg)

func _position_voice_overlay() -> void:
	# Bottom-right corner with margin
	_voice_overlay.position = Vector2(size.x - 80, size.y - 80)

func send_voice_message(text: String) -> void:
	_on_message_sent(text)
