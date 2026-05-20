extends Control

var _chat_view: Control
var _input_bar: Control
var _menu_btn: Button
var _drawer_overlay: ColorRect
var _drawer_panel: Node
var _status_overlay: Node
var _step_label: Label
var _voice_overlay: Button
var _state: Node
var _session_mgr: Node
var _react_loop: Node
var _voice_mgr: Node
var _current_messages: Array = []
var _audio: AudioStreamPlayer
var _snd_send: AudioStream
var _snd_receive: AudioStream
var _snd_error: AudioStream
var _is_android: bool = false
var _voice_overlay_tween: Tween = null

# Edge-swipe state
var _swipe_start_x: float = -1.0
var _swipe_tracking: bool = false

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_session_mgr = Engine.get_singleton("SessionManager")
	_react_loop = Engine.get_singleton("ReactLoop")
	_is_android = OS.has_feature("android")

	# ── Root VBox: ChatView (expand) → step_label → InputBar (fixed) ──
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_vbox)

	# Chat view — fills available space
	_chat_view = load("res://ui/chat_view.tscn").instantiate()
	_chat_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_chat_view)

	# Step label — tiny muted text below chat
	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 10)
	_step_label.add_theme_color_override("font_color", Color("#444460"))
	_step_label.text = ""
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(_step_label)

	# Input bar — pinned bottom
	_input_bar = load("res://ui/input_bar.tscn").instantiate()
	_input_bar.custom_minimum_size.y = 56
	root_vbox.add_child(_input_bar)

	# ── Menu button (top-left, z=10) ──
	_menu_btn = Button.new()
	_menu_btn.text = "≡"
	_menu_btn.add_theme_font_size_override("font_size", 22)
	_menu_btn.custom_minimum_size = Vector2(44, 44)
	_menu_btn.add_theme_color_override("font_color", Color("#6c63ff"))
	_menu_btn.add_theme_color_override("font_hover_color", Color("#8888ff"))
	_menu_btn.position = Vector2(4, 4)
	_menu_btn.z_index = 10
	var menu_bg := StyleBoxFlat.new()
	menu_bg.bg_color = Color.TRANSPARENT
	_menu_btn.add_theme_stylebox_override("normal", menu_bg)
	_menu_btn.pressed.connect(_toggle_drawer)
	add_child(_menu_btn)

	# ── Status overlay (top-right, z=10) ──
	_status_overlay = load("res://ui/status_overlay.tscn").instantiate()
	_status_overlay.z_index = 10
	_status_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_status_overlay)

	# ── Drawer overlay (dark backdrop, z=15) ──
	_drawer_overlay = ColorRect.new()
	_drawer_overlay.color = Color(0, 0, 0, 0.5)
	_drawer_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer_overlay.z_index = 15
	_drawer_overlay.visible = false
	_drawer_overlay.gui_input.connect(_on_overlay_input)
	add_child(_drawer_overlay)

	# ── Drawer panel (right side, z=20) ──
	_drawer_panel = load("res://ui/drawer_panel.tscn").instantiate()
	_drawer_panel.z_index = 20
	_drawer_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer_panel.position.x = size.x + 10  # off-screen right
	add_child(_drawer_panel)

	# ── Floating voice overlay (Android, z=50) ──
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
	_state.token_count_updated.connect(_on_tokens)
	_react_loop.step_completed.connect(_on_step_completed)

	# Confirmation dialog
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# Keep drawer panel anchored to right edge when closed
		if _drawer_panel and not _drawer_panel._is_open:
			_drawer_panel.position.x = size.x + 10
		if _voice_overlay.visible:
			_position_voice_overlay()

func _toggle_drawer() -> void:
	if _drawer_panel._is_open:
		_drawer_panel.close()
		_drawer_overlay.visible = false
	else:
		_drawer_panel.position.x = size.x + 10
		_drawer_overlay.visible = true
		_drawer_panel.open()

func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.pressed):
		if _drawer_panel._is_open:
			_toggle_drawer()

func _input(event: InputEvent) -> void:
	# Keyboard shortcuts
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed:
			if key_event.keycode == KEY_ESCAPE:
				if _react_loop and _react_loop.is_running():
					_react_loop.stop()
					_state.set_busy(false)
				elif _drawer_panel._is_open:
					_toggle_drawer()
			elif key_event.keycode == KEY_B and key_event.ctrl_pressed:
				_toggle_drawer()
			elif key_event.keycode == KEY_N and key_event.ctrl_pressed:
				_state.current_session = "session-%d" % Time.get_ticks_msec()
				_state.session_changed.emit(_state.current_session)
			elif key_event.keycode == KEY_S and key_event.ctrl_pressed:
				_save_session()
			elif key_event.keycode == KEY_L and key_event.ctrl_pressed:
				if _input_bar and _input_bar.has_method("focus_input"):
					_input_bar.focus_input()

	# Edge-swipe detection (Android)
	if _is_android:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				if touch.position.x >= size.x - 20:
					_swipe_start_x = touch.position.x
					_swipe_tracking = true
			else:
				_swipe_tracking = false
				_swipe_start_x = -1.0
		elif event is InputEventScreenDrag and _swipe_tracking:
			var drag := event as InputEventScreenDrag
			if _swipe_start_x - drag.position.x > 80:
				if not _drawer_panel._is_open:
					_toggle_drawer()
				_swipe_tracking = false

func _on_message_sent(text: String) -> void:
	_chat_view.add_message("user", text)
	_chat_view.set_last_user_text(text)
	_current_messages.append({"role": "user", "content": text})

	_state.set_busy(true)
	_state.reset_tokens()

	# Close drawer if open
	if _drawer_panel._is_open:
		_toggle_drawer()

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

func _on_tokens(total: int) -> void:
	_update_step_label()

func _on_step_completed(_step: int, _tokens: int) -> void:
	_update_step_label()

func _update_step_label() -> void:
	var step: int = _state.get_step()
	var tokens: int = _state.get_token_count()
	_step_label.text = "Step %d | %s tokens" % [step, _format_number(tokens)]

func _format_number(n: int) -> String:
	var s := str(n)
	var result := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	return result

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

func _on_loop_error(_msg: String) -> void:
	_play_sound(_snd_error)

func _play_sound(stream: AudioStream) -> void:
	if stream and _audio:
		_audio.stream = stream
		_audio.play()

# ── Voice mode handlers ──

func _on_voice_mode_changed(active: bool) -> void:
	_voice_overlay.visible = active
	if active:
		_position_voice_overlay()
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
	# Position 16px above the input bar, right-aligned
	_voice_overlay.position = Vector2(size.x - 80, size.y - 80 - 16)

func send_voice_message(text: String) -> void:
	_on_message_sent(text)
