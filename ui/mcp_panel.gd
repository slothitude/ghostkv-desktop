extends VBoxContainer

var _url_input: LineEdit
var _name_input: LineEdit
var _connect_btn: Button
var _server_list: ItemList
var _session_mgr: Node
var _tool_dispatch: Node
var _mcp_clients: Dictionary = {}  # server_name -> MCPClient node
var _initial_load_done := false

func _ready() -> void:
	_session_mgr = Engine.get_singleton("SessionManager")
	_tool_dispatch = Engine.get_singleton("ToolDispatch")

	add_theme_constant_override("separation", 4)

	# Section header
	var header := Label.new()
	header.text = "MCP Servers"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color("#888899"))
	add_child(header)

	# Name input
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Server name"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_name_input)

	# URL input
	_url_input = LineEdit.new()
	_url_input.placeholder_text = "http://host:port/sse"
	_url_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_url_input)

	# Connect button
	_connect_btn = Button.new()
	_connect_btn.text = "Connect"
	_connect_btn.pressed.connect(_on_connect)
	add_child(_connect_btn)

	# Server list
	_server_list = ItemList.new()
	_server_list.custom_minimum_size.y = 80
	_server_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_server_list)

	# Disconnect button
	var disconnect_btn := Button.new()
	disconnect_btn.text = "Disconnect"
	disconnect_btn.pressed.connect(_on_disconnect)
	add_child(disconnect_btn)

	# Auto-load saved MCP servers
	_session_mgr.settings_loaded.connect(_on_settings_loaded)
	# Settings are already loaded by main.gd before UI is created
	# Call _load_servers directly with merged defaults
	if _session_mgr.has_method("load_settings"):
		_load_servers()

func _on_connect() -> void:
	var server_name := _name_input.text.strip_edges()
	var url := _url_input.text.strip_edges()

	if server_name.is_empty() or url.is_empty():
		return

	_connect_server(server_name, url)
	_save_mcp_servers()

func _connect_server(server_name: String, url: String) -> void:
	# Don't duplicate
	if _mcp_clients.has(server_name):
		return

	var client := Node.new()
	client.set_script(load("res://core/mcp_client.gd"))
	client.name = "MCP_%s" % server_name
	add_child(client)

	client.tools_discovered.connect(_on_tools_discovered.bind(server_name))
	client.connection_failed.connect(_on_connection_failed.bind(server_name))
	client.connection_status_changed.connect(_on_status_changed.bind(server_name))

	client.connect_server(server_name, url)
	_mcp_clients[server_name] = client
	_tool_dispatch.register_mcp_client(server_name, client)

	_server_list.add_item("%s (connecting...)" % server_name)

func _on_disconnect() -> void:
	var selected := _server_list.get_selected_items()
	if selected.size() == 0:
		return

	var idx := selected[0]
	var text := _server_list.get_item_text(idx)
	var server_name := text.split(" (")[0]

	if _mcp_clients.has(server_name):
		var client: Node = _mcp_clients[server_name]
		client.disconnect_server()
		client.queue_free()
		_mcp_clients.erase(server_name)

	_tool_dispatch.unregister_mcp_client(server_name)
	_server_list.remove_item(idx)
	_save_mcp_servers()

func _on_tools_discovered(tools: Array, server_name: String) -> void:
	for i in _server_list.item_count:
		if _server_list.get_item_text(i).begins_with(server_name):
			_server_list.set_item_text(i, "%s (%d tools)" % [server_name, tools.size()])
			break

	var client: Node = _mcp_clients.get(server_name)
	for tool in tools:
		var tool_name: String = tool.get("name", "")
		if not tool_name.is_empty():
			_tool_dispatch.register_tool(tool_name, server_name, client)

func _on_connection_failed(_msg: String, _server_name: String) -> void:
	pass  # Status handled by _on_status_changed

func _on_status_changed(status: String, server_name: String) -> void:
	for i in _server_list.item_count:
		if _server_list.get_item_text(i).begins_with(server_name):
			match status:
				"connected":
					# Will be overwritten by _on_tools_discovered
					_server_list.set_item_text(i, "%s (connected)" % server_name)
				"failed":
					_server_list.set_item_text(i, "%s (FAILED)" % server_name)
				_:
					_server_list.set_item_text(i, "%s (%s)" % [server_name, status])
			break

func _on_settings_loaded(_settings: Dictionary) -> void:
	if _initial_load_done:
		return
	_load_servers()

func _load_servers() -> void:
	_initial_load_done = true

	var settings: Dictionary = _session_mgr.load_settings()
	var servers: Array = settings.get("mcp_servers", [])
	print("McpPanel: _load_servers, saved=%s" % str(servers))

	# Merge default MCP servers (from _default_settings) that aren't already in the saved list
	var session := Engine.get_singleton("SessionManager") as Node
	if session and session.has_method("_default_settings"):
		var defaults: Dictionary = session._default_settings()
		var default_servers: Array = defaults.get("mcp_servers", [])
		print("McpPanel: default_servers=%s" % str(default_servers))
		var existing_names: PackedStringArray = []
		for s in servers:
			existing_names.append(s.get("name", ""))
		for ds in default_servers:
			if ds.get("name", "") not in existing_names:
				servers.append(ds)

	for server in servers:
		var s_name: String = server.get("name", "")
		var s_url: String = server.get("url", "")
		if not s_name.is_empty() and not s_url.is_empty():
			print("McpPanel: connecting %s at %s" % [s_name, s_url])
			_connect_server(s_name, s_url)

func _save_mcp_servers() -> void:
	var settings: Dictionary = _session_mgr.load_settings()
	var servers: Array = []
	for name in _mcp_clients:
		var client: Node = _mcp_clients[name]
		servers.append({"name": name, "url": client.sse_url})
	settings["mcp_servers"] = servers
	_session_mgr.save_settings(settings)
