extends Node

var _theme_node: Node
var _state: Node
var _session: Node
var _api_client: Node
var _tool_dispatch: Node
var _react_loop: Node
var _markdown: Node

func _ready() -> void:
	# Setup window
	get_window().title = "GhostKV Desktop"
	get_window().size = Vector2(1200, 800)
	get_window().min_size = Vector2(800, 600)
	get_window().position = Vector2(
		(DisplayServer.screen_get_size().x - 1200) / 2,
		(DisplayServer.screen_get_size().y - 800) / 2
	)

	# Build theme
	_theme_node = Node.new()
	_theme_node.set_script(load("res://core/theme.gd"))
	add_child(_theme_node)
	get_window().theme = _theme_node.build_theme()

	# State singleton
	_state = Node.new()
	_state.set_script(load("res://core/state.gd"))
	_state.name = "AppState"
	add_child(_state)
	Engine.register_singleton("AppState", _state)

	# Session manager
	_session = Node.new()
	_session.set_script(load("res://core/session.gd"))
	_session.name = "SessionManager"
	add_child(_session)
	Engine.register_singleton("SessionManager", _session)

	# API client
	_api_client = Node.new()
	_api_client.set_script(load("res://core/api_client.gd"))
	_api_client.name = "ApiClient"
	add_child(_api_client)
	Engine.register_singleton("ApiClient", _api_client)
	_state.api_client = _api_client

	# Tool dispatch
	_tool_dispatch = Node.new()
	_tool_dispatch.set_script(load("res://core/tool_dispatch.gd"))
	_tool_dispatch.name = "ToolDispatch"
	add_child(_tool_dispatch)
	Engine.register_singleton("ToolDispatch", _tool_dispatch)

	# React loop
	_react_loop = Node.new()
	_react_loop.set_script(load("res://core/react_loop.gd"))
	_react_loop.name = "ReactLoop"
	add_child(_react_loop)
	Engine.register_singleton("ReactLoop", _react_loop)
	_state.react_loop = _react_loop

	# Markdown converter
	_markdown = Node.new()
	_markdown.set_script(load("res://core/markdown.gd"))
	_markdown.name = "Markdown"
	add_child(_markdown)
	Engine.register_singleton("Markdown", _markdown)

	# Load settings and configure API client
	var settings: Dictionary = _session.load_settings()
	if settings.has("api_base_url"):
		_api_client.configure(
			settings.get("api_base_url", ""),
			settings.get("api_key", ""),
			settings.get("model", "glm-5.1")
		)

	# Configure react loop
	_react_loop.configure(
		_api_client,
		_tool_dispatch,
		settings.get("max_steps", 10),
		settings.get("temperature", 0.8),
		settings.get("max_tokens", 2048),
		settings.get("system_prompt", "")
	)

	# Load main UI
	var app: Node = load("res://ui/app.tscn").instantiate()
	add_child(app)
