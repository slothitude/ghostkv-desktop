extends HBoxContainer

signal message_sent(text: String)

var _input: LineEdit
var _send_btn: Button
var _stop_btn: Button
var _mic_btn: Button
var _state: Node
var _is_streaming: bool = false
var _is_android: bool = false
var _mic_tween: Tween = null

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	# Detect Android
	_is_android = OS.has_feature("android")

	# Input field
	_input = LineEdit.new()
	_input.placeholder_text = "Message GhostKV..."
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.clear_button_enabled = true
	_input.text_submitted.connect(_on_submit)
	_input.custom_minimum_size.y = 48
	_input.add_theme_color_override("font_color", Color("#ffffff"))
	_input.add_theme_color_override("font_placeholder_color", Color("#555570"))
	_input.add_theme_color_override("caret_color", Color("#6c63ff"))
	_input.add_theme_color_override("selection_color", Color("#6c63ff44"))
	var input_bg := StyleBoxFlat.new()
	input_bg.bg_color = Color("#1a1a28")
	input_bg.border_color = Color("#2a2a40")
	input_bg.border_width_bottom = 1
	input_bg.content_margin_left = 14
	input_bg.content_margin_top = 8
	input_bg.content_margin_bottom = 8
	_input.add_theme_stylebox_override("normal", input_bg)
	var input_focus := input_bg.duplicate()
	input_focus.border_color = Color("#6c63ff")
	input_focus.bg_color = Color("#1e1e36")
	_input.add_theme_stylebox_override("focused", input_focus)
	add_child(_input)

	# Mic button (Android only)
	_mic_btn = Button.new()
	var mic_icon := load("res://assets/icons/mic.svg")
	if mic_icon:
		_mic_btn.icon = mic_icon
	else:
		_mic_btn.text = "🎤"
	_mic_btn.custom_minimum_size = Vector2(48, 48)
	_mic_btn.tooltip_text = "Voice input"
	_mic_btn.visible = _is_android
	var mic_bg := StyleBoxFlat.new()
	mic_bg.bg_color = Color("#1a1a28")
	mic_bg.border_color = Color("#2a2a40")
	mic_bg.border_width_bottom = 2
	mic_bg.corner_radius_top_left = 10
	mic_bg.corner_radius_top_right = 10
	mic_bg.corner_radius_bottom_left = 10
	mic_bg.corner_radius_bottom_right = 10
	_mic_btn.add_theme_stylebox_override("normal", mic_bg)
	var mic_pressed := mic_bg.duplicate()
	mic_pressed.bg_color = Color("#2a1a38")
	mic_pressed.border_color = Color("#6c63ff")
	_mic_btn.add_theme_stylebox_override("pressed", mic_pressed)
	_mic_btn.pressed.connect(_on_mic_pressed)
	add_child(_mic_btn)

	# Connect voice manager listening signal
	if _is_android:
		var vm := Engine.get_singleton("VoiceManager") as Node
		if vm:
			vm.listening_changed.connect(_on_listening_changed)

	# Send button
	_send_btn = Button.new()
	var send_icon := load("res://assets/icons/send.svg")
	if send_icon:
		_send_btn.icon = send_icon
	else:
		_send_btn.text = "Send"
	_send_btn.custom_minimum_size = Vector2(48, 48)
	_send_btn.tooltip_text = "Send message (Enter)"
	_send_btn.pressed.connect(_on_send_pressed)
	add_child(_send_btn)

	# Stop button (hidden by default)
	_stop_btn = Button.new()
	_stop_btn.text = "■"
	_stop_btn.tooltip_text = "Stop generation (Esc)"
	_stop_btn.custom_minimum_size = Vector2(48, 48)
	_stop_btn.add_theme_font_size_override("font_size", 16)
	_stop_btn.add_theme_color_override("font_color", Color("#ff5566"))
	_stop_btn.add_theme_color_override("font_hover_color", Color("#ff7788"))
	_stop_btn.visible = false
	var stop_bg := StyleBoxFlat.new()
	stop_bg.bg_color = Color("#2a1525")
	stop_bg.border_color = Color("#ff4466")
	stop_bg.border_width_bottom = 2
	stop_bg.corner_radius_top_left = 10
	stop_bg.corner_radius_top_right = 10
	stop_bg.corner_radius_bottom_left = 10
	stop_bg.corner_radius_bottom_right = 10
	_stop_btn.add_theme_stylebox_override("normal", stop_bg)
	_stop_btn.pressed.connect(_on_stop_pressed)
	add_child(_stop_btn)

	# Spacing
	add_theme_constant_override("separation", 6)

	# Connect busy state
	_state.agent_busy.connect(_on_busy_changed)

	# Connect streaming state from react loop
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		react_loop.answer_streaming.connect(_on_streaming_token)
		react_loop.answer_ready.connect(_on_streaming_done)
		react_loop.loop_error.connect(_on_streaming_done)

func _on_submit(_text: String) -> void:
	_send()

func _on_send_pressed() -> void:
	_send()

func _send() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	message_sent.emit(text)

func _on_stop_pressed() -> void:
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop and react_loop.is_running():
		react_loop.stop()
	_state.set_busy(false)

func _on_busy_changed(busy: bool) -> void:
	_input.editable = not busy
	_send_btn.visible = not busy
	_stop_btn.visible = busy
	_stop_btn.disabled = false
	if _mic_btn:
		_mic_btn.visible = (not busy) and _is_android
	if busy:
		_input.placeholder_text = "GhostKV is thinking..."
		_is_streaming = false
	else:
		_input.placeholder_text = "Ask GhostKV anything..."
		_is_streaming = false

func _on_streaming_token(_token: String) -> void:
	if not _is_streaming:
		_is_streaming = true
		_input.placeholder_text = "GhostKV is responding..."

func _on_streaming_done(_text: String = "") -> void:
	_is_streaming = false
	if _state and _state.is_busy():
		_input.placeholder_text = "GhostKV is thinking..."
	else:
		_input.placeholder_text = "Ask GhostKV anything..."

func focus_input() -> void:
	_input.grab_focus()

func _on_mic_pressed() -> void:
	var vm := Engine.get_singleton("VoiceManager") as Node
	if vm:
		vm.start_listening()

func _on_listening_changed(active: bool) -> void:
	if not _mic_btn:
		return
	if active:
		# Pulsing animation while listening
		_mic_pulse()
	else:
		# Stop animation, reset opacity
		if _mic_tween:
			_mic_tween.kill()
			_mic_tween = null
		_mic_btn.modulate.a = 1.0

func _mic_pulse() -> void:
	if _mic_tween:
		_mic_tween.kill()
	_mic_tween = create_tween()
	_mic_tween.set_loops()
	_mic_tween.tween_property(_mic_btn, "modulate:a", 0.3, 0.5).set_trans(Tween.TRANS_SINE)
	_mic_tween.tween_property(_mic_btn, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)

func set_dictated_text(text: String) -> void:
	_input.text = text
	_input.caret_column = text.length()
	_input.grab_focus()
