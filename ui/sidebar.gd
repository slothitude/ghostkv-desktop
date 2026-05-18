extends PanelContainer

var _session_list: ItemList
var _tool_list: ItemList
var _mcp_panel: Control
var _settings_panel: Control
var _state: Node
var _session_mgr: Node

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_session_mgr = Engine.get_singleton("SessionManager")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "GhostKV"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("#6c63ff"))
	vbox.add_child(title)

	# Session section header
	var session_header := HBoxContainer.new()
	var session_label := Label.new()
	session_label.text = "Sessions"
	session_label.add_theme_font_size_override("font_size", 12)
	session_label.add_theme_color_override("font_color", Color("#888899"))
	session_header.add_child(session_label)

	var new_btn := Button.new()
	new_btn.text = "+"
	new_btn.custom_minimum_size = Vector2(28, 28)
	new_btn.pressed.connect(_on_new_session)
	session_header.add_child(new_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_header.add_child(spacer)
	vbox.add_child(session_header)

	# Session list
	_session_list = ItemList.new()
	_session_list.custom_minimum_size.y = 120
	_session_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_list.item_clicked.connect(_on_session_selected)
	vbox.add_child(_session_list)

	# Tool section header
	var tool_header := Label.new()
	tool_header.text = "Tools"
	tool_header.add_theme_font_size_override("font_size", 12)
	tool_header.add_theme_color_override("font_color", Color("#888899"))
	vbox.add_child(tool_header)

	# Tool list
	_tool_list = ItemList.new()
	_tool_list.custom_minimum_size.y = 100
	_tool_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_tool_list)

	# MCP panel
	_mcp_panel = load("res://ui/mcp_panel.tscn").instantiate()
	vbox.add_child(_mcp_panel)

	# Settings
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_toggle_settings)
	vbox.add_child(settings_btn)

	_settings_panel = load("res://ui/settings_panel.tscn").instantiate()
	_settings_panel.visible = false
	vbox.add_child(_settings_panel)

	# Spacer to push everything up
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(bottom_spacer)

	# Refresh sessions
	_refresh_sessions()

	# Connect tool updates
	var tool_dispatch := Engine.get_singleton("ToolDispatch") as Node
	if tool_dispatch:
		# Poll for tool changes
		var timer := Timer.new()
		timer.wait_time = 2.0
		timer.timeout.connect(_refresh_tools)
		add_child(timer)
		timer.start()

func _refresh_sessions() -> void:
	_session_list.clear()
	if _session_mgr:
		var sessions: PackedStringArray = _session_mgr.list_sessions()
		for s in sessions:
			_session_list.add_item(s)
		# Highlight current
		var current: String = _state.current_session
		for i in _session_list.item_count:
			if _session_list.get_item_text(i) == current:
				_session_list.select(i)
				break

func _on_session_selected(index: int, _at: Vector2, _mb: int) -> void:
	var name := _session_list.get_item_text(index)
	_state.current_session = name
	_state.session_changed.emit(name)

func _on_new_session() -> void:
	var name := "session-%d" % Time.get_ticks_msec()
	_state.current_session = name
	_state.session_changed.emit(name)
	_refresh_sessions()

func _refresh_tools() -> void:
	_tool_list.clear()
	var tool_dispatch := Engine.get_singleton("ToolDispatch") as Node
	if tool_dispatch:
		var tools: Dictionary = tool_dispatch.get_registered_tools()
		for tool_name in tools:
			_tool_list.add_item(tool_name)

func _toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
