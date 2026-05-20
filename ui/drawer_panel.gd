extends PanelContainer

signal session_selected(name: String)
signal new_session_requested()
signal delete_session_requested()

var _tab_sessions: Button
var _tab_settings: Button
var _tab_servers: Button
var _session_list: ItemList
var _sessions_vbox: VBoxContainer
var _settings_vbox: VBoxContainer
var _servers_vbox: VBoxContainer
var _state: Node
var _session_mgr: Node
var _is_open: bool = false
var _delete_btn: Button
var _current_tab: int = 0

func _ready() -> void:
	_state = Engine.get_singleton("AppState")
	_session_mgr = Engine.get_singleton("SessionManager")

	# Drawer panel styling
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#111118")
	style.border_color = Color("#2a2a40")
	style.border_width_left = 1
	add_theme_stylebox_override("panel", style)

	custom_minimum_size.x = 320
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# Top padding
	var top_pad := Control.new()
	top_pad.custom_minimum_size.y = 8
	vbox.add_child(top_pad)

	# Close row
	var close_row := HBoxContainer.new()
	close_row.add_theme_constant_override("separation", 8)
	vbox.add_child(close_row)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override("font_color", Color("#888899"))
	close_btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	var close_bg := StyleBoxFlat.new()
	close_bg.bg_color = Color.TRANSPARENT
	close_btn.add_theme_stylebox_override("normal", close_bg)
	close_btn.pressed.connect(close)
	close_row.add_child(close_btn)

	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	close_row.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(spacer)

	# Separator
	vbox.add_child(_make_sep())

	# Tab row
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 2)
	vbox.add_child(tab_row)

	_tab_sessions = _make_tab_btn("Sessions")
	_tab_sessions.pressed.connect(func(): _switch_tab(0))
	_style_tab_active(_tab_sessions)
	tab_row.add_child(_tab_sessions)

	_tab_settings = _make_tab_btn("Settings")
	_tab_settings.pressed.connect(func(): _switch_tab(1))
	_style_tab_inactive(_tab_settings)
	tab_row.add_child(_tab_settings)

	_tab_servers = _make_tab_btn("Servers")
	_tab_servers.pressed.connect(func(): _switch_tab(2))
	_style_tab_inactive(_tab_servers)
	tab_row.add_child(_tab_servers)

	# Separator
	vbox.add_child(_make_sep())

	# ── Sessions tab ──
	_sessions_vbox = VBoxContainer.new()
	_sessions_vbox.add_theme_constant_override("separation", 6)
	_sessions_vbox.visible = true
	vbox.add_child(_sessions_vbox)

	var session_header := HBoxContainer.new()
	session_header.add_theme_constant_override("separation", 4)
	_sessions_vbox.add_child(session_header)

	var new_btn := Button.new()
	new_btn.text = "+ New"
	new_btn.custom_minimum_size = Vector2(64, 36)
	new_btn.add_theme_font_size_override("font_size", 12)
	new_btn.pressed.connect(_on_new_session)
	session_header.add_child(new_btn)

	_delete_btn = Button.new()
	_delete_btn.text = "Delete"
	_delete_btn.custom_minimum_size = Vector2(64, 36)
	_delete_btn.add_theme_font_size_override("font_size", 12)
	_delete_btn.add_theme_color_override("font_color", Color("#ff5566"))
	_delete_btn.add_theme_color_override("font_hover_color", Color("#ff7788"))
	_delete_btn.pressed.connect(_on_delete_session)
	session_header.add_child(_delete_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.custom_minimum_size = Vector2(64, 36)
	clear_btn.add_theme_font_size_override("font_size", 12)
	clear_btn.add_theme_color_override("font_color", Color("#666680"))
	clear_btn.pressed.connect(_on_clear_session)
	session_header.add_child(clear_btn)

	_session_list = ItemList.new()
	_session_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_session_list.fixed_column_width = 280
	_session_list.item_clicked.connect(_on_session_clicked)
	_sessions_vbox.add_child(_session_list)

	# ── Settings tab ──
	_settings_vbox = VBoxContainer.new()
	_settings_vbox.add_theme_constant_override("separation", 4)
	_settings_vbox.visible = false
	vbox.add_child(_settings_vbox)

	var settings_panel: Node = load("res://ui/settings_panel.tscn").instantiate()
	_settings_vbox.add_child(settings_panel)

	# ── Servers tab ──
	_servers_vbox = VBoxContainer.new()
	_servers_vbox.add_theme_constant_override("separation", 4)
	_servers_vbox.visible = false
	vbox.add_child(_servers_vbox)

	var mcp_panel: Node = load("res://ui/mcp_panel.tscn").instantiate()
	_servers_vbox.add_child(mcp_panel)

	# Initial refresh
	_refresh_sessions()

func _make_sep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 1
	return sep

func _make_tab_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(96, 36)
	btn.add_theme_font_size_override("font_size", 12)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn

func _style_tab_active(btn: Button) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#1a1a30")
	bg.border_width_bottom = 2
	bg.border_color = Color("#6c63ff")
	btn.add_theme_stylebox_override("normal", bg)
	btn.add_theme_color_override("font_color", Color("#6c63ff"))

func _style_tab_inactive(btn: Button) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.TRANSPARENT
	btn.add_theme_stylebox_override("normal", bg)
	btn.add_theme_color_override("font_color", Color("#6b6b80"))

func _switch_tab(idx: int) -> void:
	_current_tab = idx
	_sessions_vbox.visible = idx == 0
	_settings_vbox.visible = idx == 1
	_servers_vbox.visible = idx == 2
	_style_tab_active([_tab_sessions, _tab_settings, _tab_servers][idx])
	for i in 3:
		if i != idx:
			_style_tab_inactive([_tab_sessions, _tab_settings, _tab_servers][i])

func open() -> void:
	_is_open = true
	_refresh_sessions()
	var tween := create_tween()
	tween.tween_property(self, "position:x", get_parent().size.x - 320.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func close() -> void:
	_is_open = false
	var tween := create_tween()
	tween.tween_property(self, "position:x", get_parent().size.x + 10.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

func _refresh_sessions() -> void:
	if not _session_list:
		return
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

func _on_session_clicked(index: int, _at: Vector2, _mb: int) -> void:
	var name := _session_list.get_item_text(index)
	_state.current_session = name
	_state.session_changed.emit(name)

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
		_on_new_session()
	_session_mgr.delete_session(name)
	_refresh_sessions()

func _on_clear_session() -> void:
	# App handles the clear via state signals
	pass
