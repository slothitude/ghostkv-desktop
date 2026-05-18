extends VBoxContainer

var _url_input: LineEdit
var _name_input: LineEdit
var _connect_btn: Button
var _server_list: ItemList
var _session_mgr: Node
var _tool_dispatch: Node
var _mcp_clients: Dictionary = {}  # server_name -> MCPClient node

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

func _on_connect() -> void:
	var server_name := _name_input.text.strip_edges()
	var url := _url_input.text.strip_edges()

	if server_name.is_empty() or url.is_empty():
		return

	# Create MCP client node
	var client := Node.new()
	client.set_script(load("res://core/mcp_client.gd"))
	client.name = "MCP_%s" % server_name
	add_child(client)

	client.tools_discovered.connect(_on_tools_discovered.bind(server_name))
	client.connection_failed.connect(_on_connection_failed.bind(server_name))

	client.connect_server(server_name, url)
	_mcp_clients[server_name] = client
	_tool_dispatch.register_mcp_client(server_name, client)

	_server_list.add_item("%s (connecting...)" % server_name)

	# Save to settings
	_save_mcp_servers()

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
	# Update list item
	for i in _server_list.item_count:
		if _server_list.get_item_text(i).begins_with(server_name):
			_server_list.set_item_text(i, "%s (%d tools)" % [server_name, tools.size()])
			break

	# Register each tool
	var client: Node = _mcp_clients.get(server_name)
	for tool in tools:
		var tool_name: String = tool.get("name", "")
		if not tool_name.is_empty():
			_tool_dispatch.register_tool(tool_name, server_name, client)

func _on_connection_failed(msg: String, server_name: String) -> void:
	for i in _server_list.item_count:
		if _server_list.get_item_text(i).begins_with(server_name):
			_server_list.set_item_text(i, "%s (FAILED)" % server_name)
			break

func _on_settings_loaded(settings: Dictionary) -> void:
	var servers: Array = settings.get("mcp_servers", [])
	for server in servers:
		var s_name: String = server.get("name", "")
		var s_url: String = server.get("url", "")
		if not s_name.is_empty() and not s_url.is_empty():
			# Auto-connect
			_name_input.text = s_name
			_url_input.text = s_url
			_on_connect()
			_name_input.text = ""
			_url_input.text = ""

func _save_mcp_servers() -> void:
	var settings: Dictionary = _session_mgr.load_settings()
	var servers: Array = []
	for name in _mcp_clients:
		var client: Node = _mcp_clients[name]
		servers.append({"name": name, "url": client.sse_url})
	settings["mcp_servers"] = servers
	_session_mgr.save_settings(settings)
