extends PanelContainer

var _session_list: ItemList
var _tool_list: ItemList
var _mcp_panel: Control
var _settings_panel: Control
var _state: Node
var _session_mgr: Node
var _delete_btn: Button

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_session_mgr = Engine.get_singleton("SessionManager")

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	# Top padding
	var top_pad := Control.new()
	top_pad.custom_minimum_size.y = 8
	vbox.add_child(top_pad)

	# Title with ghost icon
	var title_box := HBoxContainer.new()
	title_box.add_theme_constant_override("separation", 8)
	vbox.add_child(title_box)

	var ghost_dot := Label.new()
	ghost_dot.text = "*"
	ghost_dot.add_theme_color_override("font_color", Color("#6c63ff"))
	ghost_dot.add_theme_font_size_override("font_size", 22)
	title_box.add_child(ghost_dot)

	var title := Label.new()
	title.text = "GhostKV"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	title_box.add_child(title)

	# Subtle version label
	var version := Label.new()
	version.text = "v0.5"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color("#555570"))
	title_box.add_child(version)

	# Separator
	vbox.add_child(_make_sep())

	# Session section
	var session_header := HBoxContainer.new()
	session_header.add_theme_constant_override("separation", 4)
	vbox.add_child(session_header)

	var session_icon := Label.new()
	session_icon.text = ">"
	session_icon.add_theme_color_override("font_color", Color("#6c63ff"))
	session_icon.add_theme_font_size_override("font_size", 10)
	session_header.add_child(session_icon)

	var session_label := Label.new()
	session_label.text = "Sessions"
	session_label.add_theme_font_size_override("font_size", 11)
	session_label.add_theme_color_override("font_color", Color("#6b6b80"))
	session_header.add_child(session_label)

	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	session_header.add_child(spacer1)

	var new_btn := Button.new()
	new_btn.text = "+"
	new_btn.custom_minimum_size = Vector2(36, 36)
	new_btn.add_theme_font_size_override("font_size", 16)
	new_btn.tooltip_text = "New session"
	new_btn.pressed.connect(_on_new_session)
	session_header.add_child(new_btn)

	# Delete session button
	_delete_btn = Button.new()
	_delete_btn.text = "x"
	_delete_btn.custom_minimum_size = Vector2(36, 36)
	_delete_btn.add_theme_font_size_override("font_size", 14)
	_delete_btn.tooltip_text = "Delete selected session"
	_delete_btn.add_theme_color_override("font_color", Color("#ff5566"))
	_delete_btn.add_theme_color_override("font_hover_color", Color("#ff7788"))
	_delete_btn.pressed.connect(_on_delete_session)
	session_header.add_child(_delete_btn)

	_session_list = ItemList.new()
	_session_list.custom_minimum_size.y = 110
	_session_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_list.fixed_column_width = 240
	_session_list.item_clicked.connect(_on_session_selected)
	_session_list.add_theme_constant_override("h_separation", 4)
	_session_list.add_theme_constant_override("v_separation", 2)
	vbox.add_child(_session_list)

	# Separator
	vbox.add_child(_make_sep())

	# Tool section
	var tool_header := HBoxContainer.new()
	tool_header.add_theme_constant_override("separation", 4)
	vbox.add_child(tool_header)

	var tool_icon := Label.new()
	tool_icon.text = ">"
	tool_icon.add_theme_color_override("font_color", Color("#6c63ff"))
	tool_icon.add_theme_font_size_override("font_size", 10)
	tool_header.add_child(tool_icon)

	var tool_label := Label.new()
	tool_label.text = "Tools"
	tool_label.add_theme_font_size_override("font_size", 11)
	tool_label.add_theme_color_override("font_color", Color("#6b6b80"))
	tool_header.add_child(tool_label)

	var tool_count := Label.new()
	tool_count.text = "0"
	tool_count.add_theme_font_size_override("font_size", 10)
	tool_count.add_theme_color_override("font_color", Color("#444460"))
	tool_count.name = "ToolCountLabel"
	tool_header.add_child(tool_count)

	_tool_list = ItemList.new()
	_tool_list.custom_minimum_size.y = 80
	_tool_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_list.add_theme_constant_override("h_separation", 4)
	_tool_list.add_theme_constant_override("v_separation", 2)
	vbox.add_child(_tool_list)

	# Separator
	vbox.add_child(_make_sep())

	# MCP panel
	_mcp_panel = load("res://ui/mcp_panel.tscn").instantiate()
	vbox.add_child(_mcp_panel)

	# Spacer to push settings to bottom
	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(bottom_spacer)

	# Settings button at bottom
	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn.pressed.connect(_toggle_settings)
	vbox.add_child(settings_btn)

	_settings_panel = load("res://ui/settings_panel.tscn").instantiate()
	_settings_panel.visible = false
	vbox.add_child(_settings_panel)

	# Refresh sessions
	_refresh_sessions()

	# Tool refresh timer
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(_refresh_tools)
	add_child(timer)
	timer.start()

func _make_sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 1
	return sep

func _refresh_sessions() -> void:
	_session_list.clear()
	if _session_mgr:
		var sessions: PackedStringArray = _session_mgr.list_sessions()
		for s in sessions:
			_session_list.add_item(s)
		var current: String = _state.current_session
		for i in _session_list.item_count:
			if _session_list.get_item_text(i) == current:
				_session_list.select(i)
				break

func _on_session_selected(index: int, _at: Vector2, _mb: int) -> void:
	var name := _session_list.get_item_text(index)
	_state.current_session = name
	_state.session_changed.emit(name)
	_delete_btn.disabled = false

func _on_new_session() -> void:
	var name := "session-%d" % Time.get_ticks_msec()
	_state.current_session = name
	_state.session_changed.emit(name)
	_refresh_sessions()

func _on_delete_session() -> void:
	var selected := _session_list.get_selected_items()
	if selected.size() == 0:
		return
	var name := _session_list.get_item_text(selected[0])
	if name == _state.current_session:
		# Can't delete active session — switch to a new one first
		_on_new_session()
	_session_mgr.delete_session(name)
	_refresh_sessions()

func _refresh_tools() -> void:
	_tool_list.clear()
	var tool_dispatch := Engine.get_singleton("ToolDispatch") as Node
	if tool_dispatch:
		var tools: Dictionary = tool_dispatch.get_registered_tools()
		for tool_name in tools:
			_tool_list.add_item(tool_name)
		# Update count
		var tc := _tool_list.get_parent().find_child("ToolCountLabel", true, false) as Label
		if tc:
			tc.text = str(tools.size())

func _toggle_settings() -> void:
	_settings_panel.visible = not _settings_panel.visible
