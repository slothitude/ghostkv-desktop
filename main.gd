extends Node

var _theme_node: Node
var _state: Node
var _session: Node
var _api_client: Node
var _tool_dispatch: Node
var _react_loop: Node
var _markdown: Node
var _builtin_tools: Node
var _memory_store: Node
var _remote_api: Node
var _telegram_bot: Node
var _telephony: Node

func _ready() -> void:
	# Setup window
	get_window().title = "GhostKV Desktop"
	get_window().min_size = Vector2(360, 640)

	# Restore window rect from settings (saved in settings.json)
	var saved_size := Vector2(1200, 800)
	var saved_pos := Vector2(
		(DisplayServer.screen_get_size().x - 1200) / 2,
		(DisplayServer.screen_get_size().y - 800) / 2
	)
	# We'll load settings below and apply; for now set defaults
	get_window().size = saved_size
	get_window().position = saved_pos

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

	# Tool selector (smart filtering of 410+ tools to ~30-50 per query)
	var _tool_selector = Node.new()
	_tool_selector.set_script(load("res://core/tool_selector.gd"))
	_tool_selector.name = "ToolSelector"
	add_child(_tool_selector)
	Engine.register_singleton("ToolSelector", _tool_selector)

	# Memory store (graph memory)
	_memory_store = Node.new()
	_memory_store.set_script(load("res://core/memory_store.gd"))
	_memory_store.name = "MemoryStore"
	add_child(_memory_store)
	Engine.register_singleton("MemoryStore", _memory_store)

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

	# Built-in tools (bridges to Android plugin or OS APIs)
	_builtin_tools = Node.new()
	_builtin_tools.set_script(load("res://core/builtin_tools.gd"))
	_builtin_tools.name = "BuiltinTools"
	add_child(_builtin_tools)
	Engine.register_singleton("BuiltinTools", _builtin_tools)

	# Voice manager (STT/TTS pipeline for voice chat)
	var _voice_mgr = Node.new()
	_voice_mgr.set_script(load("res://core/voice_manager.gd"))
	_voice_mgr.name = "VoiceManager"
	add_child(_voice_mgr)
	Engine.register_singleton("VoiceManager", _voice_mgr)

	# Telephony manager (Android phone call control)
	_telephony = Node.new()
	_telephony.set_script(load("res://core/telephony_manager.gd"))
	_telephony.name = "TelephonyManager"
	add_child(_telephony)
	Engine.register_singleton("TelephonyManager", _telephony)

	# Init TelephonyManager with plugin reference (BuiltinTools already loaded it)
	var _builtin := Engine.get_singleton("BuiltinTools") as Node
	if _builtin and _builtin.has_method("get_plugin"):
		var plugin: RefCounted = _builtin.get_plugin()
		if plugin:
			_telephony.initialise(plugin)

	# Ghost call agent (autonomous phone conversations)
	var _call_agent = Node.new()
	_call_agent.set_script(load("res://core/ghost_call_agent.gd"))
	_call_agent.name = "GhostCallAgent"
	add_child(_call_agent)
	Engine.register_singleton("GhostCallAgent", _call_agent)

	# Load settings and configure API client
	var settings: Dictionary = _session.load_settings()
	if settings.has("api_base_url"):
		_api_client.configure(
			settings.get("api_base_url", ""),
			settings.get("api_key", ""),
			settings.get("model", "glm-5.1")
		)

	# Restore window position from settings
	if settings.has("window_rect"):
		var rect: Dictionary = settings["window_rect"]
		get_window().position = Vector2(rect.get("x", saved_pos.x), rect.get("y", saved_pos.y))
		get_window().size = Vector2(rect.get("w", saved_size.x), rect.get("h", saved_size.y))

	# Save window rect on close
	get_window().close_requested.connect(_on_close)

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

	# Wire GhostCallAgent (needs VoiceManager + TelephonyManager ready)
	var call_agent := Engine.get_singleton("GhostCallAgent") as Node
	if call_agent and call_agent.has_method("initialise"):
		call_agent.initialise()

	# Remote API (HTTP on port 9797)
	_remote_api = Node.new()
	_remote_api.set_script(load("res://core/remote_api.gd"))
	_remote_api.name = "RemoteAPI"
	add_child(_remote_api)

	# Telegram bot (long-poll getUpdates → ReactLoop → sendMessage back)
	_telegram_bot = Node.new()
	_telegram_bot.set_script(load("res://core/telegram_bot.gd"))
	_telegram_bot.name = "TelegramBot"
	add_child(_telegram_bot)
	Engine.register_singleton("TelegramBot", _telegram_bot)

func _on_close() -> void:
	# Save window rect to settings
	var settings: Dictionary = _session.load_settings()
	settings["window_rect"] = {
		"x": get_window().position.x,
		"y": get_window().position.y,
		"w": get_window().size.x,
		"h": get_window().size.y
	}
	_session.save_settings(settings)
	get_tree().quit()
