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
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			var json := JSON.new()
			if json.parse(f.get_as_text()) == OK:
				_settings = json.data
				settings_loaded.emit(_settings)
				return _settings
	_settings = _default_settings()
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
		"system_prompt": "You are GhostKV, an AI assistant with access to tools. When you need information or want to take action, use the Action format.\n\nTo use a tool, write:\nAction: tool_name(\"arg1\", \"arg2\")\n\nThen stop. You will receive an Observation with the result.\nWhen you have the final answer, respond normally without Action.",
		"mcp_servers": [],
		"trusted_contacts": {},
		"auto_tts": false
	}
