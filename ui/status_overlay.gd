extends Control

var _model_label: Label
var _elapsed_label: Label
var _state: Node
var _elapsed_timer: Timer
var _start_time: int = 0

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	# Position top-right
	anchor_right = 1.0
	anchor_top = 0.0

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.anchor_left = 0.6
	hbox.anchor_right = 1.0
	hbox.offset_left = 0
	hbox.offset_top = 6
	hbox.offset_right = -8
	hbox.offset_bottom = 22
	add_child(hbox)

	# Spacer pushes labels to right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	_elapsed_label = Label.new()
	_elapsed_label.add_theme_font_size_override("font_size", 10)
	_elapsed_label.add_theme_color_override("font_color", Color("#6c63ff"))
	_elapsed_label.visible = false
	hbox.add_child(_elapsed_label)

	_model_label = Label.new()
	_model_label.add_theme_font_size_override("font_size", 10)
	_model_label.add_theme_color_override("font_color", Color("#555570"))
	hbox.add_child(_model_label)

	# Elapsed timer
	_elapsed_timer = Timer.new()
	_elapsed_timer.wait_time = 0.5
	_elapsed_timer.one_shot = false
	_elapsed_timer.timeout.connect(_update_elapsed)
	add_child(_elapsed_timer)

	# Connect signals
	_state.agent_busy.connect(_on_busy_changed)
	_state.token_count_updated.connect(_on_tokens)

	var session_mgr := Engine.get_singleton("SessionManager") as Node
	if session_mgr:
		session_mgr.settings_loaded.connect(_on_settings)

func _on_settings(settings: Dictionary) -> void:
	_model_label.text = settings.get("model", "glm-5.1")

func _on_busy_changed(busy: bool) -> void:
	if busy:
		_start_time = Time.get_ticks_msec()
		_elapsed_label.visible = true
		_elapsed_label.text = "0s"
		_elapsed_timer.start()
	else:
		_elapsed_timer.stop()
		_elapsed_label.visible = false

func _update_elapsed() -> void:
	var elapsed_ms := Time.get_ticks_msec() - _start_time
	var seconds := elapsed_ms / 1000
	if seconds >= 60:
		var mins := seconds / 60
		var secs := seconds % 60
		_elapsed_label.text = "%dm %ds" % [mins, secs]
	else:
		_elapsed_label.text = "%ds" % seconds

func _on_tokens(_total: int) -> void:
	pass
