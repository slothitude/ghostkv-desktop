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

func save_settings(s: Dictionary) -> void:
	_settings = s
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(s, "\t"))
	settings_loaded.emit(_settings)

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
		"system_prompt": "You are GhostKV, an AI assistant with access to tools.\n\nWhen you need to use a tool, you MUST write EXACTLY this format on its own line:\nAction: tool_name(\"arg1\", \"arg2\")\n\nDo NOT just describe what you will do. You MUST output the Action: line directly. No explanations before it.\nExample: if the user asks for battery level, respond with:\nAction: get_battery()\n\nAfter the Action line, stop. You will receive an Observation with the result.\nWhen you have the final answer (no more tools needed), respond normally without Action.",
		"mcp_servers": [{"name": "web-reader", "url": "http://192.168.0.33:8003/sse"}],
		"trusted_contacts": {},
		"auto_tts": false,
		"telegram_enabled": true,
		"telegram_bot_token": "8735369358:AAGS42LeK97HlNFz3TA5SEe6YZdk-BhYLpY",
		"telegram_chat_id": "5597932516",
		"stt_api_url": "http://192.168.0.33:5000/v1/audio/transcriptions",
		"memory_auto_recall": true
	}
