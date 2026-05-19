extends HBoxContainer

var _model_label: Label
var _step_label: Label
var _token_label: Label
var _state: Node
var _elapsed_timer: Timer
var _elapsed_label: Label
var _start_time: int = 0

func _ready() -> void:
	_state = Engine.get_singleton("AppState")

	_model_label = Label.new()
	_model_label.add_theme_font_size_override("font_size", 11)
	_model_label.add_theme_color_override("font_color", Color("#888899"))
	add_child(_model_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", 11)
	_step_label.add_theme_color_override("font_color", Color("#888899"))
	_step_label.text = "Step: 0"
	add_child(_step_label)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(spacer2)

	# Elapsed time (shown during generation)
	_elapsed_label = Label.new()
	_elapsed_label.add_theme_font_size_override("font_size", 11)
	_elapsed_label.add_theme_color_override("font_color", Color("#6c63ff"))
	_elapsed_label.visible = false
	add_child(_elapsed_label)

	_token_label = Label.new()
	_token_label.add_theme_font_size_override("font_size", 11)
	_token_label.add_theme_color_override("font_color", Color("#888899"))
	_token_label.text = "Tokens: 0"
	add_child(_token_label)

	# Top separator
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 1
	add_child(sep)

	# Elapsed time timer
	_elapsed_timer = Timer.new()
	_elapsed_timer.wait_time = 0.5
	_elapsed_timer.one_shot = false
	_elapsed_timer.timeout.connect(_update_elapsed)
	add_child(_elapsed_timer)

	# Connect signals
	_state.token_count_updated.connect(_on_tokens)
	_state.agent_busy.connect(_on_busy_changed)
	var session_mgr := Engine.get_singleton("SessionManager") as Node
	if session_mgr:
		session_mgr.settings_loaded.connect(_on_settings)

	# Connect streaming for live token count
	var react_loop := Engine.get_singleton("ReactLoop") as Node
	if react_loop:
		react_loop.step_completed.connect(_on_step_completed)

func _on_tokens(total: int) -> void:
	_token_label.text = "Tokens: %d" % total
	_step_label.text = "Step: %d" % _state.get_step()

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

func _on_step_completed(step: int, tokens: int) -> void:
	_step_label.text = "Step: %d" % step
