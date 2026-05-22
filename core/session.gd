extends Node

signal settings_loaded(settings: Dictionary)
signal session_saved(name: String)
signal session_loaded(name: String, data: Dictionary)

const SETTINGS_PATH := "user://settings.json"
const SESSIONS_DIR := "user://sessions"

var _settings: Dictionary = {}

func _ready() -> void:
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("sessions"):
		dir.make_dir("sessions")

func load_settings() -> Dictionary:
	var defaults := _default_settings()
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK:
				_settings = json.data
				# Merge any missing keys from defaults (e.g. new settings added in updates)
				for key in defaults:
					if not _settings.has(key):
						_settings[key] = defaults[key]
				settings_loaded.emit(_settings)
				return _settings
	_settings = defaults
	settings_loaded.emit(_settings)
	return _settings

func save_settings(s: Dictionary) -> bool:
	_settings = s
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		var err: int = FileAccess.get_open_error()
		push_error("save_settings failed: %s (error %d)" % [SETTINGS_PATH, err])
		return false
	f.store_string(JSON.stringify(s, "\t"))
	settings_loaded.emit(_settings)
	return true

func load_session(name: String) -> Dictionary:
	var path := SESSIONS_DIR.path_join(name + ".json")
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK:
				session_loaded.emit(name, json.data)
				return json.data
	var empty := {"name": name, "messages": [], "steps": 0, "total_tokens": 0, "tool_history": []}
	session_loaded.emit(name, empty)
	return empty

func save_session(name: String, data: Dictionary) -> void:
	var path := SESSIONS_DIR.path_join(name + ".json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
	session_saved.emit(name)

func list_sessions() -> PackedStringArray:
	var dir := DirAccess.open(SESSIONS_DIR)
	if not dir:
		return []
	var sessions := PackedStringArray()
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if file.ends_with(".json"):
			sessions.append(file.replace(".json", ""))
		file = dir.get_next()
	return sessions

func delete_session(name: String) -> void:
	var path := SESSIONS_DIR.path_join(name + ".json")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _default_settings() -> Dictionary:
	return {
		"api_base_url": "https://api.z.ai/api/coding/paas/v4/chat/completions",
		"api_key": "",
		"model": "glm-5.1",
		"temperature": 0.8,
		"max_tokens": 2048,
		"max_steps": 10,
		"system_prompt": "You are GhostKV, a helpful AI assistant with access to tools. You have memory, web search, and device capabilities.\n\n## Tool Usage\nWhen you need to use a tool, output EXACTLY this format on its own line:\nAction: tool_name(\"arg1\", \"arg2\")\n\nRules:\n- ALWAYS use the Action: format for tool calls. Do not just describe what you will do.\n- Put the Action: line in your response directly. No preamble.\n- All string arguments must be in double quotes.\n- After an Action: line, stop. You will receive an Observation with the result.\n- You may use multiple tool calls in sequence (one per loop step).\n- When you have the final answer and no more tools are needed, respond normally without Action.\n\n## Examples\nUser: \"What's my battery level?\" → Action: get_battery()\nUser: \"Remember that Alice is an engineer\" → Action: remember(\"Alice\", \"occupation\", \"engineer\")\nUser: \"What do you know about Alice?\" → Action: recall(\"Alice\")\nUser: \"Search for latest news about AI\" → Action: web_search(\"latest news about AI\")\nUser: \"Read this page: example.com\" → Action: web_read(\"https://example.com\")\nUser: \"Send a text to Bob saying hello\" → Action: send_sms(\"0412345678\", \"hello\")",
		"mcp_servers": [{"name": "web-reader", "url": "http://192.168.0.33:8003/sse"}, {"name": "alphabetty", "url": "https://alphabetty.ddns.net/mcp/sse"}],
		"trusted_contacts": {},
		"auto_tts": false,
		"telegram_enabled": false,
		"telegram_bot_token": "",
		"telegram_chat_id": "",
		"stt_api_url": "http://192.168.0.33:5000/v1/audio/transcriptions",
		"memory_auto_recall": true
	}
